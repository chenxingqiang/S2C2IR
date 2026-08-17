//===- ScheduleInterfaces.td - S²C² Schedule interfaces --*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_SCHEDULE_INTERFACES
#define S2C2_SCHEDULE_INTERFACES

include "mlir/IR/OpBase.td"

def HasAsyncToken : OpInterface<"HasAsyncToken"> {
  let cppNamespace = "::mlir::s2c2::sched";
  let description = [{
    Ops that produce a generic `!sched.token` completion event. The producer
    may be storage, compute, communication, or a `sched.task` region.
  }];
  let methods = [
    InterfaceMethod<
      "Return the async token type produced by this op.",
      "::mlir::Type",
      "getAsyncTokenType"
    >
  ];
}

#endif // S2C2_SCHEDULE_INTERFACES
