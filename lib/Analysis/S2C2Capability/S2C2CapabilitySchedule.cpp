//===- S2C2CapabilitySchedule.cpp - Capability → schedule ---------*- C++ -*-===//
//
// Phase 3A. CapabilityProfile is compiler decision input, not an archive.
// Query prints pair cells plus applicability. A pair may have several
// size-banded records; lookup picks the narrowest covering size_range.
// Schedule serializes only when applicable=yes, pair_relation=serial,
// and rewrite_license is not no. Does not invent sibling HB, break
// StageOrder, promote arm_specific evidence to a global rule, or
// change Cost.
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
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Visitors.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
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
enum class Applicability { Yes, No, Unknown };

struct CapCell {
  std::string relation = "underdetermined";
  std::string constraint = "none";
  std::string confidence = "unknown";
  std::string regime = "underdetermined";
  std::string sizeRange = "n/a";
  std::string synchronization = "named-nonblocking";
  std::string note;
  std::string phaseBand;
  bool rewriteLicense = true;
};

struct QueryContext {
  std::string synchronization = "named-nonblocking";
  std::optional<int64_t> sizeBytes;
};

struct CapCatalog {
  llvm::StringMap<SmallVector<CapCell, 4>> pairs;
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

static void parseNoteOverlay(CapCell &cell) {
  StringRef note = cell.note;
  while (!note.empty()) {
    auto [tok, rest] = note.split(';');
    note = rest;
    auto [key, val] = tok.split('=');
    key = key.trim();
    val = val.trim();
    if (key.equals_insensitive("phase_band"))
      cell.phaseBand = val.str();
    else if (key.equals_insensitive("rewrite_license"))
      cell.rewriteLicense = val.equals_insensitive("yes") ||
                            val.equals_insensitive("true");
  }
}

static void addCell(CapCatalog &cat, StringRef pair, StringRef relation,
                    StringRef constraint, StringRef confidence, StringRef regime,
                    StringRef sizeRange, StringRef synchronization) {
  CapCell cell;
  cell.relation = relation.str();
  cell.constraint = constraint.str();
  cell.confidence = confidence.str();
  cell.regime = regime.str();
  cell.sizeRange = sizeRange.str();
  cell.synchronization = synchronization.str();
  parseNoteOverlay(cell);
  cat.pairs[pair].push_back(std::move(cell));
}

static void loadBuiltinRtx4090(CapCatalog &cat) {
  addCell(cat, "C||HtoD", "parallel", "none", "measured", "bandwidth",
          "16MiB..256MiB", "named-nonblocking");
  addCell(cat, "C||DtoH", "parallel", "none", "measured", "bandwidth",
          "16MiB..256MiB", "named-nonblocking");
  addCell(cat, "HtoD||DtoH", "mixed", "none", "measured", "bandwidth",
          "16MiB..256MiB", "named-nonblocking");
  addCell(cat, "HtoD||HtoD", "serial", "copy_engine_contention", "measured",
          "bandwidth", "16MiB..256MiB", "named-nonblocking");
  addCell(cat, "DtoH||DtoH", "serial", "copy_engine_contention", "measured",
          "bandwidth", "16MiB..256MiB", "named-nonblocking");
  addCell(cat, "C||C", "serial", "resource_contention", "measured", "occupancy",
          "n/a", "named-nonblocking");
  addCell(cat, "C_silu||C_gemm", "serial", "resource_contention", "arm_specific",
          "occupancy", "n/a", "named-nonblocking");
}

static void loadBuiltinNpuDemo(CapCatalog &cat) {
  addCell(cat, "C||HtoD", "parallel", "none", "inferred", "bandwidth",
          "synthetic", "named-nonblocking");
  addCell(cat, "C||DtoH", "parallel", "none", "inferred", "bandwidth",
          "synthetic", "named-nonblocking");
  addCell(cat, "HtoD||DtoH", "serial", "copy_engine_contention", "inferred",
          "bandwidth", "synthetic", "named-nonblocking");
  addCell(cat, "C||C", "parallel", "none", "inferred", "occupancy", "synthetic",
          "named-nonblocking");
  addCell(cat, "C_silu||C_gemm", "parallel", "none", "inferred", "occupancy",
          "synthetic", "named-nonblocking");
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
  llvm::StringSet<> replacedInFile;
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
    if (auto c = obj->getString("regime"))
      cell.regime = c->str();
    if (auto c = obj->getString("size_range"))
      cell.sizeRange = c->str();
    if (auto c = obj->getString("synchronization"))
      cell.synchronization = c->str();
    if (auto c = obj->getString("note"))
      cell.note = c->str();
    parseNoteOverlay(cell);
    // JSONL replaces builtin cells for this pair, but keeps every
    // size-banded record that follows for the same pair.
    if (replacedInFile.insert(*pair).second)
      cat.pairs[*pair].clear();
    cat.pairs[*pair].push_back(std::move(cell));
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

// Size-aware lookup is defined after parseSizeRange.
static CapCell lookupPair(const CapCatalog &cat, StringRef pair,
                          std::optional<int64_t> sizeBytes);

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

static std::optional<int64_t> payloadBytes(Type type) {
  auto shaped = dyn_cast<ShapedType>(type);
  if (!shaped || !shaped.hasStaticShape())
    return std::nullopt;
  Type elem = shaped.getElementType();
  if (!elem.isIntOrFloat())
    return std::nullopt;
  return shaped.getNumElements() * (int64_t)(elem.getIntOrFloatBitWidth() / 8);
}

static void accumulateSizes(Region &region, std::optional<int64_t> &xferBytes,
                            std::optional<int64_t> &computeBytes) {
  auto takeMax = [](std::optional<int64_t> &slot, std::optional<int64_t> bytes) {
    if (!bytes)
      return;
    slot = slot ? std::max(*slot, *bytes) : bytes;
  };
  region.walk([&](Operation *op) {
    if (auto copy = dyn_cast<CopyOp>(op)) {
      if (auto ty = dyn_cast<BufferType>(copy.getSrc().getType()))
        takeMax(xferBytes, payloadBytes(ty.getSourceType()));
    } else if (auto stream = dyn_cast<StreamOp>(op)) {
      if (auto ty = dyn_cast<BufferType>(stream.getSrc().getType()))
        takeMax(xferBytes, payloadBytes(ty.getSourceType()));
    }
    if (isa<ElemwiseOp, MatmulOp, GatedMLPOp>(op)) {
      for (Type t : op->getOperandTypes())
        takeMax(computeBytes, payloadBytes(t));
      for (Type t : op->getResultTypes())
        takeMax(computeBytes, payloadBytes(t));
    }
  });
}

static QueryContext contextFromRegions(Region &a, Region &b, StringRef pair) {
  QueryContext ctx;
  std::optional<int64_t> xfer, compute;
  accumulateSizes(a, xfer, compute);
  accumulateSizes(b, xfer, compute);
  bool transferPair = pair.contains("HtoD") || pair.contains("DtoH");
  ctx.sizeBytes = transferPair ? xfer : compute;
  return ctx;
}

static bool syncMatches(StringRef recordSync, StringRef ctxSync) {
  auto norm = [](StringRef s) {
    s = s.trim();
    if (s.equals_insensitive("n/a") || s.equals_insensitive("none") ||
        s.equals_insensitive("unmeasured") || s.empty())
      return StringRef("n/a");
    return s;
  };
  StringRef rec = norm(recordSync);
  StringRef ctx = norm(ctxSync);
  if (rec == "n/a")
    return true;
  return rec.equals_insensitive(ctx);
}

static std::optional<int64_t> parseByteToken(StringRef tok) {
  tok = tok.trim();
  int64_t mul = 1;
  if (tok.ends_with_insensitive("mib")) {
    mul = 1024LL * 1024LL;
    tok = tok.drop_back(3).trim();
  } else if (tok.ends_with_insensitive("mb")) {
    mul = 1000LL * 1000LL;
    tok = tok.drop_back(2).trim();
  } else if (tok.ends_with_insensitive("kib")) {
    mul = 1024LL;
    tok = tok.drop_back(3).trim();
  } else if (tok.ends_with_insensitive("bytes")) {
    tok = tok.drop_back(5).trim();
  }
  int64_t n = 0;
  if (tok.getAsInteger(10, n) || n < 0)
    return std::nullopt;
  return n * mul;
}

enum class SizeSpecKind { Unconstrained, Range, Unparsed };

struct SizeSpec {
  SizeSpecKind kind = SizeSpecKind::Unparsed;
  int64_t lo = 0;
  int64_t hi = 0;
};

static SizeSpec parseSizeRange(StringRef raw) {
  SizeSpec spec;
  StringRef s = raw.trim();
  if (s.equals_insensitive("n/a") || s.equals_insensitive("none") ||
      s.equals_insensitive("unmeasured") || s.empty()) {
    spec.kind = SizeSpecKind::Unconstrained;
    return spec;
  }
  auto [left, right] = s.split("..");
  if (right.empty())
    return spec;
  auto lo = parseByteToken(left);
  auto hi = parseByteToken(right);
  if (!lo || !hi)
    return spec;
  spec.kind = SizeSpecKind::Range;
  spec.lo = *lo;
  spec.hi = *hi;
  return spec;
}

static CapCell lookupPair(const CapCatalog &cat, StringRef pair,
                          std::optional<int64_t> sizeBytes) {
  auto it = cat.pairs.find(pair);
  if (it == cat.pairs.end() || it->second.empty())
    return CapCell{};

  const SmallVector<CapCell, 4> &cells = it->second;
  if (!sizeBytes) {
    if (cells.size() == 1)
      return cells.front();
    const CapCell *unconstrained = nullptr;
    unsigned nUnconstrained = 0;
    for (const CapCell &cell : cells) {
      if (parseSizeRange(cell.sizeRange).kind == SizeSpecKind::Unconstrained) {
        unconstrained = &cell;
        ++nUnconstrained;
      }
    }
    if (nUnconstrained == 1)
      return *unconstrained;
    if (nUnconstrained > 1)
      return *unconstrained;
    CapCell many;
    many.relation = "underdetermined";
    many.confidence = "measured";
    many.regime = cells.front().regime;
    many.sizeRange = "multiple";
    many.synchronization = cells.front().synchronization;
    many.rewriteLicense = false;
    return many;
  }

  const CapCell *best = nullptr;
  bool bestUnconstrained = true;
  int64_t bestSpan = 0;
  for (const CapCell &cell : cells) {
    SizeSpec spec = parseSizeRange(cell.sizeRange);
    bool unconstrained = spec.kind == SizeSpecKind::Unconstrained;
    bool covers = unconstrained || (spec.kind == SizeSpecKind::Range &&
                                    *sizeBytes >= spec.lo &&
                                    *sizeBytes <= spec.hi);
    if (!covers)
      continue;
    int64_t span = unconstrained ? 0 : spec.hi - spec.lo;
    // Prefer a closed size band over a device-wide n/a cell.
    if (!best || (bestUnconstrained && !unconstrained) ||
        (!unconstrained && !bestUnconstrained && span < bestSpan)) {
      best = &cell;
      bestUnconstrained = unconstrained;
      bestSpan = span;
    }
  }
  if (best)
    return *best;
  // One ranged cell still describes the pair; applicability then
  // reports no/unknown. Several bands with no covering range are an
  // unmeasured size, not a last-write-wins guess.
  if (cells.size() == 1)
    return cells.front();
  return CapCell{};
}

static Applicability isApplicable(const CapCell &cell, const QueryContext &ctx) {
  // Destructive decisions require measured evidence. arm_specific / inferred
  // remain queryable but are not global compiler rules.
  if (!StringRef(cell.confidence).equals_insensitive("measured"))
    return Applicability::No;
  if (!syncMatches(cell.synchronization, ctx.synchronization))
    return Applicability::No;
  SizeSpec spec = parseSizeRange(cell.sizeRange);
  if (spec.kind == SizeSpecKind::Unconstrained)
    return Applicability::Yes;
  if (spec.kind == SizeSpecKind::Unparsed || !ctx.sizeBytes)
    return Applicability::Unknown;
  if (*ctx.sizeBytes >= spec.lo && *ctx.sizeBytes <= spec.hi)
    return Applicability::Yes;
  return Applicability::No;
}

static StringRef applicabilityStr(Applicability app) {
  switch (app) {
  case Applicability::Yes:
    return "yes";
  case Applicability::No:
    return "no";
  case Applicability::Unknown:
    return "unknown";
  }
  return "unknown";
}

static void setApplicableJson(llvm::json::Object &obj, Applicability app) {
  switch (app) {
  case Applicability::Yes:
    obj["applicable"] = true;
    break;
  case Applicability::No:
    obj["applicable"] = false;
    break;
  case Applicability::Unknown:
    obj["applicable"] = "unknown";
    break;
  }
}

static void printQueryJson(StringRef device, StringRef pair, const CapCell &cell,
                           StringRef via, Applicability app) {
  llvm::json::Object obj;
  setApplicableJson(obj, app);
  obj["device"] = device.str();
  obj["pair"] = pair.str();
  obj["pair_relation"] = cell.relation;
  obj["observed_constraint"] = cell.constraint;
  obj["confidence"] = cell.confidence;
  obj["regime"] = cell.regime;
  obj["size_range"] = cell.sizeRange;
  obj["synchronization"] = cell.synchronization;
  if (!cell.phaseBand.empty())
    obj["phase_band"] = cell.phaseBand;
  obj["rewrite_license"] = cell.rewriteLicense;
  obj["via"] = via.str();
  llvm::json::Value value(std::move(obj));
  llvm::errs() << "capability-query " << value << "\n";
}

static bool shouldSerialize(const CapCell &cell, Applicability app) {
  return app == Applicability::Yes && cell.relation == "serial" &&
         cell.rewriteLicense;
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
    QueryContext ctx = contextFromRegions(tasks[0].getBody(), tasks[1].getBody(),
                                          pair);
    CapCell cell = lookupPair(cat, pair, ctx.sizeBytes);
    printQueryJson(device, pair, cell, "concurrent", isApplicable(cell, ctx));
  });
  module.walk([&](OverlapOp ov) {
    std::string pair = classifyPair(ov.getCompute(), ov.getCommunicate());
    if (pair.empty())
      return;
    QueryContext ctx =
        contextFromRegions(ov.getCompute(), ov.getCommunicate(), pair);
    CapCell cell = lookupPair(cat, pair, ctx.sizeBytes);
    printQueryJson(device, pair, cell, "overlap", isApplicable(cell, ctx));
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
    QueryContext ctx = contextFromRegions(tasks[0].getBody(), tasks[1].getBody(),
                                          pair);
    CapCell cell = lookupPair(cat, pair, ctx.sizeBytes);
    Applicability app = isApplicable(cell, ctx);
    bool serialize = shouldSerialize(cell, app);
    llvm::errs() << "capability-schedule device=" << device << " pair=" << pair
                 << " relation=" << cell.relation
                 << " observed_constraint=" << cell.constraint
                 << " confidence=" << cell.confidence
                 << " size_range=" << cell.sizeRange
                 << " rewrite_license=" << (cell.rewriteLicense ? "yes" : "no")
                 << " applicable=" << applicabilityStr(app)
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
    QueryContext ctx =
        contextFromRegions(ov.getCompute(), ov.getCommunicate(), pair);
    CapCell cell = lookupPair(cat, pair, ctx.sizeBytes);
    Applicability app = isApplicable(cell, ctx);
    bool serialize = shouldSerialize(cell, app);
    llvm::errs() << "capability-schedule device=" << device << " pair=" << pair
                 << " relation=" << cell.relation
                 << " observed_constraint=" << cell.constraint
                 << " confidence=" << cell.confidence
                 << " size_range=" << cell.sizeRange
                 << " rewrite_license=" << (cell.rewriteLicense ? "yes" : "no")
                 << " applicable=" << applicabilityStr(app)
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
      QueryContext ctx;
      CapCell cell = lookupPair(cat, pair, ctx.sizeBytes);
      printQueryJson(device, pair, cell, "catalog", isApplicable(cell, ctx));
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
