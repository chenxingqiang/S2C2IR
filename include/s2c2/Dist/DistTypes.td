//===- DistTypes.td - S²C² distribution types ------------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_DIST_TYPES
#define S2C2_DIST_TYPES

include "s2c2/Dist/DistDialect.td"
include "s2c2/Dist/DistEnums.td"
include "mlir/IR/AttrTypeBase.td"

def Dist_GlobalType : Dist_Type<"Global", "global"> {
  let summary = "Global tensor being partitioned";
  let description = [{
    `!dist.global<tensor<...>>` is the whole model tensor. Instance identity
    is the SSA value produced by `dist.global`. Shard and distribution ops
    name that value; they do not copy it.
  }];
  let parameters = (ins "Type":$globalType);
  let assemblyFormat = "`<` $globalType `>`";
  let genVerifyDecl = 1;
}

def Dist_LocalType : Dist_Type<"Local", "local"> {
  let summary = "Local tensor of one shard";
  let description = [{
    `!dist.local<tensor<...>>` is the tensor a shard holds. For a sharded
    placement its shape is the tile shape. For a replicated placement its
    shape is the global shape. `dist.local` ties this type to a shard value.
  }];
  let parameters = (ins "Type":$localType);
  let assemblyFormat = "`<` $localType `>`";
  let genVerifyDecl = 1;
}

def Dist_ShardType : Dist_Type<"Shard", "shard"> {
  let summary = "One shard: local tensor plus its range in the global tensor";
  let description = [{
    `!dist.shard<local, placement, axis = N, offset = ..., tile = ...>`
    records how a local tensor sits inside a global tensor.

    `placement` is `replicated` or `sharded`. `axis` is the partition axis.
    A replicated shard has no partition axis and stores `axis = -1`.
    `offset` is the global index where the tile starts. `tile` is the tile
    shape and must equal the local tensor shape. Both arrays have one entry
    per global dimension. Ranges are half-open: dimension `d` covers
    `[offset[d], offset[d] + tile[d])`.
  }];
  let parameters = (ins
    "Type":$localType,
    "::mlir::s2c2::dist::Placement":$placement,
    "int64_t":$axis,
    "DenseI64ArrayAttr":$offset,
    "DenseI64ArrayAttr":$tileShape
  );
  let assemblyFormat = [{
    `<` $localType `,` $placement `,` `axis` `=` $axis `,`
        `offset` `=` $offset `,` `tile` `=` $tileShape `>`
  }];
  let genVerifyDecl = 1;
}

def Dist_DistributionType : Dist_Type<"Distribution", "distribution"> {
  let summary = "Placement of one global tensor";
  let description = [{
    `!dist.distribution<global, placement, axis = N>` is the placement of
    one global tensor. `sharded` uses partition axis `N`. `replicated`
    stores `axis = -1` and does not partition.

    Coverage, overlap, and bounds of the member shards are checked by
    `dist.distribution`, not by this type alone.
  }];
  let parameters = (ins
    "Type":$globalType,
    "::mlir::s2c2::dist::Placement":$placement,
    "int64_t":$axis
  );
  let assemblyFormat = "`<` $globalType `,` $placement `,` `axis` `=` $axis `>`";
  let genVerifyDecl = 1;
}

#endif // S2C2_DIST_TYPES
