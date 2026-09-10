//===- S2C2CapacityPlan.h - compiler-visible F_capacity object -*- C++ -*-===//
//
// Phase 6C-C. CapacityPlan is the candidate object for occupancy
// feasibility. Diagnostic path: selected is none. Query consumer
// may apply s0 or measured-capacity-v1; not a rewrite license.
// 6C-G freezes the license gate (still no). 6C-H attaches a
// TRANSFER restore record to each EVICT object. 6C-I classifies
// the license predicate (necessary vs sufficient; still no).
// 6C-B diagnostics stay frozen.
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_S2C2CAPACITYPLAN_H
#define S2C2_S2C2CAPACITYPLAN_H

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <string>

namespace mlir::s2c2 {

/// Stable identity for a capacity-feasible occupancy assignment.
/// KEEP / EVICT / REMATERIALIZE sets; empty sets stay in the string
/// so later measured-capacity-v1 / capacity-policy can match.
inline std::string capacityCandidateIdentity(
    llvm::ArrayRef<std::string> keep, llvm::ArrayRef<std::string> evict,
    llvm::ArrayRef<std::string> rematerialize) {
  auto join = [](llvm::ArrayRef<std::string> xs) {
    std::string s;
    for (size_t i = 0; i < xs.size(); ++i) {
      if (i)
        s += ',';
      s += xs[i];
    }
    return s;
  };
  return "keep{" + join(keep) + "}|evict{" + join(evict) +
         "}|rematerialize{" + join(rematerialize) + "}";
}

/// Per-EVICT TRANSFER restore attached to a CapacityCandidate.
/// TRANSFER is the existing slower-space restore realization, not a
/// new 6C action. valid iff the occupancy spec names a restore source
/// on ssd or host. Occupancy IR has no restore sources. Closure is
/// proven only when every EVICT has a valid restore. 6C-H does not
/// issue rewrite-license=yes.
struct CapacityRestore {
  std::string object;
  std::string kind = "TRANSFER";
  bool valid = false;
  std::string reason;
};

struct CapacityCandidate {
  unsigned id = 0;
  std::string identity;
  llvm::SmallVector<std::string, 4> keep;
  llvm::SmallVector<std::string, 4> evict;
  llvm::SmallVector<std::string, 4> rematerialize;
  llvm::SmallVector<CapacityRestore, 4> restores;
};

/// Compiler-visible F_capacity. Policy does not rank unless a named
/// capacity-policy is applied on the query consumer. Rewrite does
/// not run. F_capacity ⊆ F_residency; illegal ids cannot expand F.
/// Query via --query-capacity-plan (6C-D). Optional --capacity-policy=s0
/// (6C-E) or measured-capacity-v1 (6C-F) selects from F_capacity;
/// measured ranking matches profile + workload + candidate.
/// Duplicate (profile, workload, candidate) is rejected.
/// Equal measured times pick the earliest F_capacity inhabitant.
/// 6C-G freezes the rewrite-license gate (still no).
/// 6C-H attaches TRANSFER restore records to EVICT objects
/// (candidate semantics, not an identity-string parse).
/// 6C-I classifies the license predicate on the query consumer:
/// necessary conjuncts vs still-missing sufficient proof.
/// Not a rewrite license.
struct CapacityPlan {
  static constexpr llvm::StringLiteral kSchema{"s2c2.capacity_plan.v1"};
  std::string schema = std::string(kSchema);
  std::string space = "hbm";
  int capacity = 0;
  int peakLive = 0;
  bool feasible = false;
  bool enumerated = false;
  bool truncated = false;
  std::string selected = "none";
  std::string policy = "none";
  bool rewriteLicense = false;
  llvm::SmallVector<CapacityCandidate, 8> candidates;
};

} // namespace mlir::s2c2

#endif // S2C2_S2C2CAPACITYPLAN_H
