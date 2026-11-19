//===- S2C2CapabilityInternal.h - shared phase internals ---------*- C++ -*-===//
//
// Internal declarations shared between the phase files of the
// capability passes (lib/Analysis/S2C2Capability). Not installed and
// not part of the public s2c2 API. Everything here used to live in
// the single S2C2CapabilitySchedule.cpp translation unit; the split
// is structural only.
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_CAPABILITY_INTERNAL_H
#define S2C2_CAPABILITY_INTERNAL_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Support/LogicalResult.h"
#include "s2c2/Storage/StorageTypes.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/CommandLine.h"

#include <cstdint>
#include <optional>
#include <string>

namespace mlir::s2c2 {

// Command-line options are defined in S2C2CapabilitySchedule.cpp.
extern llvm::cl::opt<std::string> clS2C2Profile;
extern llvm::cl::opt<std::string> clS2C2Evidence;

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

struct ResolvedProfile {
  std::string name;
  std::string device;
  std::string evidenceDesc;
};

struct RegionClass {
  bool compute = false;
  bool silu = false;
  bool gemm = false;
  bool htod = false;
  bool dtoh = false;
  bool d2d = false;
  bool storage = false;
};

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

struct ReuseStats {
  unsigned applied = 0;
  unsigned skipped = 0;
};

struct GlobalCostRank {
  SmallVector<ChainAssignment, 4> ranked;
  int64_t score = 0;
  unsigned argminSize = 0;
  bool applicable = false;
  bool rankedInLegal = false;
  bool rankedEqDefault3g = false;
  SmallVector<int64_t, 16> candidateScores;
};

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

enum class SchedulePolicyKind { Unset, Default3g, CostV04, MeasuredStorageV1 };

struct NamedPolicyPick {
  std::string selected;
  std::string source;
  std::string reason;
  std::string coincide;
  bool applicable = false;
};

bool isHostLike(Space space);

bool isDeviceLike(Space space);

std::optional<Space> bufferSpace(Value value);

LogicalResult loadCatalog(StringRef device, StringRef profilePath,
                                 CapCatalog &cat);

std::string resolveExistingPath(StringRef path, StringRef relativeToDir);

LogicalResult
loadEvidenceBoundedCatalog(StringRef profileOpt, StringRef evidenceOpt,
                           CapCatalog &cat, ResolvedProfile &out);

Role parseRole(StringRef raw);

std::string pairFromRoles(Role a, Role b);

void classifySpaces(std::optional<Space> srcSpace,
                           std::optional<Space> dstSpace, RegionClass &cls);

std::string classifyPair(Region &a, Region &b);

QueryContext contextFromRegions(Region &a, Region &b, StringRef pair);

CapCell lookupPair(const CapCatalog &cat, StringRef pair,
                          std::optional<int64_t> sizeBytes);

Applicability isApplicable(const CapCell &cell, const QueryContext &ctx);

StringRef applicabilityStr(Applicability app);

void printQueryJson(StringRef device, StringRef pair, const CapCell &cell,
                           StringRef via, Applicability app);

bool shouldSerialize(const CapCell &cell, Applicability app);

bool isStorageCommOverlap(StringRef pair);

StringRef decisionStr(DecisionKind kind);

DecisionKind classifyDecision(const CapCell &cell, Applicability app,
                                     bool serialize, StringRef pair);

std::string decisionReason(const CapCell &cell, Applicability app,
                                  bool serialize, StringRef pair);

void fillWorkloadDecision(WorkloadDecision &d, unsigned id, StringRef via,
                                 StringRef pair, const QueryContext &ctx,
                                 const CapCell &cell, Applicability app,
                                 bool serialize);

void countDecisions(ArrayRef<WorkloadDecision> decisions, unsigned &keep,
                           unsigned &flatten, unsigned &preserve);

std::string prettyReason(StringRef reason);

void printWorkloadCandidate(const WorkloadDecision &d);

StringRef spaceName(std::optional<Space> space);

std::optional<Space> parseSpaceName(StringRef name);

StringRef hierarchyActionStr(HierarchyAction action);

std::string joinActions(ArrayRef<HierarchyAction> acts, char sep);

std::string joinGlobal(ArrayRef<ChainAssignment> asns);

void printHierarchySite(const HierarchySite &s);

void countHierarchy(ArrayRef<HierarchySite> sites, unsigned &materialize,
                           unsigned &prefetch, unsigned &transfer,
                           unsigned &keep, unsigned &preserve);

ReuseStats applyProvenResidencyReuse(ModuleOp module);

SmallVector<HierarchySite, 16> planStorageHierarchy(ModuleOp module,
                                                       const CapCatalog &cat);

bool sameAssignment(ArrayRef<HierarchyAction> a,
                           ArrayRef<HierarchyAction> b);

SmallVector<JointChain, 4>
planJointChains(ArrayRef<HierarchySite> sites);

void printJointChain(const JointChain &c);

void printJointSchedule(ArrayRef<JointChain> chains);

GlobalSchedule planGlobalSchedule(ArrayRef<JointChain> chains);

void printGlobalSchedule(const GlobalSchedule &g, unsigned nChains);

GlobalCostRank rankGlobalCost(ArrayRef<JointChain> chains,
                                     ArrayRef<HierarchySite> sites,
                                     const GlobalSchedule &g);

void printGlobalCostRank(const GlobalCostRank &r,
                                const GlobalSchedule &g);

LogicalResult
loadMeasuredCostTable(StringRef path,
                      SmallVectorImpl<MeasuredCostRecord> &out);

GlobalMeasuredRank
rankGlobalMeasured(const GlobalSchedule &g, StringRef profile,
                   ArrayRef<MeasuredCostRecord> table);

void printGlobalMeasuredRank(const GlobalMeasuredRank &r,
                                    const GlobalSchedule &g);

FailureOr<SchedulePolicyKind> parseSchedulePolicy(StringRef name);

NamedPolicyPick
pickNamedPolicy(SchedulePolicyKind kind, const GlobalSchedule &g,
                const GlobalCostRank &cost, const GlobalMeasuredRank &meas);

void printNamedSchedulePolicy(SchedulePolicyKind kind,
                                     const NamedPolicyPick &p);

void printScheduleExplain(SchedulePolicyKind kind, StringRef profile,
                                 ArrayRef<HierarchySite> sites,
                                 const GlobalSchedule &g,
                                 const GlobalCostRank &cost,
                                 const GlobalMeasuredRank &meas,
                                 const NamedPolicyPick &p);

void reportLoopPipeline(ModuleOp module);

LogicalResult reportCapacity(ModuleOp module, StringRef budgetStr,
                                    StringRef specPath, StringRef dumpPath);

LogicalResult queryCapacityPlan(ModuleOp module, StringRef budgetStr,
                                       StringRef specPath, StringRef dumpPath,
                                       StringRef policyName,
                                       StringRef tablePath,
                                       StringRef profile);

} // namespace mlir::s2c2
#endif // S2C2_CAPABILITY_INTERNAL_H
