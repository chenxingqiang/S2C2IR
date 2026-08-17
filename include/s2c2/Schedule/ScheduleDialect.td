//===- ScheduleDialect.td - S²C² Schedule dialect --------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_SCHEDULE_DIALECT
#define S2C2_SCHEDULE_DIALECT

include "mlir/IR/OpBase.td"

def Schedule_Dialect : Dialect {
  let name = "sched";
  let summary = "S2C2 schedule dialect: when ops run and how they overlap.";
  let description = [{
    Async tokens, wait, compute/communication overlap, and pipeline stages.
    This is intentionally independent of IREE Stream/HAL.
  }];
  let cppNamespace = "::mlir::s2c2::sched";
  let useDefaultTypePrinterParser = 1;
  let extraClassDeclaration = [{
    void registerTypes();
  }];
}

class Sched_Op<string mnemonic, list<Trait> traits = []>
    : Op<Schedule_Dialect, mnemonic, traits>;

#endif // S2C2_SCHEDULE_DIALECT
