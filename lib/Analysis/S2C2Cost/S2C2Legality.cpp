//===- S2C2Legality.cpp - IsLegal(P, D, M) capability oracle ----*- C++ -*-===//
//
// Shared capability predicate. Enumerator / Search / Placement must
// call this instead of inventing a second matrix.
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Legality.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"

using llvm::StringRef;

namespace mlir::s2c2 {

bool isLegalRealization(func::FuncOp program, StringRef sched,
                        StringRef spaceMap, StringRef device) {
  if (program.getBody().empty())
    return false;
  if (spaceMap != "default" && spaceMap != "t5")
    return false;

  if (sched == "cpu-seq")
    return device == "cpu" || device == "cim";
  if (sched == "gpu-async")
    return device == "gpu";
  if (sched == "npu-staged-dma")
    return device == "npu";
  return false;
}

} // namespace mlir::s2c2
