//===- ComputeOps.td - S²C² Compute operations -----------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_COMPUTE_OPS
#define S2C2_COMPUTE_OPS

include "s2c2/Compute/ComputeDialect.td"
include "mlir/IR/EnumAttr.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Comp_Unit : I32EnumAttr<"Unit", "compute unit", [
    I32EnumAttrCase<"CPU", 0, "cpu">,
    I32EnumAttrCase<"GPU", 1, "gpu">,
    I32EnumAttrCase<"NPU", 2, "npu">,
    I32EnumAttrCase<"CIM", 3, "cim">
  ]> {
  let cppNamespace = "::mlir::s2c2::comp";
  let genSpecializedAttr = 0;
}
def Comp_UnitAttr : EnumAttr<Compute_Dialect, Comp_Unit, "unit"> {
  let assemblyFormat = "`<` $value `>`";
}

def Comp_Activation : I32EnumAttr<"Activation", "gated-MLP activation", [
    I32EnumAttrCase<"SILU", 0, "silu">,
    I32EnumAttrCase<"GELU", 1, "gelu">,
    I32EnumAttrCase<"RELU", 2, "relu">
  ]> {
  let cppNamespace = "::mlir::s2c2::comp";
  let genSpecializedAttr = 0;
}
def Comp_ActivationAttr : EnumAttr<Compute_Dialect, Comp_Activation, "activation"> {
  let assemblyFormat = "`<` $value `>`";
}

def Comp_ElemwiseKind : I32EnumAttr<"ElemwiseKind", "elementwise kind", [
    I32EnumAttrCase<"ADD", 0, "add">,
    I32EnumAttrCase<"MUL", 1, "mul">,
    I32EnumAttrCase<"SILU", 2, "silu">,
    I32EnumAttrCase<"GELU", 3, "gelu">
  ]> {
  let cppNamespace = "::mlir::s2c2::comp";
  let genSpecializedAttr = 0;
}
def Comp_ElemwiseKindAttr : EnumAttr<Compute_Dialect, Comp_ElemwiseKind, "elemwise"> {
  let assemblyFormat = "`<` $value `>`";
}

def Comp_MatmulOp : Comp_Op<"matmul", [Pure]> {
  let summary = "Matrix multiply";
  let arguments = (ins
    AnyRankedTensor:$lhs,
    AnyRankedTensor:$rhs,
    OptionalAttr<Comp_UnitAttr>:$unit
  );
  let results = (outs AnyRankedTensor:$result);
  let assemblyFormat = [{
    $lhs `,` $rhs attr-dict `:` type($lhs) `,` type($rhs) `->` type($result)
  }];
}

def Comp_ElemwiseOp : Comp_Op<"elemwise", [Pure]> {
  let summary = "Elementwise compute or activation";
  let arguments = (ins
    Variadic<AnyRankedTensor>:$inputs,
    Comp_ElemwiseKindAttr:$kind,
    OptionalAttr<Comp_UnitAttr>:$unit
  );
  let results = (outs AnyRankedTensor:$result);
  let assemblyFormat = [{
    $inputs attr-dict `:` type($inputs) `->` type($result)
  }];
}

def Comp_GatedMLPOp : Comp_Op<"gated_mlp", [Pure]> {
  let summary = "Fused gated MLP: silu(x@Wg)*(x@Wu) @ Wd";
  let description = [{
    First-class Gated MLP so storage and schedule decisions can attach to
    the fused kernel rather than a lowered matmul chain.

    Example:

    ```mlir
    %y = comp.gated_mlp %x, %wg, %wu, %wd
      {activation = #comp.activation<silu>, unit = #comp.unit<npu>}
      : tensor<1x4096xf16>, tensor<4096x11008xf16>,
        tensor<4096x11008xf16>, tensor<11008x4096xf16> -> tensor<1x4096xf16>
    ```
  }];
  let arguments = (ins
    AnyRankedTensor:$input,
    AnyRankedTensor:$gateWeight,
    AnyRankedTensor:$upWeight,
    AnyRankedTensor:$downWeight,
    OptionalAttr<Comp_ActivationAttr>:$activation,
    OptionalAttr<Comp_UnitAttr>:$unit
  );
  let results = (outs AnyRankedTensor:$output);
  let assemblyFormat = [{
    $input `,` $gateWeight `,` $upWeight `,` $downWeight attr-dict `:`
    type($input) `,` type($gateWeight) `,` type($upWeight) `,`
    type($downWeight) `->` type($output)
  }];
}

#endif // S2C2_COMPUTE_OPS
