//===- S2C2Walk.cpp - Hamming-1 inhabitant of A (v0.4.9) --------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// First executable inhabitant of A = (N, S, Rst, Nxt, Acc):
//   N   = N_1
//   S   = StartFirst
//   Rst = StartUnused
//   Nxt = first(Best) on Frontier
// Does not rewrite IR, pick a unique M* as output, or redefine HB / Cost.
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Family.h"
#include "s2c2/S2C2Legality.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/S2C2Score3.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/raw_ostream.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2WALK
#include "s2c2/S2C2Passes.h.inc"

namespace {
struct Triple {
  StringRef sched;
  StringRef map;
  StringRef device;

  std::string key() const {
    return (Twine(sched) + "|" + map + "|" + device).str();
  }
};

static int indexOf(ArrayRef<StringRef> axis, StringRef v) {
  for (int i = 0, n = (int)axis.size(); i < n; ++i)
    if (axis[i] == v)
      return i;
  return -1;
}

/// F_0 product order: sched, then map, then device.
static bool earlier(const Triple &a, const Triple &b, ArrayRef<StringRef> schedF,
                    ArrayRef<StringRef> mapF, ArrayRef<StringRef> devF) {
  int as = indexOf(schedF, a.sched), bs = indexOf(schedF, b.sched);
  if (as != bs)
    return as < bs;
  int am = indexOf(mapF, a.map), bm = indexOf(mapF, b.map);
  if (am != bm)
    return am < bm;
  return indexOf(devF, a.device) < indexOf(devF, b.device);
}

struct S2C2Walk : impl::S2C2WalkBase<S2C2Walk> {
  using impl::S2C2WalkBase<S2C2Walk>::S2C2WalkBase;

  void runOnOperation() override {
    SmallVector<StringRef, 4> schedF, mapF, devF;
    Operation *mod = getOperation();
    if (failed(selectFamilyAxis(scheds, "walk", "sched", familyF0Scheds(),
                                schedF, mod)) ||
        failed(selectFamilyAxis(maps, "walk", "map", familyF0Maps(), mapF,
                                mod)) ||
        failed(selectFamilyAxis(devices, "walk", "device", familyF0Devices(),
                                devF, mod))) {
      signalPassFailure();
      return;
    }

    for (auto func : getOperation().getOps<func::FuncOp>()) {
      if (func.getBody().empty())
        continue;
      if (failed(walkFunc(func, schedF, mapF, devF))) {
        signalPassFailure();
        return;
      }
    }
  }

  LogicalResult walkFunc(func::FuncOp func, ArrayRef<StringRef> schedF,
                         ArrayRef<StringRef> mapF, ArrayRef<StringRef> devF) {
    SmallVector<Triple, 16> x;
    for (StringRef s : schedF)
      for (StringRef m : mapF)
        for (StringRef d : devF)
          if (isLegalRealization(func, s, m, d))
            x.push_back(Triple{s, m, d});
    if (x.empty()) {
      llvm::errs() << "s2c2-walk func=" << func.getName()
                   << " complete accepted=0\n";
      return success();
    }

    llvm::StringSet<> generated, checked, legalChecked, scored, accepted;
    llvm::StringMap<Score3> cache;
    llvm::StringMap<Score3> scoreOf;
    Triple current = x.front();
    if (failed(install(func, current, generated, checked, legalChecked, scored,
                       accepted, cache, scoreOf)))
      return failure();
    llvm::errs() << "s2c2-walk func=" << func.getName() << " start sched="
                 << current.sched << " map=" << current.map
                 << " device=" << current.device << "\n";

    while (accepted.size() < x.size()) {
      bool stepped = false;
      while (true) {
        SmallVector<Triple, 8> frontier;
        generateValidate(func, current, schedF, mapF, devF, generated, checked,
                         legalChecked, accepted, frontier);
        if (failed(scoreFrontier(func, frontier, scored, cache, scoreOf)))
          return failure();
        Triple nxt;
        if (!selectNext(frontier, scoreOf, schedF, mapF, devF, nxt))
          break;
        accepted.insert(nxt.key());
        current = nxt;
        stepped = true;
        llvm::errs() << "s2c2-walk func=" << func.getName() << " step sched="
                     << current.sched << " map=" << current.map
                     << " device=" << current.device
                     << " total=" << scoreOf.lookup(current.key()).total
                     << "\n";
      }
      if (accepted.size() >= x.size())
        break;
      llvm::errs() << "s2c2-walk func=" << func.getName()
                   << " localstop accepted=" << accepted.size() << "\n";
      Triple restart;
      bool found = false;
      for (const Triple &t : x) {
        if (!accepted.contains(t.key())) {
          restart = t;
          found = true;
          break;
        }
      }
      if (!found)
        break;
      if (failed(install(func, restart, generated, checked, legalChecked,
                         scored, accepted, cache, scoreOf)))
        return failure();
      current = restart;
      llvm::errs() << "s2c2-walk func=" << func.getName() << " restart sched="
                   << current.sched << " map=" << current.map
                   << " device=" << current.device << "\n";
      (void)stepped;
    }

    llvm::errs() << "s2c2-walk func=" << func.getName()
                 << " complete accepted=" << accepted.size() << "\n";

    int64_t best = -1;
    SmallVector<Triple, 8> argmin;
    for (const Triple &t : x) {
      if (!accepted.contains(t.key()))
        continue;
      int64_t tot = scoreOf.lookup(t.key()).total;
      if (best < 0 || tot < best) {
        best = tot;
        argmin.clear();
        argmin.push_back(t);
      } else if (tot == best) {
        argmin.push_back(t);
      }
    }
    llvm::errs() << "s2c2-walk func=" << func.getName()
                 << " argmin count=" << argmin.size() << "\n";
    for (const Triple &t : argmin)
      llvm::errs() << "s2c2-walk func=" << func.getName()
                   << " argmin sched=" << t.sched << " map=" << t.map
                   << " device=" << t.device << " total=" << best << "\n";
    return success();
  }

  LogicalResult install(func::FuncOp func, const Triple &m,
                        llvm::StringSet<> &generated, llvm::StringSet<> &checked,
                        llvm::StringSet<> &legalChecked,
                        llvm::StringSet<> &scored, llvm::StringSet<> &accepted,
                        llvm::StringMap<Score3> &cache,
                        llvm::StringMap<Score3> &scoreOf) {
    std::string k = m.key();
    generated.insert(k);
    checked.insert(k);
    legalChecked.insert(k);
    if (!scoreOf.count(k)) {
      Score3 s;
      if (!cache.count(m.device)) {
        if (failed(computeScore3(func, m.device, s)))
          return failure();
        cache[m.device] = s;
      } else {
        s = cache.lookup(m.device);
      }
      scoreOf[k] = s;
      scored.insert(k);
    }
    accepted.insert(k);
    return success();
  }

  void generateValidate(func::FuncOp func, const Triple &cur,
                        ArrayRef<StringRef> schedF, ArrayRef<StringRef> mapF,
                        ArrayRef<StringRef> devF, llvm::StringSet<> &generated,
                        llvm::StringSet<> &checked,
                        llvm::StringSet<> &legalChecked,
                        const llvm::StringSet<> &accepted,
                        SmallVectorImpl<Triple> &frontier) {
    SmallVector<Triple, 8> neigh;
    for (StringRef s : schedF)
      if (s != cur.sched)
        neigh.push_back(Triple{s, cur.map, cur.device});
    for (StringRef m : mapF)
      if (m != cur.map)
        neigh.push_back(Triple{cur.sched, m, cur.device});
    for (StringRef d : devF)
      if (d != cur.device)
        neigh.push_back(Triple{cur.sched, cur.map, d});

    for (const Triple &n : neigh) {
      std::string k = n.key();
      generated.insert(k);
      if (!checked.contains(k)) {
        checked.insert(k);
        if (isLegalRealization(func, n.sched, n.map, n.device))
          legalChecked.insert(k);
      }
      if (legalChecked.contains(k) && !accepted.contains(k))
        frontier.push_back(n);
    }
  }

  LogicalResult scoreFrontier(func::FuncOp func, ArrayRef<Triple> frontier,
                              llvm::StringSet<> &scored,
                              llvm::StringMap<Score3> &cache,
                              llvm::StringMap<Score3> &scoreOf) {
    for (const Triple &n : frontier) {
      std::string k = n.key();
      if (scored.contains(k))
        continue;
      Score3 s;
      if (!cache.count(n.device)) {
        if (failed(computeScore3(func, n.device, s)))
          return failure();
        cache[n.device] = s;
      } else {
        s = cache.lookup(n.device);
      }
      scoreOf[k] = s;
      scored.insert(k);
    }
    return success();
  }

  bool selectNext(ArrayRef<Triple> frontier,
                  const llvm::StringMap<Score3> &scoreOf,
                  ArrayRef<StringRef> schedF, ArrayRef<StringRef> mapF,
                  ArrayRef<StringRef> devF, Triple &out) {
    if (frontier.empty())
      return false;
    int64_t best = scoreOf.lookup(frontier.front().key()).total;
    for (const Triple &n : frontier) {
      int64_t t = scoreOf.lookup(n.key()).total;
      if (t < best)
        best = t;
    }
    bool have = false;
    for (const Triple &n : frontier) {
      if (scoreOf.lookup(n.key()).total != best)
        continue;
      if (!have || earlier(n, out, schedF, mapF, devF)) {
        out = n;
        have = true;
      }
    }
    return have;
  }
};
} // namespace
} // namespace mlir::s2c2
