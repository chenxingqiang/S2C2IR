//===- s2c2-opt.cpp - S2C2 optimizer driver ---------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2.h"

#include "mlir/IR/MLIRContext.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

int main(int argc, char **argv) {
  mlir::registerAllPasses();
  mlir::s2c2::registerPasses();

  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  registry.insert<mlir::s2c2::stor::StorageDialect,
                  mlir::s2c2::comp::ComputeDialect,
                  mlir::s2c2::comm::CommDialect,
                  mlir::s2c2::sched::ScheduleDialect>();

  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "S2C2 optimizer driver\n", registry));
}
