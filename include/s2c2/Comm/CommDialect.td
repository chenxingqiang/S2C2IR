//===- CommDialect.td - S²C² Communication dialect -------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_COMM_DIALECT
#define S2C2_COMM_DIALECT

include "mlir/IR/OpBase.td"

def Comm_Dialect : Dialect {
  let name = "comm";
  let summary = "S2C2 communication dialect: how data moves.";
  let description = [{
    Copies, streaming transfers, and barriers between storage buffers.
    Later phases lower these to `mpi`, `async`, or DMA-like runtime ops.
  }];
  let cppNamespace = "::mlir::s2c2::comm";
  let useDefaultAttributePrinterParser = 1;
  let dependentDialects = [
    "::mlir::s2c2::stor::StorageDialect",
    "::mlir::s2c2::sched::ScheduleDialect"
  ];
  let extraClassDeclaration = [{
    void registerAttributes();
  }];
}

class Comm_Op<string mnemonic, list<Trait> traits = []>
    : Op<Comm_Dialect, mnemonic, traits>;

#endif // S2C2_COMM_DIALECT
