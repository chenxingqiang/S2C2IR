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
  let summary = "Copy payload between residencies of the same logical object";
  let description = [{
    Synchronizes two residencies. After completion, `dst` contents are
    **valid**. Does not create a new logical object and does not alias the
    same allocation. Optional `-> !sched.token` makes the copy a
    non-blocking event producer; the token means the destination is valid.
  }];
  let arguments = (ins
    Stor_BufferType:$src,
    Stor_BufferType:$dst,
    OptionalAttr<Comm_KindAttr>:$kind
  );
  let results = (outs Optional<Sched_TokenType>:$token);
  let assemblyFormat = [{
    $src `,` $dst attr-dict `:` qualified(type($src)) `,` qualified(type($dst))
    (`->` type($token)^)?
  }];
  let hasVerifier = 1;
}

def Comm_StreamOp : Comm_Op<"stream", [HasAsyncToken]> {
  let summary = "Asynchronous streaming transfer between storage spaces";
  let description = [{
    SSD-to-HBM (or DMA) streaming between residencies of the same logical
    object. Payload types must match; spaces must differ.
    Produces a generic `!sched.token` completion event: after the token
    is waited, `dst` contents are **valid**.

    Phase 2A blocking baseline lowers this to synchronous `memref.copy`.
    That is an approximation, not event-preserving comm lowering.
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
