//===- S2C2CapacityPlan.cpp - occupancy F_capacity (Phase 6C) ---*- C++ -*-===//
//
// Phase 6C layer of the capability passes. 6C-B prints F_capacity
// occupancy candidates; 6C-C materializes CapacityPlan (selected=none
// on the diagnostic path); 6C-E selects first(F_capacity); 6C-F ranks
// under measured-capacity-v1; 6C-G freezes the rewrite-license gate;
// 6C-H attaches TRANSFER restores to EVICT objects; 6C-I/6C-J/6C-K/
// 6C-L classify the license predicate, source data, restore ordering,
// and dest invalidation. Diagnostics only; rewrite stays no. Split
// from S2C2CapabilitySchedule.cpp; behavior and printed output are
// unchanged.
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

static std::string normalizeCapacityObject(StringRef name) {
  if (name.starts_with("tile") &&
      name.drop_front(4).ltrim("0123456789").empty())
    return name.drop_front(4).str();
  return name.str();
}

struct CapSourceDataProof {
  std::string replica;
  std::string witness;
  std::string scope;
  int start = 0;
  int end = 0;
};

struct CapRestoreOrderProof {
  std::string witness;
  std::string scope;
  int before = 0;
};

struct CapDestInvalidationProof {
  std::string destination;
  std::string witness;
  std::string scope;
};

static constexpr llvm::StringLiteral kSourceWitness{"spec-unmutated-cover"};
static constexpr llvm::StringLiteral kSourceScope{"occupancy-live"};
static constexpr llvm::StringLiteral kOrderWitness{"spec-before-consumer"};
static constexpr llvm::StringLiteral kOrderScope{"occupancy-live"};
static constexpr llvm::StringLiteral kDestWitness{"spec-drop-stale"};
static constexpr llvm::StringLiteral kDestScope{"occupancy-live"};

static void attachCapacityRestores(
    CapacityCandidate &cc, const llvm::StringMap<std::string> &restoreSources,
    ArrayRef<CapResidency> rs,
    const llvm::StringMap<CapSourceDataProof> &sourceData,
    const llvm::StringMap<CapRestoreOrderProof> &restoreOrder,
    const llvm::StringMap<CapDestInvalidationProof> &destInv,
    StringRef occSpace) {
  llvm::StringMap<std::pair<int, int>> occLive;
  for (const CapResidency &r : rs)
    occLive[r.object] = {r.start, r.end};
  cc.restores.clear();
  for (const std::string &e : cc.evict) {
    CapacityRestore rec;
    rec.object = e;
    rec.kind = "TRANSFER";
    auto srcIt = restoreSources.find(e);
    rec.replicaExists = srcIt != restoreSources.end();
    rec.valid = rec.replicaExists;
    rec.reason = rec.valid ? "has-source-replica" : "no-source-replica";
    rec.sourceData = false;
    rec.restoreOrdering = false;
    rec.usable = false;
    rec.replica = "n/a";
    rec.witness = "n/a";
    rec.scope = "n/a";
    rec.orderBefore = "n/a";
    rec.orderWitness = "n/a";
    rec.orderScope = "n/a";
    rec.destInvalidation = false;
    rec.destSpace = "n/a";
    rec.destWitness = "n/a";
    rec.destScope = "n/a";
    if (!rec.replicaExists) {
      rec.sourceDataReason = "no-source-replica";
      rec.restoreOrderingReason = "no-source-replica";
      rec.destInvalidationReason = "no-source-replica";
    } else {
      rec.replica = srcIt->second;
      auto it = sourceData.find(e);
      if (it == sourceData.end()) {
        rec.sourceDataReason = "no-validity-witness";
      } else {
        rec.witness = it->second.witness;
        rec.scope = it->second.scope;
        if (it->second.replica != rec.replica) {
          rec.sourceDataReason = "replica-scope-mismatch";
        } else if (it->second.witness != kSourceWitness) {
          rec.sourceDataReason = "unknown-witness";
        } else if (it->second.scope != kSourceScope) {
          rec.sourceDataReason = "unknown-scope";
        } else {
          auto liveIt = occLive.find(e);
          if (liveIt == occLive.end() ||
              it->second.start > liveIt->second.first ||
              it->second.end < liveIt->second.second) {
            rec.sourceDataReason = "interval-does-not-cover";
          } else {
            rec.sourceData = true;
            rec.sourceDataReason = "witnessed-unmutated-cover";
          }
        }
      }
      auto oit = restoreOrder.find(e);
      if (oit == restoreOrder.end()) {
        rec.restoreOrderingReason = "no-ordering-witness";
      } else {
        rec.orderBefore = std::to_string(oit->second.before);
        rec.orderWitness = oit->second.witness;
        rec.orderScope = oit->second.scope;
        if (oit->second.witness != kOrderWitness) {
          rec.restoreOrderingReason = "unknown-witness";
        } else if (oit->second.scope != kOrderScope) {
          rec.restoreOrderingReason = "unknown-scope";
        } else {
          auto liveIt = occLive.find(e);
          if (liveIt == occLive.end() ||
              oit->second.before != liveIt->second.second) {
            rec.restoreOrderingReason = "not-before-consumer";
          } else {
            rec.restoreOrdering = true;
            rec.restoreOrderingReason = "witnessed-before-consumer";
          }
        }
      }
      auto dit = destInv.find(e);
      if (dit == destInv.end()) {
        rec.destInvalidationReason = "no-invalidation-witness";
      } else {
        rec.destSpace = dit->second.destination;
        rec.destWitness = dit->second.witness;
        rec.destScope = dit->second.scope;
        if (dit->second.destination != occSpace) {
          rec.destInvalidationReason = "destination-scope-mismatch";
        } else if (dit->second.witness != kDestWitness) {
          rec.destInvalidationReason = "unknown-witness";
        } else if (dit->second.scope != kDestScope) {
          rec.destInvalidationReason = "unknown-scope";
        } else {
          rec.destInvalidation = true;
          rec.destInvalidationReason = "witnessed-drop-stale";
        }
      }
    }
    rec.usable = rec.sourceData && rec.restoreOrdering;
    cc.restores.push_back(std::move(rec));
  }
}

static FailureOr<CapacityPlan>
buildCapacityPlan(ArrayRef<CapResidency> rs, Space space, int cap, int peak,
                  bool truncated, ArrayRef<CapCandidate> cands,
                  const llvm::StringMap<std::string> &restoreSources,
                  const llvm::StringMap<CapSourceDataProof> &sourceData,
                  const llvm::StringMap<CapRestoreOrderProof> &restoreOrder,
                  const llvm::StringMap<CapDestInvalidationProof> &destInv) {
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
    attachCapacityRestores(cc, restoreSources, rs, sourceData, restoreOrder,
                           destInv, plan.space);
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
    llvm::json::Array restores;
    for (const CapacityRestore &r : c.restores) {
      llvm::json::Object rec;
      rec["object"] = r.object;
      rec["kind"] = r.kind;
      rec["valid"] = r.valid;
      rec["reason"] = r.reason;
      rec["source_data"] = r.sourceData;
      rec["source_data_reason"] = r.sourceDataReason;
      rec["replica_exists"] = r.replicaExists;
      rec["replica"] = r.replica;
      rec["witness"] = r.witness;
      rec["scope"] = r.scope;
      rec["usable"] = r.usable;
      rec["restore_ordering"] = r.restoreOrdering;
      rec["restore_ordering_reason"] = r.restoreOrderingReason;
      rec["order_before"] = r.orderBefore;
      rec["order_witness"] = r.orderWitness;
      rec["order_scope"] = r.orderScope;
      rec["dest_invalidation"] = r.destInvalidation;
      rec["dest_invalidation_reason"] = r.destInvalidationReason;
      rec["dest_space"] = r.destSpace;
      rec["dest_witness"] = r.destWitness;
      rec["dest_scope"] = r.destScope;
      restores.push_back(std::move(rec));
    }
    obj["restores"] = std::move(restores);
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
                                      std::string *workloadClass = nullptr,
                                      llvm::StringMap<std::string> *restoreSources =
                                          nullptr,
                                      llvm::StringMap<CapSourceDataProof> *sourceData =
                                          nullptr,
                                      llvm::StringMap<CapRestoreOrderProof> *restoreOrder =
                                          nullptr,
                                      llvm::StringMap<CapDestInvalidationProof> *destInv =
                                          nullptr) {
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
  specOk.insert("restore_sources");
  specOk.insert("source_data");
  specOk.insert("restore_order");
  specOk.insert("dest_invalidation");
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
      r.object = normalizeCapacityObject(*objN);
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
    llvm::StringSet<> occupancyIds;
    for (const CapResidency &r : out)
      occupancyIds.insert(r.object);
    if (obj->get("restore_sources")) {
      auto *srcs = obj->getArray("restore_sources");
      if (!srcs) {
        llvm::errs()
            << "s2c2-storage-capacity: restore_sources must be an array\n";
        return failure();
      }
      llvm::StringSet<> srcOk;
      srcOk.insert("object");
      srcOk.insert("space");
      srcOk.insert("kind");
      llvm::StringSet<> seenSrc;
      for (const llvm::json::Value &item : *srcs) {
        auto *rec = item.getAsObject();
        if (!rec)
          return failure();
        for (const auto &kv : *rec) {
          if (!srcOk.contains(kv.getFirst())) {
            llvm::errs()
                << "s2c2-storage-capacity: restore_sources extra keys\n";
            return failure();
          }
        }
        auto objN = rec->getString("object");
        if (!objN) {
          llvm::errs()
              << "s2c2-storage-capacity: restore source object required\n";
          return failure();
        }
        std::string id = normalizeCapacityObject(*objN);
        if (!occupancyIds.contains(id)) {
          llvm::errs()
              << "s2c2-storage-capacity: restore source not in occupancy\n";
          return failure();
        }
        auto spaceS = rec->getString("space");
        if (!spaceS || (*spaceS != "ssd" && *spaceS != "host")) {
          llvm::errs() << "s2c2-storage-capacity: restore source space must "
                          "be ssd or host\n";
          return failure();
        }
        if (auto kind = rec->getString("kind")) {
          if (*kind != "TRANSFER") {
            llvm::errs()
                << "s2c2-storage-capacity: restore kind must be TRANSFER\n";
            return failure();
          }
        }
        if (!seenSrc.insert(id).second) {
          llvm::errs()
              << "s2c2-storage-capacity: duplicate restore source\n";
          return failure();
        }
        if (restoreSources)
          (*restoreSources)[id] = spaceS->str();
      }
    }
    if (obj->get("source_data")) {
      auto *proofs = obj->getArray("source_data");
      if (!proofs) {
        llvm::errs()
            << "s2c2-storage-capacity: source_data must be an array\n";
        return failure();
      }
      llvm::StringSet<> dataOk;
      dataOk.insert("object");
      dataOk.insert("replica");
      dataOk.insert("live");
      dataOk.insert("witness");
      dataOk.insert("scope");
      llvm::StringSet<> seenData;
      for (const llvm::json::Value &item : *proofs) {
        auto *rec = item.getAsObject();
        if (!rec)
          return failure();
        for (const auto &kv : *rec) {
          if (!dataOk.contains(kv.getFirst())) {
            llvm::errs()
                << "s2c2-storage-capacity: source_data extra keys\n";
            return failure();
          }
        }
        auto objN = rec->getString("object");
        if (!objN) {
          llvm::errs()
              << "s2c2-storage-capacity: source_data object required\n";
          return failure();
        }
        std::string id = normalizeCapacityObject(*objN);
        if (!occupancyIds.contains(id)) {
          llvm::errs()
              << "s2c2-storage-capacity: source_data not in occupancy\n";
          return failure();
        }
        auto replica = rec->getString("replica");
        if (!replica || (*replica != "ssd" && *replica != "host")) {
          llvm::errs() << "s2c2-storage-capacity: source_data replica must "
                          "be ssd or host\n";
          return failure();
        }
        auto witness = rec->getString("witness");
        auto scope = rec->getString("scope");
        if (!witness || !scope) {
          llvm::errs() << "s2c2-storage-capacity: source_data witness and "
                          "scope required\n";
          return failure();
        }
        auto *live = rec->getArray("live");
        if (!live || live->size() != 2) {
          llvm::errs()
              << "s2c2-storage-capacity: source_data live must be [start, end)\n";
          return failure();
        }
        auto s0 = (*live)[0].getAsInteger();
        auto s1 = (*live)[1].getAsInteger();
        if (!s0 || !s1 || *s0 >= *s1) {
          llvm::errs()
              << "s2c2-storage-capacity: source_data live must be [start, end)\n";
          return failure();
        }
        if (!seenData.insert(id).second) {
          llvm::errs()
              << "s2c2-storage-capacity: duplicate source_data\n";
          return failure();
        }
        if (sourceData) {
          CapSourceDataProof proof;
          proof.replica = replica->str();
          proof.witness = witness->str();
          proof.scope = scope->str();
          proof.start = (int)*s0;
          proof.end = (int)*s1;
          (*sourceData)[id] = proof;
        }
      }
    }
    if (obj->get("restore_order")) {
      auto *orders = obj->getArray("restore_order");
      if (!orders) {
        llvm::errs()
            << "s2c2-storage-capacity: restore_order must be an array\n";
        return failure();
      }
      llvm::StringSet<> orderOk;
      orderOk.insert("object");
      orderOk.insert("before");
      orderOk.insert("witness");
      orderOk.insert("scope");
      llvm::StringSet<> seenOrder;
      for (const llvm::json::Value &item : *orders) {
        auto *rec = item.getAsObject();
        if (!rec)
          return failure();
        for (const auto &kv : *rec) {
          if (!orderOk.contains(kv.getFirst())) {
            llvm::errs()
                << "s2c2-storage-capacity: restore_order extra keys\n";
            return failure();
          }
        }
        auto objN = rec->getString("object");
        if (!objN) {
          llvm::errs()
              << "s2c2-storage-capacity: restore_order object required\n";
          return failure();
        }
        std::string id = normalizeCapacityObject(*objN);
        if (!occupancyIds.contains(id)) {
          llvm::errs()
              << "s2c2-storage-capacity: restore_order not in occupancy\n";
          return failure();
        }
        auto before = rec->getInteger("before");
        auto witness = rec->getString("witness");
        auto scope = rec->getString("scope");
        if (!before || !witness || !scope) {
          llvm::errs() << "s2c2-storage-capacity: restore_order before, "
                          "witness, scope required\n";
          return failure();
        }
        if (!seenOrder.insert(id).second) {
          llvm::errs()
              << "s2c2-storage-capacity: duplicate restore_order\n";
          return failure();
        }
        if (restoreOrder) {
          CapRestoreOrderProof proof;
          proof.witness = witness->str();
          proof.scope = scope->str();
          proof.before = (int)*before;
          (*restoreOrder)[id] = proof;
        }
      }
    }
    if (obj->get("dest_invalidation")) {
      auto *drops = obj->getArray("dest_invalidation");
      if (!drops) {
        llvm::errs()
            << "s2c2-storage-capacity: dest_invalidation must be an array\n";
        return failure();
      }
      llvm::StringSet<> destOk;
      destOk.insert("object");
      destOk.insert("destination");
      destOk.insert("witness");
      destOk.insert("scope");
      llvm::StringSet<> seenDest;
      for (const llvm::json::Value &item : *drops) {
        auto *rec = item.getAsObject();
        if (!rec)
          return failure();
        for (const auto &kv : *rec) {
          if (!destOk.contains(kv.getFirst())) {
            llvm::errs()
                << "s2c2-storage-capacity: dest_invalidation extra keys\n";
            return failure();
          }
        }
        auto objN = rec->getString("object");
        if (!objN) {
          llvm::errs()
              << "s2c2-storage-capacity: dest_invalidation object required\n";
          return failure();
        }
        std::string id = normalizeCapacityObject(*objN);
        if (!occupancyIds.contains(id)) {
          llvm::errs()
              << "s2c2-storage-capacity: dest_invalidation not in occupancy\n";
          return failure();
        }
        auto dest = rec->getString("destination");
        auto witness = rec->getString("witness");
        auto scope = rec->getString("scope");
        if (!dest || !witness || !scope) {
          llvm::errs() << "s2c2-storage-capacity: dest_invalidation "
                          "destination, witness, scope required\n";
          return failure();
        }
        if (*dest != "hbm" && *dest != "ssd" && *dest != "host") {
          llvm::errs() << "s2c2-storage-capacity: dest_invalidation "
                          "destination must be hbm, ssd, or host\n";
          return failure();
        }
        if (!seenDest.insert(id).second) {
          llvm::errs()
              << "s2c2-storage-capacity: duplicate dest_invalidation\n";
          return failure();
        }
        if (destInv) {
          CapDestInvalidationProof proof;
          proof.destination = dest->str();
          proof.witness = witness->str();
          proof.scope = scope->str();
          (*destInv)[id] = proof;
        }
      }
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
  llvm::StringMap<std::string> restoreSources;
  llvm::StringMap<CapSourceDataProof> sourceData;
  llvm::StringMap<CapRestoreOrderProof> restoreOrder;
  llvm::StringMap<CapDestInvalidationProof> destInv;
  if (workloadClass)
    *workloadClass = std::string(kCapacityIrWorkload);
  if (!specPath.empty()) {
    if (failed(loadCapacitySpec(specPath, rs, space, cap, workloadClass,
                                &restoreSources, &sourceData, &restoreOrder,
                                &destInv)))
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
  auto planOr = buildCapacityPlan(rs, space, cap, peak, truncated, cands,
                                  restoreSources, sourceData, restoreOrder,
                                  destInv);
  if (failed(planOr))
    return failure();
  if (candsOut)
    *candsOut = std::move(cands);
  return *planOr;
}

LogicalResult reportCapacity(ModuleOp module, StringRef budgetStr,
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

static void printCapacityLicense(const CapacityPlan &plan) {
  StringRef sel = plan.selected;
  bool none = sel == "none";
  bool evictEmpty = none || sel.contains("|evict{}|");
  StringRef restore = none ? "n/a" : (evictEmpty ? "unused" : "unspecified");
  StringRef closed = none || evictEmpty ? "n/a" : "no";
  llvm::errs() << "s2c2-capacity-license schema=s2c2.capacity_license.v1\n";
  llvm::errs() << "s2c2-capacity-license selected=" << sel
               << " rewrite-license=no\n";
  llvm::errs() << "s2c2-capacity-license restore=" << restore
               << " restore-legal=TRANSFER|REMATERIALIZE"
               << " rematerialize-empty=yes evict-closed=" << closed << "\n";
  llvm::errs() << "s2c2-capacity-license note selected-ne-rewrite-license\n";
  llvm::errs() << "s2c2-capacity-license note evict-requires-restore\n";
  llvm::errs() << "s2c2-capacity-license note restore-unspecified\n";
  llvm::errs() << "s2c2-capacity-license note rematerialize-empty-this-stage\n";
  llvm::errs() << "s2c2-capacity-license note transfer-existing-realization\n";
  llvm::errs() << "s2c2-capacity-license note capability-license-ne-capacity-license\n";
  llvm::errs() << "s2c2-capacity-license note measured-ne-rewrite-license\n";
  llvm::errs() << "s2c2-capacity-license note six-c-g-license-gate-this-cut "
                  "cost=unchanged\n";
  llvm::errs() << "s2c2-capacity-license rewrite=no\n";
}

static void printCapacityRestore(const CapacityPlan &plan) {
  const CapacityCandidate *sel = nullptr;
  if (plan.selected != "none") {
    for (const CapacityCandidate &c : plan.candidates) {
      if (c.identity == plan.selected) {
        sel = &c;
        break;
      }
    }
  }
  bool none = !sel;
  bool evictEmpty = sel && sel->evict.empty();
  StringRef closed = "n/a";
  if (!none && !evictEmpty) {
    bool allValid = !sel->restores.empty() &&
                    sel->restores.size() == sel->evict.size();
    for (const CapacityRestore &r : sel->restores)
      allValid = allValid && r.valid;
    closed = allValid ? "yes" : "no";
  }
  llvm::errs() << "s2c2-capacity-restore schema=s2c2.capacity_restore.v1\n";
  llvm::errs() << "s2c2-capacity-restore selected=" << plan.selected
               << " closed=" << closed << "\n";
  if (sel && evictEmpty)
    llvm::errs() << "s2c2-capacity-restore restore=unused\n";
  if (sel && !evictEmpty) {
    for (const CapacityRestore &r : sel->restores) {
      llvm::errs() << "s2c2-capacity-restore object=" << r.object
                   << " kind=" << r.kind
                   << " valid=" << (r.valid ? "yes" : "no")
                   << " reason=" << r.reason << "\n";
    }
  }
  llvm::errs() << "s2c2-capacity-restore rewrite-license=no\n";
  llvm::errs() << "s2c2-capacity-restore note restore-ne-identity-string\n";
  llvm::errs() << "s2c2-capacity-restore note transfer-existing-realization\n";
  llvm::errs() << "s2c2-capacity-restore note occupancy-ir-ne-restore-source\n";
  llvm::errs() << "s2c2-capacity-restore note closed-ne-rewrite-license\n";
  llvm::errs() << "s2c2-capacity-restore note rematerialize-empty-this-stage\n";
  llvm::errs() << "s2c2-capacity-restore note six-c-g-license-gate-frozen\n";
  llvm::errs() << "s2c2-capacity-restore note six-c-h-restore-closure-this-cut "
                  "cost=unchanged\n";
  llvm::errs() << "s2c2-capacity-restore rewrite=no\n";
}

static const CapacityCandidate *
selectedCapacityCandidate(const CapacityPlan &plan) {
  if (plan.selected == "none")
    return nullptr;
  for (const CapacityCandidate &c : plan.candidates)
    if (c.identity == plan.selected)
      return &c;
  return nullptr;
}

static StringRef evictClosedOf(const CapacityCandidate *sel) {
  if (!sel || sel->evict.empty())
    return "n/a";
  bool allValid =
      !sel->restores.empty() && sel->restores.size() == sel->evict.size();
  for (const CapacityRestore &r : sel->restores)
    allValid = allValid && r.valid;
  return allValid ? "yes" : "no";
}

static void printCapacityPredicate(const CapacityPlan &plan) {
  const CapacityCandidate *sel = selectedCapacityCandidate(plan);
  bool inF = sel != nullptr;
  bool enumerated = plan.enumerated && !plan.truncated;
  StringRef closed = evictClosedOf(sel);
  StringRef restoreKind = "n/a";
  if (sel && sel->evict.empty())
    restoreKind = "unused";
  else if (sel)
    restoreKind = "TRANSFER";
  StringRef capacityProof = inF && enumerated ? "yes" : (inF ? "no" : "n/a");
  StringRef necessary = "no";
  if (sel && sel->evict.empty())
    necessary = "n/a";
  else if (inF && enumerated && closed == "yes" && restoreKind == "TRANSFER")
    necessary = "yes";
  llvm::errs() << "s2c2-capacity-predicate schema=s2c2.capacity_predicate.v1\n";
  llvm::errs() << "s2c2-capacity-predicate selected=" << plan.selected
               << " necessary=" << necessary << " sufficient=no"
               << " rewrite-license=no\n";
  llvm::errs() << "s2c2-capacity-predicate selected-in-f="
               << (inF ? "yes" : "no")
               << " enumerated=" << (enumerated ? "yes" : "no")
               << " capacity-proof=" << capacityProof
               << " evict-closed=" << closed
               << " restore-kind=" << restoreKind << "\n";
  StringRef sourceDataStatus = "no";
  if (!sel || sel->evict.empty())
    sourceDataStatus = "n/a";
  else {
    bool allData = !sel->restores.empty() &&
                   sel->restores.size() == sel->evict.size();
    for (const CapacityRestore &r : sel->restores)
      allData = allData && r.sourceData;
    sourceDataStatus = allData ? "yes" : "no";
  }
  StringRef restoreOrderingStatus = "no";
  if (!sel || sel->evict.empty())
    restoreOrderingStatus = "n/a";
  else {
    bool allOrd = !sel->restores.empty() &&
                  sel->restores.size() == sel->evict.size();
    for (const CapacityRestore &r : sel->restores)
      allOrd = allOrd && r.restoreOrdering;
    restoreOrderingStatus = allOrd ? "yes" : "no";
  }
  StringRef destInvStatus = "no";
  if (!sel || sel->evict.empty())
    destInvStatus = "n/a";
  else {
    bool allDest = !sel->restores.empty() &&
                   sel->restores.size() == sel->evict.size();
    for (const CapacityRestore &r : sel->restores)
      allDest = allDest && r.destInvalidation;
    destInvStatus = allDest ? "yes" : "no";
  }
  llvm::errs() << "s2c2-capacity-predicate source-data=" << sourceDataStatus
               << " restore-ordering=" << restoreOrderingStatus
               << " dest-invalidation=" << destInvStatus
               << " rewrite-path=no\n";
  llvm::errs() << "s2c2-capacity-predicate note necessary-ne-sufficient\n";
  llvm::errs() << "s2c2-capacity-predicate note closed-ne-rewrite-license\n";
  llvm::errs() << "s2c2-capacity-predicate note source-declaration-ne-data-validity\n";
  llvm::errs() << "s2c2-capacity-predicate note restore-source-ne-ordering\n";
  llvm::errs() << "s2c2-capacity-predicate note restore-source-ne-invalidation\n";
  llvm::errs() << "s2c2-capacity-predicate note six-c-g-license-gate-frozen\n";
  llvm::errs() << "s2c2-capacity-predicate note six-c-h-restore-closure-frozen\n";
  llvm::errs() << "s2c2-capacity-predicate note six-c-i-license-predicate-this-cut "
                  "cost=unchanged\n";
  llvm::errs() << "s2c2-capacity-predicate rewrite=no\n";
}

static StringRef sourceDataOf(const CapacityCandidate *sel) {
  if (!sel || sel->evict.empty())
    return "n/a";
  bool allData =
      !sel->restores.empty() && sel->restores.size() == sel->evict.size();
  for (const CapacityRestore &r : sel->restores)
    allData = allData && r.sourceData;
  return allData ? "yes" : "no";
}

static StringRef replicaExistsOf(const CapacityCandidate *sel) {
  if (!sel || sel->evict.empty())
    return "n/a";
  bool any = false;
  bool all = !sel->restores.empty() && sel->restores.size() == sel->evict.size();
  for (const CapacityRestore &r : sel->restores) {
    any = any || r.replicaExists;
    all = all && r.replicaExists;
  }
  if (all)
    return "yes";
  if (any)
    return "mixed";
  return "no";
}

static StringRef restoreOrderingOf(const CapacityCandidate *sel) {
  if (!sel || sel->evict.empty())
    return "n/a";
  bool allOrd =
      !sel->restores.empty() && sel->restores.size() == sel->evict.size();
  for (const CapacityRestore &r : sel->restores)
    allOrd = allOrd && r.restoreOrdering;
  return allOrd ? "yes" : "no";
}

static StringRef usableOf(const CapacityCandidate *sel) {
  if (!sel || sel->evict.empty())
    return "n/a";
  bool allU =
      !sel->restores.empty() && sel->restores.size() == sel->evict.size();
  for (const CapacityRestore &r : sel->restores)
    allU = allU && r.usable;
  return allU ? "yes" : "no";
}

static StringRef destInvalidationOf(const CapacityCandidate *sel) {
  if (!sel || sel->evict.empty())
    return "n/a";
  bool allDest =
      !sel->restores.empty() && sel->restores.size() == sel->evict.size();
  for (const CapacityRestore &r : sel->restores)
    allDest = allDest && r.destInvalidation;
  return allDest ? "yes" : "no";
}

static void printCapacitySourceData(const CapacityPlan &plan) {
  const CapacityCandidate *sel = selectedCapacityCandidate(plan);
  StringRef status = sourceDataOf(sel);
  llvm::errs() << "s2c2-capacity-sourcedata schema=s2c2.capacity_sourcedata.v1\n";
  llvm::errs() << "s2c2-capacity-sourcedata selected=" << plan.selected
               << " source-data=" << status
               << " replica-exists=" << replicaExistsOf(sel)
               << " usable=" << usableOf(sel) << "\n";
  if (sel && sel->evict.empty())
    llvm::errs() << "s2c2-capacity-sourcedata restore=unused\n";
  if (sel && !sel->evict.empty()) {
    for (const CapacityRestore &r : sel->restores) {
      llvm::errs() << "s2c2-capacity-sourcedata object=" << r.object
                   << " replica=" << r.replica << " witness=" << r.witness
                   << " scope=" << r.scope
                   << " replica-exists=" << (r.replicaExists ? "yes" : "no")
                   << " source-data=" << (r.sourceData ? "yes" : "no")
                   << " usable=" << (r.usable ? "yes" : "no")
                   << " reason=" << r.sourceDataReason << "\n";
    }
  }
  llvm::errs() << "s2c2-capacity-sourcedata rewrite-license=no\n";
  llvm::errs() << "s2c2-capacity-sourcedata note replica-exists-ne-data-validity\n";
  llvm::errs() << "s2c2-capacity-sourcedata note source-declaration-ne-data-validity\n";
  llvm::errs() << "s2c2-capacity-sourcedata note source-data-ne-usable\n";
  llvm::errs() << "s2c2-capacity-sourcedata note token-eq-validity-witness\n";
  llvm::errs() << "s2c2-capacity-sourcedata note no-validity-fsm\n";
  llvm::errs() << "s2c2-capacity-sourcedata note closed-ne-data-valid\n";
  llvm::errs() << "s2c2-capacity-sourcedata note unknown-ne-rewrite\n";
  llvm::errs() << "s2c2-capacity-sourcedata note source-data-ne-sufficient\n";
  llvm::errs() << "s2c2-capacity-sourcedata note restore-source-ne-ordering\n";
  llvm::errs() << "s2c2-capacity-sourcedata note restore-source-ne-invalidation\n";
  llvm::errs() << "s2c2-capacity-sourcedata note six-c-g-license-gate-frozen\n";
  llvm::errs() << "s2c2-capacity-sourcedata note six-c-h-restore-closure-frozen\n";
  llvm::errs() << "s2c2-capacity-sourcedata note six-c-i-license-predicate-frozen\n";
  llvm::errs() << "s2c2-capacity-sourcedata note six-c-j-source-data-this-cut "
                  "cost=unchanged\n";
  llvm::errs() << "s2c2-capacity-sourcedata rewrite=no\n";
}

static void printCapacityOrdering(const CapacityPlan &plan) {
  const CapacityCandidate *sel = selectedCapacityCandidate(plan);
  llvm::errs() << "s2c2-capacity-ordering schema=s2c2.capacity_ordering.v1\n";
  llvm::errs() << "s2c2-capacity-ordering selected=" << plan.selected
               << " restore-ordering=" << restoreOrderingOf(sel)
               << " usable=" << usableOf(sel) << "\n";
  if (sel && sel->evict.empty())
    llvm::errs() << "s2c2-capacity-ordering restore=unused\n";
  if (sel && !sel->evict.empty()) {
    for (const CapacityRestore &r : sel->restores) {
      llvm::errs() << "s2c2-capacity-ordering object=" << r.object
                   << " before=" << r.orderBefore
                   << " witness=" << r.orderWitness
                   << " scope=" << r.orderScope
                   << " restore-ordering="
                   << (r.restoreOrdering ? "yes" : "no")
                   << " usable=" << (r.usable ? "yes" : "no")
                   << " reason=" << r.restoreOrderingReason << "\n";
    }
  }
  llvm::errs() << "s2c2-capacity-ordering rewrite-license=no\n";
  llvm::errs() << "s2c2-capacity-ordering note source-data-ne-ordering\n";
  llvm::errs() << "s2c2-capacity-ordering note source-valid-ne-restore-at-point\n";
  llvm::errs() << "s2c2-capacity-ordering note restore-ordering-ne-usable\n";
  llvm::errs() << "s2c2-capacity-ordering note restore-ordering-ne-sufficient\n";
  llvm::errs() << "s2c2-capacity-ordering note dest-invalidation-still-no\n";
  llvm::errs() << "s2c2-capacity-ordering note unknown-ne-rewrite\n";
  llvm::errs() << "s2c2-capacity-ordering note six-c-g-license-gate-frozen\n";
  llvm::errs() << "s2c2-capacity-ordering note six-c-h-restore-closure-frozen\n";
  llvm::errs() << "s2c2-capacity-ordering note six-c-i-license-predicate-frozen\n";
  llvm::errs() << "s2c2-capacity-ordering note six-c-j-source-data-frozen\n";
  llvm::errs() << "s2c2-capacity-ordering note six-c-k-restore-ordering-this-cut "
                  "cost=unchanged\n";
  llvm::errs() << "s2c2-capacity-ordering rewrite=no\n";
}

static void printCapacityInvalidation(const CapacityPlan &plan) {
  const CapacityCandidate *sel = selectedCapacityCandidate(plan);
  llvm::errs() << "s2c2-capacity-invalidation schema=s2c2.capacity_invalidation.v1\n";
  llvm::errs() << "s2c2-capacity-invalidation selected=" << plan.selected
               << " dest-invalidation=" << destInvalidationOf(sel)
               << " usable=" << usableOf(sel) << "\n";
  if (sel && sel->evict.empty())
    llvm::errs() << "s2c2-capacity-invalidation restore=unused\n";
  if (sel && !sel->evict.empty()) {
    for (const CapacityRestore &r : sel->restores) {
      llvm::errs() << "s2c2-capacity-invalidation object=" << r.object
                   << " destination=" << r.destSpace
                   << " witness=" << r.destWitness
                   << " scope=" << r.destScope
                   << " dest-invalidation="
                   << (r.destInvalidation ? "yes" : "no")
                   << " usable=" << (r.usable ? "yes" : "no")
                   << " reason=" << r.destInvalidationReason << "\n";
    }
  }
  llvm::errs() << "s2c2-capacity-invalidation rewrite-license=no\n";
  llvm::errs() << "s2c2-capacity-invalidation note usable-ne-dest-invalidation\n";
  llvm::errs() << "s2c2-capacity-invalidation note dest-invalidation-ne-sufficient\n";
  llvm::errs() << "s2c2-capacity-invalidation note dest-invalidation-ne-rewrite-path\n";
  llvm::errs() << "s2c2-capacity-invalidation note rewrite-path-still-no\n";
  llvm::errs() << "s2c2-capacity-invalidation note unknown-ne-rewrite\n";
  llvm::errs() << "s2c2-capacity-invalidation note six-c-g-license-gate-frozen\n";
  llvm::errs() << "s2c2-capacity-invalidation note six-c-h-restore-closure-frozen\n";
  llvm::errs() << "s2c2-capacity-invalidation note six-c-i-license-predicate-frozen\n";
  llvm::errs() << "s2c2-capacity-invalidation note six-c-j-source-data-frozen\n";
  llvm::errs() << "s2c2-capacity-invalidation note six-c-k-restore-ordering-frozen\n";
  llvm::errs() << "s2c2-capacity-invalidation note six-c-l-dest-invalidation-this-cut "
                  "cost=unchanged\n";
  llvm::errs() << "s2c2-capacity-invalidation rewrite=no\n";
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

LogicalResult queryCapacityPlan(ModuleOp module, StringRef budgetStr,
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
  printCapacityLicense(plan);
  printCapacityRestore(plan);
  printCapacityPredicate(plan);
  printCapacitySourceData(plan);
  printCapacityOrdering(plan);
  printCapacityInvalidation(plan);
  if (!dumpPath.empty() && failed(dumpCapacityPlanJson(dumpPath, plan)))
    return failure();
  return success();
}
} // namespace mlir::s2c2
