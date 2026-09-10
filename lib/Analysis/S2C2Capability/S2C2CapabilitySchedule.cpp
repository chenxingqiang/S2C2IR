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
// Phase 3H applies KEEP_RESIDENCY only when a dominating, unmutated,
// same-type live replica is proven; not C||Storage flatten.
// Phase 3I reports scf.for software-pipeline structure and lifts
// reuse across a dominating prologue replica when the loop does not
// pack/dealloc it. For-iter-args stay underdetermined.
// Phase 4A enumerates the legal action set F(site) and selects the
// default-3G inhabitant. Cost does not rank, license, or decide
// legality. Selection is not a rewrite license.
// Phase 4B jointly enumerates F(chain) over maximal contiguous
// runs of one storage object in program order. Interleaving
// starts a new chain. default-3g still reproduces the 3G tuple;
// Phase 4C composes F(program) as the product of F(chain) over all
// chains in program order when that product is at most 64. A larger
// product is not enumerated and is not reported as legal. Chain
// definition stays frozen. default-3g must inhabit F; otherwise the
// pass fails. Phase 4D ranks a fully enumerated F(program) under
// policy=cost-v04 and is FROZEN at the coincide witness. Do not add
// structural ticks. Ranking does not invent members, does not
// replace default-3g, and does not rank a truncated product.
// Phase 5A ranks enumerated F(program) under
// policy=measured-storage-v1 from candidate-local records. It does
// not add ticks, does not retarget default-3g, and does not apply
// the measured winner as a rewrite. Frozen --s2c2-cost /
// --s2c2-argmin / Score_3 stay untouched.
// Phase 6C-B prints F_capacity occupancy candidates under
// --capacity / --capacity-spec. Diagnostics only; rewrite=no.
// EVICT is not a rewrite. 6C-E selects first(F_capacity) on
// the query consumer. 6C-F ranks enumerated F_capacity under
// measured-capacity-v1 (ArgMin; still not a rewrite license).
// Duplicate (profile, workload, candidate) is rejected.
// Equal times pick the earliest F_capacity inhabitant.
// Phase 6C-C materializes CapacityPlan as the compiler-visible
// candidate object (selected=none on the diagnostic path).
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
#include "s2c2/S2C2CapacityPlan.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleDialect.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageDialect.h"
#include "s2c2/Storage/StorageOps.h"
#include "s2c2/Storage/StorageTypes.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Support/LogicalResult.h"
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
#include <climits>
#include <cstdint>
#include <initializer_list>
#include <optional>
#include <string>
#include <system_error>
#include <utility>

#ifndef S2C2_SOURCE_DIR
#define S2C2_SOURCE_DIR ""
#endif

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2CAPABILITYQUERY
#define GEN_PASS_DEF_S2C2CAPABILITYSCHEDULE
#define GEN_PASS_DEF_S2C2EVIDENCEBOUNDEDSCHEDULE
#define GEN_PASS_DEF_S2C2CAPACITYPLANQUERY
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
using stor::DeallocOp;
using stor::MaterializeOp;
using stor::PackOp;
using stor::Space;
using stor::TransferOp;
using stor::UnpackOp;

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
llvm::cl::opt<std::string> clSchedulePolicy(
    "schedule-policy",
    llvm::cl::desc("S2C2 schedule selection policy: default-3g, cost-v04, "
                   "or measured-storage-v1. Selection only; not legality "
                   "and not a rewrite license."),
    llvm::cl::ValueRequired, llvm::cl::init(""));
llvm::cl::opt<bool> clScheduleExplain(
    "explain",
    llvm::cl::desc("Print F, evidence, named-policy selection, and rewrite=no"),
    llvm::cl::init(false));
llvm::cl::opt<std::string> clMeasuredCostTable(
    "measured-cost-table",
    llvm::cl::desc("Canonical measured-storage-v1 JSONL (not a campaign log)"),
    llvm::cl::ValueRequired, llvm::cl::init(""));
llvm::cl::opt<std::string> clCapacityBudget(
    "capacity",
    llvm::cl::desc("F_capacity budget as space:tiles (hbm:2). Diagnostics "
                   "only; not a rewrite license."),
    llvm::cl::ValueRequired, llvm::cl::init(""));
llvm::cl::opt<std::string> clCapacitySpec(
    "capacity-spec",
    llvm::cl::desc("Optional s2c2.capacity.v1 JSONL (not a hardware ledger)"),
    llvm::cl::ValueRequired, llvm::cl::init(""));
llvm::cl::opt<std::string> clDumpCapacityPlan(
    "dump-capacity-plan",
    llvm::cl::desc("Write s2c2.capacity_plan.v1 JSON (not a rewrite license; "
                   "selected=none on the diagnostic path)"),
    llvm::cl::ValueRequired, llvm::cl::init(""));
[[maybe_unused]] llvm::cl::opt<bool> clQueryCapacityPlan(
    "query-capacity-plan",
    llvm::cl::desc("Query CapacityPlan as a consumer API (selected=none; "
                   "does not run the schedule pass)"),
    llvm::cl::init(false));
llvm::cl::opt<std::string> clCapacityPolicy(
    "capacity-policy",
    llvm::cl::desc("Select from F_capacity: none, s0, or measured-capacity-v1. "
                   "Selection only; not a rewrite license."),
    llvm::cl::ValueRequired, llvm::cl::init(""));
llvm::cl::opt<std::string> clMeasuredCapacityTable(
    "measured-capacity-table",
    llvm::cl::desc("JSONL of s2c2.measured_capacity_cost.v1 records "
                   "(not a campaign log; do not FileCheck microseconds)"),
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
  unsigned objectKey = 0;
  std::string op;
  std::string src;
  std::string dst;
  std::string pair;
  std::string when;
  std::string reason;
  HierarchyAction action = HierarchyAction::Preserve;
  SmallVector<HierarchyAction, 4> legal;
  std::string policy = "default-3g";
};

struct JointChain {
  unsigned id = 0;
  unsigned objectKey = 0;
  SmallVector<unsigned, 8> siteIds;
  SmallVector<SmallVector<HierarchyAction, 8>, 16> legal;
  SmallVector<HierarchyAction, 8> selected;
  std::string policy = "default-3g";
};

using ChainAssignment = SmallVector<HierarchyAction, 8>;

struct GlobalSchedule {
  /// Populated only when the product is fully enumerated.
  /// A truncated product is not F(program) and stays empty.
  SmallVector<SmallVector<ChainAssignment, 4>, 16> legal;
  SmallVector<ChainAssignment, 4> selected;
  uint64_t product = 1;
  bool productOverflow = false;
  bool truncated = false;
  bool enumerated = false;
  bool historicalInF = false;
  std::string policy = "default-3g";
};

/// Completeness cap for constructing F(program). Exceeding it means
/// the compiler does not claim a complete legal set.
static constexpr uint64_t kGlobalFEnumerateCap = 64;

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

static std::optional<Space> parseSpaceName(StringRef name) {
  if (name.equals_insensitive("hbm"))
    return Space::HBM;
  if (name.equals_insensitive("host"))
    return Space::Host;
  if (name.equals_insensitive("ssd"))
    return Space::SSD;
  if (name.equals_insensitive("dram"))
    return Space::DRAM;
  if (name.equals_insensitive("sram"))
    return Space::SRAM;
  if (name.equals_insensitive("cim"))
    return Space::CIM;
  if (name.equals_insensitive("register"))
    return Space::Register;
  return std::nullopt;
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

static std::string joinActions(ArrayRef<HierarchyAction> acts, char sep = ',') {
  std::string out;
  for (size_t i = 0; i < acts.size(); ++i) {
    if (i)
      out += sep;
    out += hierarchyActionStr(acts[i]).str();
  }
  return out;
}

static std::string joinIds(ArrayRef<unsigned> ids) {
  std::string out;
  for (size_t i = 0; i < ids.size(); ++i) {
    if (i)
      out += ",";
    out += std::to_string(ids[i]);
  }
  return out;
}

static std::string joinGlobal(ArrayRef<ChainAssignment> asns) {
  std::string out;
  for (size_t i = 0; i < asns.size(); ++i) {
    if (i)
      out += "//";
    out += joinActions(asns[i], '|');
  }
  return out;
}

static HierarchyAction selectDefault3G(ArrayRef<HierarchyAction> legal,
                                       HierarchyAction preferred) {
  for (HierarchyAction a : legal) {
    if (a == preferred)
      return a;
  }
  return legal.empty() ? HierarchyAction::Preserve : legal.front();
}

static void setLegalSelect(HierarchySite &s,
                           std::initializer_list<HierarchyAction> legal,
                           HierarchyAction preferred) {
  s.legal.assign(legal.begin(), legal.end());
  s.policy = "default-3g";
  s.action = selectDefault3G(s.legal, preferred);
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
  llvm::errs() << "    candidates: " << joinActions(s.legal) << "\n";
  llvm::errs() << "    selected  : " << hierarchyActionStr(s.action) << "\n";
  llvm::errs() << "    policy    : " << s.policy << "\n";
  llvm::errs() << "hierarchy-candidates #" << s.id
               << " legal=" << joinActions(s.legal)
               << " selected=" << hierarchyActionStr(s.action)
               << " policy=" << s.policy
               << " note selection-ne-cost\n";
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

static Value getLiveResidency(
    const llvm::DenseMap<Value, llvm::DenseMap<unsigned, Value>> &live,
    Value object, std::optional<Space> space) {
  if (!object || !space)
    return Value();
  auto it = live.find(object);
  if (it == live.end())
    return Value();
  auto slot = it->second.find(static_cast<unsigned>(*space));
  if (slot == it->second.end())
    return Value();
  return slot->second;
}

// Prefer the concurrent result that aliases an inner transfer, so
// later consumers reuse a dominating parent-block SSA value.
static Value outwardResidency(Value inner) {
  for (OpOperand &use : inner.getUses()) {
    auto yield = dyn_cast<YieldOp>(use.getOwner());
    if (!yield)
      continue;
    auto task = dyn_cast<TaskOp>(yield->getParentOp());
    if (!task)
      continue;
    unsigned yIdx = use.getOperandNumber();
    if (yIdx >= task.getValues().size())
      continue;
    Value taskVal = task.getValues()[yIdx];
    for (OpOperand &tUse : taskVal.getUses()) {
      auto cy = dyn_cast<YieldOp>(tUse.getOwner());
      if (!cy)
        continue;
      auto conc = dyn_cast<ConcurrentOp>(cy->getParentOp());
      if (!conc)
        continue;
      unsigned cIdx = tUse.getOperandNumber();
      if (cIdx < conc.getNumResults())
        return conc.getResult(cIdx);
    }
  }
  return inner;
}

static bool isForIterArg(Value value) {
  auto barg = dyn_cast<BlockArgument>(value);
  if (!barg)
    return false;
  return isa<scf::ForOp>(barg.getOwner()->getParentOp());
}

static bool sameBlockDominates(Value live, Operation *op) {
  if (isForIterArg(live))
    return false;
  Operation *def = live.getDefiningOp();
  if (!def || !op)
    return false;
  return def->getBlock() == op->getBlock() && def->isBeforeInBlock(op);
}

static bool mutatesBuffer(Operation *op, Value buf) {
  if (auto pack = dyn_cast<PackOp>(op))
    return pack.getBuffer() == buf;
  if (auto dealloc = dyn_cast<DeallocOp>(op))
    return dealloc.getBuffer() == buf;
  return false;
}

static bool regionMutates(Operation *root, Value buf) {
  bool mut = false;
  root->walk([&](Operation *op) {
    if (mutatesBuffer(op, buf))
      mut = true;
  });
  return mut;
}

static bool mutatedBetween(Value buf, Operation *from, Operation *to) {
  if (!from || !to || from->getBlock() != to->getBlock())
    return true;
  for (Operation *cur = from->getNextNode(); cur && cur != to;
       cur = cur->getNextNode()) {
    if (mutatesBuffer(cur, buf) || regionMutates(cur, buf))
      return true;
  }
  return false;
}

/// Prologue residency that dominates an enclosing `scf.for` and is
/// not packed/deallocated inside the loop (loop-invariant replica).
static bool provenLiveAcrossLoop(Value live, Operation *op) {
  if (!live || !op || isForIterArg(live) || llvm::isa<BlockArgument>(live))
    return false;
  Operation *def = live.getDefiningOp();
  if (!def)
    return false;
  auto forOp = op->getParentOfType<scf::ForOp>();
  if (!forOp)
    return false;
  if (def->getBlock() != forOp->getBlock() || !def->isBeforeInBlock(forOp))
    return false;
  return !regionMutates(forOp, live);
}

static bool provenLiveAcross(Value live, Operation *op) {
  if (isForIterArg(live))
    return false;
  if (sameBlockDominates(live, op))
    return !mutatedBetween(live, live.getDefiningOp(), op);
  return provenLiveAcrossLoop(live, op);
}

struct ReuseStats {
  unsigned applied = 0;
  unsigned skipped = 0;
};

// Proven-safe KEEP_RESIDENCY only: sequential rematerialize of a
// dominating, unmutated, same-type live replica. Not C||Storage
// flatten. Does not invent sibling sched.wait.
static ReuseStats applyProvenResidencyReuse(ModuleOp module) {
  llvm::DenseMap<Value, llvm::DenseMap<unsigned, Value>> live;
  SmallVector<TransferOp> erase;
  ReuseStats st;
  module.walk([&](Operation *op) {
    if (auto mat = dyn_cast<MaterializeOp>(op)) {
      recordLiveResidency(live, mat.getObject(), mat.getStorageSpace(),
                          mat.getBuffer());
      return;
    }
    auto xfer = dyn_cast<TransferOp>(op);
    if (!xfer)
      return;
    Value object = objectIdentity(xfer.getSource());
    auto dstSpace = bufferSpace(xfer.getBuffer());
    Value liveBuf = getLiveResidency(live, object, dstSpace);
    if (liveBuf && !enclosingConcurrent(xfer)) {
      bool safe = liveBuf.getType() == xfer.getBuffer().getType() &&
                  provenLiveAcross(liveBuf, xfer);
      if (safe) {
        xfer.getBuffer().replaceAllUsesWith(liveBuf);
        erase.push_back(xfer);
        ++st.applied;
        return;
      }
      ++st.skipped;
    }
    recordLiveResidency(live, object, dstSpace,
                        outwardResidency(xfer.getBuffer()));
  });
  for (TransferOp x : erase)
    x.erase();
  return st;
}

static SmallVector<HierarchySite, 16> planStorageHierarchy(ModuleOp module,
                                                       const CapCatalog &cat) {
  SmallVector<HierarchySite, 16> sites;
  llvm::DenseMap<Value, llvm::DenseMap<unsigned, Value>> live;
  llvm::DenseMap<Value, unsigned> objectKeys;
  unsigned nextId = 0;
  unsigned nextObj = 0;
  unsigned nextAnon = 1000;
  auto objectKeyOf = [&](Value obj) -> unsigned {
    if (!obj)
      return nextAnon++;
    auto it = objectKeys.find(obj);
    if (it != objectKeys.end())
      return it->second;
    unsigned k = nextObj++;
    objectKeys[obj] = k;
    return k;
  };
  module.walk([&](Operation *op) {
    if (auto mat = dyn_cast<MaterializeOp>(op)) {
      HierarchySite s;
      s.id = nextId++;
      s.objectKey = objectKeyOf(mat.getObject());
      s.op = "stor.materialize";
      s.src = "none";
      s.dst = spaceName(mat.getStorageSpace()).str();
      s.pair = "n/a";
      setLegalSelect(s, {HierarchyAction::Materialize},
                     HierarchyAction::Materialize);
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
    s.objectKey = objectKeyOf(object);
    s.op = "stor.transfer";
    s.src = spaceName(srcSpace).str();
    s.dst = spaceName(dstSpace).str();
    s.pair = movementPair(srcSpace, dstSpace).str();
    if (hasLiveResidency(live, object, dstSpace)) {
      setLegalSelect(s,
                     {HierarchyAction::KeepResidency, HierarchyAction::Transfer},
                     HierarchyAction::KeepResidency);
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
        setLegalSelect(s,
                       {HierarchyAction::Prefetch, HierarchyAction::Preserve},
                       HierarchyAction::Prefetch);
        s.when = "overlap";
        s.reason = reason;
      } else {
        setLegalSelect(s, {HierarchyAction::Preserve},
                       HierarchyAction::Preserve);
        s.when = "as-written";
        s.reason = reason;
      }
    } else if (srcSpace && *srcSpace == Space::SSD && dstSpace &&
               isHostLike(*dstSpace)) {
      setLegalSelect(s, {HierarchyAction::Materialize},
                     HierarchyAction::Materialize);
      s.when = "eager";
      s.reason = "first-host-residency";
    } else {
      setLegalSelect(s, {HierarchyAction::Transfer},
                     HierarchyAction::Transfer);
      s.when = "sequential";
      s.reason = "consume-requires-device";
    }
    recordLiveResidency(live, object, dstSpace,
                        outwardResidency(xfer.getBuffer()));
    sites.push_back(std::move(s));
  });
  return sites;
}

/// KEEP_RESIDENCY is jointly legal only if a prior selected action on
/// the same object produced that dst space. MATERIALIZE / PREFETCH /
/// TRANSFER / PRESERVE all still execute the as-written movement, so
/// they produce dst. This filter does not invent actions or skip
/// transfers. Cost does not participate.
static bool jointCompatible(ArrayRef<HierarchySite> sites,
                            ArrayRef<unsigned> siteIds,
                            ArrayRef<HierarchyAction> acts) {
  llvm::StringSet<> live;
  for (size_t i = 0; i < siteIds.size(); ++i) {
    const HierarchySite &s = sites[siteIds[i]];
    if (acts[i] == HierarchyAction::KeepResidency && !live.contains(s.dst))
      return false;
    live.insert(s.dst);
  }
  return true;
}

static void enumerateJoint(ArrayRef<HierarchySite> sites,
                           ArrayRef<unsigned> siteIds, unsigned idx,
                           SmallVectorImpl<HierarchyAction> &cur,
                           SmallVectorImpl<SmallVector<HierarchyAction, 8>> &out) {
  constexpr unsigned kCap = 64;
  if (out.size() >= kCap)
    return;
  if (idx == siteIds.size()) {
    if (jointCompatible(sites, siteIds, cur))
      out.emplace_back(cur.begin(), cur.end());
    return;
  }
  for (HierarchyAction a : sites[siteIds[idx]].legal) {
    cur.push_back(a);
    enumerateJoint(sites, siteIds, idx + 1, cur, out);
    cur.pop_back();
  }
}

static bool sameAssignment(ArrayRef<HierarchyAction> a,
                           ArrayRef<HierarchyAction> b) {
  if (a.size() != b.size())
    return false;
  for (size_t i = 0; i < a.size(); ++i)
    if (a[i] != b[i])
      return false;
  return true;
}

/// Maximal contiguous runs of the same objectKey in program order.
/// Interleaved objects start a new chain; the same object later is a
/// new chain, not a splice. F(chain) is the compatible product of
/// F(site). default-3g selects the historical 3G tuple; it does not
/// re-decide legality and is not Cost.
static void finalizeJointChain(JointChain &c, ArrayRef<HierarchySite> sites) {
  c.policy = "default-3g";
  SmallVector<HierarchyAction, 8> cur;
  enumerateJoint(sites, c.siteIds, 0, cur, c.legal);
  SmallVector<HierarchyAction, 8> preferred;
  for (unsigned id : c.siteIds)
    preferred.push_back(sites[id].action);
  bool found = false;
  for (const auto &asn : c.legal) {
    if (sameAssignment(asn, preferred)) {
      c.selected.assign(asn.begin(), asn.end());
      found = true;
      break;
    }
  }
  if (!found && !c.legal.empty())
    c.selected = c.legal.front();
}

static SmallVector<JointChain, 4>
planJointChains(ArrayRef<HierarchySite> sites) {
  SmallVector<JointChain, 4> chains;
  JointChain cur;
  auto flush = [&]() {
    if (cur.siteIds.empty())
      return;
    cur.id = static_cast<unsigned>(chains.size());
    finalizeJointChain(cur, sites);
    chains.push_back(std::move(cur));
    cur = JointChain();
  };
  for (const HierarchySite &s : sites) {
    if (!cur.siteIds.empty() && cur.objectKey != s.objectKey)
      flush();
    if (cur.siteIds.empty())
      cur.objectKey = s.objectKey;
    cur.siteIds.push_back(s.id);
  }
  flush();
  return chains;
}

static void printJointChain(const JointChain &c) {
  llvm::errs() << "hierarchy-joint #" << c.id << " object=" << c.objectKey
               << " sites=" << joinIds(c.siteIds) << " legal=" << c.legal.size()
               << " selected=" << joinActions(c.selected, '|')
               << " policy=" << c.policy
               << " note selection-ne-cost note default-3g-frozen\n";
  llvm::errs() << "hierarchy-joint #" << c.id << " : object " << c.objectKey
               << "\n";
  llvm::errs() << "    sites     : " << joinIds(c.siteIds) << "\n";
  llvm::errs() << "    |F|       : " << c.legal.size() << "\n";
  llvm::errs() << "    selected  : " << joinActions(c.selected, '|') << "\n";
  llvm::errs() << "    policy    : " << c.policy << "\n";
  for (const auto &asn : c.legal)
    llvm::errs() << "hierarchy-joint-candidate #" << c.id
                 << " actions=" << joinActions(asn, '|') << "\n";
}

static void printJointSchedule(ArrayRef<JointChain> chains) {
  unsigned product = 1;
  bool inLegal = true;
  for (const JointChain &c : chains) {
    product *= std::max<unsigned>(1, c.legal.size());
    bool found = false;
    for (const auto &asn : c.legal)
      if (sameAssignment(asn, c.selected))
        found = true;
    if (!found)
      inLegal = false;
  }
  llvm::errs() << "hierarchy-joint-schedule chains=" << chains.size()
               << " legal=" << product
               << " selected-in-legal=" << (inLegal ? "yes" : "no")
               << " policy=default-3g note selection-ne-cost"
               << " note default-3g-frozen cost=unchanged\n";
}

/// F(program) is the product of F(chain) in program order, and only
/// when that product is fully enumerated. Does not splice chains or
/// change the contiguous-run definition. default-3g is the historical
/// per-chain tuple; if that tuple is not in F, it is an invariant
/// failure, not a first-tuple fallback. Cost does not prune or invent
/// members.
static bool sameGlobal(ArrayRef<ChainAssignment> a,
                       ArrayRef<ChainAssignment> b) {
  if (a.size() != b.size())
    return false;
  for (size_t i = 0; i < a.size(); ++i)
    if (!sameAssignment(a[i], b[i]))
      return false;
  return true;
}

static bool chainSelectedInF(const JointChain &c) {
  for (const auto &asn : c.legal)
    if (sameAssignment(asn, c.selected))
      return true;
  return false;
}

static bool historicalTupleInChains(ArrayRef<JointChain> chains) {
  for (const JointChain &c : chains)
    if (!chainSelectedInF(c))
      return false;
  return true;
}

static void enumerateGlobal(ArrayRef<JointChain> chains, unsigned idx,
                            SmallVectorImpl<ChainAssignment> &cur,
                            SmallVectorImpl<SmallVector<ChainAssignment, 4>> &out) {
  if (idx == chains.size()) {
    out.emplace_back(cur.begin(), cur.end());
    return;
  }
  // An empty F(chain) makes the product empty. Do not invent a
  // placeholder assignment.
  if (chains[idx].legal.empty())
    return;
  for (const auto &asn : chains[idx].legal) {
    cur.push_back(asn);
    enumerateGlobal(chains, idx + 1, cur, out);
    cur.pop_back();
  }
}

static std::string globalProductLabel(const GlobalSchedule &g) {
  if (g.productOverflow)
    return "overflow";
  return std::to_string(g.product);
}

static std::string globalLegalLabel(const GlobalSchedule &g) {
  if (g.truncated)
    return "not-enumerated";
  return std::to_string(g.legal.size());
}

static GlobalSchedule planGlobalSchedule(ArrayRef<JointChain> chains) {
  GlobalSchedule g;
  g.policy = "default-3g";
  g.product = 1;
  for (const JointChain &c : chains) {
    uint64_t n = c.legal.size();
    if (n == 0) {
      g.product = 0;
      break;
    }
    if (g.product > UINT64_MAX / n) {
      g.productOverflow = true;
      break;
    }
    g.product *= n;
  }
  g.truncated = g.productOverflow || g.product > kGlobalFEnumerateCap;
  g.enumerated = !g.truncated;
  for (const JointChain &c : chains)
    g.selected.push_back(c.selected);
  g.historicalInF = historicalTupleInChains(chains);
  if (g.enumerated) {
    SmallVector<ChainAssignment, 4> cur;
    enumerateGlobal(chains, 0, cur, g.legal);
    if (g.historicalInF) {
      bool inProduct = false;
      for (const auto &asn : g.legal)
        if (sameGlobal(asn, g.selected))
          inProduct = true;
      g.historicalInF = inProduct;
    }
  }
  return g;
}

static void printGlobalSchedule(const GlobalSchedule &g, unsigned nChains) {
  if (!g.historicalInF)
    llvm::errs() << "hierarchy-global-error historical-tuple-not-in-F\n";
  llvm::errs() << "hierarchy-global selected=" << joinGlobal(g.selected)
               << " product=" << globalProductLabel(g)
               << " enumerated=" << (g.enumerated ? "yes" : "no")
               << " truncated=" << (g.truncated ? "yes" : "no")
               << " legal=" << globalLegalLabel(g) << " policy=" << g.policy
               << " note selection-ne-cost note default-3g-frozen"
               << " note chain-def-frozen note truncated-ne-complete-F"
               << " note historical-tuple-or-fail\n";
  llvm::errs() << "hierarchy-global-schedule chains=" << nChains
               << " product=" << globalProductLabel(g)
               << " enumerated=" << (g.enumerated ? "yes" : "no")
               << " truncated=" << (g.truncated ? "yes" : "no")
               << " legal=" << globalLegalLabel(g)
               << " selected-in-legal=" << (g.historicalInF ? "yes" : "no")
               << " policy=default-3g note selection-ne-cost"
               << " note default-3g-frozen note chain-def-frozen"
               << " note truncated-ne-complete-F"
               << " note historical-tuple-or-fail cost=unchanged\n";
  if (!g.enumerated)
    return;
  for (const auto &asn : g.legal)
    llvm::errs() << "hierarchy-global-candidate actions="
                 << joinGlobal(asn) << "\n";
}

/// Structural ticks over an enumerated F(program) member.
/// PRESERVE pays 1 against overlap (PREFETCH is 0). Rematerialize
/// TRANSFER pays 1 against KEEP_RESIDENCY. Singleton TRANSFER /
/// MATERIALIZE do not. Not Score_3, not microseconds, not a new
/// Capability cell. Cost does not invent members of F.
static bool legalContains(const HierarchySite &s, HierarchyAction want) {
  for (HierarchyAction a : s.legal)
    if (a == want)
      return true;
  return false;
}

static const HierarchySite *siteById(ArrayRef<HierarchySite> sites,
                                     unsigned id) {
  if (id < sites.size() && sites[id].id == id)
    return &sites[id];
  for (const HierarchySite &s : sites)
    if (s.id == id)
      return &s;
  return nullptr;
}

static int64_t costV04Ticks(ArrayRef<JointChain> chains,
                            ArrayRef<HierarchySite> sites,
                            ArrayRef<ChainAssignment> tuple) {
  int64_t ticks = 0;
  unsigned n = std::min((unsigned)chains.size(), (unsigned)tuple.size());
  for (unsigned i = 0; i < n; ++i) {
    const JointChain &c = chains[i];
    ArrayRef<HierarchyAction> acts = tuple[i];
    unsigned m = std::min((unsigned)c.siteIds.size(), (unsigned)acts.size());
    for (unsigned j = 0; j < m; ++j) {
      HierarchyAction a = acts[j];
      const HierarchySite *s = siteById(sites, c.siteIds[j]);
      if (!s)
        continue;
      if (a == HierarchyAction::Preserve)
        ticks += 1;
      else if (a == HierarchyAction::Transfer &&
               legalContains(*s, HierarchyAction::KeepResidency))
        ticks += 1;
    }
  }
  return ticks;
}

struct GlobalCostRank {
  SmallVector<ChainAssignment, 4> ranked;
  int64_t score = 0;
  unsigned argminSize = 0;
  bool applicable = false;
  bool rankedInLegal = false;
  bool rankedEqDefault3g = false;
  SmallVector<int64_t, 16> candidateScores;
};

/// Rank fully enumerated F(program) under policy=cost-v04.
/// A truncated product is not ranked. default-3g is not retargeted.
/// Among ArgMin ties, prefer the historical tuple when it is a minimum.
static GlobalCostRank rankGlobalCost(ArrayRef<JointChain> chains,
                                     ArrayRef<HierarchySite> sites,
                                     const GlobalSchedule &g) {
  GlobalCostRank r;
  if (!g.enumerated)
    return r;
  r.applicable = true;
  int64_t best = INT64_MAX;
  SmallVector<unsigned, 8> argminIdx;
  r.candidateScores.resize(g.legal.size());
  for (unsigned i = 0; i < g.legal.size(); ++i) {
    int64_t t = costV04Ticks(chains, sites, g.legal[i]);
    r.candidateScores[i] = t;
    if (t < best) {
      best = t;
      argminIdx.clear();
      argminIdx.push_back(i);
    } else if (t == best) {
      argminIdx.push_back(i);
    }
  }
  r.score = best == INT64_MAX ? 0 : best;
  r.argminSize = argminIdx.size();
  int pick = -1;
  for (unsigned i : argminIdx) {
    if (sameGlobal(g.legal[i], g.selected)) {
      pick = (int)i;
      break;
    }
  }
  if (pick < 0 && !argminIdx.empty())
    pick = (int)argminIdx.front();
  if (pick >= 0) {
    r.ranked.assign(g.legal[pick].begin(), g.legal[pick].end());
    r.rankedInLegal = true;
  }
  r.rankedEqDefault3g = g.historicalInF && pick >= 0 &&
                        sameGlobal(r.ranked, g.selected);
  return r;
}

static void printGlobalCostRank(const GlobalCostRank &r,
                                const GlobalSchedule &g) {
  if (!r.applicable) {
    llvm::errs() << "hierarchy-global-cost ranked=not-enumerated score=n/a"
                 << " policy=cost-v04 note cost-does-not-rank-truncated-F"
                 << " note cost-ne-legality note cost-ne-rewrite-license"
                 << " note default-3g-frozen note truncated-ne-ranked"
                 << " note not-s2c2-argmin note not-score3"
                 << " note not-new-capability-grid"
                 << " note cost-v04-structural-frozen\n";
    llvm::errs() << "hierarchy-global-cost-schedule enumerated=no truncated=yes"
                 << " ranked-in-legal=n/a ranked-eq-default-3g=n/a"
                 << " argmin-size=n/a policy=cost-v04"
                 << " note cost-does-not-rank-truncated-F"
                 << " note default-3g-frozen\n";
    llvm::errs() << "hierarchy-global-cost-coincide diverge=n/a"
                 << " note cost-does-not-rank-truncated-F"
                 << " note structural-ticks-not-wallclock"
                 << " note runtime-correlation-not-applicable"
                 << " note cost-v04-structural-frozen\n";
    return;
  }
  llvm::errs() << "hierarchy-global-cost ranked=" << joinGlobal(r.ranked)
               << " score=" << r.score << " policy=cost-v04"
               << " note cost-ne-legality note cost-ne-rewrite-license"
               << " note default-3g-frozen note truncated-ne-ranked"
               << " note not-s2c2-argmin note not-score3"
               << " note not-new-capability-grid"
               << " note cost-v04-structural-frozen\n";
  llvm::errs() << "hierarchy-global-cost-schedule enumerated=yes truncated=no"
               << " ranked-in-legal=" << (r.rankedInLegal ? "yes" : "no")
               << " ranked-eq-default-3g="
               << (r.rankedEqDefault3g ? "yes" : "no")
               << " argmin-size=" << r.argminSize << " policy=cost-v04"
               << " note cost-ne-legality note default-3g-frozen\n";
  llvm::errs() << "hierarchy-global-cost-coincide diverge="
               << (r.rankedEqDefault3g ? "no" : "yes")
               << " note structural-ticks-not-wallclock"
               << " note runtime-correlation-not-applicable"
               << " note cost-v04-structural-frozen\n";
  for (unsigned i = 0; i < g.legal.size(); ++i)
    llvm::errs() << "hierarchy-global-cost-candidate actions="
                 << joinGlobal(g.legal[i]) << " score=" << r.candidateScores[i]
                 << "\n";
}

enum class MeasuredStatus { No, Yes, Pending };

struct MeasuredCostRecord {
  std::string profile;
  std::string workloadClass;
  std::string signature;
  int64_t timeUs = 0;
  int64_t correctness = 0;
  MeasuredStatus measured = MeasuredStatus::No;
};

struct GlobalMeasuredRank {
  SmallVector<ChainAssignment, 4> ranked;
  unsigned measuredCount = 0;
  unsigned argminSize = 0;
  bool enumerated = false;
  bool applicable = false;
  bool rankedInLegal = false;
  bool rankedEqDefault3g = false;
  bool defaultMeasured = false;
  SmallVector<bool, 16> hasEvidence;
  SmallVector<int64_t, 16> candidateUs;
};

static LogicalResult
loadMeasuredCostTable(StringRef path,
                      SmallVectorImpl<MeasuredCostRecord> &out) {
  if (path.empty())
    return success();
  std::string resolved = resolveExistingPath(path, {});
  auto fileOr = llvm::MemoryBuffer::getFile(resolved);
  if (!fileOr) {
    llvm::errs() << "s2c2-evidence-bounded-schedule: cannot read "
                 << "measured-cost-table " << path << "\n";
    return failure();
  }
  StringRef text = fileOr.get()->getBuffer();
  while (!text.empty()) {
    auto [line, rest] = text.split('\n');
    text = rest;
    line = line.trim();
    if (line.empty() || line.starts_with("#"))
      continue;
    auto parsed = llvm::json::parse(line);
    if (!parsed) {
      llvm::errs() << "s2c2-evidence-bounded-schedule: invalid JSONL in "
                   << path << "\n";
      return failure();
    }
    auto *obj = parsed->getAsObject();
    if (!obj)
      continue;
    MeasuredCostRecord rec;
    if (auto p = obj->getString("profile"))
      rec.profile = p->str();
    if (auto w = obj->getString("workload_class"))
      rec.workloadClass = w->str();
    if (auto s = obj->getString("candidate_signature"))
      rec.signature = s->str();
    if (auto t = obj->getInteger("measured_time_us"))
      rec.timeUs = *t;
    else if (auto tn = obj->getNumber("measured_time_us"))
      rec.timeUs = (int64_t)*tn;
    if (auto c = obj->getInteger("correctness"))
      rec.correctness = *c;
    else if (auto cn = obj->getNumber("correctness"))
      rec.correctness = (int64_t)*cn;
    if (auto m = obj->getString("measured")) {
      if (m->equals_insensitive("yes"))
        rec.measured = MeasuredStatus::Yes;
      else if (m->equals_insensitive("pending"))
        rec.measured = MeasuredStatus::Pending;
      else
        rec.measured = MeasuredStatus::No;
    }
    // Keep no/pending rows so the matcher can reject them. Only
    // measured=yes && correctness=1 is ranking evidence.
    if (rec.signature.empty())
      continue;
    out.push_back(std::move(rec));
  }
  return success();
}

static const MeasuredCostRecord *
findMeasuredRecord(ArrayRef<MeasuredCostRecord> table, StringRef profile,
                   StringRef signature) {
  const MeasuredCostRecord *hit = nullptr;
  for (const MeasuredCostRecord &r : table) {
    if (r.profile == profile && r.signature == signature &&
        r.measured == MeasuredStatus::Yes && r.correctness == 1)
      hit = &r;
  }
  return hit;
}

/// Rank enumerated F(program) under policy=measured-storage-v1.
/// ArgMin is over measured ∩ F only. A truncated product is not
/// ranked. default-3g is not retargeted. cost-v04 is not changed.
static GlobalMeasuredRank
rankGlobalMeasured(const GlobalSchedule &g, StringRef profile,
                   ArrayRef<MeasuredCostRecord> table) {
  GlobalMeasuredRank r;
  if (!g.enumerated)
    return r;
  r.enumerated = true;
  r.hasEvidence.resize(g.legal.size());
  r.candidateUs.assign(g.legal.size(), -1);
  int64_t best = INT64_MAX;
  SmallVector<unsigned, 8> argminIdx;
  for (unsigned i = 0; i < g.legal.size(); ++i) {
    std::string sig = joinGlobal(g.legal[i]);
    const MeasuredCostRecord *rec = findMeasuredRecord(table, profile, sig);
    if (!rec)
      continue;
    r.hasEvidence[i] = true;
    r.candidateUs[i] = rec->timeUs;
    r.measuredCount += 1;
    if (sameGlobal(g.legal[i], g.selected))
      r.defaultMeasured = true;
    if (rec->timeUs < best) {
      best = rec->timeUs;
      argminIdx.clear();
      argminIdx.push_back(i);
    } else if (rec->timeUs == best) {
      argminIdx.push_back(i);
    }
  }
  if (r.measuredCount < 2)
    return r;
  r.applicable = true;
  r.argminSize = argminIdx.size();
  int pick = -1;
  if (r.defaultMeasured) {
    for (unsigned i : argminIdx) {
      if (sameGlobal(g.legal[i], g.selected)) {
        pick = (int)i;
        break;
      }
    }
  }
  if (pick < 0 && !argminIdx.empty())
    pick = (int)argminIdx.front();
  if (pick >= 0) {
    r.ranked.assign(g.legal[pick].begin(), g.legal[pick].end());
    r.rankedInLegal = true;
  }
  r.rankedEqDefault3g = r.defaultMeasured && pick >= 0 &&
                        sameGlobal(r.ranked, g.selected);
  return r;
}

static void printGlobalMeasuredRank(const GlobalMeasuredRank &r,
                                    const GlobalSchedule &g) {
  if (!g.enumerated) {
    llvm::errs() << "hierarchy-global-measured ranked=not-enumerated"
                 << " policy=measured-storage-v1"
                 << " note measured-does-not-rank-truncated-F"
                 << " note measured-ne-legality"
                 << " note measured-ne-rewrite-license"
                 << " note default-3g-frozen"
                 << " note cost-v04-structural-frozen"
                 << " note not-new-capability-grid"
                 << " note do-not-filecheck-microseconds"
                 << " note measured-last-wins-duplicate-policy\n";
    llvm::errs() << "hierarchy-global-measured-schedule enumerated=no"
                 << " truncated=yes ranked-in-legal=n/a"
                 << " ranked-eq-default-3g=n/a measured-count=n/a"
                 << " argmin-size=n/a policy=measured-storage-v1"
                 << " note measured-does-not-rank-truncated-F"
                 << " note default-3g-frozen\n";
    llvm::errs() << "hierarchy-global-measured-diverge diverge=n/a"
                 << " note measured-does-not-rank-truncated-F"
                 << " note runtime-validation-pending"
                 << " note cost-v04-structural-frozen\n";
    return;
  }
  if (!r.applicable) {
    llvm::errs() << "hierarchy-global-measured ranked=not-measured"
                 << " policy=measured-storage-v1"
                 << " note measured-needs-two-records"
                 << " note measured-yes-and-correctness"
                 << " note measured-ne-legality"
                 << " note measured-ne-rewrite-license"
                 << " note default-3g-frozen"
                 << " note cost-v04-structural-frozen"
                 << " note not-new-capability-grid"
                 << " note do-not-filecheck-microseconds"
                 << " note measured-last-wins-duplicate-policy\n";
    llvm::errs() << "hierarchy-global-measured-schedule enumerated=yes"
                 << " truncated=no ranked-in-legal=n/a"
                 << " ranked-eq-default-3g=n/a measured-count="
                 << r.measuredCount << " argmin-size=n/a"
                 << " policy=measured-storage-v1"
                 << " note measured-needs-two-records"
                 << " note measured-yes-and-correctness"
                 << " note default-3g-frozen\n";
    llvm::errs() << "hierarchy-global-measured-diverge diverge=n/a"
                 << " note measured-needs-two-records"
                 << " note runtime-validation-pending"
                 << " note cost-v04-structural-frozen\n";
    return;
  }
  llvm::errs() << "hierarchy-global-measured ranked=" << joinGlobal(r.ranked)
               << " policy=measured-storage-v1"
               << " note measured-yes-and-correctness"
               << " note measured-ne-legality"
               << " note measured-ne-rewrite-license"
               << " note default-3g-frozen"
               << " note cost-v04-structural-frozen"
               << " note not-new-capability-grid"
               << " note do-not-filecheck-microseconds"
               << " note measured-last-wins-duplicate-policy\n";
  llvm::errs() << "hierarchy-global-measured-schedule enumerated=yes"
               << " truncated=no ranked-in-legal="
               << (r.rankedInLegal ? "yes" : "no")
               << " ranked-eq-default-3g="
               << (!r.defaultMeasured ? "n/a"
                                      : (r.rankedEqDefault3g ? "yes" : "no"))
               << " measured-count=" << r.measuredCount
               << " argmin-size=" << r.argminSize
               << " policy=measured-storage-v1"
               << " note measured-ne-legality note default-3g-frozen\n";
  llvm::errs() << "hierarchy-global-measured-diverge diverge="
               << (!r.defaultMeasured ? "n/a"
                                      : (r.rankedEqDefault3g ? "no" : "yes"))
               << " note runtime-validation-pending"
               << " note cost-v04-structural-frozen\n";
  for (unsigned i = 0; i < g.legal.size(); ++i)
    llvm::errs() << "hierarchy-global-measured-candidate actions="
                 << joinGlobal(g.legal[i])
                 << " evidence=" << (r.hasEvidence[i] ? "yes" : "no") << "\n";
}

enum class SchedulePolicyKind { Unset, Default3g, CostV04, MeasuredStorageV1 };

static FailureOr<SchedulePolicyKind> parseSchedulePolicy(StringRef name) {
  if (name.empty())
    return SchedulePolicyKind::Unset;
  if (name == "default-3g")
    return SchedulePolicyKind::Default3g;
  if (name == "cost-v04")
    return SchedulePolicyKind::CostV04;
  if (name == "measured-storage-v1")
    return SchedulePolicyKind::MeasuredStorageV1;
  llvm::errs() << "s2c2-opt: unknown --schedule-policy=" << name
               << " (default-3g|cost-v04|measured-storage-v1)\n";
  return failure();
}

static StringRef schedulePolicyName(SchedulePolicyKind k) {
  switch (k) {
  case SchedulePolicyKind::Default3g:
    return "default-3g";
  case SchedulePolicyKind::CostV04:
    return "cost-v04";
  case SchedulePolicyKind::MeasuredStorageV1:
    return "measured-storage-v1";
  case SchedulePolicyKind::Unset:
    return "unset";
  }
  return "unset";
}

struct NamedPolicyPick {
  std::string selected;
  std::string source;
  std::string reason;
  std::string coincide;
  bool applicable = false;
};

static NamedPolicyPick
pickNamedPolicy(SchedulePolicyKind kind, const GlobalSchedule &g,
                const GlobalCostRank &cost, const GlobalMeasuredRank &meas) {
  NamedPolicyPick p;
  p.selected = joinGlobal(g.selected);
  p.source = "default-3g";
  p.reason = "historical-tuple";
  p.coincide = "yes";
  p.applicable = g.historicalInF;
  if (kind == SchedulePolicyKind::Unset || kind == SchedulePolicyKind::Default3g)
    return p;
  if (kind == SchedulePolicyKind::CostV04) {
    if (!g.enumerated || !cost.applicable) {
      p.applicable = false;
      p.reason = g.enumerated ? "cost-not-ranked" : "not-enumerated";
      return p;
    }
    p.applicable = true;
    p.selected = joinGlobal(cost.ranked);
    p.source = "cost-v04";
    p.reason = "cost-v04-argmin";
    p.coincide = cost.rankedEqDefault3g ? "yes" : "no";
    return p;
  }
  if (!g.enumerated || !meas.applicable) {
    p.applicable = false;
    p.reason = g.enumerated ? "not-measured" : "not-enumerated";
    return p;
  }
  p.applicable = true;
  p.selected = joinGlobal(meas.ranked);
  p.source = "measured-storage-v1";
  p.reason = "measured-cost-argmin";
  p.coincide = !meas.defaultMeasured ? "n/a"
                                     : (meas.rankedEqDefault3g ? "yes" : "no");
  return p;
}

static void printNamedSchedulePolicy(SchedulePolicyKind kind,
                                     const NamedPolicyPick &p) {
  if (kind == SchedulePolicyKind::Unset)
    return;
  llvm::errs() << "s2c2-schedule-policy name=" << schedulePolicyName(kind)
               << " selected=" << p.selected
               << " applicable=" << (p.applicable ? "yes" : "no")
               << " source=" << p.source << " rewrite=no"
               << " note selection-ne-legality"
               << " note selection-ne-rewrite-license"
               << " note default-3g-frozen"
               << " note cost-v04-structural-frozen"
               << " note five-e-not-opened"
               << " note campaign-5a-5d-frozen"
               << " note measured-ne-rewrite-license cost=unchanged\n";
  llvm::errs() << "s2c2-schedule-policy coincide-default-3g=" << p.coincide
               << " reason=" << p.reason << " rewrite=no\n";
}

static void printScheduleExplain(SchedulePolicyKind kind, StringRef profile,
                                 ArrayRef<HierarchySite> sites,
                                 const GlobalSchedule &g,
                                 const GlobalCostRank &cost,
                                 const GlobalMeasuredRank &meas,
                                 const NamedPolicyPick &p) {
  SchedulePolicyKind shown =
      kind == SchedulePolicyKind::Unset ? SchedulePolicyKind::Default3g : kind;
  llvm::errs() << "s2c2-schedule-explain profile=" << profile
               << " policy=" << schedulePolicyName(shown) << "\n";
  llvm::errs() << "s2c2-schedule-explain enumerated="
               << (g.enumerated ? "yes" : "no")
               << " truncated=" << (g.truncated ? "yes" : "no")
               << " product=" << globalProductLabel(g)
               << " legal=" << globalLegalLabel(g) << "\n";
  for (const HierarchySite &s : sites) {
    llvm::errs() << "s2c2-schedule-explain site #" << s.id
                 << " legal=" << joinActions(s.legal)
                 << " selected=" << hierarchyActionStr(s.action)
                 << " policy=default-3g\n";
  }
  if (!g.enumerated) {
    llvm::errs() << "s2c2-schedule-explain ranking=not-enumerated\n";
  } else {
    for (unsigned i = 0; i < g.legal.size(); ++i) {
      llvm::errs() << "s2c2-schedule-explain F-member actions="
                   << joinGlobal(g.legal[i]);
      if (meas.hasEvidence.empty() || i >= meas.hasEvidence.size() ||
          !meas.hasEvidence[i])
        llvm::errs() << " evidence=no time-us=n/a";
      else
        llvm::errs() << " evidence=yes time-us=" << meas.candidateUs[i];
      if (cost.applicable && i < cost.candidateScores.size())
        llvm::errs() << " cost-v04=" << cost.candidateScores[i];
      else
        llvm::errs() << " cost-v04=n/a";
      llvm::errs() << "\n";
    }
    if (shown == SchedulePolicyKind::MeasuredStorageV1 && !meas.applicable)
      llvm::errs() << "s2c2-schedule-explain ranking=not-measured\n";
    if (shown == SchedulePolicyKind::CostV04 && !cost.applicable)
      llvm::errs() << "s2c2-schedule-explain ranking=not-ranked\n";
  }
  llvm::errs() << "s2c2-schedule-explain selected=" << p.selected
               << " source=" << p.source
               << " applicable=" << (p.applicable ? "yes" : "no") << "\n";
  llvm::errs() << "s2c2-schedule-explain rewrite=no reason=" << p.reason
               << "\n";
  llvm::errs() << "s2c2-schedule-explain default-3g=" << joinGlobal(g.selected)
               << " coincide=" << p.coincide << "\n";
  llvm::errs() << "s2c2-schedule-explain note selection-ne-legality"
               << " note selection-ne-rewrite-license"
               << " note five-e-not-opened"
               << " note do-not-filecheck-microseconds"
               << " note compiler-ne-campaign-log cost=unchanged\n";
}

static bool isStorageOverlapConcurrent(ConcurrentOp conc) {
  SmallVector<TaskOp> tasks(conc.getBody().front().getOps<TaskOp>());
  if (tasks.size() != 2)
    return false;
  return isStorageCommOverlap(
      classifyPair(tasks[0].getBody(), tasks[1].getBody()));
}

/// Report `scf.for` storage-pipeline structure. Does not rewrite the loop.
static void reportLoopPipeline(ModuleOp module) {
  unsigned loops = 0;
  module.walk([&](scf::ForOp forOp) {
    loops += 1;
    int64_t trip = -1;
    auto lb = forOp.getLowerBound().getDefiningOp<arith::ConstantIndexOp>();
    auto ub = forOp.getUpperBound().getDefiningOp<arith::ConstantIndexOp>();
    auto st = forOp.getStep().getDefiningOp<arith::ConstantIndexOp>();
    if (lb && ub && st && st.value() != 0) {
      int64_t step = st.value();
      trip = (ub.value() - lb.value() + step - 1) / step;
    }

    unsigned prefetchSites = 0;
    unsigned consumeSites = 0;
    unsigned concurrent = 0;
    forOp.walk([&](ConcurrentOp conc) {
      concurrent += 1;
      if (isStorageOverlapConcurrent(conc))
        prefetchSites += 1;
    });
    forOp.walk([&](TransferOp t) {
      auto dst = bufferSpace(t.getBuffer());
      if (dst && isDeviceLike(*dst))
        consumeSites += 1;
    });

    llvm::errs() << "loop-pipeline op=scf.for";
    if (trip >= 0)
      llvm::errs() << " trip=" << trip;
    llvm::errs() << " iter-args=" << forOp.getNumRegionIterArgs();
    llvm::errs() << " prefetch-sites=" << prefetchSites;
    llvm::errs() << " consume-sites=" << consumeSites;
    llvm::errs() << " concurrent=" << concurrent;
    llvm::errs() << " note software-pipeline-storage\n";
  });
  llvm::errs() << "loop-pipeline loops=" << loops
               << " note loop-carried-lifetime cost=unchanged\n";
}

static LogicalResult dumpWorkloadSchedule(StringRef path,
                                          const ResolvedProfile &evi,
                                          ArrayRef<WorkloadDecision> decs,
                                          ArrayRef<HierarchySite> sites,
                                          ArrayRef<JointChain> chains,
                                          ReuseStats reuse,
                                          ArrayRef<MeasuredCostRecord> table,
                                          StringRef schedulePolicy = {}) {
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
    llvm::json::Array legal;
    for (HierarchyAction a : s.legal)
      legal.push_back(hierarchyActionStr(a).str());
    obj["legal"] = std::move(legal);
    obj["selected"] = hierarchyActionStr(s.action).str();
    obj["policy"] = s.policy;
    obj["object"] = (int64_t)s.objectKey;
    hier.push_back(std::move(obj));
  }
  root["hierarchy"] = std::move(hier);
  root["hierarchy_sites"] = (int64_t)sites.size();
  root["hierarchy_materialize"] = (int64_t)hMat;
  root["hierarchy_prefetch"] = (int64_t)hPref;
  root["hierarchy_transfer"] = (int64_t)hXfer;
  root["hierarchy_keep_residency"] = (int64_t)hKeep;
  root["hierarchy_preserve"] = (int64_t)hPres;
  unsigned multi = 0;
  bool inLegal = true;
  for (const HierarchySite &s : sites) {
    if (s.legal.size() > 1)
      ++multi;
    bool found = false;
    for (HierarchyAction a : s.legal)
      if (a == s.action)
        found = true;
    if (!found)
      inLegal = false;
  }
  root["hierarchy_multi_candidate"] = (int64_t)multi;
  root["hierarchy_selected_in_legal"] = inLegal ? "yes" : "no";
  root["hierarchy_policy"] = "default-3g";
  llvm::json::Array joint;
  unsigned jointProduct = 1;
  bool jointInLegal = true;
  for (const JointChain &c : chains) {
    llvm::json::Object obj;
    obj["id"] = (int64_t)c.id;
    obj["object"] = (int64_t)c.objectKey;
    llvm::json::Array ids;
    for (unsigned id : c.siteIds)
      ids.push_back((int64_t)id);
    obj["sites"] = std::move(ids);
    llvm::json::Array legal;
    for (const auto &asn : c.legal) {
      llvm::json::Array acts;
      for (HierarchyAction a : asn)
        acts.push_back(hierarchyActionStr(a).str());
      legal.push_back(std::move(acts));
    }
    obj["legal"] = std::move(legal);
    llvm::json::Array selected;
    for (HierarchyAction a : c.selected)
      selected.push_back(hierarchyActionStr(a).str());
    obj["selected"] = std::move(selected);
    obj["policy"] = c.policy;
    obj["legal_count"] = (int64_t)c.legal.size();
    joint.push_back(std::move(obj));
    jointProduct *= std::max<unsigned>(1, c.legal.size());
    bool found = false;
    for (const auto &asn : c.legal)
      if (sameAssignment(asn, c.selected))
        found = true;
    if (!found)
      jointInLegal = false;
  }
  root["hierarchy_joint"] = std::move(joint);
  root["hierarchy_joint_chains"] = (int64_t)chains.size();
  root["hierarchy_joint_legal"] = (int64_t)jointProduct;
  root["hierarchy_joint_selected_in_legal"] = jointInLegal ? "yes" : "no";
  root["hierarchy_joint_policy"] = "default-3g";
  GlobalSchedule glob = planGlobalSchedule(chains);
  llvm::json::Array globLegal;
  if (glob.enumerated) {
    for (const auto &asn : glob.legal) {
      llvm::json::Array chainsAsn;
      for (const auto &chainAsn : asn) {
        llvm::json::Array acts;
        for (HierarchyAction a : chainAsn)
          acts.push_back(hierarchyActionStr(a).str());
        chainsAsn.push_back(std::move(acts));
      }
      globLegal.push_back(std::move(chainsAsn));
    }
  }
  llvm::json::Array globSelected;
  for (const auto &chainAsn : glob.selected) {
    llvm::json::Array acts;
    for (HierarchyAction a : chainAsn)
      acts.push_back(hierarchyActionStr(a).str());
    globSelected.push_back(std::move(acts));
  }
  root["hierarchy_global"] = std::move(globLegal);
  root["hierarchy_global_selected"] = std::move(globSelected);
  root["hierarchy_global_chains"] = (int64_t)chains.size();
  if (glob.productOverflow)
    root["hierarchy_global_product"] = "overflow";
  else
    root["hierarchy_global_product"] = (int64_t)glob.product;
  root["hierarchy_global_enumerated"] = glob.enumerated ? "yes" : "no";
  root["hierarchy_global_truncated"] = glob.truncated ? "yes" : "no";
  if (glob.truncated)
    root["hierarchy_global_legal"] = "not-enumerated";
  else
    root["hierarchy_global_legal"] = (int64_t)glob.legal.size();
  root["hierarchy_global_selected_in_legal"] =
      glob.historicalInF ? "yes" : "no";
  root["hierarchy_global_policy"] = "default-3g";
  if (!glob.historicalInF)
    root["hierarchy_global_error"] = "historical-tuple-not-in-F";
  GlobalCostRank costRank = rankGlobalCost(chains, sites, glob);
  root["hierarchy_global_cost_policy"] = "cost-v04";
  if (!costRank.applicable) {
    root["hierarchy_global_cost_ranked"] = "not-enumerated";
    root["hierarchy_global_cost_score"] = "n/a";
    root["hierarchy_global_cost_ranked_in_legal"] = "n/a";
    root["hierarchy_global_cost_ranked_eq_default_3g"] = "n/a";
    root["hierarchy_global_cost_argmin_size"] = "n/a";
    root["hierarchy_global_cost_diverge"] = "n/a";
  } else {
    root["hierarchy_global_cost_ranked"] = joinGlobal(costRank.ranked);
    root["hierarchy_global_cost_score"] = costRank.score;
    root["hierarchy_global_cost_ranked_in_legal"] =
        costRank.rankedInLegal ? "yes" : "no";
    root["hierarchy_global_cost_ranked_eq_default_3g"] =
        costRank.rankedEqDefault3g ? "yes" : "no";
    root["hierarchy_global_cost_argmin_size"] = (int64_t)costRank.argminSize;
    root["hierarchy_global_cost_diverge"] =
        costRank.rankedEqDefault3g ? "no" : "yes";
    llvm::json::Array costCands;
    for (unsigned i = 0; i < glob.legal.size(); ++i) {
      llvm::json::Object obj;
      obj["actions"] = joinGlobal(glob.legal[i]);
      obj["score"] = costRank.candidateScores[i];
      costCands.push_back(std::move(obj));
    }
    root["hierarchy_global_cost"] = std::move(costCands);
  }
  GlobalMeasuredRank measRank = rankGlobalMeasured(glob, evi.name, table);
  root["hierarchy_global_measured_policy"] = "measured-storage-v1";
  if (!glob.enumerated) {
    root["hierarchy_global_measured_ranked"] = "not-enumerated";
    root["hierarchy_global_measured_ranked_in_legal"] = "n/a";
    root["hierarchy_global_measured_ranked_eq_default_3g"] = "n/a";
    root["hierarchy_global_measured_count"] = "n/a";
    root["hierarchy_global_measured_argmin_size"] = "n/a";
    root["hierarchy_global_measured_diverge"] = "n/a";
  } else if (!measRank.applicable) {
    root["hierarchy_global_measured_ranked"] = "not-measured";
    root["hierarchy_global_measured_ranked_in_legal"] = "n/a";
    root["hierarchy_global_measured_ranked_eq_default_3g"] = "n/a";
    root["hierarchy_global_measured_count"] = (int64_t)measRank.measuredCount;
    root["hierarchy_global_measured_argmin_size"] = "n/a";
    root["hierarchy_global_measured_diverge"] = "n/a";
  } else {
    root["hierarchy_global_measured_ranked"] = joinGlobal(measRank.ranked);
    root["hierarchy_global_measured_ranked_in_legal"] =
        measRank.rankedInLegal ? "yes" : "no";
    root["hierarchy_global_measured_ranked_eq_default_3g"] =
        !measRank.defaultMeasured ? "n/a"
                                  : (measRank.rankedEqDefault3g ? "yes" : "no");
    root["hierarchy_global_measured_count"] = (int64_t)measRank.measuredCount;
    root["hierarchy_global_measured_argmin_size"] =
        (int64_t)measRank.argminSize;
    root["hierarchy_global_measured_diverge"] =
        !measRank.defaultMeasured ? "n/a"
                                  : (measRank.rankedEqDefault3g ? "no" : "yes");
    llvm::json::Array measCands;
    for (unsigned i = 0; i < glob.legal.size(); ++i) {
      llvm::json::Object obj;
      obj["actions"] = joinGlobal(glob.legal[i]);
      obj["evidence"] = measRank.hasEvidence[i] ? "yes" : "no";
      measCands.push_back(std::move(obj));
    }
    root["hierarchy_global_measured"] = std::move(measCands);
  }
  root["hierarchy_reuse_applied"] = (int64_t)reuse.applied;
  root["hierarchy_reuse_skipped"] = (int64_t)reuse.skipped;
  if (!schedulePolicy.empty()) {
    root["schedule_policy"] = schedulePolicy.str();
    root["schedule_policy_rewrite"] = "no";
  }
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

struct CapResidency {
  std::string object;
  int64_t size = 1;
  int start = 0;
  int end = 0;
};

struct CapCandidate {
  std::string action;
  SmallVector<std::string, 4> keep;
  SmallVector<std::string, 4> evict;
};

static FailureOr<std::pair<Space, int>> parseCapacityBudget(StringRef spec) {
  if (spec.empty())
    return failure();
  StringRef left, right;
  std::tie(left, right) = spec.split(':');
  Space space = Space::HBM;
  StringRef tiles = spec;
  if (!right.empty()) {
    auto parsed = parseSpaceName(left);
    if (!parsed)
      return failure();
    space = *parsed;
    tiles = right;
  }
  int n = 0;
  if (tiles.getAsInteger(10, n) || n <= 0)
    return failure();
  return std::make_pair(space, n);
}

static int capLiveSum(ArrayRef<CapResidency> live) {
  int s = 0;
  for (const CapResidency &r : live)
    s += (int)r.size;
  return s;
}

static SmallVector<CapResidency, 8> capLiveAt(ArrayRef<CapResidency> rs, int t) {
  SmallVector<CapResidency, 8> out;
  for (const CapResidency &r : rs)
    if (r.start <= t && t < r.end)
      out.push_back(r);
  return out;
}

static void printCapacityReport(Space space, int cap, int peak, bool conflict,
                                bool truncated,
                                ArrayRef<CapCandidate> cands) {
  llvm::errs() << "s2c2-storage-capacity query=f-capacity\n";
  llvm::errs() << "s2c2-storage-capacity space=" << spaceName(space)
               << " capacity=" << cap << " peak-live=" << peak << "\n";
  llvm::errs() << "s2c2-storage-capacity capacity-conflict="
               << (conflict ? "yes" : "no") << "\n";
  if (truncated) {
    llvm::errs() << "s2c2-storage-capacity enumerated=no truncated=yes "
                    "legal=not-enumerated\n";
    llvm::errs() << "s2c2-storage-capacity candidate-count=0\n";
  } else {
    llvm::errs() << "s2c2-storage-capacity enumerated=yes truncated=no legal="
                 << cands.size() << "\n";
    llvm::errs() << "s2c2-storage-capacity candidate-count=" << cands.size()
                 << "\n";
    for (unsigned i = 0; i < cands.size(); ++i) {
      const CapCandidate &c = cands[i];
      llvm::errs() << "s2c2-storage-capacity candidate #" << i << " keep=";
      for (unsigned k = 0; k < c.keep.size(); ++k) {
        if (k)
          llvm::errs() << ",";
        llvm::errs() << c.keep[k];
      }
      if (!c.evict.empty()) {
        llvm::errs() << " evict=";
        for (unsigned k = 0; k < c.evict.size(); ++k) {
          if (k)
            llvm::errs() << ",";
          llvm::errs() << c.evict[k];
        }
      }
      llvm::errs() << " action=" << c.action;
      if (!c.evict.empty())
        llvm::errs() << " restore-legal=TRANSFER,REMATERIALIZE "
                        "restore=unspecified";
      else
        llvm::errs() << " restore=unspecified";
      llvm::errs() << "\n";
    }
  }
  llvm::errs() << "s2c2-storage-capacity rewrite=no\n";
  llvm::errs() << "s2c2-storage-capacity note f-capacity-ne-f-program\n";
  llvm::errs() << "s2c2-storage-capacity note capacity-exceeded-ne-must-evict\n";
  llvm::errs() << "s2c2-storage-capacity note evict-ne-rewrite\n";
  llvm::errs() << "s2c2-storage-capacity note selection-ne-rewrite-license\n";
  llvm::errs() << "s2c2-storage-capacity note compiler-emits-f-capacity\n";
  llvm::errs() << "s2c2-storage-capacity note compiler-ne-rewrite\n";
  llvm::errs() << "s2c2-storage-capacity note tile-count-occupancy\n";
  llvm::errs() << "s2c2-storage-capacity note ir-discovery-ne-alias-analysis\n";
  llvm::errs() << "s2c2-storage-capacity note measured-capacity-v1-not-opened\n";
  llvm::errs() << "s2c2-storage-capacity note six-c-diagnostics-frozen "
                  "cost=unchanged\n";
}

static FailureOr<CapacityPlan>
buildCapacityPlan(ArrayRef<CapResidency> rs, Space space, int cap, int peak,
                  bool truncated, ArrayRef<CapCandidate> cands) {
  CapacityPlan plan;
  plan.space = spaceName(space).str();
  plan.capacity = cap;
  plan.peakLive = peak;
  plan.truncated = truncated;
  plan.enumerated = !truncated;
  plan.selected = "none";
  plan.policy = "none";
  plan.rewriteLicense = false;
  llvm::StringSet<> objects;
  for (const CapResidency &r : rs)
    objects.insert(r.object);
  if (truncated) {
    plan.feasible = false;
    return plan;
  }
  llvm::StringSet<> seenId;
  for (unsigned i = 0; i < cands.size(); ++i) {
    CapacityCandidate cc;
    cc.id = i;
    cc.keep = cands[i].keep;
    cc.evict = cands[i].evict;
    llvm::StringSet<> inKeep;
    for (const std::string &k : cc.keep) {
      if (!objects.contains(k)) {
        llvm::errs() << "s2c2-capacity-plan: keep id not in residency\n";
        return failure();
      }
      inKeep.insert(k);
    }
    for (const std::string &e : cc.evict) {
      if (!objects.contains(e)) {
        llvm::errs() << "s2c2-capacity-plan: evict id not in residency\n";
        return failure();
      }
      if (inKeep.contains(e)) {
        llvm::errs() << "s2c2-capacity-plan: keep/evict overlap\n";
        return failure();
      }
    }
    for (const std::string &m : cc.rematerialize) {
      if (!objects.contains(m)) {
        llvm::errs()
            << "s2c2-capacity-plan: rematerialize id not in residency\n";
        return failure();
      }
    }
    cc.identity =
        capacityCandidateIdentity(cc.keep, cc.evict, cc.rematerialize);
    if (!seenId.insert(cc.identity).second) {
      llvm::errs() << "s2c2-capacity-plan: duplicate identity\n";
      return failure();
    }
    plan.candidates.push_back(std::move(cc));
  }
  plan.feasible = !plan.candidates.empty();
  return plan;
}

static void printCapacityPlan(const CapacityPlan &plan) {
  llvm::errs() << "s2c2-capacity-plan schema=" << plan.schema << "\n";
  llvm::errs() << "s2c2-capacity-plan space=" << plan.space
               << " capacity=" << plan.capacity
               << " peak-live=" << plan.peakLive << "\n";
  llvm::errs() << "s2c2-capacity-plan feasible="
               << (plan.feasible ? "yes" : "no")
               << " enumerated=" << (plan.enumerated ? "yes" : "no")
               << " truncated=" << (plan.truncated ? "yes" : "no")
               << " legal="
               << (plan.truncated ? "not-enumerated"
                                  : std::to_string(plan.candidates.size()))
               << "\n";
  llvm::errs() << "s2c2-capacity-plan selected=" << plan.selected
               << " policy=" << plan.policy << " rewrite-license=no\n";
  if (!plan.truncated) {
    for (const CapacityCandidate &c : plan.candidates) {
      llvm::errs() << "s2c2-capacity-plan candidate #" << c.id
                   << " identity=" << c.identity << " keep=";
      for (unsigned k = 0; k < c.keep.size(); ++k) {
        if (k)
          llvm::errs() << ",";
        llvm::errs() << c.keep[k];
      }
      llvm::errs() << " evict=";
      for (unsigned k = 0; k < c.evict.size(); ++k) {
        if (k)
          llvm::errs() << ",";
        llvm::errs() << c.evict[k];
      }
      llvm::errs() << " rematerialize=";
      for (unsigned k = 0; k < c.rematerialize.size(); ++k) {
        if (k)
          llvm::errs() << ",";
        llvm::errs() << c.rematerialize[k];
      }
      llvm::errs() << "\n";
    }
  }
  llvm::errs() << "s2c2-capacity-plan subseteq-residency=yes\n";
  llvm::errs() << "s2c2-capacity-plan rewrite=no\n";
  llvm::errs() << "s2c2-capacity-plan note f-capacity-subseteq-f-residency\n";
  llvm::errs() << "s2c2-capacity-plan note selected-none\n";
  llvm::errs() << "s2c2-capacity-plan note policy-none\n";
  llvm::errs() << "s2c2-capacity-plan note rewrite-license-no\n";
  llvm::errs() << "s2c2-capacity-plan note compiler-visible-candidate-object\n";
  llvm::errs() << "s2c2-capacity-plan note six-c-b-diagnostics-frozen\n";
  llvm::errs() << "s2c2-capacity-plan note six-c-c-candidate-object-this-cut "
                  "cost=unchanged\n";
}

static llvm::json::Object capacityPlanToJson(const CapacityPlan &plan) {
  llvm::json::Object root;
  root["schema"] = plan.schema;
  root["space"] = plan.space;
  root["capacity"] = (int64_t)plan.capacity;
  root["peak_live"] = (int64_t)plan.peakLive;
  root["feasible"] = plan.feasible;
  root["enumerated"] = plan.enumerated;
  root["truncated"] = plan.truncated;
  root["selected"] = plan.selected;
  root["policy"] = plan.policy;
  root["rewrite"] = "no";
  root["rewrite_license"] = "no";
  root["subseteq_residency"] = true;
  llvm::json::Array cands;
  for (const CapacityCandidate &c : plan.candidates) {
    llvm::json::Object obj;
    obj["id"] = (int64_t)c.id;
    obj["identity"] = c.identity;
    llvm::json::Array keep;
    for (const std::string &k : c.keep)
      keep.push_back(k);
    llvm::json::Array evict;
    for (const std::string &e : c.evict)
      evict.push_back(e);
    llvm::json::Array remat;
    for (const std::string &m : c.rematerialize)
      remat.push_back(m);
    obj["keep"] = std::move(keep);
    obj["evict"] = std::move(evict);
    obj["rematerialize"] = std::move(remat);
    cands.push_back(std::move(obj));
  }
  root["candidates"] = std::move(cands);
  return root;
}

static LogicalResult dumpCapacityPlanJson(StringRef path,
                                          const CapacityPlan &plan) {
  std::error_code ec;
  llvm::raw_fd_ostream out(path, ec, llvm::sys::fs::OF_Text);
  if (ec) {
    llvm::errs() << "s2c2-capacity-plan: cannot write " << path << ": "
                 << ec.message() << "\n";
    return failure();
  }
  out << llvm::json::Value(capacityPlanToJson(plan)) << "\n";
  return success();
}

static void enumerateCapacityF(ArrayRef<CapResidency> rs, int cap,
                               bool &conflict, int &peak, bool &truncated,
                               SmallVectorImpl<CapCandidate> &cands) {
  SmallVector<int, 8> times;
  for (const CapResidency &r : rs)
    times.push_back(r.start);
  llvm::sort(times);
  times.erase(llvm::unique(times), times.end());
  peak = 0;
  conflict = false;
  truncated = false;
  SmallVector<CapResidency, 8> liveStar;
  for (int t : times) {
    auto live = capLiveAt(rs, t);
    int occ = capLiveSum(live);
    if (occ > peak)
      peak = occ;
    if (occ > cap && !conflict) {
      conflict = true;
      liveStar = live;
    }
  }
  cands.clear();
  if (!conflict) {
    CapCandidate all;
    all.action = "KEEP";
    for (const CapResidency &r : rs)
      all.keep.push_back(r.object);
    llvm::sort(all.keep);
    if (!all.keep.empty())
      cands.push_back(std::move(all));
    return;
  }
  int occ = capLiveSum(liveStar);
  const CapResidency *incoming = &*std::max_element(
      liveStar.begin(), liveStar.end(),
      [](const CapResidency &a, const CapResidency &b) {
        if (a.start != b.start)
          return a.start < b.start;
        return a.object < b.object;
      });
  SmallVector<const CapResidency *, 8> order;
  order.push_back(incoming);
  SmallVector<const CapResidency *, 8> rest;
  for (const CapResidency &r : liveStar)
    if (&r != incoming)
      rest.push_back(&r);
  llvm::sort(rest, [](const CapResidency *a, const CapResidency *b) {
    return a->object < b->object;
  });
  order.append(rest.begin(), rest.end());
  for (const CapResidency *rec : order) {
    if (occ - (int)rec->size > cap) {
      truncated = true;
      cands.clear();
      return;
    }
    CapCandidate c;
    c.action = "EVICT";
    c.evict.push_back(rec->object);
    for (const CapResidency &r : liveStar)
      if (&r != rec)
        c.keep.push_back(r.object);
    llvm::sort(c.keep);
    cands.push_back(std::move(c));
  }
}

static LogicalResult loadCapacitySpec(StringRef path,
                                      SmallVectorImpl<CapResidency> &out,
                                      Space &space, int &cap,
                                      std::string *workloadClass = nullptr) {
  std::string resolved = resolveExistingPath(path, {});
  auto fileOr = llvm::MemoryBuffer::getFile(resolved);
  if (!fileOr) {
    llvm::errs() << "s2c2-storage-capacity: cannot read capacity-spec " << path
                 << "\n";
    return failure();
  }
  StringRef text = fileOr.get()->getBuffer();
  int rows = 0;
  llvm::StringSet<> specOk;
  specOk.insert("schema");
  specOk.insert("workload_class");
  specOk.insert("space");
  specOk.insert("capacity_tiles");
  specOk.insert("residencies");
  specOk.insert("note");
  llvm::StringSet<> resOk;
  resOk.insert("id");
  resOk.insert("object");
  resOk.insert("space");
  resOk.insert("size");
  resOk.insert("live");
  resOk.insert("producer");
  resOk.insert("consumer");
  resOk.insert("reuse_distance");
  while (!text.empty()) {
    auto [line, rest] = text.split('\n');
    text = rest;
    line = line.trim();
    if (line.empty() || line.starts_with("#"))
      continue;
    auto parsed = llvm::json::parse(line);
    if (!parsed) {
      llvm::errs() << "s2c2-storage-capacity: invalid JSONL in " << path << "\n";
      return failure();
    }
    auto *obj = parsed->getAsObject();
    if (!obj)
      return failure();
    ++rows;
    if (rows != 1) {
      llvm::errs() << "s2c2-storage-capacity: capacity spec must be one row\n";
      return failure();
    }
    for (const auto &kv : *obj) {
      if (!specOk.contains(kv.getFirst())) {
        llvm::errs() << "s2c2-storage-capacity: extra keys\n";
        return failure();
      }
    }
    auto schema = obj->getString("schema");
    if (!schema || *schema != "s2c2.capacity.v1") {
      llvm::errs() << "s2c2-storage-capacity: bad schema\n";
      return failure();
    }
    auto spaceS = obj->getString("space");
    auto parsedSpace = spaceS ? parseSpaceName(*spaceS) : std::nullopt;
    if (!parsedSpace) {
      llvm::errs() << "s2c2-storage-capacity: bad space\n";
      return failure();
    }
    space = *parsedSpace;
    if (workloadClass) {
      if (auto w = obj->getString("workload_class"))
        *workloadClass = w->str();
      else
        workloadClass->clear();
    }
    if (auto c = obj->getInteger("capacity_tiles"))
      cap = (int)*c;
    else {
      llvm::errs() << "s2c2-storage-capacity: capacity_tiles required\n";
      return failure();
    }
    if (cap <= 0)
      return failure();
    auto *arr = obj->getArray("residencies");
    if (!arr || arr->empty()) {
      llvm::errs() << "s2c2-storage-capacity: residencies required\n";
      return failure();
    }
    for (const llvm::json::Value &item : *arr) {
      auto *rec = item.getAsObject();
      if (!rec)
        return failure();
      for (const auto &kv : *rec) {
        if (!resOk.contains(kv.getFirst())) {
          llvm::errs() << "s2c2-storage-capacity: residency extra keys\n";
          return failure();
        }
      }
      CapResidency r;
      auto objN = rec->getString("object");
      if (!objN)
        return failure();
      StringRef name = *objN;
      if (name.starts_with("tile") && name.drop_front(4).ltrim("0123456789").empty())
        r.object = name.drop_front(4).str();
      else
        r.object = name.str();
      if (auto sz = rec->getInteger("size"))
        r.size = *sz;
      if (r.size <= 0)
        return failure();
      auto *live = rec->getArray("live");
      if (!live || live->size() != 2)
        return failure();
      auto s0 = (*live)[0].getAsInteger();
      auto s1 = (*live)[1].getAsInteger();
      if (!s0 || !s1 || *s0 >= *s1)
        return failure();
      r.start = (int)*s0;
      r.end = (int)*s1;
      out.push_back(std::move(r));
    }
  }
  if (rows != 1) {
    llvm::errs() << "s2c2-storage-capacity: capacity spec must be one row\n";
    return failure();
  }
  return success();
}

static void discoverCapacityFromIR(ModuleOp module, Space space,
                                   SmallVectorImpl<CapResidency> &out) {
  // Tile-count occupancy diagnostics: each constrained-space
  // materialize/transfer is one residency of size 1. Not a
  // byte-capacity allocator and not residency/alias analysis.
  DenseMap<Operation *, unsigned> order;
  unsigned idx = 0;
  module.walk([&](Operation *op) { order[op] = idx++; });
  unsigned n = 0;
  module.walk([&](Operation *op) {
    Value buf;
    if (auto xfer = dyn_cast<TransferOp>(op))
      buf = xfer.getBuffer();
    else if (auto mat = dyn_cast<MaterializeOp>(op))
      buf = mat.getBuffer();
    else
      return;
    auto ty = dyn_cast<BufferType>(buf.getType());
    if (!ty || ty.getSpace() != space)
      return;
    CapResidency r;
    r.object = std::to_string(n++);
    r.size = 1;
    r.start = (int)order[op];
    int last = r.start;
    for (Operation *user : buf.getUsers()) {
      auto it = order.find(user);
      if (it != order.end() && (int)it->second > last)
        last = (int)it->second;
    }
    r.end = last + 1;
    if (r.end <= r.start)
      r.end = r.start + 1;
    out.push_back(std::move(r));
  });
}

// Occupancy IR without a capacity-spec has no declared workload.
// Ranking uses the frozen 4-tile witness name so measured tables
// scoped to ssd-capacity-4tile match this compiler IR; a spec
// overrides. Not a new Evidence DB identity field.
static constexpr llvm::StringLiteral kCapacityIrWorkload{"ssd-capacity-4tile"};

static FailureOr<CapacityPlan>
computeCapacityPlan(ModuleOp module, StringRef budgetStr, StringRef specPath,
                    SmallVectorImpl<CapCandidate> *candsOut, Space &space,
                    int &cap, int &peak, bool &conflict, bool &truncated,
                    StringRef errPrefix = "s2c2-storage-capacity",
                    std::string *workloadClass = nullptr) {
  SmallVector<CapResidency, 8> rs;
  space = Space::HBM;
  cap = 0;
  if (workloadClass)
    *workloadClass = std::string(kCapacityIrWorkload);
  if (!specPath.empty()) {
    if (failed(loadCapacitySpec(specPath, rs, space, cap, workloadClass)))
      return failure();
  }
  if (!budgetStr.empty()) {
    auto parsed = parseCapacityBudget(budgetStr);
    if (failed(parsed)) {
      llvm::errs() << errPrefix << ": invalid --capacity=" << budgetStr << "\n";
      return failure();
    }
    space = parsed->first;
    cap = parsed->second;
  }
  if (specPath.empty())
    discoverCapacityFromIR(module, space, rs);
  if (rs.empty()) {
    llvm::errs() << errPrefix << ": no constrained-space residencies\n";
    return failure();
  }
  conflict = false;
  peak = 0;
  truncated = false;
  SmallVector<CapCandidate, 8> cands;
  enumerateCapacityF(rs, cap, conflict, peak, truncated, cands);
  auto planOr = buildCapacityPlan(rs, space, cap, peak, truncated, cands);
  if (failed(planOr))
    return failure();
  if (candsOut)
    *candsOut = std::move(cands);
  return *planOr;
}

static LogicalResult reportCapacity(ModuleOp module, StringRef budgetStr,
                                    StringRef specPath, StringRef dumpPath) {
  if (budgetStr.empty() && specPath.empty()) {
    if (!dumpPath.empty()) {
      llvm::errs() << "s2c2-capacity-plan: --dump-capacity-plan requires "
                      "--capacity or --capacity-spec\n";
      return failure();
    }
    return success();
  }
  Space space = Space::HBM;
  int cap = 0;
  int peak = 0;
  bool conflict = false;
  bool truncated = false;
  SmallVector<CapCandidate, 8> cands;
  auto planOr = computeCapacityPlan(module, budgetStr, specPath, &cands, space,
                                    cap, peak, conflict, truncated);
  if (failed(planOr))
    return failure();
  printCapacityReport(space, cap, peak, conflict, truncated, cands);
  printCapacityPlan(*planOr);
  if (!dumpPath.empty() && failed(dumpCapacityPlanJson(dumpPath, *planOr)))
    return failure();
  return success();
}

static void printCapacityPlanQuery(const CapacityPlan &plan) {
  llvm::errs() << "s2c2-capacity-plan-query schema=" << plan.schema << "\n";
  llvm::errs() << "s2c2-capacity-plan-query space=" << plan.space
               << " capacity=" << plan.capacity
               << " peak-live=" << plan.peakLive << "\n";
  llvm::errs() << "s2c2-capacity-plan-query feasible="
               << (plan.feasible ? "yes" : "no")
               << " enumerated=" << (plan.enumerated ? "yes" : "no")
               << " truncated=" << (plan.truncated ? "yes" : "no")
               << " legal="
               << (plan.truncated ? "not-enumerated"
                                  : std::to_string(plan.candidates.size()))
               << "\n";
  llvm::errs() << "s2c2-capacity-plan-query selected=" << plan.selected
               << " policy=" << plan.policy << " rewrite-license=no\n";
  if (!plan.truncated) {
    for (const CapacityCandidate &c : plan.candidates)
      llvm::errs() << "s2c2-capacity-plan-query candidate #" << c.id
                   << " identity=" << c.identity << "\n";
  }
  llvm::errs() << "s2c2-capacity-plan-query "
               << llvm::json::Value(capacityPlanToJson(plan)) << "\n";
  llvm::errs() << "s2c2-capacity-plan-query rewrite=no\n";
  llvm::errs() << "s2c2-capacity-plan-query note not-schedule-pass\n";
  if (plan.selected == "none")
    llvm::errs() << "s2c2-capacity-plan-query note selected-none\n";
  else
    llvm::errs() << "s2c2-capacity-plan-query note selected-in-f-capacity\n";
  llvm::errs() << "s2c2-capacity-plan-query note rewrite-license-no\n";
  llvm::errs() << "s2c2-capacity-plan-query note consumer-api\n";
  if (plan.policy == "s0")
    llvm::errs() << "s2c2-capacity-plan-query note s0-ne-must-evict\n";
  if (plan.policy == "measured-capacity-v1") {
    llvm::errs() << "s2c2-capacity-plan-query note measured-capacity-v1-ranking-only\n";
    llvm::errs() << "s2c2-capacity-plan-query note measured-ne-rewrite-license\n";
    llvm::errs() << "s2c2-capacity-plan-query note do-not-filecheck-microseconds\n";
  } else {
    llvm::errs() << "s2c2-capacity-plan-query note measured-capacity-v1-not-opened\n";
  }
  if (plan.policy == "none")
    llvm::errs() << "s2c2-capacity-plan-query note six-c-d-query-this-cut "
                    "cost=unchanged\n";
  else if (plan.policy == "s0")
    llvm::errs() << "s2c2-capacity-plan-query note six-c-e-selection-this-cut "
                    "cost=unchanged\n";
  else
    llvm::errs() << "s2c2-capacity-plan-query note six-c-f-measured-ranking-this-cut "
                    "cost=unchanged\n";
}

struct MeasuredCapacityRecord {
  std::string profile;
  std::string workloadClass;
  std::string identity;
  int64_t timeUs = 0;
  int64_t correctness = 0;
  MeasuredStatus measured = MeasuredStatus::No;
};

static LogicalResult
loadMeasuredCapacityTable(StringRef path,
                          SmallVectorImpl<MeasuredCapacityRecord> &out) {
  std::string resolved = resolveExistingPath(path, {});
  auto fileOr = llvm::MemoryBuffer::getFile(resolved);
  if (!fileOr) {
    llvm::errs() << "s2c2-capacity-policy: cannot read measured-capacity-table "
                 << path << "\n";
    return failure();
  }
  llvm::StringSet<> ok;
  ok.insert("schema");
  ok.insert("profile");
  ok.insert("workload_class");
  ok.insert("candidate_identity");
  ok.insert("measured_time_us");
  ok.insert("repetitions");
  ok.insert("correctness");
  ok.insert("source");
  ok.insert("measured");
  ok.insert("note");
  llvm::StringSet<> seen;
  StringRef text = fileOr.get()->getBuffer();
  while (!text.empty()) {
    auto [line, rest] = text.split('\n');
    text = rest;
    line = line.trim();
    if (line.empty() || line.starts_with("#"))
      continue;
    auto parsed = llvm::json::parse(line);
    if (!parsed) {
      llvm::errs() << "s2c2-capacity-policy: invalid JSONL in " << path << "\n";
      return failure();
    }
    auto *obj = parsed->getAsObject();
    if (!obj) {
      llvm::errs() << "s2c2-capacity-policy: invalid JSONL in " << path << "\n";
      return failure();
    }
    for (const auto &kv : *obj) {
      if (!ok.contains(kv.getFirst())) {
        llvm::errs() << "s2c2-capacity-policy: extra keys\n";
        return failure();
      }
    }
    auto schema = obj->getString("schema");
    if (!schema || *schema != "s2c2.measured_capacity_cost.v1") {
      llvm::errs() << "s2c2-capacity-policy: bad schema\n";
      return failure();
    }
    MeasuredCapacityRecord rec;
    if (auto p = obj->getString("profile"))
      rec.profile = p->str();
    if (auto w = obj->getString("workload_class"))
      rec.workloadClass = w->str();
    if (auto id = obj->getString("candidate_identity"))
      rec.identity = id->str();
    if (auto t = obj->getInteger("measured_time_us"))
      rec.timeUs = *t;
    else if (auto tn = obj->getNumber("measured_time_us"))
      rec.timeUs = (int64_t)*tn;
    if (auto c = obj->getInteger("correctness"))
      rec.correctness = *c;
    else if (auto cn = obj->getNumber("correctness"))
      rec.correctness = (int64_t)*cn;
    if (auto m = obj->getString("measured")) {
      if (m->equals_insensitive("yes"))
        rec.measured = MeasuredStatus::Yes;
      else if (m->equals_insensitive("pending"))
        rec.measured = MeasuredStatus::Pending;
      else
        rec.measured = MeasuredStatus::No;
    }
    if (rec.identity.empty()) {
      llvm::errs() << "s2c2-capacity-policy: candidate_identity required\n";
      return failure();
    }
    if (rec.profile.empty() || rec.workloadClass.empty()) {
      llvm::errs() << "s2c2-capacity-policy: profile and workload_class required\n";
      return failure();
    }
    std::string scoped = rec.profile;
    scoped.push_back('\x1f');
    scoped += rec.workloadClass;
    scoped.push_back('\x1f');
    scoped += rec.identity;
    if (!seen.insert(scoped).second) {
      llvm::errs() << "s2c2-capacity-policy: duplicate-measured-identity\n";
      return failure();
    }
    out.push_back(std::move(rec));
  }
  return success();
}

struct MeasuredCapacityTrace {
  bool active = false;
  unsigned measuredCount = 0;
  unsigned argminSize = 0;
  bool coincideS0 = false;
  std::string profile;
  std::string workloadClass;
  llvm::StringSet<> evidence;
};

static LogicalResult
rankMeasuredCapacity(CapacityPlan &plan,
                     ArrayRef<MeasuredCapacityRecord> table,
                     StringRef profile, StringRef workload,
                     MeasuredCapacityTrace &trace) {
  llvm::StringSet<> legal;
  for (const CapacityCandidate &c : plan.candidates)
    legal.insert(c.identity);
  llvm::StringMap<int64_t> us;
  for (const MeasuredCapacityRecord &r : table) {
    if (r.profile != profile || r.workloadClass != workload)
      continue;
    if (!legal.contains(r.identity))
      continue;
    if (r.measured != MeasuredStatus::Yes || r.correctness != 1)
      continue;
    if (us.count(r.identity)) {
      llvm::errs() << "s2c2-capacity-policy: duplicate-measured-identity\n";
      return failure();
    }
    us[r.identity] = r.timeUs;
  }
  if (us.size() < 2) {
    llvm::errs() << "s2c2-capacity-measured ranked=not-measured "
                    "policy=measured-capacity-v1 "
                    "profile=" << profile << " workload=" << workload
                 << " note measured-needs-two-records "
                    "note measured-yes-and-correctness "
                    "note measured-scope-profile-workload-candidate "
                    "note measured-ne-cross-profile "
                    "note measured-ne-cross-workload "
                    "note measured-ne-legality "
                    "note measured-ne-rewrite-license "
                    "note measured-does-not-expand-f "
                    "note do-not-filecheck-microseconds\n";
    llvm::errs() << "s2c2-capacity-policy: measured-needs-two-records\n";
    return failure();
  }
  int64_t best = INT64_MAX;
  SmallVector<unsigned, 4> argmin;
  for (unsigned i = 0; i < plan.candidates.size(); ++i) {
    auto it = us.find(plan.candidates[i].identity);
    if (it == us.end())
      continue;
    int64_t t = it->second;
    if (t < best) {
      best = t;
      argmin.clear();
      argmin.push_back(i);
    } else if (t == best) {
      argmin.push_back(i);
    }
  }
  unsigned pick = argmin.front();
  plan.policy = "measured-capacity-v1";
  plan.selected = plan.candidates[pick].identity;
  trace.active = true;
  trace.measuredCount = us.size();
  trace.argminSize = argmin.size();
  trace.coincideS0 = plan.selected == plan.candidates.front().identity;
  trace.profile = profile.str();
  trace.workloadClass = workload.str();
  for (const CapacityCandidate &c : plan.candidates)
    if (us.count(c.identity))
      trace.evidence.insert(c.identity);
  return success();
}

static void printMeasuredCapacity(const CapacityPlan &plan,
                                  const MeasuredCapacityTrace &trace) {
  if (!trace.active)
    return;
  llvm::errs() << "s2c2-capacity-measured ranked=" << plan.selected
               << " policy=measured-capacity-v1 measured-count="
               << trace.measuredCount << " argmin-size=" << trace.argminSize
               << " coincide-s0=" << (trace.coincideS0 ? "yes" : "no")
               << " profile=" << trace.profile
               << " workload=" << trace.workloadClass
               << " rewrite=no rewrite-license=no"
               << " note measured-yes-and-correctness"
               << " note measured-scope-profile-workload-candidate"
               << " note measured-ne-cross-profile"
               << " note measured-ne-cross-workload"
               << " note measured-ne-legality"
               << " note measured-ne-rewrite-license"
               << " note measured-does-not-expand-f"
               << " note measured-does-not-rank-truncated-F"
               << " note duplicate-measured-identity"
               << " note argmin-ties-earliest-F"
               << " note do-not-filecheck-microseconds"
               << " note not-hardware-campaign"
               << " note not-new-evidence-db"
               << " note six-c-f-measured-ranking-this-cut cost=unchanged\n";
  for (const CapacityCandidate &c : plan.candidates)
    llvm::errs() << "s2c2-capacity-measured-candidate identity=" << c.identity
                 << " evidence="
                 << (trace.evidence.contains(c.identity) ? "yes" : "no")
                 << "\n";
}

static LogicalResult applyCapacityPolicy(CapacityPlan &plan, StringRef name,
                                         StringRef tablePath, StringRef profile,
                                         StringRef workload,
                                         MeasuredCapacityTrace &trace) {
  StringRef n = name.trim();
  if (n.empty() || n.equals_insensitive("none"))
    return success();
  if (plan.truncated || !plan.enumerated) {
    llvm::errs() << "s2c2-capacity-policy: truncated plan cannot be selected\n";
    return failure();
  }
  if (plan.candidates.empty()) {
    llvm::errs() << "s2c2-capacity-policy: empty F_capacity cannot be selected\n";
    return failure();
  }
  if (n.equals_insensitive("s0")) {
    plan.policy = "s0";
    plan.selected = plan.candidates.front().identity;
    return success();
  }
  if (n.equals_insensitive("measured-capacity-v1") ||
      n.equals_insensitive("measured")) {
    if (tablePath.empty()) {
      llvm::errs() << "s2c2-capacity-policy: --capacity-policy=measured-capacity-v1 "
                      "requires --measured-capacity-table\n";
      return failure();
    }
    if (profile.empty()) {
      llvm::errs() << "s2c2-capacity-policy: --capacity-policy=measured-capacity-v1 "
                      "requires --profile\n";
      return failure();
    }
    if (workload.empty()) {
      llvm::errs() << "s2c2-capacity-policy: --capacity-policy=measured-capacity-v1 "
                      "requires workload_class\n";
      return failure();
    }
    SmallVector<MeasuredCapacityRecord, 8> table;
    if (failed(loadMeasuredCapacityTable(tablePath, table)))
      return failure();
    return rankMeasuredCapacity(plan, table, profile, workload, trace);
  }
  llvm::errs() << "s2c2-opt: unknown --capacity-policy=" << name << "\n";
  return failure();
}

static void printCapacityPolicy(const CapacityPlan &plan) {
  if (plan.policy == "none")
    return;
  llvm::errs() << "s2c2-capacity-policy name=" << plan.policy
               << " selected=" << plan.selected << " applicable=yes source="
               << plan.policy << " rewrite=no rewrite-license=no"
               << " note selection-ne-legality"
               << " note selection-ne-rewrite-license";
  if (plan.policy == "s0")
    llvm::errs() << " note s0-ne-must-evict note truncated-ne-select"
                 << " note measured-capacity-v1-not-opened cost=unchanged\n";
  else
    llvm::errs() << " note measured-capacity-v1-ranking-only"
                 << " note measured-ne-rewrite-license"
                 << " note do-not-filecheck-microseconds"
                 << " note truncated-ne-select cost=unchanged\n";
}

static LogicalResult queryCapacityPlan(ModuleOp module, StringRef budgetStr,
                                       StringRef specPath, StringRef dumpPath,
                                       StringRef policyName,
                                       StringRef tablePath,
                                       StringRef profile) {
  if (budgetStr.empty() && specPath.empty()) {
    llvm::errs() << "s2c2-capacity-plan-query: --query-capacity-plan requires "
                    "--capacity or --capacity-spec\n";
    return failure();
  }
  Space space = Space::HBM;
  int cap = 0;
  int peak = 0;
  bool conflict = false;
  bool truncated = false;
  std::string workload;
  auto planOr = computeCapacityPlan(module, budgetStr, specPath, nullptr, space,
                                    cap, peak, conflict, truncated,
                                    "s2c2-capacity-plan-query", &workload);
  if (failed(planOr))
    return failure();
  CapacityPlan plan = *planOr;
  MeasuredCapacityTrace measured;
  if (failed(applyCapacityPolicy(plan, policyName, tablePath, profile, workload,
                                 measured)))
    return failure();
  printCapacityPlanQuery(plan);
  printMeasuredCapacity(plan, measured);
  printCapacityPolicy(plan);
  if (!dumpPath.empty() && failed(dumpCapacityPlanJson(dumpPath, plan)))
    return failure();
  return success();
}

static LogicalResult applySchedule(ModuleOp module, StringRef device,
                                   const CapCatalog &cat,
                                   const ResolvedProfile *evi = nullptr,
                                   StringRef dumpPath = {},
                                   StringRef measuredTablePath = {},
                                   StringRef schedulePolicy = {},
                                   bool explain = false) {
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
    SmallVector<HierarchySite, 16> sites = planStorageHierarchy(module, cat);
    unsigned hMat = 0, hPref = 0, hXfer = 0, hKeep = 0, hPres = 0;
    countHierarchy(sites, hMat, hPref, hXfer, hKeep, hPres);
    for (const HierarchySite &s : sites)
      printHierarchySite(s);
    llvm::errs() << "hierarchy-schedule sites=" << sites.size()
                 << " materialize=" << hMat << " prefetch=" << hPref
                 << " transfer=" << hXfer << " keep-residency=" << hKeep
                 << " preserve=" << hPres;
    unsigned multi = 0;
    bool inLegal = true;
    for (const HierarchySite &s : sites) {
      if (s.legal.size() > 1)
        ++multi;
      bool found = false;
      for (HierarchyAction a : s.legal)
        if (a == s.action)
          found = true;
      if (!found)
        inLegal = false;
    }
    llvm::errs() << " multi-candidate=" << multi
                 << " selected-in-legal=" << (inLegal ? "yes" : "no")
                 << " policy=default-3g note selection-ne-cost"
                 << " focus=ssd-host-hbm-compute cost=unchanged\n";
    SmallVector<JointChain, 4> chains = planJointChains(sites);
    for (const JointChain &c : chains)
      printJointChain(c);
    printJointSchedule(chains);
    GlobalSchedule glob = planGlobalSchedule(chains);
    printGlobalSchedule(glob, chains.size());
    GlobalCostRank costRank = rankGlobalCost(chains, sites, glob);
    printGlobalCostRank(costRank, glob);
    SmallVector<MeasuredCostRecord, 8> measuredTable;
    if (failed(loadMeasuredCostTable(measuredTablePath, measuredTable)))
      return failure();
    GlobalMeasuredRank measRank =
        rankGlobalMeasured(glob, evi->name, measuredTable);
    printGlobalMeasuredRank(measRank, glob);
    FailureOr<SchedulePolicyKind> parsed = parseSchedulePolicy(schedulePolicy);
    if (failed(parsed))
      return failure();
    NamedPolicyPick pick =
        pickNamedPolicy(*parsed, glob, costRank, measRank);
    printNamedSchedulePolicy(*parsed, pick);
    if (explain)
      printScheduleExplain(*parsed, evi->name, sites, glob, costRank, measRank,
                           pick);
    ReuseStats reuse = applyProvenResidencyReuse(module);
    llvm::errs() << "hierarchy-reuse applied=" << reuse.applied
                 << " skipped=" << reuse.skipped
                 << " note proven-live-residency\n";
    llvm::errs() << "hierarchy-reuse note not-c-storage-flatten\n";
    llvm::errs() << "hierarchy-reuse note no-invented-wait\n";
    llvm::errs() << "hierarchy-reuse note loop-carried-underdetermined\n";
    llvm::errs() << "hierarchy-reuse note not-cost-v04 cost=unchanged\n";
    reportLoopPipeline(module);
    if (!dumpPath.empty() &&
        failed(dumpWorkloadSchedule(dumpPath, *evi, decisions, sites, chains,
                                    reuse, measuredTable, schedulePolicy)))
      return failure();
    if (!glob.historicalInF)
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
    std::string policy = schedulePolicy;
    if (policy.empty())
      policy = clSchedulePolicy;
    bool doExplain = explain || clScheduleExplain;
    std::string table = measuredCostTable;
    if (table.empty())
      table = clMeasuredCostTable;
    std::string cap = capacityBudget;
    if (cap.empty())
      cap = clCapacityBudget;
    std::string spec = capacitySpec;
    if (spec.empty())
      spec = clCapacitySpec;
    std::string dumpPlan = dumpCapacityPlan;
    if (dumpPlan.empty())
      dumpPlan = clDumpCapacityPlan;
    // Occupancy is a fact about the input program, not post-rewrite IR.
    // KEEP/EVICT candidates are diagnostic only; applySchedule is unchanged.
    // CapacityPlan is compiler-visible; selected=none; not a rewrite license.
    if (failed(reportCapacity(getOperation(), cap, spec, dumpPlan))) {
      signalPassFailure();
      return;
    }
    if (failed(applySchedule(getOperation(), resolved.device, cat, &resolved,
                             dumpSchedule, table, policy, doExplain)))
      signalPassFailure();
  }
};

struct S2C2CapacityPlanQuery
    : impl::S2C2CapacityPlanQueryBase<S2C2CapacityPlanQuery> {
  using impl::S2C2CapacityPlanQueryBase<
      S2C2CapacityPlanQuery>::S2C2CapacityPlanQueryBase;

  void runOnOperation() override {
    // Occupancy query only. Does not load Evidence DB or rewrite IR.
    // Default selected=none. capacity-policy=s0 selects first(F_capacity).
    // measured-capacity-v1 ranks enumerated F; matcher is
    // profile + workload + candidate. Not a rewrite license.
    std::string cap = capacityBudget.empty() ? clCapacityBudget : capacityBudget;
    std::string spec = capacitySpec.empty() ? clCapacitySpec : capacitySpec;
    std::string dump =
        dumpCapacityPlan.empty() ? clDumpCapacityPlan : dumpCapacityPlan;
    std::string policy =
        capacityPolicy.empty() ? clCapacityPolicy : capacityPolicy;
    std::string table = measuredCapacityTable.empty() ? clMeasuredCapacityTable
                                                      : measuredCapacityTable;
    std::string profile = clS2C2Profile;
    if (failed(queryCapacityPlan(getOperation(), cap, spec, dump, policy,
                                 table, profile)))
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
