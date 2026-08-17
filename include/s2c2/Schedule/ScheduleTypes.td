//===- ScheduleTypes.td - S²C² Schedule types ------------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_SCHEDULE_TYPES
#define S2C2_SCHEDULE_TYPES

include "s2c2/Schedule/ScheduleDialect.td"
include "mlir/IR/AttrTypeBase.td"

class Sched_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<Schedule_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

def Sched_TokenType : Sched_Type<"Token", "token"> {
  let summary = "Asynchronous completion token";
  let description = [{
    Produced by asynchronous communication and consumed by `sched.wait`.
  }];
}

#endif // S2C2_SCHEDULE_TYPES
