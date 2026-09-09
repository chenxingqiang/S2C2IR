#!/usr/bin/env python3
"""Phase 6C Capacity-aware Residency (diagnostics frozen).

Host witness for F_capacity. Compiler diagnostics live in
s2c2-opt --capacity (tile-count occupancy). Does not rank,
rewrite, or touch cost-v04 / #69 / Evidence DB identity /
F(program). IR discovery is not alias analysis.
Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SCHEMA = "s2c2.capacity.v1"
RESTORE_LEGAL = "TRANSFER,REMATERIALIZE"

SPEC_FIELDS = (
    "schema",
    "workload_class",
    "space",
    "capacity_tiles",
    "residencies",
    "note",
)

RES_FIELDS = (
    "id",
    "object",
    "space",
    "size",
    "live",
    "producer",
    "consumer",
    "reuse_distance",
)


def print_contract() -> int:
    print("storage-capacity compiler-driven=yes")
    print("action KEEP|EVICT|REMATERIALIZE")
    print("restore-legal TRANSFER|REMATERIALIZE")
    print("note f-capacity-ne-f-program")
    print("note keep-ne-keep-residency")
    print("note capacity-exceeded-ne-must-evict")
    print("note evict-ne-rewrite")
    print("note transfer-existing-realization")
    print("note first-conflict-only")
    print("note single-evict-or-truncated")
    print("note restore-unspecified")
    print("note selection-ne-legality")
    print("note selection-ne-rewrite-license")
    print("note rewrite=no")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note evidence-db-identity-frozen")
    print("note five-e-not-opened")
    print("note measured-capacity-v1-not-opened")
    print("note not-new-capability-grid")
    print("note not-hardware-campaign")
    print("note stable-baseline")
    print("note six-c-design-this-cut")
    print("note six-c-diagnostics-frozen")
    print("note compiler-emits-f-capacity")
    print("note compiler-ne-rewrite")
    print("note tile-count-occupancy")
    print("note ir-discovery-ne-alias-analysis")
    print("note do-not-filecheck-microseconds")
    print("cost=unchanged")
    return 0


def _tile_key(obj: str) -> str:
    if obj.startswith("tile") and obj[4:].isdigit():
        return obj[4:]
    return obj


def _load_spec(path: Path) -> dict[str, Any]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        obj = json.loads(line)
        if isinstance(obj, dict):
            rows.append(obj)
    if len(rows) != 1:
        raise ValueError("capacity spec must be exactly one JSONL row")
    spec = rows[0]
    if spec.get("schema") != SCHEMA:
        raise ValueError("bad schema")
    extra = sorted(set(spec) - set(SPEC_FIELDS))
    if extra:
        raise ValueError(f"extra keys {extra}")
    missing = [k for k in SPEC_FIELDS if k not in spec]
    if missing:
        raise ValueError(f"missing keys {missing}")
    residencies = spec["residencies"]
    if not isinstance(residencies, list) or not residencies:
        raise ValueError("residencies required")
    for rec in residencies:
        if not isinstance(rec, dict):
            raise ValueError("residency must be an object")
        extra_r = sorted(set(rec) - set(RES_FIELDS))
        if extra_r:
            raise ValueError(f"residency extra keys {extra_r}")
        missing_r = [k for k in RES_FIELDS if k not in rec]
        if missing_r:
            raise ValueError(f"residency missing keys {missing_r}")
        live = rec["live"]
        if (
            not isinstance(live, list)
            or len(live) != 2
            or int(live[0]) >= int(live[1])
        ):
            raise ValueError("live interval must be [start, end)")
        if rec.get("space") != spec["space"]:
            raise ValueError("residency space must match constrained space")
        if int(rec["size"]) <= 0:
            raise ValueError("size must be positive")
    try:
        cap = int(spec["capacity_tiles"])
    except (TypeError, ValueError) as exc:
        raise ValueError("capacity_tiles must be int") from exc
    if cap <= 0:
        raise ValueError("capacity_tiles must be positive")
    return spec


def _live_at(residencies: list[dict[str, Any]], t: int) -> list[dict[str, Any]]:
    out = []
    for rec in residencies:
        start, end = int(rec["live"][0]), int(rec["live"][1])
        if start <= t < end:
            out.append(rec)
    return out


def _live_sum(live: list[dict[str, Any]]) -> int:
    return sum(int(r["size"]) for r in live)


def _object_id(rec: dict[str, Any]) -> str:
    return _tile_key(str(rec["object"]))


def analyze_capacity(path: Path) -> int:
    try:
        spec = _load_spec(path)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"record_capacity: {exc}", file=sys.stderr)
        return 4
    residencies = spec["residencies"]
    cap = int(spec["capacity_tiles"])
    times = sorted({int(r["live"][0]) for r in residencies})
    peak = 0
    t_star: int | None = None
    live_star: list[dict[str, Any]] = []
    for t in times:
        live = _live_at(residencies, t)
        occ = _live_sum(live)
        if occ > peak:
            peak = occ
        if occ > cap and t_star is None:
            t_star = t
            live_star = live
    conflict = t_star is not None
    print("storage-capacity query=f-capacity")
    print(f"storage-capacity space={spec['space']} capacity={cap} peak-live={peak}")
    print(f"storage-capacity capacity-conflict={'yes' if conflict else 'no'}")
    candidates: list[tuple[str, list[str], list[str]]] = []
    truncated = False
    if not conflict:
        keep = [_object_id(r) for r in sorted(residencies, key=_object_id)]
        candidates.append(("KEEP", keep, []))
    else:
        occ = _live_sum(live_star)
        incoming = max(live_star, key=lambda r: (int(r["live"][0]), _object_id(r)))
        order = [incoming] + sorted(
            [r for r in live_star if r is not incoming],
            key=_object_id,
        )
        for rec in order:
            if occ - int(rec["size"]) > cap:
                truncated = True
                candidates = []
                break
            evict = [_object_id(rec)]
            keep = sorted(_object_id(r) for r in live_star if r is not rec)
            candidates.append(("EVICT", keep, evict))
    if truncated:
        print("storage-capacity enumerated=no truncated=yes legal=not-enumerated")
        print("storage-capacity candidate-count=0")
    else:
        print(
            "storage-capacity enumerated=yes truncated=no "
            f"legal={len(candidates)}"
        )
        print(f"storage-capacity candidate-count={len(candidates)}")
        for i, (action, keep, evict) in enumerate(candidates):
            keep_s = ",".join(keep)
            if evict:
                evict_s = ",".join(evict)
                print(
                    f"storage-capacity candidate #{i} keep={keep_s} "
                    f"evict={evict_s} action={action} "
                    f"restore-legal={RESTORE_LEGAL} restore=unspecified"
                )
            else:
                print(
                    f"storage-capacity candidate #{i} keep={keep_s} "
                    f"action={action} restore=unspecified"
                )
    print("storage-capacity rewrite=no")
    print("storage-capacity note f-capacity-ne-f-program")
    print("storage-capacity note capacity-exceeded-ne-must-evict")
    print("storage-capacity note evict-ne-rewrite")
    print("storage-capacity note selection-ne-rewrite-license")
    print("storage-capacity note measured-capacity-v1-not-opened")
    print("storage-capacity note six-c-design-this-cut")
    print("storage-capacity note six-c-diagnostics-frozen")
    print("storage-capacity note tile-count-occupancy")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Capacity F (Phase 6C design)")
    p.add_argument("--print-storage-capacity-contract", action="store_true")
    p.add_argument("--analyze-storage-capacity", type=Path)
    args = p.parse_args(argv)
    n = sum(
        bool(x)
        for x in (args.print_storage_capacity_contract, args.analyze_storage_capacity)
    )
    if n != 1:
        print(
            "record_capacity: choose one of "
            "--print-storage-capacity-contract, --analyze-storage-capacity",
            file=sys.stderr,
        )
        return 2
    if args.print_storage_capacity_contract:
        return print_contract()
    return analyze_capacity(args.analyze_storage_capacity)


if __name__ == "__main__":
    sys.exit(main())
