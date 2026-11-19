//===- DistOps.td - S²C² distribution operations ---------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_DIST_OPS
#define S2C2_DIST_OPS

include "s2c2/Dist/DistTypes.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Dist_GlobalOp : Dist_Op<"global", []> {
  let summary = "Name a global tensor";
  let description = [{
    Introduces the SSA identity of a global tensor. Shards of this value
    are created with `dist.shard`. Two `dist.global` operations are
    different tensors even when their types match, and are not folded
    together.

    Example:

    ```mlir
    %g = dist.global : !dist.global<tensor<4xf32>>
    ```
  }];
  let arguments = (ins);
  let results = (outs Dist_GlobalType:$global);
  let assemblyFormat = "attr-dict `:` qualified(type($global))";
}

def Dist_ShardOp : Dist_Op<"shard", []> {
  let summary = "Cut one shard out of a global tensor";
  let description = [{
    Associates `global` with one local tensor. The result type carries the
    placement, partition axis, offset, and tile shape. Two `dist.shard`
    operations are different shards even when their types match, including
    two full replicas of one global tensor. They are not folded together.

    A sharded shard must stay inside the global tensor. Off the partition
    axis it must cover the whole extent. A replicated shard must have
    `axis = -1`, a zero offset, and a tile shape equal to the global shape.
    Overlap and missing coverage are checked when shards are grouped by
    `dist.distribution`.
  }];
  let arguments = (ins Dist_GlobalType:$global);
  let results = (outs Dist_ShardType:$shard);
  let assemblyFormat = [{
    $global attr-dict `:` qualified(type($global)) `->` qualified(type($shard))
  }];
  let hasVerifier = 1;
}

def Dist_LocalOp : Dist_Op<"local", [Pure]> {
  let summary = "Associate a shard with its local tensor";
  let description = [{
    Projects a shard to the local tensor named by that shard's type. The
    local type must be the shard's local tensor, so the use-def chain is
    global (`dist.shard`'s operand) to shard to local.
  }];
  let arguments = (ins Dist_ShardType:$shard);
  let results = (outs Dist_LocalType:$local);
  let assemblyFormat = [{
    $shard attr-dict `:` qualified(type($shard)) `->` qualified(type($local))
  }];
  let hasVerifier = 1;
}

def Dist_DistributionOp : Dist_Op<"distribution", []> {
  let summary = "Group the shards of one global tensor";
  let description = [{
    Every shard operand must be a `dist.shard` of `global`, and the same
    SSA value cannot be listed twice. The result placement and partition
    axis must match those shards.

    For `sharded`, ranges are half-open intervals on the partition axis.
    After sorting those intervals, the verifier reports the first failure
    in this order:

    * a shard range that leaves the global tensor is out of bounds;
    * two intervals that intersect overlap;
    * a union other than the whole axis does not cover the global tensor.

    Touching endpoints do not overlap: `[0, 2)` and `[2, 4)` cover a
    length-4 axis. For `replicated`, distinct shards may be full copies of
    the same index space. That is not overlap and is not a coverage gap.
    Naming one replicated shard twice is still one shard.
  }];
  let arguments = (ins
    Dist_GlobalType:$global,
    Variadic<Dist_ShardType>:$shards
  );
  let results = (outs Dist_DistributionType:$distribution);
  let assemblyFormat = [{
    $global `shards` `(` $shards `)` attr-dict `:`
        functional-type(operands, results)
  }];
  let hasVerifier = 1;
}

def Dist_MeshOp : Dist_Op<"mesh", []> {
  let summary = "Name a device mesh";
  let description = [{
    A device mesh is a grid of ranks with one name per axis. Coordinates
    on this mesh are device identity. A storage space is not a mesh.
    Two `dist.mesh` operations stay distinct even when their types match.
  }];
  let arguments = (ins);
  let results = (outs Dist_MeshType:$mesh);
  let assemblyFormat = "attr-dict `:` qualified(type($mesh))";
}

def Dist_DeviceOp : Dist_Op<"device", []> {
  let summary = "Name one rank on a device mesh";
  let description = [{
    The result type carries the mesh shape, axis names, coordinate, and
    rank. The rank is the row-major index of that coordinate. Two devices
    differ when their coordinates differ.
  }];
  let arguments = (ins Dist_MeshType:$mesh);
  let results = (outs Dist_DeviceType:$device);
  let assemblyFormat = [{
    $mesh attr-dict `:` qualified(type($mesh)) `->` qualified(type($device))
  }];
  let hasVerifier = 1;
}

def Dist_TopologyOp : Dist_Op<"topology", []> {
  let summary = "Name a hardware topology";
  let description = [{
    `line` is one axis. `grid` is two axes. The shape is the hardware
    arrangement, separate from the logical shard distribution. Two
    topologies stay distinct even when their types match.
  }];
  let arguments = (ins);
  let results = (outs Dist_TopologyType:$topology);
  let assemblyFormat = "attr-dict `:` qualified(type($topology))";
}

def Dist_PlaceOp : Dist_Op<"place", [SameVariadicOperandSize]> {
  let summary = "Map one logical distribution onto one hardware topology";
  let description = [{
    Logical placement stays on `dist.distribution`: the same shards and
    the same coverage. This op checks that those shards land on device
    coordinates of `mesh`, and that the mesh shape is the hardware
    topology. It does not change shard offsets or tiles.

    A storage residency is not a device. Each shard of the distribution
    is named once. Each device coordinate is used once.
  }];
  let arguments = (ins
    Dist_DistributionType:$distribution,
    Dist_TopologyType:$topology,
    Dist_MeshType:$mesh,
    Variadic<AnyType>:$devices,
    Variadic<Dist_ShardType>:$shards
  );
  let results = (outs Dist_MappingType:$mapping);
  let assemblyFormat = [{
    $distribution `,` $topology `,` $mesh
      `devices` `(` $devices `)` `shards` `(` $shards `)` attr-dict
      `:` functional-type(operands, results)
  }];
  let hasVerifier = 1;
}

#endif // S2C2_DIST_OPS
