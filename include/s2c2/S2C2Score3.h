//===- S2C2Score3.h - Frozen v0.3 CanonicalRealizationCost ------*- C++ -*-===//
//
// Shared Score_3 used by --s2c2-cost-cp and ArgMin_F / Pareto_F.
// Does not rewrite IR, redefine HB, or change v0.3 numbers.
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_S2C2SCORE3_H
#define S2C2_S2C2SCORE3_H

#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>

namespace mlir {
namespace func {
class FuncOp;
} // namespace func
namespace s2c2 {

/// Frozen Cost Model v0.3:
///   Score_3.total = T_HB + C_contention + C_capacity
///                 = T_full + C_capacity
/// `total` is the scalar objective, not a fourth Pareto axis.
struct Score3 {
  int64_t criticalPath = 0;
  int64_t contention = 0;
  int64_t capacity = 0;
  int64_t total = 0;
};

/// Strict Pareto domination on Cost⃗ = (T_HB, C_contention, C_capacity).
/// `total` is not a fourth axis. Shared by `--s2c2-argmin` and Nxt_P.
inline bool strictlyDominates(const Score3 &a, const Score3 &b) {
  bool le = a.criticalPath <= b.criticalPath && a.contention <= b.contention &&
            a.capacity <= b.capacity;
  bool lt = a.criticalPath < b.criticalPath || a.contention < b.contention ||
            a.capacity < b.capacity;
  return le && lt;
}

/// True for the frozen v0.3 device table: cpu, gpu, npu, cim.
bool isKnownScore3Device(llvm::StringRef device);

/// Score `program` with frozen v0.3 CanonicalRealizationCost for `device`.
/// Does not rewrite IR. Emits cyclic-graph errors on `program`.
/// Unknown device returns failure without emitting.
mlir::LogicalResult computeScore3(func::FuncOp program, llvm::StringRef device,
                                  Score3 &out);

} // namespace s2c2
} // namespace mlir

#endif
