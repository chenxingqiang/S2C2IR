//===- ScheduleOps.td - S²C² Schedule operations ---------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_SCHEDULE_OPS
#define S2C2_SCHEDULE_OPS

include "s2c2/Schedule/ScheduleTypes.td"
include "s2c2/Schedule/ScheduleInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Sched_YieldOp : Sched_Op<"yield", [Pure, ReturnLike, Terminator]> {
  let summary = "Terminator for schedule regions";
  let arguments = (ins Variadic<AnyType>:$operands);
  let assemblyFormat = "$operands attr-dict (`:` type($operands)^)?";
  let builders = [
    OpBuilder<(ins), [{
      build($_builder, $_state, ::mlir::ValueRange());
    }]>
  ];
}

def Sched_WaitOp : Sched_Op<"wait", []> {
  let summary = "Wait for asynchronous tokens";
  let arguments = (ins Variadic<Sched_TokenType>:$tokens);
  let assemblyFormat = "$tokens attr-dict `:` type($tokens)";
}

def Sched_OverlapOp : Sched_Op<"overlap", [
    RecursiveMemoryEffects,
    SingleBlockImplicitTerminator<"YieldOp">
  ]> {
  let summary = "Overlap a compute region with a communication region";
  let description = [{
    Two regions intended to execute concurrently:

    * `compute` yields the overlap results
    * `communicate` performs copies/streams (side-effecting)

    Example:

    ```mlir
    %y = sched.overlap -> tensor<4xf32> {
      sched.wait %t : !sched.token
      sched.yield %v : tensor<4xf32>
    } {
      %t = comm.stream %src, %dst : ... -> !sched.token
      sched.yield
    }
    ```
  }];
  let regions = (region
    SizedRegion<1>:$compute,
    SizedRegion<1>:$communicate
  );
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = [{
    (`->` type($results)^)? attr-dict-with-keyword $compute $communicate
  }];
  let hasVerifier = 1;
}

def Sched_PipelineOp : Sched_Op<"pipeline", [
    RecursiveMemoryEffects,
    SingleBlockImplicitTerminator<"YieldOp">
  ]> {
  let summary = "Ordered pipeline of named stages";
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "attr-dict-with-keyword $body";
}

def Sched_StageOp : Sched_Op<"stage", [
    RecursiveMemoryEffects,
    SingleBlockImplicitTerminator<"YieldOp">
  ]> {
  let summary = "Named pipeline stage";
  let arguments = (ins StrAttr:$name);
  let regions = (region SizedRegion<1>:$body);
  let assemblyFormat = "$name attr-dict-with-keyword $body";
}

#endif // S2C2_SCHEDULE_OPS
