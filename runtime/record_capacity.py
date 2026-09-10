#!/usr/bin/env python3
"""Phase 6C Capacity-aware Residency (6C-B–E frozen, 6C-F measured ranking).

Host witness for F_capacity, CapacityPlan identity, query,
s0 selection, and measured-capacity-v1 ArgMin. Ranking only;
not a rewrite license. Duplicate scoped identity is rejected.
Equal times pick the earliest F_capacity inhabitant.
Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SCHEMA = "s2c2.capacity.v1"
PLAN_SCHEMA = "s2c2.capacity_plan.v1"
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


def print_plan_contract() -> int:
    print("capacity-plan compiler-visible=yes")
    print(f"schema {PLAN_SCHEMA}")
    print("selected none")
    print("policy none")
    print("rewrite-license no")
    print("note f-capacity-subseteq-f-residency")
    print("note selected-none")
    print("note policy-none")
    print("note rewrite-license-no")
    print("note compiler-visible-candidate-object")
    print("note six-c-b-diagnostics-frozen")
    print("note six-c-c-candidate-object-this-cut")
    print("note measured-capacity-v1-not-opened")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_query_contract() -> int:
    print("capacity-plan-query consumer-api=yes")
    print(f"schema {PLAN_SCHEMA}")
    print("selected none")
    print("policy none")
    print("rewrite-license no")
    print("note not-schedule-pass")
    print("note selected-none")
    print("note policy-none")
    print("note rewrite-license-no")
    print("note consumer-api")
    print("note six-c-b-diagnostics-frozen")
    print("note six-c-c-candidate-object-frozen")
    print("note six-c-d-query-this-cut")
    print("note measured-capacity-v1-not-opened")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_policy_contract() -> int:
    print("capacity-policy consumer=query")
    print("policy none|s0|measured-capacity-v1")
    print("s0 first(F_capacity)")
    print("selected-in-f-capacity yes")
    print("rewrite-license no")
    print("note selection-ne-rewrite-license")
    print("note s0-ne-must-evict")
    print("note truncated-ne-select")
    print("note measured-capacity-v1-ranking-only")
    print("note six-c-b-diagnostics-frozen")
    print("note six-c-c-candidate-object-frozen")
    print("note six-c-d-query-frozen")
    print("note six-c-e-selection-frozen")
    print("note six-c-f-measured-ranking-this-cut")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_measured_capacity_contract() -> int:
    print("measured-capacity-v1 ranking-only=yes")
    print("schema s2c2.measured_capacity_cost.v1")
    print("match profile,workload_class,candidate_identity")
    print("argmin scoped-measured-intersect-F")
    print("rewrite-license no")
    print("note measured-yes-and-correctness")
    print("note measured-needs-two-records")
    print("note measured-scope-profile-workload-candidate")
    print("note measured-ne-cross-profile")
    print("note measured-ne-cross-workload")
    print("note measured-ne-legality")
    print("note measured-ne-rewrite-license")
    print("note measured-does-not-expand-f")
    print("note measured-does-not-rank-truncated-F")
    print("note duplicate-measured-identity")
    print("note argmin-ties-earliest-F")
    print("note do-not-filecheck-microseconds")
    print("note not-hardware-campaign")
    print("note not-new-evidence-db")
    print("note six-c-e-selection-frozen")
    print("note six-c-f-measured-ranking-this-cut")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def capacity_candidate_identity(
    keep: list[str], evict: list[str], rematerialize: list[str] | None = None
) -> str:
    rematerialize = rematerialize or []
    return (
        f"keep{{{','.join(keep)}}}|"
        f"evict{{{','.join(evict)}}}|"
        f"rematerialize{{{','.join(rematerialize)}}}"
    )


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


def _enumerate_capacity(spec: dict[str, Any]) -> dict[str, Any]:
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
    objects = {_object_id(r) for r in residencies}
    return {
        "space": spec["space"],
        "capacity": cap,
        "peak": peak,
        "conflict": conflict,
        "truncated": truncated,
        "candidates": candidates,
        "objects": objects,
    }


def _build_capacity_plan(spec: dict[str, Any]) -> dict[str, Any]:
    enum = _enumerate_capacity(spec)
    objects: set[str] = enum["objects"]
    plan_cands = []
    if not enum["truncated"]:
        seen = set()
        for i, (_action, keep, evict) in enumerate(enum["candidates"]):
            rematerialize: list[str] = []
            used = set(keep)
            for k in keep:
                if k not in objects:
                    raise ValueError("keep id not in residency")
            for e in evict:
                if e not in objects:
                    raise ValueError("evict id not in residency")
                if e in used:
                    raise ValueError("keep/evict overlap")
            ident = capacity_candidate_identity(keep, evict, rematerialize)
            if ident in seen:
                raise ValueError("duplicate identity")
            seen.add(ident)
            plan_cands.append(
                {
                    "id": i,
                    "identity": ident,
                    "keep": keep,
                    "evict": evict,
                    "rematerialize": rematerialize,
                }
            )
    return {
        "schema": PLAN_SCHEMA,
        "space": enum["space"],
        "capacity": enum["capacity"],
        "peak_live": enum["peak"],
        "feasible": bool(plan_cands),
        "enumerated": not enum["truncated"],
        "truncated": enum["truncated"],
        "selected": "none",
        "policy": "none",
        "rewrite": "no",
        "rewrite_license": "no",
        "subseteq_residency": True,
        "candidates": plan_cands,
    }


def analyze_capacity(path: Path) -> int:
    try:
        spec = _load_spec(path)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"record_capacity: {exc}", file=sys.stderr)
        return 4
    enum = _enumerate_capacity(spec)
    cap = enum["capacity"]
    peak = enum["peak"]
    conflict = enum["conflict"]
    truncated = enum["truncated"]
    candidates = enum["candidates"]
    print("storage-capacity query=f-capacity")
    print(f"storage-capacity space={spec['space']} capacity={cap} peak-live={peak}")
    print(f"storage-capacity capacity-conflict={'yes' if conflict else 'no'}")
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


def analyze_capacity_plan(path: Path) -> int:
    try:
        spec = _load_spec(path)
        plan = _build_capacity_plan(spec)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"record_capacity: {exc}", file=sys.stderr)
        return 4
    print(f"capacity-plan schema={plan['schema']}")
    print(
        f"capacity-plan space={plan['space']} capacity={plan['capacity']} "
        f"peak-live={plan['peak_live']}"
    )
    legal = (
        "not-enumerated"
        if plan["truncated"]
        else str(len(plan["candidates"]))
    )
    print(
        f"capacity-plan feasible={'yes' if plan['feasible'] else 'no'} "
        f"enumerated={'yes' if plan['enumerated'] else 'no'} "
        f"truncated={'yes' if plan['truncated'] else 'no'} legal={legal}"
    )
    print("capacity-plan selected=none policy=none rewrite-license=no")
    if not plan["truncated"]:
        for c in plan["candidates"]:
            keep_s = ",".join(c["keep"])
            evict_s = ",".join(c["evict"])
            remat_s = ",".join(c["rematerialize"])
            print(
                f"capacity-plan candidate #{c['id']} identity={c['identity']} "
                f"keep={keep_s} evict={evict_s} rematerialize={remat_s}"
            )
    print("capacity-plan subseteq-residency=yes")
    print("capacity-plan rewrite=no")
    print("capacity-plan note f-capacity-subseteq-f-residency")
    print("capacity-plan note selected-none")
    print("capacity-plan note policy-none")
    print("capacity-plan note rewrite-license-no")
    print("capacity-plan note compiler-visible-candidate-object")
    print("capacity-plan note six-c-b-diagnostics-frozen")
    print("capacity-plan note six-c-c-candidate-object-this-cut")
    print("cost=unchanged")
    return 0


MEAS_CAP_SCHEMA = "s2c2.measured_capacity_cost.v1"
MEAS_CAP_FIELDS = (
    "schema",
    "profile",
    "workload_class",
    "candidate_identity",
    "measured_time_us",
    "repetitions",
    "correctness",
    "source",
    "measured",
    "note",
)


def apply_capacity_policy(
    plan: dict[str, Any],
    policy: str,
    table_path: Path | None = None,
    profile: str = "",
    workload: str = "",
) -> dict[str, Any]:
    name = (policy or "none").strip().lower()
    if name in ("", "none"):
        return plan
    if plan["truncated"] or not plan["enumerated"]:
        raise ValueError("truncated plan cannot be selected")
    if not plan["candidates"]:
        raise ValueError("empty F_capacity cannot be selected")
    if name == "s0":
        out = dict(plan)
        out["policy"] = "s0"
        out["selected"] = plan["candidates"][0]["identity"]
        return out
    if name in ("measured-capacity-v1", "measured"):
        if table_path is None:
            raise ValueError(
                "--capacity-policy=measured-capacity-v1 requires "
                "--measured-capacity-table"
            )
        if not profile:
            raise ValueError(
                "--capacity-policy=measured-capacity-v1 requires --profile"
            )
        if not workload:
            raise ValueError(
                "--capacity-policy=measured-capacity-v1 requires workload_class"
            )
        return rank_measured_capacity(plan, table_path, profile, workload)
    raise ValueError(f"unknown --capacity-policy={policy}")


def _load_measured_capacity_table(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        obj = json.loads(line)
        if not isinstance(obj, dict):
            raise ValueError("invalid JSONL")
        extra = sorted(set(obj) - set(MEAS_CAP_FIELDS))
        if extra:
            raise ValueError("extra keys")
        if obj.get("schema") != MEAS_CAP_SCHEMA:
            raise ValueError("bad schema")
        ident = obj.get("candidate_identity")
        if not ident:
            raise ValueError("candidate_identity required")
        if not obj.get("profile") or not obj.get("workload_class"):
            raise ValueError("profile and workload_class required")
        key = (
            str(obj.get("profile") or ""),
            str(obj.get("workload_class") or ""),
            str(ident),
        )
        if key in seen:
            raise ValueError("duplicate-measured-identity")
        seen.add(key)
        rows.append(obj)
    return rows


def rank_measured_capacity(
    plan: dict[str, Any],
    table_path: Path,
    profile: str,
    workload: str,
) -> dict[str, Any]:
    legal = {c["identity"] for c in plan["candidates"]}
    us: dict[str, int] = {}
    for rec in _load_measured_capacity_table(table_path):
        if rec.get("profile") != profile or rec.get("workload_class") != workload:
            continue
        ident = rec["candidate_identity"]
        if ident not in legal:
            continue
        measured = str(rec.get("measured") or "no").lower()
        correctness = int(rec.get("correctness") or 0)
        if measured != "yes" or correctness != 1:
            continue
        if ident in us:
            raise ValueError("duplicate-measured-identity")
        us[ident] = int(rec["measured_time_us"])
    if len(us) < 2:
        raise ValueError("measured-needs-two-records")
    best = None
    argmin: list[dict[str, Any]] = []
    for c in plan["candidates"]:
        ident = c["identity"]
        if ident not in us:
            continue
        t = us[ident]
        if best is None or t < best:
            best = t
            argmin = [c]
        elif t == best:
            argmin.append(c)
    pick = argmin[0]
    out = dict(plan)
    out["policy"] = "measured-capacity-v1"
    out["selected"] = pick["identity"]
    out["_measured_count"] = len(us)
    out["_argmin_size"] = len(argmin)
    out["_coincide_s0"] = pick["identity"] == plan["candidates"][0]["identity"]
    out["_evidence"] = {c["identity"]: c["identity"] in us for c in plan["candidates"]}
    out["_profile"] = profile
    out["_workload"] = workload
    return out


def query_capacity_plan(
    path: Path,
    policy: str = "",
    table_path: Path | None = None,
    profile: str = "",
) -> int:
    try:
        spec = _load_spec(path)
        plan = apply_capacity_policy(
            _build_capacity_plan(spec),
            policy,
            table_path,
            profile,
            str(spec.get("workload_class") or ""),
        )
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"record_capacity: {exc}", file=sys.stderr)
        return 4
    prefix = "capacity-plan-query"
    print(f"{prefix} schema={plan['schema']}")
    print(
        f"{prefix} space={plan['space']} capacity={plan['capacity']} "
        f"peak-live={plan['peak_live']}"
    )
    legal = (
        "not-enumerated"
        if plan["truncated"]
        else str(len(plan["candidates"]))
    )
    print(
        f"{prefix} feasible={'yes' if plan['feasible'] else 'no'} "
        f"enumerated={'yes' if plan['enumerated'] else 'no'} "
        f"truncated={'yes' if plan['truncated'] else 'no'} legal={legal}"
    )
    print(
        f"{prefix} selected={plan['selected']} policy={plan['policy']} "
        "rewrite-license=no"
    )
    if not plan["truncated"]:
        for c in plan["candidates"]:
            print(f"{prefix} candidate #{c['id']} identity={c['identity']}")
    dump = {k: v for k, v in plan.items() if not k.startswith("_")}
    print(f"{prefix} {json.dumps(dump, separators=(',', ':'))}")
    print(f"{prefix} rewrite=no")
    print(f"{prefix} note not-schedule-pass")
    if plan["selected"] == "none":
        print(f"{prefix} note selected-none")
    else:
        print(f"{prefix} note selected-in-f-capacity")
    print(f"{prefix} note rewrite-license-no")
    print(f"{prefix} note consumer-api")
    if plan["policy"] == "s0":
        print(f"{prefix} note s0-ne-must-evict")
        print(
            "capacity-policy name=s0 "
            f"selected={plan['selected']} applicable=yes source=s0 "
            "rewrite=no rewrite-license=no"
        )
        print("capacity-policy note selection-ne-rewrite-license")
        print("capacity-policy note s0-ne-must-evict")
        print(f"{prefix} note measured-capacity-v1-not-opened")
        print(f"{prefix} note six-c-e-selection-this-cut")
    elif plan["policy"] == "measured-capacity-v1":
        print(f"{prefix} note measured-capacity-v1-ranking-only")
        print(f"{prefix} note measured-ne-rewrite-license")
        print(f"{prefix} note do-not-filecheck-microseconds")
        coincide = "yes" if plan["_coincide_s0"] else "no"
        print(
            "capacity-measured ranked="
            f"{plan['selected']} policy=measured-capacity-v1 "
            f"measured-count={plan['_measured_count']} "
            f"argmin-size={plan['_argmin_size']} coincide-s0={coincide} "
            f"profile={plan['_profile']} workload={plan['_workload']} "
            "rewrite=no rewrite-license=no"
        )
        print("capacity-measured note measured-does-not-expand-f")
        print("capacity-measured note measured-scope-profile-workload-candidate")
        print("capacity-measured note measured-ne-cross-profile")
        print("capacity-measured note measured-ne-cross-workload")
        print("capacity-measured note duplicate-measured-identity")
        print("capacity-measured note argmin-ties-earliest-F")
        for c in plan["candidates"]:
            ev = "yes" if plan["_evidence"].get(c["identity"]) else "no"
            print(
                f"capacity-measured-candidate identity={c['identity']} "
                f"evidence={ev}"
            )
        print(
            "capacity-policy name=measured-capacity-v1 "
            f"selected={plan['selected']} applicable=yes "
            "source=measured-capacity-v1 rewrite=no rewrite-license=no"
        )
        print(f"{prefix} note six-c-f-measured-ranking-this-cut")
    else:
        print(f"{prefix} note measured-capacity-v1-not-opened")
        print(f"{prefix} note six-c-d-query-this-cut")
    print("cost=unchanged")
    return 0


def dump_capacity_plan(path: Path) -> int:
    try:
        spec = _load_spec(path)
        plan = _build_capacity_plan(spec)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"record_capacity: {exc}", file=sys.stderr)
        return 4
    json.dump(plan, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Capacity F (Phase 6C)")
    p.add_argument("--print-storage-capacity-contract", action="store_true")
    p.add_argument("--analyze-storage-capacity", type=Path)
    p.add_argument("--print-capacity-plan-contract", action="store_true")
    p.add_argument("--analyze-capacity-plan", type=Path)
    p.add_argument("--dump-capacity-plan", type=Path)
    p.add_argument("--print-capacity-plan-query-contract", action="store_true")
    p.add_argument("--print-capacity-policy-contract", action="store_true")
    p.add_argument("--print-measured-capacity-contract", action="store_true")
    p.add_argument("--query-capacity-plan", type=Path)
    p.add_argument("--capacity-policy", default="")
    p.add_argument("--measured-capacity-table", type=Path)
    p.add_argument("--profile", default="")
    args = p.parse_args(argv)
    n = sum(
        bool(x)
        for x in (
            args.print_storage_capacity_contract,
            args.analyze_storage_capacity,
            args.print_capacity_plan_contract,
            args.analyze_capacity_plan,
            args.dump_capacity_plan,
            args.print_capacity_plan_query_contract,
            args.print_capacity_policy_contract,
            args.print_measured_capacity_contract,
            args.query_capacity_plan,
        )
    )
    if n != 1:
        print(
            "record_capacity: choose one of "
            "--print-storage-capacity-contract, --analyze-storage-capacity, "
            "--print-capacity-plan-contract, --analyze-capacity-plan, "
            "--dump-capacity-plan, --print-capacity-plan-query-contract, "
            "--print-capacity-policy-contract, "
            "--print-measured-capacity-contract, --query-capacity-plan",
            file=sys.stderr,
        )
        return 2
    if args.capacity_policy and not args.query_capacity_plan:
        print(
            "record_capacity: --capacity-policy requires --query-capacity-plan",
            file=sys.stderr,
        )
        return 2
    if args.measured_capacity_table and not args.query_capacity_plan:
        print(
            "record_capacity: --measured-capacity-table requires "
            "--query-capacity-plan",
            file=sys.stderr,
        )
        return 2
    if args.profile and not args.query_capacity_plan:
        print(
            "record_capacity: --profile requires --query-capacity-plan",
            file=sys.stderr,
        )
        return 2
    if args.print_storage_capacity_contract:
        return print_contract()
    if args.analyze_storage_capacity:
        return analyze_capacity(args.analyze_storage_capacity)
    if args.print_capacity_plan_contract:
        return print_plan_contract()
    if args.analyze_capacity_plan:
        return analyze_capacity_plan(args.analyze_capacity_plan)
    if args.print_capacity_plan_query_contract:
        return print_query_contract()
    if args.print_capacity_policy_contract:
        return print_policy_contract()
    if args.print_measured_capacity_contract:
        return print_measured_capacity_contract()
    if args.query_capacity_plan:
        return query_capacity_plan(
            args.query_capacity_plan,
            args.capacity_policy,
            args.measured_capacity_table,
            args.profile,
        )
    return dump_capacity_plan(args.dump_capacity_plan)


if __name__ == "__main__":
    sys.exit(main())
