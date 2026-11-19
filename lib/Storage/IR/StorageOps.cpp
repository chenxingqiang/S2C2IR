//===- StorageOps.cpp - S2C2 Storage ops ------------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Storage/StorageOps.h"
#include "s2c2/Storage/StorageDialect.h"
#include "s2c2/DistributionCoverage.h"

#include "mlir/IR/OpImplementation.h"

#include "s2c2/Storage/StorageInterfaces.cpp.inc"

#define GET_OP_CLASSES
#include "s2c2/Storage/StorageOps.cpp.inc"

using namespace mlir;
using namespace mlir::s2c2::stor;

Value mlir::s2c2::stor::getLogicalObject(Value buffer) {
  Operation *def = buffer.getDefiningOp();
  if (!def)
    return {};
  if (auto materialize = dyn_cast<MaterializeOp>(def))
    return materialize.getObject();
  if (auto transfer = dyn_cast<TransferOp>(def))
    return getLogicalObject(transfer.getSource());
  return {};
}

ParseResult LocalizeOp::parse(OpAsmParser &parser, OperationState &result) {
  OpAsmParser::UnresolvedOperand global;
  OpAsmParser::UnresolvedOperand sharding;
  int64_t rank = 0;
  Type globalType;
  Type shardingType;
  Type localType;
  if (parser.parseOperand(global) || parser.parseKeyword("to") ||
      parser.parseOperand(sharding) || parser.parseKeyword("rank") ||
      parser.parseEqual() || parser.parseInteger(rank) ||
      parser.parseOptionalAttrDict(result.attributes) || parser.parseColon() ||
      parser.parseType(globalType) || parser.parseComma() ||
      parser.parseType(shardingType) || parser.parseArrow() ||
      parser.parseType(localType) ||
      parser.resolveOperand(global, globalType, result.operands) ||
      parser.resolveOperand(sharding, shardingType, result.operands))
    return failure();
  result.addAttribute("rank", parser.getBuilder().getI64IntegerAttr(rank));
  result.addTypes(localType);
  return success();
}

void LocalizeOp::print(OpAsmPrinter &p) {
  p << ' ' << getGlobal() << " to " << getSharding() << " rank = " << getRank();
  p.printOptionalAttrDict((*this)->getAttrs(), {"rank"});
  p << " : ";
  p.printType(getGlobal().getType());
  p << ", ";
  p.printType(getSharding().getType());
  p << " -> ";
  p.printType(getLocal().getType());
}

LogicalResult LocalizeOp::verify() {
  auto globalType = dyn_cast<RankedTensorType>(
      llvm::cast<ObjectType>(getGlobal().getType()).getPayloadType());
  if (!globalType)
    return emitOpError("local shape is not the shard tile");
  FailureOr<LocalShard> tile =
      localShardFor(getOperation(), getSharding(), globalType, getRank());
  if (failed(tile))
    return failure();
  auto got = dyn_cast<RankedTensorType>(
      llvm::cast<ObjectType>(getLocal().getType()).getPayloadType());
  auto expect = RankedTensorType::get(tile->shape, globalType.getElementType());
  if (got != expect)
    return emitOpError("local shape is not the shard tile");
  return success();
}

LogicalResult MaterializeOp::verify() {
  auto objTy = llvm::cast<ObjectType>(getObject().getType());
  auto bufTy = llvm::cast<BufferType>(getBuffer().getType());
  if (objTy.getPayloadType() != bufTy.getSourceType())
    return emitOpError("materialized buffer payload must match logical object");
  return success();
}

LogicalResult TransferOp::verify() {
  auto srcTy = llvm::cast<BufferType>(getSource().getType());
  auto dstTy = llvm::cast<BufferType>(getBuffer().getType());
  if (srcTy.getSourceType() != dstTy.getSourceType())
    return emitOpError(
        "transfer result payload must match the source buffer payload");
  return success();
}

LogicalResult PackOp::verify() {
  auto bufTy = llvm::cast<BufferType>(getBuffer().getType());
  if (getValue().getType() != bufTy.getSourceType())
    return emitOpError("packed tensor type must match buffer payload");
  return success();
}

LogicalResult UnpackOp::verify() {
  auto bufTy = llvm::cast<BufferType>(getBuffer().getType());
  if (getResult().getType() != bufTy.getSourceType())
    return emitOpError("unpacked tensor type must match buffer payload");
  return success();
}
