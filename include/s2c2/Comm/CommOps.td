//===- CommOps.td - S²C² Communication operations --------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_COMM_OPS
#define S2C2_COMM_OPS

include "s2c2/Comm/CommEnums.td"
include "s2c2/Storage/StorageTypes.td"
include "s2c2/Schedule/ScheduleTypes.td"
include "s2c2/Schedule/ScheduleInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Comm_CopyOp : Comm_Op<"copy", []> {
  let summary = "Copy between storage buffers";
  let arguments = (ins
    Stor_BufferType:$src,
    Stor_BufferType:$dst,
    OptionalAttr<Comm_KindAttr>:$kind
  );
  let assemblyFormat = "$src `,` $dst attr-dict `:` qualified(type($src)) `,` qualified(type($dst))";
  let hasVerifier = 1;
}

def Comm_StreamOp : Comm_Op<"stream", [HasAsyncToken]> {
  let summary = "Asynchronous streaming transfer between storage spaces";
  let description = [{
    SSD-to-HBM (or DMA) streaming. Payload types must match; spaces must differ.
    Produces a `!sched.token` for `sched.wait` / compute-comm overlap.
  }];
  let arguments = (ins
    Stor_BufferType:$src,
    Stor_BufferType:$dst,
    OptionalAttr<Comm_EngineAttr>:$engine
  );
  let results = (outs Sched_TokenType:$token);
  let assemblyFormat = [{
    $src `,` $dst attr-dict `:` qualified(type($src)) `,` qualified(type($dst)) `->` type($token)
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::Type getAsyncTokenType() { return getToken().getType(); }
  }];
}

def Comm_BarrierOp : Comm_Op<"barrier", []> {
  let summary = "Synchronize on optional async tokens";
  let arguments = (ins Variadic<Sched_TokenType>:$tokens);
  let assemblyFormat = "$tokens attr-dict (`:` type($tokens)^)?";
}

#endif // S2C2_COMM_OPS
