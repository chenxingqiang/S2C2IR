//===- S2C2CapabilityCatalog.cpp - capability profile & query -*- C++ -*-===//
//
// Phase 3A + 3D + 3E/3F layer of the capability passes.
// CapabilityProfile is compiler decision input, not an archive. A pair
// may have several size-banded records; lookup picks the narrowest
// covering size_range. This file owns the capability catalog (builtin
// 4090 / 910B / npu-demo grids, compiler-profile JSON, evidence JSONL),
// region/pair classification, applicability, and the query printing
// shared by the schedule driver. Split from S2C2CapabilitySchedule.cpp;
// behavior and printed output are unchanged.
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

#include "S2C2CapabilityInternal.h"

#ifndef S2C2_SOURCE_DIR
#define S2C2_SOURCE_DIR ""
#endif

namespace mlir::s2c2 {
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

bool isHostLike(Space space) {
  return space == Space::Host || space == Space::SSD;
}

bool isDeviceLike(Space space) {
  return space == Space::HBM || space == Space::DRAM || space == Space::SRAM ||
         space == Space::CIM;
}

std::optional<Space> bufferSpace(Value value) {
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

LogicalResult loadCatalog(StringRef device, StringRef profilePath,
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

static bool looksLikePath(StringRef s) {
  if (s.contains(','))
    return false;
  return s.contains('/') || s.ends_with_insensitive(".json") ||
         s.ends_with_insensitive(".jsonl");
}

std::string resolveExistingPath(StringRef path, StringRef relativeToDir) {
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

LogicalResult
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

Role parseRole(StringRef raw) {
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

std::string pairFromRoles(Role a, Role b) {
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

void classifySpaces(std::optional<Space> srcSpace,
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

std::string classifyPair(Region &a, Region &b) {
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

QueryContext contextFromRegions(Region &a, Region &b, StringRef pair) {
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

CapCell lookupPair(const CapCatalog &cat, StringRef pair,
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

Applicability isApplicable(const CapCell &cell, const QueryContext &ctx) {
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

StringRef applicabilityStr(Applicability app) {
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

void printQueryJson(StringRef device, StringRef pair, const CapCell &cell,
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

bool shouldSerialize(const CapCell &cell, Applicability app) {
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

bool isStorageCommOverlap(StringRef pair) {
  return pair == "C||Storage" || pair == "C||HtoD" || pair == "C||DtoH";
}

StringRef decisionStr(DecisionKind kind) {
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

DecisionKind classifyDecision(const CapCell &cell, Applicability app,
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

std::string decisionReason(const CapCell &cell, Applicability app,
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

void fillWorkloadDecision(WorkloadDecision &d, unsigned id, StringRef via,
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

void countDecisions(ArrayRef<WorkloadDecision> decisions, unsigned &keep,
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

std::string prettyReason(StringRef reason) {
  std::string out = reason.str();
  for (char &c : out) {
    if (c == '-')
      c = ' ';
  }
  return out;
}

void printWorkloadCandidate(const WorkloadDecision &d) {
  llvm::errs() << "workload-candidate #" << d.id << " pair=" << d.pair
               << " payload=" << d.payload << " relation=" << d.relation
               << " decision=" << decisionStr(d.kind)
               << " reason=" << d.reason << "\n";
  llvm::errs() << "candidate #" << d.id << " : " << prettyPair(d.pair) << "\n";
  llvm::errs() << "    decision : " << decisionStr(d.kind) << "\n";
  llvm::errs() << "    reason   : " << prettyReason(d.reason) << "\n";
}
} // namespace mlir::s2c2
