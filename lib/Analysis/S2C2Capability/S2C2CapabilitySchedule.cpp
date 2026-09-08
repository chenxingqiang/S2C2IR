//===- S2C2CapabilitySchedule.cpp - Capability → schedule ---------*- C++ -*-===//
//
// Phase 3A + 3D + 3E/3F. CapabilityProfile is compiler decision input,
// not an archive. Query prints pair cells plus applicability. A pair
// may have several size-banded records; lookup picks the narrowest
// covering size_range. Schedule serializes only when applicable=yes,
// pair_relation=serial, and rewrite_license is not no.
//
// Workload candidates print KEEP (storage/communication overlap),
// FLATTEN (licensed compute contention), or PRESERVE (no evidence).
// C||Storage is SSD↔Host beside compute; inferred, not a new grid.
//
// Phase 3G walks stor.materialize / stor.transfer and prints a
// hierarchy plan: MATERIALIZE / PREFETCH / TRANSFER / KEEP_RESIDENCY
// / PRESERVE. Inferred overlap authorizes PREFETCH (KEEP) only.
// KEEP_RESIDENCY is not a rematerialize rewrite.
//
// Generic rewrite pipeline (one inhabitant: concurrent→serial):
//   RewriteCandidate → EvidenceQuery → Applicability
//     → RewriteLicense → Rewrite → Verifier
// Pair kind is selected by evidence, not by the flatten.
// Does not invent sibling HB, break StageOrder, promote arm_specific
// evidence to a global rule, or change Cost.
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
#include "s2c2/Storage/StorageOps.h"
#include "s2c2/Storage/StorageTypes.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Visitors.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <optional>
#include <string>
#include <utility>

#ifndef S2C2_SOURCE_DIR
#define S2C2_SOURCE_DIR ""
#endif

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2CAPABILITYQUERY
#define GEN_PASS_DEF_S2C2CAPABILITYSCHEDULE
#define GEN_PASS_DEF_S2C2EVIDENCEBOUNDEDSCHEDULE
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
using stor::MaterializeOp;
using stor::Space;
using stor::TransferOp;

namespace {
llvm::cl::opt<std::string> clS2C2Profile(
    "profile",
    llvm::cl::desc("S2C2 compiler profile: rtx4090, 910B, unknown, or a "
                   "compiler-profile JSON path"),
    llvm::cl::ValueRequired, llvm::cl::init(""));
llvm::cl::opt<std::string> clS2C2Evidence(
    "evidence",
    llvm::cl::desc(
        "S2C2 evidence JSONL override (compiler catalog, not a benchmark log)"),
    llvm::cl::ValueRequired, llvm::cl::init(""));

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

enum class Role { Unknown, Compute, Silu, Gemm, HtoD, DtoH, Storage };

enum class DecisionKind { Keep, Flatten, Preserve };

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
                    StringRef sizeRange, StringRef synchronization,
                    bool rewriteLicense = true) {
  CapCell cell;
  cell.relation = relation.str();
  cell.constraint = constraint.str();
  cell.confidence = confidence.str();
  cell.regime = regime.str();
  cell.sizeRange = sizeRange.str();
  cell.synchronization = synchronization.str();
  cell.rewriteLicense = rewriteLicense;
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
  // Inferred overlap class, not a new 4090 grid point: SSD↔Host
  // movement can run beside compute the same way C||HtoD can.
  addCell(cat, "C||Storage", "parallel", "none", "inferred", "bandwidth", "n/a",
          "named-nonblocking");
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

// Compiler-profile projection of
// docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl.
// Does not overwrite #69 capability.jsonl.
static void loadBuiltin910B(CapCatalog &cat) {
  addCell(cat, "C||C", "mixed", "none", "measured", "occupancy", "16MiB..48MiB",
          "named-nonblocking", /*rewriteLicense=*/false);
  addCell(cat, "C||C", "underdetermined", "none", "measured", "occupancy",
          "64MiB..127MiB", "named-nonblocking", /*rewriteLicense=*/false);
  addCell(cat, "C||C", "serial", "resource_contention", "measured", "occupancy",
          "128MiB..512MiB", "named-nonblocking", /*rewriteLicense=*/true);
  // Overlay projection is C||C only. Storage/HtoD overlap is inferred
  // KEEP, not a new 910B measurement and not #69.
  addCell(cat, "C||HtoD", "parallel", "none", "inferred", "bandwidth", "n/a",
          "named-nonblocking");
  addCell(cat, "C||DtoH", "parallel", "none", "inferred", "bandwidth", "n/a",
          "named-nonblocking");
  addCell(cat, "C||Storage", "parallel", "none", "inferred", "bandwidth", "n/a",
          "named-nonblocking");
}

static StringRef canonicalDevice(StringRef device) {
  if (device.contains_insensitive("4090") ||
      device.contains_insensitive("rtx4090") ||
      device.contains_insensitive("sm89"))
    return "rtx4090";
  if (device.contains_insensitive("npu"))
    return "npu-demo";
  if (device.equals_insensitive("unknown"))
    return "unknown";
  if (device.contains_insensitive("910b") ||
      device.contains_insensitive("ascend910b"))
    return "ascend910b:ascend";
  return device;
}

static bool hardwareMatches(StringRef hardwareId, StringRef device) {
  StringRef canon = canonicalDevice(device);
  if (canon == "rtx4090")
    return hardwareId.contains_insensitive("4090") ||
           hardwareId.contains_insensitive("sm89");
  if (canon == "npu-demo")
    return hardwareId.contains_insensitive("npu");
  if (canon == "ascend910b:ascend")
    return hardwareId.contains_insensitive("910b");
  if (canon == "unknown")
    return false;
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

struct ResolvedProfile {
  std::string name;
  std::string device;
  std::string evidenceDesc;
};

static bool looksLikePath(StringRef s) {
  if (s.contains(','))
    return false;
  return s.contains('/') || s.ends_with_insensitive(".json") ||
         s.ends_with_insensitive(".jsonl");
}

static std::string resolveExistingPath(StringRef path, StringRef relativeToDir) {
  if (path.empty())
    return {};
  if (llvm::sys::fs::exists(path))
    return path.str();
  llvm::SmallString<256> tmp;
  if (!relativeToDir.empty()) {
    llvm::sys::path::append(tmp, relativeToDir, path);
    if (llvm::sys::fs::exists(tmp))
      return std::string(tmp);
  }
  tmp.clear();
  llvm::sys::path::append(tmp, S2C2_SOURCE_DIR, path);
  if (llvm::sys::fs::exists(tmp))
    return std::string(tmp);
  return path.str();
}

static LogicalResult loadBuiltinEvidence(StringRef which, CapCatalog &cat) {
  if (which.equals_insensitive("rtx4090") || which.equals_insensitive("4090")) {
    loadBuiltinRtx4090(cat);
    return success();
  }
  if (which.equals_insensitive("910B") || which.equals_insensitive("910b") ||
      which.equals_insensitive("ascend910b")) {
    loadBuiltin910B(cat);
    return success();
  }
  if (which.equals_insensitive("npu-demo") || which.equals_insensitive("npu")) {
    loadBuiltinNpuDemo(cat);
    return success();
  }
  llvm::errs() << "s2c2-evidence-bounded-schedule: unknown builtin evidence "
               << which << "\n";
  return failure();
}

static LogicalResult loadInlineEvidence(const llvm::json::Array &arr,
                                        CapCatalog &cat) {
  for (const llvm::json::Value &item : arr) {
    const llvm::json::Object *obj = item.getAsObject();
    if (!obj)
      continue;
    auto pair = obj->getString("pair");
    auto rel = obj->getString("pair_relation");
    if (!pair || pair->empty() || !rel)
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
    if (auto b = obj->getBoolean("rewrite_license"))
      cell.rewriteLicense = *b;
    else if (auto s = obj->getString("rewrite_license"))
      cell.rewriteLicense = s->equals_insensitive("yes") ||
                            s->equals_insensitive("true");
    cat.pairs[*pair].push_back(std::move(cell));
  }
  return success();
}

static LogicalResult loadCompilerProfileJson(StringRef path, CapCatalog &cat,
                                             ResolvedProfile &out) {
  auto fileOr = llvm::MemoryBuffer::getFile(path);
  if (!fileOr) {
    llvm::errs() << "s2c2-evidence-bounded-schedule: cannot read profile "
                 << path << "\n";
    return failure();
  }
  auto parsed = llvm::json::parse(fileOr.get()->getBuffer());
  if (!parsed) {
    llvm::errs() << "s2c2-evidence-bounded-schedule: invalid JSON in " << path
                 << "\n";
    return failure();
  }
  llvm::json::Object *obj = parsed->getAsObject();
  if (!obj) {
    llvm::errs()
        << "s2c2-evidence-bounded-schedule: compiler profile must be an object\n";
    return failure();
  }
  if (auto p = obj->getString("profile"))
    out.name = p->str();
  if (auto d = obj->getString("device"))
    out.device = d->str();
  if (out.device.empty())
    out.device = out.name;

  llvm::json::Value *ev = obj->get("evidence");
  if (!ev) {
    out.evidenceDesc = "empty";
    return success();
  }
  if (std::optional<llvm::StringRef> spec = ev->getAsString()) {
    if (spec->empty()) {
      out.evidenceDesc = "empty";
      return success();
    }
    if (spec->starts_with("builtin:")) {
      StringRef which = spec->drop_front(StringRef("builtin:").size());
      if (failed(loadBuiltinEvidence(which, cat)))
        return failure();
      out.evidenceDesc = spec->str();
      return success();
    }
    llvm::SmallString<256> profileDir(path);
    llvm::sys::path::remove_filename(profileDir);
    std::string evPath = resolveExistingPath(*spec, profileDir);
    if (failed(loadJsonl(evPath, out.device, cat)))
      return failure();
    out.evidenceDesc = evPath;
    return success();
  }
  if (const llvm::json::Array *arr = ev->getAsArray()) {
    if (failed(loadInlineEvidence(*arr, cat)))
      return failure();
    out.evidenceDesc = path.str() + ":inline";
    return success();
  }
  llvm::errs() << "s2c2-evidence-bounded-schedule: evidence must be a builtin "
                  "id, JSONL path, or array\n";
  return failure();
}

static LogicalResult
loadEvidenceBoundedCatalog(StringRef profileOpt, StringRef evidenceOpt,
                           CapCatalog &cat, ResolvedProfile &out) {
  std::string profile = profileOpt.str();
  if (profile.empty() && !clS2C2Profile.empty())
    profile = clS2C2Profile;
  if (profile.empty())
    profile = "unknown";

  std::string evidence = evidenceOpt.str();
  if (evidence.empty() && !clS2C2Evidence.empty())
    evidence = clS2C2Evidence;

  if (looksLikePath(profile)) {
    std::string path = resolveExistingPath(profile, "");
    if (failed(loadCompilerProfileJson(path, cat, out)))
      return failure();
    if (out.name.empty())
      out.name = llvm::sys::path::filename(path).str();
  } else if (StringRef(profile).equals_insensitive("rtx4090") ||
             StringRef(profile).equals_insensitive("4090")) {
    out.name = "rtx4090";
    out.device = "rtx4090";
    loadBuiltinRtx4090(cat);
    out.evidenceDesc = "builtin:rtx4090";
  } else if (StringRef(profile).equals_insensitive("910B") ||
             StringRef(profile).equals_insensitive("910b") ||
             StringRef(profile).equals_insensitive("ascend910b")) {
    out.name = "910B";
    out.device = "ascend910b:ascend";
    loadBuiltin910B(cat);
    out.evidenceDesc = "builtin:910B";
  } else if (StringRef(profile).equals_insensitive("unknown")) {
    out.name = "unknown";
    out.device = "unknown";
    out.evidenceDesc = "empty";
  } else {
    llvm::errs() << "s2c2-evidence-bounded-schedule: unknown profile '"
                 << profile << "'\n";
    return failure();
  }

  if (!evidence.empty()) {
    std::string evPath = resolveExistingPath(evidence, "");
    if (failed(loadJsonl(evPath, out.device, cat)))
      return failure();
    out.evidenceDesc = evPath;
  }
  if (out.device.empty())
    out.device = "unknown";
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
  if ((isCompute(a) && b == Role::Storage) ||
      (isCompute(b) && a == Role::Storage))
    return "C||Storage";
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
  bool storage = false;
};

static void classifySpaces(std::optional<Space> srcSpace,
                           std::optional<Space> dstSpace, RegionClass &cls) {
  if (!srcSpace || !dstSpace)
    return;
  if (isHostLike(*srcSpace) && isDeviceLike(*dstSpace))
    cls.htod = true;
  else if (isDeviceLike(*srcSpace) && isHostLike(*dstSpace))
    cls.dtoh = true;
  else if (isDeviceLike(*srcSpace) && isDeviceLike(*dstSpace))
    cls.d2d = true;
  else if (*srcSpace == Space::SSD || *dstSpace == Space::SSD)
    cls.storage = true;
}

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
  if (auto copy = dyn_cast<CopyOp>(op)) {
    classifySpaces(bufferSpace(copy.getSrc()), bufferSpace(copy.getDst()), cls);
    return;
  }
  if (auto stream = dyn_cast<StreamOp>(op)) {
    classifySpaces(bufferSpace(stream.getSrc()), bufferSpace(stream.getDst()),
                   cls);
    return;
  }
  if (auto xfer = dyn_cast<TransferOp>(op)) {
    classifySpaces(bufferSpace(xfer.getSource()),
                   bufferSpace(xfer.getBuffer()), cls);
  }
}

static RegionClass classifyRegion(Region &region) {
  RegionClass cls;
  region.walk([&](Operation *op) { classifyOp(op, cls); });
  return cls;
}

static Role roleOf(const RegionClass &cls) {
  if (cls.d2d)
    return Role::Unknown;
  int nXfer = (int)cls.htod + (int)cls.dtoh + (int)cls.storage;
  int nComp = (int)cls.compute;
  if (nXfer && nComp)
    return Role::Unknown;
  if (cls.htod && !cls.dtoh)
    return Role::HtoD;
  if (cls.dtoh && !cls.htod)
    return Role::DtoH;
  if (cls.storage)
    return Role::Storage;
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
    } else if (auto xfer = dyn_cast<TransferOp>(op)) {
      if (auto ty = dyn_cast<BufferType>(xfer.getSource().getType()))
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
  bool transferPair = pair.contains("HtoD") || pair.contains("DtoH") ||
                      pair.contains("Storage");
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

static CapCell ambiguousPairCell(const SmallVector<CapCell, 4> &cells) {
  CapCell many;
  many.relation = "underdetermined";
  many.confidence = "measured";
  many.regime = cells.front().regime;
  many.sizeRange = "multiple";
  many.synchronization = cells.front().synchronization;
  many.rewriteLicense = false;
  return many;
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
    return ambiguousPairCell(cells);
  }

  const CapCell *best = nullptr;
  bool bestUnconstrained = true;
  int64_t bestSpan = 0;
  unsigned nUncCover = 0;
  unsigned nRangeCover = 0;
  for (const CapCell &cell : cells) {
    SizeSpec spec = parseSizeRange(cell.sizeRange);
    bool unconstrained = spec.kind == SizeSpecKind::Unconstrained;
    bool covers = unconstrained || (spec.kind == SizeSpecKind::Range &&
                                    *sizeBytes >= spec.lo &&
                                    *sizeBytes <= spec.hi);
    if (!covers)
      continue;
    if (unconstrained)
      ++nUncCover;
    else
      ++nRangeCover;
    int64_t span = unconstrained ? 0 : spec.hi - spec.lo;
    // Prefer a closed size band over a device-wide n/a cell.
    if (!best || (bestUnconstrained && !unconstrained) ||
        (!unconstrained && !bestUnconstrained && span < bestSpan)) {
      best = &cell;
      bestUnconstrained = unconstrained;
      bestSpan = span;
    }
  }
  if (nRangeCover == 0 && nUncCover > 1)
    return ambiguousPairCell(cells);
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

static std::string formatPayload(std::optional<int64_t> bytes) {
  if (!bytes)
    return "n/a";
  const int64_t mib = 1024LL * 1024LL;
  if (*bytes % mib == 0)
    return std::to_string(*bytes / mib) + "MiB";
  return std::to_string(*bytes) + "B";
}

static bool isStorageCommOverlap(StringRef pair) {
  return pair == "C||Storage" || pair == "C||HtoD" || pair == "C||DtoH";
}

static StringRef decisionStr(DecisionKind kind) {
  switch (kind) {
  case DecisionKind::Flatten:
    return "FLATTEN";
  case DecisionKind::Keep:
    return "KEEP";
  case DecisionKind::Preserve:
    return "PRESERVE";
  }
  return "PRESERVE";
}

static DecisionKind classifyDecision(const CapCell &cell, Applicability app,
                                     bool serialize, StringRef pair) {
  (void)app;
  (void)pair;
  if (serialize)
    return DecisionKind::Flatten;
  // KEEP is not a rewrite. Inferred parallel overlap (C||Storage,
  // C||HtoD) stays concurrent. Only missing / mixed / unlicensed
  // evidence is PRESERVE.
  if (cell.relation == "parallel")
    return DecisionKind::Keep;
  return DecisionKind::Preserve;
}

static std::string decisionReason(const CapCell &cell, Applicability app,
                                  bool serialize, StringRef pair) {
  if (serialize)
    return "licensed-compute-contention";
  if (cell.relation == "parallel" && isStorageCommOverlap(pair))
    return "storage-communication-overlap";
  if (cell.relation == "parallel")
    return "relation-parallel";
  if (!cell.rewriteLicense)
    return "rewrite-license-no";
  if (cell.relation == "mixed")
    return "relation-mixed";
  if (app != Applicability::Yes || cell.relation == "underdetermined")
    return "no-evidence";
  return "preserve";
}

struct WorkloadDecision {
  unsigned id = 0;
  std::string via;
  std::string pair;
  std::string payload;
  std::string relation;
  std::string reason;
  DecisionKind kind = DecisionKind::Preserve;
  bool flatten = false;
  Applicability app = Applicability::Unknown;
  bool rewriteLicense = true;
};

static void fillWorkloadDecision(WorkloadDecision &d, unsigned id, StringRef via,
                                 StringRef pair, const QueryContext &ctx,
                                 const CapCell &cell, Applicability app,
                                 bool serialize) {
  d.id = id;
  d.via = via.str();
  d.pair = pair.str();
  d.payload = formatPayload(ctx.sizeBytes);
  d.relation = cell.relation;
  d.reason = decisionReason(cell, app, serialize, pair);
  d.kind = classifyDecision(cell, app, serialize, pair);
  d.flatten = serialize;
  d.app = app;
  d.rewriteLicense = cell.rewriteLicense;
}

static void countDecisions(ArrayRef<WorkloadDecision> decisions, unsigned &keep,
                           unsigned &flatten, unsigned &preserve) {
  keep = flatten = preserve = 0;
  for (const WorkloadDecision &d : decisions) {
    switch (d.kind) {
    case DecisionKind::Flatten:
      ++flatten;
      break;
    case DecisionKind::Keep:
      ++keep;
      break;
    case DecisionKind::Preserve:
      ++preserve;
      break;
    }
  }
}

static std::string prettyPair(StringRef pair) {
  std::string out;
  for (size_t i = 0; i < pair.size(); ++i) {
    if (i + 1 < pair.size() && pair[i] == '|' && pair[i + 1] == '|') {
      out += " || ";
      ++i;
    } else {
      out += pair[i];
    }
  }
  return out;
}

static std::string prettyReason(StringRef reason) {
  std::string out = reason.str();
  for (char &c : out) {
    if (c == '-')
      c = ' ';
  }
  return out;
}

static void printWorkloadCandidate(const WorkloadDecision &d) {
  llvm::errs() << "workload-candidate #" << d.id << " pair=" << d.pair
               << " payload=" << d.payload << " relation=" << d.relation
               << " decision=" << decisionStr(d.kind)
               << " reason=" << d.reason << "\n";
  llvm::errs() << "candidate #" << d.id << " : " << prettyPair(d.pair) << "\n";
  llvm::errs() << "    decision : " << decisionStr(d.kind) << "\n";
  llvm::errs() << "    reason   : " << prettyReason(d.reason) << "\n";
}

enum class HierarchyAction {
  Materialize,
  Prefetch,
  Transfer,
  KeepResidency,
  Preserve
};

struct HierarchySite {
  unsigned id = 0;
  std::string op;
  std::string src;
  std::string dst;
  std::string pair;
  std::string when;
  std::string reason;
  HierarchyAction action = HierarchyAction::Preserve;
};

static StringRef spaceName(std::optional<Space> space) {
  if (!space)
    return "none";
  switch (*space) {
  case Space::Register:
    return "register";
  case Space::SRAM:
    return "sram";
  case Space::DRAM:
    return "dram";
  case Space::HBM:
    return "hbm";
  case Space::SSD:
    return "ssd";
  case Space::CIM:
    return "cim";
  case Space::Host:
    return "host";
  }
  return "none";
}

static StringRef hierarchyActionStr(HierarchyAction action) {
  switch (action) {
  case HierarchyAction::Materialize:
    return "MATERIALIZE";
  case HierarchyAction::Prefetch:
    return "PREFETCH";
  case HierarchyAction::Transfer:
    return "TRANSFER";
  case HierarchyAction::KeepResidency:
    return "KEEP_RESIDENCY";
  case HierarchyAction::Preserve:
    return "PRESERVE";
  }
  return "PRESERVE";
}

static StringRef movementPair(std::optional<Space> src,
                              std::optional<Space> dst) {
  RegionClass cls;
  classifySpaces(src, dst, cls);
  if (cls.storage)
    return "Storage";
  if (cls.htod)
    return "HtoD";
  if (cls.dtoh)
    return "DtoH";
  return "n/a";
}

static Value peelScheduleResult(Value value) {
  while (value) {
    Operation *def = value.getDefiningOp();
    if (!def)
      break;
    if (auto conc = dyn_cast<ConcurrentOp>(def)) {
      unsigned idx = cast<OpResult>(value).getResultNumber();
      auto yield = dyn_cast<YieldOp>(conc.getBody().front().getTerminator());
      if (!yield || idx >= yield.getNumOperands())
        break;
      value = yield.getOperand(idx);
      continue;
    }
    if (auto task = dyn_cast<TaskOp>(def)) {
      unsigned idx = cast<OpResult>(value).getResultNumber();
      auto yield = dyn_cast<YieldOp>(task.getBody().front().getTerminator());
      // Task result 0 is the completion token; yielded values start at 1.
      if (!yield || idx == 0 || idx - 1 >= yield.getNumOperands())
        break;
      value = yield.getOperand(idx - 1);
      continue;
    }
    break;
  }
  return value;
}

static Value objectIdentity(Value buffer) {
  buffer = peelScheduleResult(buffer);
  if (auto xfer = buffer.getDefiningOp<TransferOp>())
    return objectIdentity(xfer.getSource());
  if (auto mat = buffer.getDefiningOp<MaterializeOp>())
    return mat.getObject();
  return Value();
}

static ConcurrentOp enclosingConcurrent(Operation *op) {
  for (Operation *parent = op->getParentOp(); parent;
       parent = parent->getParentOp()) {
    if (auto conc = dyn_cast<ConcurrentOp>(parent))
      return conc;
  }
  return ConcurrentOp();
}

static void classifyOverlapSite(ConcurrentOp conc, const CapCatalog &cat,
                                std::string &pair, DecisionKind &kind,
                                std::string &reason) {
  pair.clear();
  kind = DecisionKind::Preserve;
  reason = "no-evidence";
  SmallVector<TaskOp> tasks(conc.getBody().front().getOps<TaskOp>());
  if (tasks.size() != 2)
    return;
  pair = classifyPair(tasks[0].getBody(), tasks[1].getBody());
  if (pair.empty())
    return;
  QueryContext ctx =
      contextFromRegions(tasks[0].getBody(), tasks[1].getBody(), pair);
  CapCell cell = lookupPair(cat, pair, ctx.sizeBytes);
  Applicability app = isApplicable(cell, ctx);
  bool serialize = shouldSerialize(cell, app);
  kind = classifyDecision(cell, app, serialize, pair);
  reason = decisionReason(cell, app, serialize, pair);
}

static void printHierarchySite(const HierarchySite &s) {
  llvm::errs() << "hierarchy-site #" << s.id << " op=" << s.op
               << " src=" << s.src << " dst=" << s.dst << " pair=" << s.pair
               << " action=" << hierarchyActionStr(s.action)
               << " when=" << s.when << " reason=" << s.reason << "\n";
  llvm::errs() << "hierarchy-site #" << s.id << " : " << s.op << " " << s.src
               << " -> " << s.dst << "\n";
  llvm::errs() << "    action   : " << hierarchyActionStr(s.action) << "\n";
  llvm::errs() << "    when     : " << prettyReason(s.when) << "\n";
  llvm::errs() << "    reason   : " << prettyReason(s.reason) << "\n";
}

static void countHierarchy(ArrayRef<HierarchySite> sites, unsigned &materialize,
                           unsigned &prefetch, unsigned &transfer,
                           unsigned &keep, unsigned &preserve) {
  materialize = prefetch = transfer = keep = preserve = 0;
  for (const HierarchySite &s : sites) {
    switch (s.action) {
    case HierarchyAction::Materialize:
      ++materialize;
      break;
    case HierarchyAction::Prefetch:
      ++prefetch;
      break;
    case HierarchyAction::Transfer:
      ++transfer;
      break;
    case HierarchyAction::KeepResidency:
      ++keep;
      break;
    case HierarchyAction::Preserve:
      ++preserve;
      break;
    }
  }
}

static void recordLiveResidency(
    llvm::DenseMap<Value, llvm::DenseMap<unsigned, Value>> &live, Value object,
    std::optional<Space> space, Value buffer) {
  if (!object || !space)
    return;
  auto &slots = live[object];
  unsigned key = static_cast<unsigned>(*space);
  if (!slots.count(key))
    slots[key] = buffer;
}

static bool hasLiveResidency(
    const llvm::DenseMap<Value, llvm::DenseMap<unsigned, Value>> &live,
    Value object, std::optional<Space> space) {
  if (!object || !space)
    return false;
  auto it = live.find(object);
  if (it == live.end())
    return false;
  return it->second.count(static_cast<unsigned>(*space));
}

static SmallVector<HierarchySite> planStorageHierarchy(ModuleOp module,
                                                       const CapCatalog &cat) {
  SmallVector<HierarchySite> sites;
  llvm::DenseMap<Value, llvm::DenseMap<unsigned, Value>> live;
  unsigned nextId = 0;
  module.walk([&](Operation *op) {
    if (auto mat = dyn_cast<MaterializeOp>(op)) {
      HierarchySite s;
      s.id = nextId++;
      s.op = "stor.materialize";
      s.src = "none";
      s.dst = spaceName(mat.getStorageSpace()).str();
      s.pair = "n/a";
      s.action = HierarchyAction::Materialize;
      s.when = "eager";
      s.reason = "object-residency";
      recordLiveResidency(live, mat.getObject(), mat.getStorageSpace(),
                          mat.getBuffer());
      sites.push_back(std::move(s));
      return;
    }
    auto xfer = dyn_cast<TransferOp>(op);
    if (!xfer)
      return;
    auto srcSpace = bufferSpace(xfer.getSource());
    auto dstSpace = bufferSpace(xfer.getBuffer());
    Value object = objectIdentity(xfer.getSource());
    HierarchySite s;
    s.id = nextId++;
    s.op = "stor.transfer";
    s.src = spaceName(srcSpace).str();
    s.dst = spaceName(dstSpace).str();
    s.pair = movementPair(srcSpace, dstSpace).str();
    if (hasLiveResidency(live, object, dstSpace)) {
      s.action = HierarchyAction::KeepResidency;
      s.when = "reuse";
      s.reason = (dstSpace && isDeviceLike(*dstSpace))
                     ? "live-device-residency"
                     : "live-host-residency";
    } else if (ConcurrentOp conc = enclosingConcurrent(xfer)) {
      std::string pair;
      DecisionKind kind = DecisionKind::Preserve;
      std::string reason;
      classifyOverlapSite(conc, cat, pair, kind, reason);
      if (!pair.empty())
        s.pair = pair;
      if (kind == DecisionKind::Keep && isStorageCommOverlap(pair)) {
        s.action = HierarchyAction::Prefetch;
        s.when = "overlap";
        s.reason = reason;
      } else {
        s.action = HierarchyAction::Preserve;
        s.when = "as-written";
        s.reason = reason;
      }
    } else if (srcSpace && *srcSpace == Space::SSD && dstSpace &&
               isHostLike(*dstSpace)) {
      s.action = HierarchyAction::Materialize;
      s.when = "eager";
      s.reason = "first-host-residency";
    } else {
      s.action = HierarchyAction::Transfer;
      s.when = "sequential";
      s.reason = "consume-requires-device";
    }
    recordLiveResidency(live, object, dstSpace, xfer.getBuffer());
    sites.push_back(std::move(s));
  });
  return sites;
}

static LogicalResult dumpWorkloadSchedule(StringRef path,
                                          const ResolvedProfile &evi,
                                          ArrayRef<WorkloadDecision> decs,
                                          ArrayRef<HierarchySite> sites) {
  llvm::json::Array cands;
  unsigned keep = 0, flatten = 0, preserve = 0;
  for (const WorkloadDecision &d : decs) {
    llvm::json::Object obj;
    obj["id"] = (int64_t)d.id;
    obj["via"] = d.via;
    obj["pair"] = d.pair;
    obj["payload"] = d.payload;
    obj["pair_relation"] = d.relation;
    obj["decision"] = decisionStr(d.kind).str();
    obj["reason"] = d.reason;
    obj["applicable"] = applicabilityStr(d.app).str();
    obj["rewrite_license"] = d.rewriteLicense;
    cands.push_back(std::move(obj));
    switch (d.kind) {
    case DecisionKind::Flatten:
      ++flatten;
      break;
    case DecisionKind::Keep:
      ++keep;
      break;
    case DecisionKind::Preserve:
      ++preserve;
      break;
    }
  }
  llvm::json::Object root;
  root["schema"] = "s2c2.workload_schedule.v1";
  root["profile"] = evi.name;
  root["device"] = evi.device;
  root["evidence"] = evi.evidenceDesc;
  root["rewrite"] = "concurrent-to-serial";
  root["focus"] = "storage-data-movement-compute-overlap";
  root["candidates"] = (int64_t)decs.size();
  root["keep"] = (int64_t)keep;
  root["flatten"] = (int64_t)flatten;
  root["preserve"] = (int64_t)preserve;
  root["decisions"] = std::move(cands);
  unsigned hMat = 0, hPref = 0, hXfer = 0, hKeep = 0, hPres = 0;
  countHierarchy(sites, hMat, hPref, hXfer, hKeep, hPres);
  llvm::json::Array hier;
  for (const HierarchySite &s : sites) {
    llvm::json::Object obj;
    obj["id"] = (int64_t)s.id;
    obj["op"] = s.op;
    obj["src"] = s.src;
    obj["dst"] = s.dst;
    obj["pair"] = s.pair;
    obj["action"] = hierarchyActionStr(s.action).str();
    obj["when"] = s.when;
    obj["reason"] = s.reason;
    hier.push_back(std::move(obj));
  }
  root["hierarchy"] = std::move(hier);
  root["hierarchy_sites"] = (int64_t)sites.size();
  root["hierarchy_materialize"] = (int64_t)hMat;
  root["hierarchy_prefetch"] = (int64_t)hPref;
  root["hierarchy_transfer"] = (int64_t)hXfer;
  root["hierarchy_keep_residency"] = (int64_t)hKeep;
  root["hierarchy_preserve"] = (int64_t)hPres;
  root["cost"] = "unchanged";
  std::error_code ec;
  llvm::raw_fd_ostream out(path, ec, llvm::sys::fs::OF_Text);
  if (ec) {
    llvm::errs() << "s2c2-evidence-bounded-schedule: cannot write "
                 << path << ": " << ec.message() << "\n";
    return failure();
  }
  out << llvm::json::Value(std::move(root)) << "\n";
  return success();
}

// Generic licensed concurrent→serial rewrite. Not pair-specific.
// Unbundle a 2-task sched.concurrent (or sched.overlap) into parent
// IR order. EvidenceQuery + Applicability + RewriteLicense decide
// whether to apply; this is only the Rewrite step.
static void rewriteConcurrentToSerial(ConcurrentOp conc) {
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

static void rewriteOverlapToSerial(OverlapOp ov) {
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

static LogicalResult applySchedule(ModuleOp module, StringRef device,
                                   const CapCatalog &cat,
                                   const ResolvedProfile *evi = nullptr,
                                   StringRef dumpPath = {}) {
  if (evi) {
    llvm::errs() << "evidence-bounded-schedule profile=" << evi->name
                 << " device=" << evi->device
                 << " evidence=" << evi->evidenceDesc
                 << " rewrite=concurrent-to-serial cost=unchanged\n";
  }
  SmallVector<WorkloadDecision> decisions;
  unsigned nextId = 0;

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
                 << " decision=" << (serialize ? "serialize" : "keep");
    if (serialize)
      llvm::errs() << " rewrite=concurrent-to-serial";
    llvm::errs() << "\n";
    if (evi) {
      WorkloadDecision d;
      fillWorkloadDecision(d, nextId++, "concurrent", pair, ctx, cell, app,
                           serialize);
      printWorkloadCandidate(d);
      decisions.push_back(std::move(d));
    }
    if (serialize)
      rewriteConcurrentToSerial(conc);
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
                 << " decision=" << (serialize ? "serialize" : "keep");
    if (serialize)
      llvm::errs() << " rewrite=concurrent-to-serial";
    llvm::errs() << "\n";
    if (evi) {
      WorkloadDecision d;
      fillWorkloadDecision(d, nextId++, "overlap", pair, ctx, cell, app,
                           serialize);
      printWorkloadCandidate(d);
      decisions.push_back(std::move(d));
    }
    if (serialize)
      rewriteOverlapToSerial(ov);
  }
  llvm::errs() << "capability-schedule device=" << device
               << " semantics=unchanged v3=not-claimed cost=unchanged\n";
  if (evi) {
    unsigned keep = 0, flatten = 0, preserve = 0;
    countDecisions(decisions, keep, flatten, preserve);
    llvm::errs() << "workload-schedule candidates=" << decisions.size()
                 << " keep=" << keep << " flatten=" << flatten
                 << " preserve=" << preserve
                 << " hb=verify-with-check-s2c2-execution cost=unchanged\n";
    llvm::errs() << "HB verification : --check-s2c2-execution\n";
    llvm::errs() << "lowering        : --s2c2-lower\n";
    SmallVector<HierarchySite> sites = planStorageHierarchy(module, cat);
    unsigned hMat = 0, hPref = 0, hXfer = 0, hKeep = 0, hPres = 0;
    countHierarchy(sites, hMat, hPref, hXfer, hKeep, hPres);
    for (const HierarchySite &s : sites)
      printHierarchySite(s);
    llvm::errs() << "hierarchy-schedule sites=" << sites.size()
                 << " materialize=" << hMat << " prefetch=" << hPref
                 << " transfer=" << hXfer << " keep-residency=" << hKeep
                 << " preserve=" << hPres
                 << " focus=ssd-host-hbm-compute cost=unchanged\n";
    if (!dumpPath.empty() &&
        failed(dumpWorkloadSchedule(dumpPath, *evi, decisions, sites)))
      return failure();
  }
  return success();
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
    if (failed(applySchedule(getOperation(), device, cat)))
      signalPassFailure();
  }
};

struct S2C2EvidenceBoundedSchedule
    : impl::S2C2EvidenceBoundedScheduleBase<S2C2EvidenceBoundedSchedule> {
  using impl::S2C2EvidenceBoundedScheduleBase<
      S2C2EvidenceBoundedSchedule>::S2C2EvidenceBoundedScheduleBase;

  void runOnOperation() override {
    CapCatalog cat;
    ResolvedProfile resolved;
    if (failed(loadEvidenceBoundedCatalog(profileName, evidencePath, cat,
                                          resolved))) {
      signalPassFailure();
      return;
    }
    if (failed(applySchedule(getOperation(), resolved.device, cat, &resolved,
                             dumpSchedule)))
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
