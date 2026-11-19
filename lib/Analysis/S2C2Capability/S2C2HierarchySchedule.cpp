//===- S2C2HierarchySchedule.cpp - hierarchy & F(program) -------*- C++ -*-===//
//
// Phase 3G/3H/3I + 4A-4D + 5A layer of the capability passes.
// 3G walks stor.materialize / stor.transfer and prints a hierarchy
// plan; 3H applies KEEP_RESIDENCY only on a proven dominating replica;
// 3I reports scf.for software-pipeline structure. 4A enumerates
// F(site), 4B F(chain), 4C F(program) (cap 64), and 4D ranks under
// policy=cost-v04 (frozen). 5A ranks enumerated F(program) under
// policy=measured-storage-v1. Cost does not rank, license, or decide
// legality. Split from S2C2CapabilitySchedule.cpp; behavior and
// printed output are unchanged.
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

/// Completeness cap for constructing F(program). Exceeding it means
/// the compiler does not claim a complete legal set.
static constexpr uint64_t kGlobalFEnumerateCap = 64;

StringRef spaceName(std::optional<Space> space) {
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

std::optional<Space> parseSpaceName(StringRef name) {
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

StringRef hierarchyActionStr(HierarchyAction action) {
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

std::string joinActions(ArrayRef<HierarchyAction> acts, char sep) {
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

std::string joinGlobal(ArrayRef<ChainAssignment> asns) {
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

void printHierarchySite(const HierarchySite &s) {
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

void countHierarchy(ArrayRef<HierarchySite> sites, unsigned &materialize,
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

// Proven-safe KEEP_RESIDENCY only: sequential rematerialize of a
// dominating, unmutated, same-type live replica. Not C||Storage
// flatten. Does not invent sibling sched.wait.
ReuseStats applyProvenResidencyReuse(ModuleOp module) {
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

SmallVector<HierarchySite, 16> planStorageHierarchy(ModuleOp module,
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

bool sameAssignment(ArrayRef<HierarchyAction> a,
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

SmallVector<JointChain, 4>
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

void printJointChain(const JointChain &c) {
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

void printJointSchedule(ArrayRef<JointChain> chains) {
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

GlobalSchedule planGlobalSchedule(ArrayRef<JointChain> chains) {
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

void printGlobalSchedule(const GlobalSchedule &g, unsigned nChains) {
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

/// Rank fully enumerated F(program) under policy=cost-v04.
/// A truncated product is not ranked. default-3g is not retargeted.
/// Among ArgMin ties, prefer the historical tuple when it is a minimum.
GlobalCostRank rankGlobalCost(ArrayRef<JointChain> chains,
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

void printGlobalCostRank(const GlobalCostRank &r,
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

LogicalResult
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
GlobalMeasuredRank
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

void printGlobalMeasuredRank(const GlobalMeasuredRank &r,
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

FailureOr<SchedulePolicyKind> parseSchedulePolicy(StringRef name) {
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

NamedPolicyPick
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

void printNamedSchedulePolicy(SchedulePolicyKind kind,
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

void printScheduleExplain(SchedulePolicyKind kind, StringRef profile,
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
void reportLoopPipeline(ModuleOp module) {
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
} // namespace mlir::s2c2
