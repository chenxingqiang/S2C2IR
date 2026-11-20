//===- s2c2-dist-runtime.cpp - Host MPI witness for HB_D --------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// D4 minimal runtime slice. NCCL and HCCL are not on this host: there is
// no GPU and no NPU. OpenMPI runs the three v0 collectives as host
// processes. That is not a device execution and not a trace.
//
// A collective completion is a !sched.token (the enclosing sched.task
// token). MPI_SUCCESS is not acceptance. The witness is accepted only
// when the ranks that entered are the mesh and the token is HB_D-after
// each input pack and HB_D-before each result pack and result read.
// Clock order is not consulted.

#include "s2c2/ExecutionModel/CollectiveDependency.h"
#include "s2c2/ExecutionModel/RankContext.h"
#include "s2c2/Schedule/ScheduleDialect.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageDialect.h"
#include "s2c2/Storage/StorageOps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Shard/IR/ShardDialect.h"
#include "mlir/Dialect/Shard/IR/ShardOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Parser/Parser.h"

#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/raw_ostream.h"

#include <mpi.h>

#include <algorithm>
#include <optional>
#include <string>
#include <vector>

using namespace mlir;
using namespace mlir::s2c2;
using sched::TaskOp;
using sched::TokenType;
using stor::PackOp;
using stor::UnpackOp;

namespace {

int gRank = 0;

void say(llvm::raw_ostream &os, const std::string &line) {
  if (gRank == 0) {
    os << line << '\n';
    os.flush();
  }
}

struct Requirement {
  std::string func;
  std::string collective;
  std::vector<int64_t> participants;
  bool tokenIsSched = false;
  bool inputBefore = false;
  bool resultAfter = false;
  bool readsAfter = false;
};

struct RuntimeEvent {
  std::vector<int64_t> participants;
  bool tokenIsSched = false;
  bool inputBefore = false;
  bool resultAfter = false;
  bool readsAfter = false;
  bool mpiOk = false;
};

bool eventSatisfies(const RuntimeEvent &event, const Requirement &req) {
  if (!event.tokenIsSched || event.participants != req.participants)
    return false;
  if (!event.inputBefore || !event.resultAfter || !event.readsAfter)
    return false;
  // An API success with none of the above must not pass. mpiOk is not read.
  (void)event.mpiOk;
  (void)req;
  return true;
}

int64_t meshSizeOf(shard::GridOp grid) {
  if (!grid || grid.getShape().empty())
    return 0;
  int64_t n = 1;
  for (int64_t extent : grid.getShape()) {
    if (extent <= 0)
      return 0;
    n *= extent;
  }
  return n;
}

shard::GridOp gridOf(Operation *op) {
  auto sym = op->getAttrOfType<FlatSymbolRefAttr>("grid");
  if (!sym)
    return {};
  return dyn_cast_or_null<shard::GridOp>(
      SymbolTable::lookupNearestSymbolFrom(op, sym));
}

bool tokenIsSched(Operation *collective) {
  auto task = collective->getParentOfType<TaskOp>();
  return task && isa<TokenType>(task.getToken().getType());
}

bool hbHolds(func::FuncOp func, Operation *collective, int64_t rank,
             const s2c2::exec::HBGraph &graph, bool &inputBefore,
             bool &resultAfter, bool &readsAfter) {
  inputBefore = false;
  resultAfter = false;
  readsAfter = false;
  auto unpack = collective->getOperand(0).getDefiningOp<UnpackOp>();
  if (!unpack)
    return false;
  func.walk([&](PackOp pack) {
    if (pack.getBuffer() != unpack.getBuffer())
      return;
    if (s2c2::exec::isCollectiveImage(pack.getValue(), collective))
      return;
    auto owner = s2c2::exec::ownerRank(pack.getBuffer());
    if (!owner || *owner != rank)
      return;
    if (graph.reaches(pack, collective))
      inputBefore = true;
  });
  resultAfter = false;
  bool sawResult = false;
  func.walk([&](PackOp pack) {
    if (!s2c2::exec::isCollectiveImage(pack.getValue(), collective))
      return;
    auto owner = s2c2::exec::ownerRank(pack.getBuffer());
    if (!owner || *owner != rank)
      return;
    sawResult = true;
    if (graph.reaches(collective, pack))
      resultAfter = true;
  });
  readsAfter = true;
  func.walk([&](UnpackOp read) {
    bool output = false;
    for (Operation *user : read.getBuffer().getUsers()) {
      auto pack = dyn_cast<PackOp>(user);
      if (!pack || !s2c2::exec::isCollectiveImage(pack.getValue(), collective))
        continue;
      auto owner = s2c2::exec::ownerRank(pack.getBuffer());
      if (owner && *owner == rank)
        output = true;
    }
    if (output && !graph.reaches(collective, read))
      readsAfter = false;
  });
  return inputBefore && sawResult && resultAfter && readsAfter;
}

int runCollective(StringRef name) {
  int in = gRank + 1;
  int world = 0;
  MPI_Comm_size(MPI_COMM_WORLD, &world);
  if (name == "shard.all_reduce") {
    int out = 0;
    return MPI_Allreduce(&in, &out, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
  }
  if (name == "shard.all_gather") {
    std::vector<int> gathered(world, 0);
    return MPI_Allgather(&in, 1, MPI_INT, gathered.data(), 1, MPI_INT,
                         MPI_COMM_WORLD);
  }
  std::vector<int> send(world, in);
  int recv = 0;
  return MPI_Reduce_scatter_block(send.data(), &recv, 1, MPI_INT, MPI_SUM,
                                  MPI_COMM_WORLD);
}

int runModule(ModuleOp module) {
  int world = 0;
  MPI_Comm_size(MPI_COMM_WORLD, &world);
  bool any = false;
  bool rejectedApiOnly = false;

  for (func::FuncOp func : module.getOps<func::FuncOp>()) {
    s2c2::exec::HBGraph graph;
    s2c2::exec::buildHbD(func, graph);
    SmallVector<StringRef> kinds = {"shard.all_reduce", "shard.all_gather",
                                    "shard.reduce_scatter"};
    for (StringRef kind : kinds) {
      SmallVector<Operation *> ops;
      func.walk([&](Operation *op) {
        if (op->getName().getStringRef() == kind)
          ops.push_back(op);
      });
      if (ops.empty())
        continue;
      any = true;
      shard::GridOp grid = gridOf(ops.front());
      int64_t mesh = meshSizeOf(grid);
      if (mesh <= 0 || world != mesh) {
        say(llvm::errs(), "error: runtime world does not match the mesh");
        return 1;
      }
      std::vector<int64_t> participants;
      for (Operation *op : ops) {
        auto unpack = op->getOperand(0).getDefiningOp<UnpackOp>();
        auto rank = unpack ? s2c2::exec::ownerRank(unpack.getBuffer())
                           : std::nullopt;
        if (!rank) {
          say(llvm::errs(),
              "error: runtime participants do not match the mesh");
          return 1;
        }
        participants.push_back(*rank);
      }
      llvm::sort(participants);
      participants.erase(std::unique(participants.begin(), participants.end()),
                         participants.end());
      std::vector<int64_t> expect(mesh);
      for (int64_t i = 0; i < mesh; ++i)
        expect[i] = i;
      if (participants != expect) {
        say(llvm::errs(),
            "error: runtime participants do not match the mesh");
        return 1;
      }

      Requirement req;
      req.func = func.getSymName().str();
      req.collective = kind.str();
      req.participants = participants;
      req.tokenIsSched = true;
      req.inputBefore = true;
      req.resultAfter = true;
      req.readsAfter = true;

      bool inputBefore = true;
      bool resultAfter = true;
      bool readsAfter = true;
      bool tokens = true;
      for (Operation *op : ops) {
        auto unpack = op->getOperand(0).getDefiningOp<UnpackOp>();
        int64_t rank = *s2c2::exec::ownerRank(unpack.getBuffer());
        bool in = false, result = false, reads = false;
        if (!tokenIsSched(op) ||
            !hbHolds(func, op, rank, graph, in, result, reads)) {
          tokens = tokens && tokenIsSched(op);
          inputBefore = inputBefore && in;
          resultAfter = resultAfter && result;
          readsAfter = readsAfter && reads;
          if (!tokenIsSched(op)) {
            say(llvm::errs(),
                "error: runtime completion is not a sched.token");
            return 1;
          }
          if (!reads) {
            say(llvm::errs(),
                "error: runtime completion is not HB_D-before the result read");
            return 1;
          }
          say(llvm::errs(), "error: runtime event breaks HB_D");
          return 1;
        }
      }

      RuntimeEvent apiOnly;
      apiOnly.mpiOk = true;
      apiOnly.tokenIsSched = true;
      if (!rejectedApiOnly) {
        if (eventSatisfies(apiOnly, req)) {
          say(llvm::errs(),
              "error: runtime accepted an API success without HB_D");
          return 1;
        }
        say(llvm::outs(), "api-only=rejected");
        rejectedApiOnly = true;
      }

      int rc = runCollective(kind);
      RuntimeEvent event;
      event.participants = participants;
      event.tokenIsSched = tokens;
      event.inputBefore = inputBefore;
      event.resultAfter = resultAfter;
      event.readsAfter = readsAfter;
      event.mpiOk = rc == MPI_SUCCESS;
      if (rc != MPI_SUCCESS || !eventSatisfies(event, req)) {
        say(llvm::errs(), "error: runtime event breaks HB_D");
        return 1;
      }

      std::string ranks;
      for (int64_t rank : participants) {
        if (!ranks.empty())
          ranks.push_back(',');
        ranks += std::to_string(rank);
      }
      say(llvm::outs(), "func @" + req.func + " collective " + req.collective +
                            " participants=" + ranks +
                            " token=!sched.token hb-d=satisfied mpi=ok");
    }
  }
  if (!any) {
    say(llvm::errs(), "error: runtime found no collective");
    return 1;
  }
  return 0;
}

} // namespace

int main(int argc, char **argv) {
  if (MPI_Init(&argc, &argv) != MPI_SUCCESS)
    return 1;
  MPI_Comm_rank(MPI_COMM_WORLD, &gRank);
  int code = 1;
  if (argc < 2) {
    say(llvm::errs(), "error: runtime expects an MLIR module");
  } else {
    say(llvm::outs(), "runtime mpi");
    say(llvm::outs(), "real-device no");
    say(llvm::outs(),
        "device-note host MPI has no GPU or NPU; completion is not a trace timestamp");
    say(llvm::outs(), "hb-source ir-hb-d");

    MLIRContext context;
    DialectRegistry registry;
    registry.insert<func::FuncDialect, s2c2::stor::StorageDialect,
                    s2c2::sched::ScheduleDialect, shard::ShardDialect>();
    context.appendDialectRegistry(registry);
    context.loadAllAvailableDialects();
    llvm::SourceMgr source;
    std::string path = argv[1];
    auto buffer = llvm::MemoryBuffer::getFile(path);
    if (!buffer) {
      say(llvm::errs(), "error: runtime could not read the module");
    } else {
      source.AddNewSourceBuffer(std::move(*buffer), llvm::SMLoc());
      auto module = parseSourceFile<ModuleOp>(source, &context);
      if (!module)
        say(llvm::errs(), "error: runtime could not parse the module");
      else
        code = runModule(*module);
    }
  }
  MPI_Finalize();
  return code;
}
