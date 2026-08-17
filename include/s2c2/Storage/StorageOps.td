//===- StorageOps.td - S²C² Storage operations -----------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_STORAGE_OPS
#define S2C2_STORAGE_OPS

include "s2c2/Storage/StorageTypes.td"
include "s2c2/Storage/StorageInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Stor_AllocOp : Stor_Op<"alloc", [
    MemoryEffects<[MemAlloc]>,
    StorageResource
  ]> {
  let summary = "Allocate a buffer in a storage space";
  let description = [{
    Allocates a logical buffer. The storage space is part of the result type.

    Example:

    ```mlir
    %buf = stor.alloc : !stor.buffer<tensor<2x4xf32>, hbm>
    ```
  }];
  let arguments = (ins);
  let results = (outs Stor_BufferType:$buffer);
  let assemblyFormat = "attr-dict `:` qualified(type($buffer))";
  let extraClassDeclaration = [{
    ::mlir::s2c2::stor::Space getStorageSpace() {
      return ::llvm::cast<BufferType>(getBuffer().getType()).getSpace();
    }
  }];
}

def Stor_DeallocOp : Stor_Op<"dealloc", [MemoryEffects<[MemFree]>]> {
  let summary = "Deallocate a storage buffer";
  let arguments = (ins Stor_BufferType:$buffer);
  let assemblyFormat = "$buffer attr-dict `:` qualified(type($buffer))";
}

def Stor_PackOp : Stor_Op<"pack", []> {
  let summary = "Write a tensor into a storage buffer";
  let arguments = (ins AnyRankedTensor:$value, Stor_BufferType:$buffer);
  let assemblyFormat = [{
    $value `into` $buffer attr-dict `:` type($value) `,` qualified(type($buffer))
  }];
  let hasVerifier = 1;
}

def Stor_UnpackOp : Stor_Op<"unpack", [Pure]> {
  let summary = "Read a tensor from a storage buffer";
  let arguments = (ins Stor_BufferType:$buffer);
  let results = (outs AnyRankedTensor:$result);
  let assemblyFormat = [{
    $buffer attr-dict `:` qualified(type($buffer)) `->` type($result)
  }];
  let hasVerifier = 1;
}

#endif // S2C2_STORAGE_OPS
