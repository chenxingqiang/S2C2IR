//===- S2C2Legality.h - IsLegal(P, D, M) capability oracle ------*- C++ -*-===//
//
// Frozen capability predicate consumed by Enumerator (and later
// Search / Placement). Does not redefine HB or Cost.
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_S2C2LEGALITY_H
#define S2C2_S2C2LEGALITY_H

#include "llvm/ADT/StringRef.h"

namespace mlir {
namespace func {
class FuncOp;
} // namespace func
namespace s2c2 {

/// IsLegal(P, D, M) for M = (sched, spaceMap, device) on F_0 axes.
/// T1/T2/T3 profile pairing from capability-mapping.md:
///   cpu-seq          ↔ cpu, cim
///   gpu-async        ↔ gpu
///   npu-staged-dma   ↔ npu
///   default, t5      legal maps
/// HB_M = HB_source is a construction invariant of non-rewriting
/// consumers; this oracle does not rebuild HB.
bool isLegalRealization(func::FuncOp program, llvm::StringRef sched,
                        llvm::StringRef spaceMap, llvm::StringRef device);

} // namespace s2c2
} // namespace mlir

#endif
