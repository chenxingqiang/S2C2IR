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
#include "mlir/Parser/Parser.h"

#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/raw_ostream.h"

#include <mpi.h>

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

struct WitnessValue {
  int rc = 1;
  bool valuesOk = false;
  std::string note;
};

int witnessSum(int world) { return world * (world + 1) / 2; }

// Host scalars, one MPI call per (mesh, callsite). Not a tensor runtime.
WitnessValue runWitness(StringRef name, int world) {
  int in = gRank + 1;
  int expect = witnessSum(world);
  WitnessValue result;
  if (name == "shard.all_reduce") {
    int out = 0;
    result.rc = MPI_Allreduce(&in, &out, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
    result.valuesOk = result.rc == MPI_SUCCESS && out == expect;
    result.note = "allreduce-sum=" + std::to_string(out);
    return result;
  }
  if (name == "shard.all_gather") {
    std::vector<int> gathered(static_cast<size_t>(world), 0);
    result.rc = MPI_Allgather(&in, 1, MPI_INT, gathered.data(), 1, MPI_INT,
                              MPI_COMM_WORLD);
    result.valuesOk = result.rc == MPI_SUCCESS;
    std::string order;
    for (int slot = 0; slot < world; ++slot) {
      if (gathered[static_cast<size_t>(slot)] != slot + 1)
        result.valuesOk = false;
      if (!order.empty())
        order.push_back(',');
      order += std::to_string(gathered[static_cast<size_t>(slot)]);
    }
    result.note = "allgather-order=" + order;
    return result;
  }
  std::vector<int> send(static_cast<size_t>(world), in);
  int recv = 0;
  result.rc = MPI_Reduce_scatter_block(send.data(), &recv, 1, MPI_INT, MPI_SUM,
                                       MPI_COMM_WORLD);
  result.valuesOk = result.rc == MPI_SUCCESS && recv == expect;
  result.note = "reducescatter-shard=" + std::to_string(recv);
  return result;
}

int runModule(ModuleOp module) {
  int world = 0;
  MPI_Comm_size(MPI_COMM_WORLD, &world);
  bool any = false;
  bool rejectedApiOnly = false;

  for (func::FuncOp func : module.getOps<func::FuncOp>()) {
    s2c2::exec::HBGraph graph;
    s2c2::exec::buildHbD(func, graph);
    bool sawOp = false;
    func.walk([&](Operation *op) {
      if (s2c2::exec::isV0Collective(op))
        sawOp = true;
    });
    if (!sawOp)
      continue;
    any = true;
    s2c2::exec::CollectiveMatch matched =
        s2c2::exec::matchCollectiveInstances(func);
    if (matched.faultOp || matched.instances.empty()) {
      say(llvm::errs(), "error: runtime participants do not match the mesh");
      return 1;
    }
    for (const s2c2::exec::CollectiveInstance &instance : matched.instances) {
      int64_t mesh = static_cast<int64_t>(instance.participants.size());
      if (mesh <= 0 || world != mesh) {
        say(llvm::errs(), "error: runtime world does not match the mesh");
        return 1;
      }
      std::vector<int64_t> participants;
      for (const auto &participant : instance.participants)
        participants.push_back(participant.rank);
      llvm::sort(participants);
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
      req.collective = instance.kind.str();
      req.participants = participants;
      req.tokenIsSched = true;
      req.inputBefore = true;
      req.resultAfter = true;
      req.readsAfter = true;

      bool inputBefore = true;
      bool resultAfter = true;
      bool readsAfter = true;
      bool tokens = true;
      for (const auto &participant : instance.participants) {
        bool in = false, result = false, reads = false;
        if (!tokenIsSched(participant.collective) ||
            !hbHolds(func, participant.collective, participant.rank, graph, in,
                     result, reads)) {
          tokens = tokens && tokenIsSched(participant.collective);
          inputBefore = inputBefore && in;
          resultAfter = resultAfter && result;
          readsAfter = readsAfter && reads;
          if (!tokenIsSched(participant.collective)) {
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

      WitnessValue witness = runWitness(instance.kind, static_cast<int>(world));
      RuntimeEvent event;
      event.participants = participants;
      event.tokenIsSched = tokens;
      event.inputBefore = inputBefore;
      event.resultAfter = resultAfter;
      event.readsAfter = readsAfter;
      event.mpiOk = witness.rc == MPI_SUCCESS && witness.valuesOk;
      if (!witness.valuesOk) {
        say(llvm::errs(), "error: runtime witness value mismatch");
        return 1;
      }
      if (witness.rc != MPI_SUCCESS || !eventSatisfies(event, req)) {
        say(llvm::errs(), "error: runtime event breaks HB_D");
        return 1;
      }

      std::string ranks;
      for (int64_t rank : participants) {
        if (!ranks.empty())
          ranks.push_back(',');
        ranks += std::to_string(rank);
      }
      say(llvm::outs(),
          "func @" + req.func + " collective " + req.collective +
              " participants=" + ranks +
              " token=!sched.token hb-d=satisfied mpi=ok instance mesh=@" +
              instance.mesh.str() +
              " callsite=" + std::to_string(instance.callsite) + " " +
              witness.note);
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
    say(llvm::outs(), "tensor-runtime no");

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
