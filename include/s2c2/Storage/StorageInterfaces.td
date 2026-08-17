//===- StorageInterfaces.td - S²C² Storage interfaces ----*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_STORAGE_INTERFACES
#define S2C2_STORAGE_INTERFACES

include "mlir/IR/OpBase.td"

def StorageResource : OpInterface<"StorageResource"> {
  let cppNamespace = "::mlir::s2c2::stor";
  let description = [{
    Ops that allocate or reference a placed storage resource.
  }];
  let methods = [
    InterfaceMethod<
      "Return the storage space of this resource.",
      "::mlir::s2c2::stor::Space",
      "getStorageSpace"
    >
  ];
}

#endif // S2C2_STORAGE_INTERFACES
