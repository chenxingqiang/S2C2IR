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

def Sched_TaskOp : Sched_Op<"task", [
    RecursiveMemoryEffects,
    SingleBlockImplicitTerminator<"YieldOp">,
    HasAsyncToken
  ]> {
  let summary = "A concurrently schedulable region with a completion event";
  let description = [{
    Always produces a `!sched.token`. Additional results match the body's
    `sched.yield` operands and are visible to the parent block.

    Example:

    ```mlir
    %t, %out = sched.task -> tensor<4xf32> {
      %out = comp.matmul %a, %b : tensor<4x4xf32>, tensor<4x4xf32> -> tensor<4x4xf32>
      sched.yield %out : tensor<4xf32>
    }
    ```
  }];
  let regions = (region SizedRegion<1>:$body);
  let results = (outs Sched_TokenType:$token, Variadic<AnyType>:$values);
  let assemblyFormat = [{
    (`->` type($values)^)? attr-dict-with-keyword $body
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::Type getAsyncTokenType() { return getToken().getType(); }
  }];
}

def Sched_ConcurrentOp : Sched_Op<"concurrent", [
    RecursiveMemoryEffects,
    SingleBlockImplicitTerminator<"YieldOp">
  ]> {
  let summary = "N-way concurrent tasks (storage, compute, and/or communication)";
  let description = [{
    Core concurrency construct: `Concurrent(A, B, C)`, not
    `Overlap(Compute, Comm)`.

    Semantics: children have **no ordering requirement**. They may run
    concurrently, or in any legal total order consistent with explicit
    `sched.wait` / token dependencies. Sequentialization is a legal
    degeneration, not schedule preservation.

    Phase 2A / v0.1: the body may contain only `sched.task` ops plus the
    terminator. Nested `sched.pipeline` / `sched.overlap` / `sched.concurrent`
    is rejected until structured-schedule lowering exists.

    Results match this op's `sched.yield` operands.

    Example:

    ```mlir
    %y = sched.concurrent -> tensor<4xf32> {
      %tc, %out = sched.task -> tensor<4xf32> {
        sched.yield %v : tensor<4xf32>
      }
      %ts = sched.task {
        sched.yield
      }
      sched.yield %out : tensor<4xf32>
    }
    ```
  }];
  let regions = (region SizedRegion<1>:$body);
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = [{
    (`->` type($results)^)? attr-dict-with-keyword $body
  }];
  let hasVerifier = 1;
}

def Sched_OverlapOp : Sched_Op<"overlap", [
    RecursiveMemoryEffects,
    SingleBlockImplicitTerminator<"YieldOp">
  ]> {
  let summary = "Two-region compute/comm overlap (sugar for sched.concurrent)";
  let description = [{
    Convenience 2-way form. Prefer `sched.concurrent` + `sched.task` when
    more than two sides overlap (storage || compute || communication).

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
