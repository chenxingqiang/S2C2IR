//===- TargetSpaceMap.h - Logical space to memref mapping -------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_TARGETSPACEMAP_H
#define S2C2_TARGETSPACEMAP_H

#include "s2c2/Storage/StorageTypes.h"
#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/ADT/Twine.h"

#include <array>
#include <cassert>
#include <optional>

namespace mlir {
namespace s2c2 {

/// Maps logical `stor::Space` values to integer memref memory spaces.
/// Enum discriminants are *not* a hardware ABI; this table is.
class TargetSpaceMap {
public:
  static constexpr unsigned kNumSpaces = 7;

  static TargetSpaceMap getDefault() {
    TargetSpaceMap map;
    map.ids = {0, 1, 2, 3, 4, 5, 6};
    return map;
  }

  int64_t lookup(stor::Space space) const {
    unsigned idx = static_cast<unsigned>(space);
    assert(idx < kNumSpaces && "unknown storage space");
    return ids[idx];
  }

  /// Apply comma-separated `name=int` overrides (e.g. `hbm=9,ssd=100`).
  /// Unspecified names keep their current value.
  template <typename EmitError>
  LogicalResult applyOverrides(StringRef spec, EmitError emitError) {
    spec = spec.trim();
    while (!spec.empty()) {
      auto [pair, rest] = spec.split(',');
      spec = rest;
      auto [name, value] = pair.split('=');
      name = name.trim();
      value = value.trim();
      std::optional<stor::Space> space = parseSpaceName(name);
      if (!space)
        return emitError() << "unknown logical storage space '" << name << "'";
      int64_t id = 0;
      if (value.getAsInteger(10, id))
        return emitError() << "invalid memory space id '" << value << "'";
      ids[static_cast<unsigned>(*space)] = id;
    }
    return success();
  }

private:
  std::array<int64_t, kNumSpaces> ids{};

  static std::optional<stor::Space> parseSpaceName(StringRef name) {
    return StringSwitch<std::optional<stor::Space>>(name)
        .Case("register", stor::Space::Register)
        .Case("sram", stor::Space::SRAM)
        .Case("dram", stor::Space::DRAM)
        .Case("hbm", stor::Space::HBM)
        .Case("ssd", stor::Space::SSD)
        .Case("cim", stor::Space::CIM)
        .Case("host", stor::Space::Host)
        .Default(std::nullopt);
  }
};

} // namespace s2c2
} // namespace mlir

#endif // S2C2_TARGETSPACEMAP_H
