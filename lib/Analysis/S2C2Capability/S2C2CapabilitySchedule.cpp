//===- S2C2CapabilitySchedule.cpp - Capability → schedule ---------*- C++ -*-===//
//
// Phase 3A. CapabilityProfile is compiler decision input, not an archive.
// Query prints pair cells. Schedule keeps or serializes 2-task concurrent
// groups. Does not invent sibling HB, break StageOrder, or change Cost.
//
//===----------------------------------------------------------------------===//

#include "s2c2/Comm/CommDialect.h"
#include "s2c2/Comm/CommOps.h"
#include "s2c2/Compute/ComputeDialect.h"
#include "s2c2/Compute/ComputeOps.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleDialect.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageDialect.h"
#include "s2c2/Storage/StorageTypes.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Visitors.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"

#include <optional>
#include <string>
#include <utility>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2CAPABILITYQUERY
#define GEN_PASS_DEF_S2C2CAPABILITYSCHEDULE
#include "s2c2/S2C2Passes.h.inc"

using comm::CopyOp;
using comm::StreamOp;
using comp::ElemwiseKind;
using comp::ElemwiseOp;
using comp::GatedMLPOp;
using comp::MatmulOp;
using sched::ConcurrentOp;
using sched::OverlapOp;
using sched::TaskOp;
using sched::YieldOp;
using stor::BufferType;
using stor::Space;

namespace {
struct CapCell {
  std::string relation = "underdetermined";
  std::string constraint = "none";
  std::string confidence = "unknown";
};

struct CapCatalog {
  llvm::StringMap<CapCell> pairs;
};

enum class Role { Unknown, Compute, Silu, Gemm, HtoD, DtoH };

static bool isHostLike(Space space) {
  return space == Space::Host || space == Space::SSD;
}

static bool isDeviceLike(Space space) {
  return space == Space::HBM || space == Space::DRAM || space == Space::SRAM ||
         space == Space::CIM;
}

static std::optional<Space> bufferSpace(Value value) {
  if (auto ty = dyn_cast<BufferType>(value.getType()))
    return ty.getSpace();
  return std::nullopt;
}

static void addCell(CapCatalog &cat, StringRef pair, StringRef relation,
                    StringRef constraint, StringRef confidence) {
  CapCell cell;
  cell.relation = relation.str();
  cell.constraint = constraint.str();
  cell.confidence = confidence.str();
  cat.pairs[pair] = std::move(cell);
}

static void loadBuiltinRtx4090(CapCatalog &cat) {
  addCell(cat, "C||HtoD", "parallel", "none", "measured");
  addCell(cat, "C||DtoH", "parallel", "none", "measured");
  addCell(cat, "HtoD||DtoH", "mixed", "none", "measured");
  addCell(cat, "HtoD||HtoD", "serial", "copy_engine_contention", "measured");
  addCell(cat, "DtoH||DtoH", "serial", "copy_engine_contention", "measured");
  addCell(cat, "C||C", "serial", "resource_contention", "measured");
  addCell(cat, "C_silu||C_gemm", "serial", "resource_contention",
          "arm_specific");
}

static void loadBuiltinNpuDemo(CapCatalog &cat) {
  addCell(cat, "C||HtoD", "parallel", "none", "inferred");
  addCell(cat, "C||DtoH", "parallel", "none", "inferred");
  addCell(cat, "HtoD||DtoH", "serial", "copy_engine_contention", "inferred");
  addCell(cat, "C||C", "parallel", "none", "inferred");
  addCell(cat, "C_silu||C_gemm", "parallel", "none", "inferred");
}

static StringRef canonicalDevice(StringRef device) {
  if (device.contains_insensitive("4090") ||
      device.contains_insensitive("rtx4090") ||
      device.contains_insensitive("sm89"))
    return "rtx4090";
  if (device.contains_insensitive("npu"))
    return "npu-demo";
  return device;
}

static bool hardwareMatches(StringRef hardwareId, StringRef device) {
  StringRef canon = canonicalDevice(device);
  if (canon == "rtx4090")
    return hardwareId.contains_insensitive("4090") ||
           hardwareId.contains_insensitive("sm89");
  if (canon == "npu-demo")
    return hardwareId.contains_insensitive("npu");
  return hardwareId.contains_insensitive(device);
}

static LogicalResult loadJsonl(StringRef path, StringRef device,
                               CapCatalog &cat) {
  auto fileOr = llvm::MemoryBuffer::getFile(path);
  if (!fileOr) {
    llvm::errs() << "s2c2-capability: cannot read profile " << path << "\n";
    return failure();
  }
  StringRef text = fileOr.get()->getBuffer();
  while (!text.empty()) {
    auto [line, rest] = text.split('\n');
    text = rest;
    line = line.trim();
    if (line.empty())
      continue;
    auto parsed = llvm::json::parse(line);
    if (!parsed) {
      llvm::errs() << "s2c2-capability: invalid JSONL in " << path << "\n";
      return failure();
    }
    auto *obj = parsed->getAsObject();
    if (!obj)
      continue;
    auto kind = obj->getString("record_kind");
    auto pair = obj->getString("pair");
    auto hid = obj->getString("hardware_id");
    auto rel = obj->getString("pair_relation");
    if (!kind || *kind != "pair" || !pair || pair->empty() || !rel)
      continue;
    if (hid && !hardwareMatches(*hid, device))
      continue;
    CapCell cell;
    cell.relation = rel->str();
    if (auto c = obj->getString("observed_constraint"))
      cell.constraint = c->str();
    if (auto c = obj->getString("confidence"))
      cell.confidence = c->str();
    cat.pairs[*pair] = std::move(cell);
  }
  return success();
}

static LogicalResult loadCatalog(StringRef device, StringRef profilePath,
                                 CapCatalog &cat) {
  StringRef canon = canonicalDevice(device);
  if (canon == "rtx4090")
    loadBuiltinRtx4090(cat);
  else if (canon == "npu-demo")
    loadBuiltinNpuDemo(cat);
  if (!profilePath.empty() && failed(loadJsonl(profilePath, device, cat)))
    return failure();
  return success();
}

static CapCell lookupPair(const CapCatalog &cat, StringRef pair) {
  auto it = cat.pairs.find(pair);
  if (it != cat.pairs.end())
    return it->second;
  if (pair == "C_silu||C_gemm") {
    auto fallback = cat.pairs.find("C||C");
    if (fallback != cat.pairs.end())
      return fallback->second;
  }
  return CapCell{};
}

static Role parseRole(StringRef raw) {
  std::string lower = raw.lower();
  StringRef s(lower);
  if (s.contains("htod") || s.contains("host_to_device"))
    return Role::HtoD;
  if (s.contains("dtoh") || s.contains("device_to_host"))
    return Role::DtoH;
  if (s.contains("silu") || s.contains("gelu") || s.contains("relu"))
    return Role::Silu;
  if (s.contains("gemm") || s.contains("matmul"))
    return Role::Gemm;
  if (s.contains("compute") || s == "c" || s.contains("comp."))
    return Role::Compute;
  return Role::Unknown;
}

static std::string pairFromRoles(Role a, Role b) {
  auto isCompute = [](Role r) {
    return r == Role::Compute || r == Role::Silu || r == Role::Gemm;
  };
  if ((a == Role::Silu && b == Role::Gemm) ||
      (a == Role::Gemm && b == Role::Silu))
    return "C_silu||C_gemm";
  if (isCompute(a) && isCompute(b))
    return "C||C";
  if ((isCompute(a) && b == Role::HtoD) || (isCompute(b) && a == Role::HtoD))
    return "C||HtoD";
  if ((isCompute(a) && b == Role::DtoH) || (isCompute(b) && a == Role::DtoH))
    return "C||DtoH";
  if ((a == Role::HtoD && b == Role::DtoH) ||
      (a == Role::DtoH && b == Role::HtoD))
    return "HtoD||DtoH";
  if (a == Role::HtoD && b == Role::HtoD)
    return "HtoD||HtoD";
  if (a == Role::DtoH && b == Role::DtoH)
    return "DtoH||DtoH";
  return {};
}

struct RegionClass {
  bool compute = false;
  bool silu = false;
  bool gemm = false;
  bool htod = false;
  bool dtoh = false;
  bool d2d = false;
};

static void classifyOp(Operation *op, RegionClass &cls) {
  if (isa<ElemwiseOp>(op)) {
    cls.compute = true;
    auto kind = cast<ElemwiseOp>(op).getKind();
    if (kind == ElemwiseKind::SILU || kind == ElemwiseKind::GELU ||
        kind == ElemwiseKind::RELU)
      cls.silu = true;
  }
  if (isa<MatmulOp>(op)) {
    cls.compute = true;
    cls.gemm = true;
  }
  if (isa<GatedMLPOp>(op)) {
    cls.compute = true;
    cls.silu = true;
    cls.gemm = true;
  }
  Value src, dst;
  if (auto copy = dyn_cast<CopyOp>(op)) {
    src = copy.getSrc();
    dst = copy.getDst();
  } else if (auto stream = dyn_cast<StreamOp>(op)) {
    src = stream.getSrc();
    dst = stream.getDst();
  } else {
    return;
  }
  auto srcSpace = bufferSpace(src);
  auto dstSpace = bufferSpace(dst);
  if (!srcSpace || !dstSpace)
    return;
  if (isHostLike(*srcSpace) && isDeviceLike(*dstSpace))
    cls.htod = true;
  else if (isDeviceLike(*srcSpace) && isHostLike(*dstSpace))
    cls.dtoh = true;
  else if (isDeviceLike(*srcSpace) && isDeviceLike(*dstSpace))
    cls.d2d = true;
}

static RegionClass classifyRegion(Region &region) {
  RegionClass cls;
  region.walk([&](Operation *op) { classifyOp(op, cls); });
  return cls;
}

static Role roleOf(const RegionClass &cls) {
  if (cls.d2d)
    return Role::Unknown;
  int nXfer = (int)cls.htod + (int)cls.dtoh;
  int nComp = (int)cls.compute;
  if (nXfer && nComp)
    return Role::Unknown;
  if (cls.htod && !cls.dtoh)
    return Role::HtoD;
  if (cls.dtoh && !cls.htod)
    return Role::DtoH;
  if (cls.silu && !cls.gemm)
    return Role::Silu;
  if (cls.gemm && !cls.silu)
    return Role::Gemm;
  if (cls.compute)
    return Role::Compute;
  return Role::Unknown;
}

static std::string classifyPair(Region &a, Region &b) {
  return pairFromRoles(roleOf(classifyRegion(a)), roleOf(classifyRegion(b)));
}

static void printQueryJson(StringRef device, StringRef pair, const CapCell &cell,
                           StringRef via) {
  llvm::json::Object obj;
  obj["device"] = device.str();
  obj["pair"] = pair.str();
  obj["pair_relation"] = cell.relation;
  obj["observed_constraint"] = cell.constraint;
  obj["confidence"] = cell.confidence;
  obj["via"] = via.str();
  llvm::json::Value value(std::move(obj));
  llvm::errs() << "capability-query " << value << "\n";
}

static bool shouldSerialize(const CapCell &cell) {
  return cell.relation == "serial";
}

static void flattenConcurrent(ConcurrentOp conc) {
  Block &body = conc.getBody().front();
  auto yield = dyn_cast<YieldOp>(body.getTerminator());
  if (!yield)
    return;
  SmallVector<TaskOp> tasks(body.getOps<TaskOp>());
  Operation *insertPt = conc.getOperation();
  for (TaskOp task : tasks)
    task->moveBefore(insertPt);
  conc.replaceAllUsesWith(yield.getOperands());
  conc.erase();
}

static void flattenOverlap(OverlapOp ov) {
  Block &comm = ov.getCommunicate().front();
  Block &compute = ov.getCompute().front();
  auto yield = dyn_cast<YieldOp>(compute.getTerminator());
  if (!yield)
    return;
  Operation *insertPt = ov.getOperation();
  SmallVector<Operation *> commOps;
  for (Operation &op : comm.without_terminator())
    commOps.push_back(&op);
  for (Operation *op : commOps)
    op->moveBefore(insertPt);
  SmallVector<Operation *> computeOps;
  for (Operation &op : compute.without_terminator())
    computeOps.push_back(&op);
  for (Operation *op : computeOps)
    op->moveBefore(insertPt);
  ov.replaceAllUsesWith(yield.getOperands());
  ov.erase();
}

static void walkAndQuery(ModuleOp module, StringRef device,
                         const CapCatalog &cat) {
  module.walk([&](ConcurrentOp conc) {
    SmallVector<TaskOp> tasks(conc.getBody().front().getOps<TaskOp>());
    if (tasks.size() != 2)
      return;
    std::string pair = classifyPair(tasks[0].getBody(), tasks[1].getBody());
    if (pair.empty())
      return;
    printQueryJson(device, pair, lookupPair(cat, pair), "concurrent");
  });
  module.walk([&](OverlapOp ov) {
    std::string pair = classifyPair(ov.getCompute(), ov.getCommunicate());
    if (pair.empty())
      return;
    printQueryJson(device, pair, lookupPair(cat, pair), "overlap");
  });
}

static void applySchedule(ModuleOp module, StringRef device,
                          const CapCatalog &cat) {
  SmallVector<ConcurrentOp> concs;
  module.walk([&](ConcurrentOp conc) { concs.push_back(conc); });
  for (ConcurrentOp conc : concs) {
    SmallVector<TaskOp> tasks(conc.getBody().front().getOps<TaskOp>());
    if (tasks.size() != 2)
      continue;
    std::string pair = classifyPair(tasks[0].getBody(), tasks[1].getBody());
    if (pair.empty())
      continue;
    CapCell cell = lookupPair(cat, pair);
    bool serialize = shouldSerialize(cell);
    llvm::errs() << "capability-schedule device=" << device << " pair=" << pair
                 << " relation=" << cell.relation
                 << " observed_constraint=" << cell.constraint
                 << " decision=" << (serialize ? "serialize" : "keep") << "\n";
    if (serialize)
      flattenConcurrent(conc);
  }

  SmallVector<OverlapOp> overlaps;
  module.walk([&](OverlapOp ov) { overlaps.push_back(ov); });
  for (OverlapOp ov : overlaps) {
    std::string pair = classifyPair(ov.getCompute(), ov.getCommunicate());
    if (pair.empty())
      continue;
    CapCell cell = lookupPair(cat, pair);
    bool serialize = shouldSerialize(cell);
    llvm::errs() << "capability-schedule device=" << device << " pair=" << pair
                 << " relation=" << cell.relation
                 << " observed_constraint=" << cell.constraint
                 << " decision=" << (serialize ? "serialize" : "keep") << "\n";
    if (serialize)
      flattenOverlap(ov);
  }
  llvm::errs() << "capability-schedule device=" << device
               << " semantics=unchanged v3=not-claimed cost=unchanged\n";
}

struct S2C2CapabilityQuery
    : impl::S2C2CapabilityQueryBase<S2C2CapabilityQuery> {
  using impl::S2C2CapabilityQueryBase<
      S2C2CapabilityQuery>::S2C2CapabilityQueryBase;

  void runOnOperation() override {
    CapCatalog cat;
    if (failed(loadCatalog(device, profilePath, cat))) {
      signalPassFailure();
      return;
    }
    if (!producer.empty() || !consumer.empty()) {
      std::string pair = pairFromRoles(parseRole(producer), parseRole(consumer));
      if (pair.empty()) {
        llvm::errs() << "s2c2-capability-query: unsupported producer/consumer\n";
        signalPassFailure();
        return;
      }
      printQueryJson(device, pair, lookupPair(cat, pair), "catalog");
    }
    walkAndQuery(getOperation(), device, cat);
  }
};

struct S2C2CapabilitySchedule
    : impl::S2C2CapabilityScheduleBase<S2C2CapabilitySchedule> {
  using impl::S2C2CapabilityScheduleBase<
      S2C2CapabilitySchedule>::S2C2CapabilityScheduleBase;

  void runOnOperation() override {
    CapCatalog cat;
    if (failed(loadCatalog(device, profilePath, cat))) {
      signalPassFailure();
      return;
    }
    applySchedule(getOperation(), device, cat);
  }
};
} // namespace
} // namespace mlir::s2c2
