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

#include "llvm/ADT/StringRef.h"

#include <string>
#include <vector>

static bool argvHas(int argc, char **argv, llvm::StringRef key) {
  std::string eq = (key + "=").str();
  for (int i = 1; i < argc; ++i) {
    llvm::StringRef a(argv[i]);
    if (a == key || a.starts_with(eq))
      return true;
  }
  return false;
}

int main(int argc, char **argv) {
  mlir::registerAllPasses();
  mlir::s2c2::registerPasses();

  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  registry.insert<mlir::s2c2::stor::StorageDialect,
                  mlir::s2c2::comp::ComputeDialect,
                  mlir::s2c2::comm::CommDialect,
                  mlir::s2c2::sched::ScheduleDialect>();

  // --query-capacity-plan is a consumer API: inject the query pass
  // only. Do not pull in evidence-bounded-schedule. --capacity alone
  // still injects the schedule pass (frozen 6C-B/C diagnostics).
  bool wantsQuery = argvHas(argc, argv, "--query-capacity-plan") ||
                    argvHas(argc, argv, "--s2c2-capacity-plan-query") ||
                    argvHas(argc, argv, "--capacity-policy") ||
                    argvHas(argc, argv, "--measured-capacity-table");
  bool wantsScheduleExplicit =
      argvHas(argc, argv, "--schedule-policy") ||
      argvHas(argc, argv, "--explain") ||
      argvHas(argc, argv, "--measured-cost-table");
  bool wantsCapacity = argvHas(argc, argv, "--capacity") ||
                       argvHas(argc, argv, "--capacity-spec") ||
                       argvHas(argc, argv, "--dump-capacity-plan");
  bool wantsSchedule =
      wantsScheduleExplicit || (wantsCapacity && !wantsQuery);
  bool hasSchedulePass =
      argvHas(argc, argv, "--s2c2-evidence-bounded-schedule");
  bool hasQueryPass = argvHas(argc, argv, "--s2c2-capacity-plan-query");

  std::vector<std::string> inject;
  if (wantsQuery && !hasQueryPass)
    inject.emplace_back("--s2c2-capacity-plan-query");
  if (wantsSchedule && !hasSchedulePass)
    inject.emplace_back("--s2c2-evidence-bounded-schedule");
  if (!inject.empty()) {
    std::vector<std::string> storage;
    storage.emplace_back(argv[0]);
    storage.insert(storage.end(), inject.begin(), inject.end());
    for (int i = 1; i < argc; ++i)
      storage.emplace_back(argv[i]);
    std::vector<char *> ptrs;
    ptrs.reserve(storage.size());
    for (std::string &s : storage)
      ptrs.push_back(s.data());
    return mlir::asMainReturnCode(mlir::MlirOptMain(
        static_cast<int>(ptrs.size()), ptrs.data(),
        "S2C2 optimizer driver\n", registry));
  }

  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "S2C2 optimizer driver\n", registry));
}
