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

def Stor_ObjectOp : Stor_Op<"object", [Pure]> {
  let summary = "Create a logical data object (identity, no allocation)";
  let description = [{
    Introduces a logical identity. Residencies are created separately with
    `stor.materialize` or `stor.transfer`.

    Example:

    ```mlir
    %w = stor.object : !stor.object<tensor<2x4xf32>>
    ```
  }];
  let arguments = (ins);
  let results = (outs Stor_ObjectType:$object);
  let assemblyFormat = "attr-dict `:` qualified(type($object))";
}

def Stor_MaterializeOp : Stor_Op<"materialize", [
    MemoryEffects<[MemAlloc]>,
    StorageResource
  ]> {
  let summary = "Allocate a residency of a logical object";
  let description = [{
    Multiple materializations of the same object are independent replicas
    (SSD vs HBM, or two HBM slots for double buffering).

    Example:

    ```mlir
    %w_hbm = stor.materialize %w
      : !stor.object<tensor<2x4xf32>> -> !stor.buffer<tensor<2x4xf32>, hbm>
    ```
  }];
  let arguments = (ins Stor_ObjectType:$object);
  let results = (outs Stor_BufferType:$buffer);
  let assemblyFormat = [{
    $object attr-dict `:` qualified(type($object)) `->` qualified(type($buffer))
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::s2c2::stor::Space getStorageSpace() {
      return ::llvm::cast<BufferType>(getBuffer().getType()).getSpace();
    }
  }];
}

def Stor_TransferOp : Stor_Op<"transfer", [
    MemoryEffects<[MemAlloc]>,
    StorageResource
  ]> {
  let summary = "Create a new residency of the same object and copy payload";
  let description = [{
    Destination space comes from the result type. Same-space transfer is
    allowed (double buffering). Does not create a new logical object.
  }];
  let arguments = (ins Stor_BufferType:$source);
  let results = (outs Stor_BufferType:$buffer);
  let assemblyFormat = [{
    $source attr-dict `:` qualified(type($source)) `->` qualified(type($buffer))
  }];
  let hasVerifier = 1;
  let extraClassDeclaration = [{
    ::mlir::s2c2::stor::Space getStorageSpace() {
      return ::llvm::cast<BufferType>(getBuffer().getType()).getSpace();
    }
  }];
}

def Stor_AllocOp : Stor_Op<"alloc", [
    MemoryEffects<[MemAlloc]>,
    StorageResource
  ]> {
  let summary = "Allocate an anonymous residency (no logical object)";
  let description = [{
    Scratch / legacy allocation. The result has no `!stor.object` identity,
    so it cannot participate in object-level alias analysis.

    Prefer `stor.object` + `stor.materialize` for data that has replicas.

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
