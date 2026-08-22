//===- S2C2Family.h - Finite family F_0 axis helpers ------------*- C++ -*-===//
//
// Shared F_0 declaration order for Enumerator and ArgMin / Pareto.
// Deterministic product order, not a search rank.
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_S2C2FAMILY_H
#define S2C2_S2C2FAMILY_H

#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

namespace mlir {
class Operation;
namespace s2c2 {

/// F_0 axes (declaration order):
///   scheds  = cpu-seq, gpu-async, npu-staged-dma
///   maps    = default, t5
///   devices = cpu, gpu, npu, cim
llvm::ArrayRef<llvm::StringRef> familyF0Scheds();
llvm::ArrayRef<llvm::StringRef> familyF0Maps();
llvm::ArrayRef<llvm::StringRef> familyF0Devices();

/// Intersect CSV `field` with `universe`, emit in universe order.
/// Empty field means the full universe. Unknown labels fail with
///   unknown <passName> <what> '<label>'; not in F_0
LogicalResult selectFamilyAxis(llvm::StringRef field, llvm::StringRef passName,
                               llvm::StringRef what,
                               llvm::ArrayRef<llvm::StringRef> universe,
                               llvm::SmallVectorImpl<llvm::StringRef> &out,
                               Operation *reporter);

} // namespace s2c2
} // namespace mlir

#endif
