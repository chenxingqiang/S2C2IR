//===- S2C2CapabilitySchedule.cpp - pass driver ------------------*- C++ -*-===//
//
// Driver TU for the capability passes (s2c2-capability-query,
// s2c2-capability-schedule, s2c2-evidence-bounded-schedule,
// s2c2-capacity-plan-query). Owns the command-line options, the
// workload-schedule JSON dump, the licensed concurrent-to-serial
// rewrite step, and the pass structs. The Phase 3A-3E/3F catalog and
// query live in S2C2CapabilityCatalog.cpp, 3G/3H/3I + 4A-4D + 5A
// hierarchy/F(program) in S2C2HierarchySchedule.cpp, and Phase 6C
// capacity in S2C2CapacityPlan.cpp. The split is structural; behavior
// and printed output are unchanged.
//
// Generic rewrite pipeline (one inhabitant: concurrent->serial):
//   RewriteCandidate -> EvidenceQuery -> Applicability
//     -> RewriteLicense -> Rewrite -> Verifier
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

#include "S2C2CapabilityInternal.h"

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
namespace {
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
