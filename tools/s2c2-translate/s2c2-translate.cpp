//===- s2c2-translate.cpp - S2C2 translation driver -------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/InitAllTranslations.h"
#include "mlir/Tools/mlir-translate/MlirTranslateMain.h"

int main(int argc, char **argv) {
  mlir::registerAllTranslations();

  mlir::TranslateFromMLIRRegistration registration(
      "s2c2-to-debug", "print S2C2 module as MLIR (identity stub)",
      [](mlir::Operation *op, llvm::raw_ostream &output) {
        op->print(output);
        output << '\n';
        return llvm::LogicalResult::success();
      },
      [](mlir::DialectRegistry &registry) {
        registry.insert<mlir::s2c2::stor::StorageDialect,
                        mlir::s2c2::comp::ComputeDialect,
                        mlir::s2c2::comm::CommDialect,
                        mlir::s2c2::sched::ScheduleDialect>();
      });

  return failed(
      mlir::mlirTranslateMain(argc, argv, "S2C2 MLIR translation tool"));
}
