#!/usr/bin/env python3
"""Phase 6B Evidence DB / Contract.

Normalizer + store + query in front of s2c2-opt. The optimizer
still consumes s2c2.measured_storage_cost.v1 via
--measured-cost-table. This module does not change ranking,
cost-v04, #69, or rewrite license. Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

_REPO = Path(__file__).resolve().parents[1]
_DEFAULT_DB = _REPO / "docs" / "design" / "v3-dataset" / "evidence-db.jsonl"
_V1_DIR = _REPO / "docs" / "design" / "v3-dataset"

SCHEMA = "s2c2.evidence.v1"
V1_SCHEMA = "s2c2.measured_storage_cost.v1"
STATUSES = ("measured", "inferred", "fixture", "pending", "invalid")
SCOPE = "candidate-local"

RECORD_FIELDS = (
    "schema",
    "profile",
    "workload_signature",
    "candidate_signature",
    "measurement_status",
    "correctness",
    "cost",
    "scope",
    "source",
    "measurement_revision",
    "recorded_at",
    "note",
)

REVISION_FROM_NAME = {
    "storage-measured-v1.jsonl": "fixture-v1",
    "storage-measured-v1-4090.jsonl": "5a-pipeline-4090",
    "storage-measured-v1-910b.jsonl": "5a-pipeline-910b",
    "storage-measured-v1-hierarchy-4090.jsonl": "5b-hierarchy-4090",
    "storage-measured-v1-hierarchy-910b.jsonl": "5b-hierarchy-910b",
    "storage-measured-v1-ntile-4090.jsonl": "5c-ntile-4090",
    "storage-measured-v1-ntile-910b.jsonl": "5c-ntile-910b",
    "storage-measured-v1-loop-4090.jsonl": "5d-loop-4090",
    "storage-measured-v1-loop-910b.jsonl": "5d-loop-910b",
}


def evidence_id(rec: dict[str, Any]) -> tuple[str, str, str, str]:
    return (
        str(rec.get("profile", "")),
        str(rec.get("workload_signature", "")),
        str(rec.get("candidate_signature", "")),
        str(rec.get("measurement_revision", "")),
    )


def ranking_eligible(rec: dict[str, Any]) -> bool:
    return rec.get("measurement_status") == "measured" and rec.get("correctness") == 1


def map_v1_status(measured: str, source: str) -> str:
    m = (measured or "").lower()
    src = (source or "").lower()
    if m == "yes" and src == "device-log":
        return "measured"
    if m == "pending":
        return "pending"
    if src == "fixture-table" or m == "no":
        return "fixture"
    if m == "inferred":
        return "inferred"
    return "invalid"


def normalize_v1_row(
    obj: dict[str, Any], revision: str, recorded_at: str
) -> dict[str, Any] | None:
    sig = str(obj.get("candidate_signature") or "")
    if not sig:
        return None
    status = map_v1_status(str(obj.get("measured") or ""), str(obj.get("source") or ""))
    cost_us = obj.get("measured_time_us", 0)
    try:
        cost_us = int(cost_us)
    except (TypeError, ValueError):
        status = "invalid"
        cost_us = 0
    correctness = obj.get("correctness", 0)
    try:
        correctness = int(correctness)
    except (TypeError, ValueError):
        correctness = 0
        status = "invalid"
    rec = {
        "schema": SCHEMA,
        "profile": str(obj.get("profile") or ""),
        "workload_signature": str(obj.get("workload_class") or obj.get("workload_signature") or ""),
        "candidate_signature": sig,
        "measurement_status": status,
        "correctness": correctness,
        "cost": {"measured_time_us": cost_us},
        "scope": SCOPE,
        "source": str(obj.get("source") or "unknown"),
        "measurement_revision": revision,
        "recorded_at": recorded_at,
        "note": str(obj.get("note") or "Normalized from measured-storage-v1. Not a Capability cell."),
    }
    extra = sorted(set(rec) - set(RECORD_FIELDS))
    if extra:
        raise ValueError(f"evidence extra keys {extra}")
    return rec


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        obj = json.loads(line)
        if isinstance(obj, dict):
            rows.append(obj)
    return rows


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for rec in rows:
            fh.write(json.dumps(rec, ensure_ascii=True, separators=(",", ":")) + "\n")


def upsert(db: list[dict[str, Any]], rec: dict[str, Any]) -> None:
    eid = evidence_id(rec)
    for i, old in enumerate(db):
        if evidence_id(old) == eid:
            db[i] = rec
            return
    db.append(rec)


def ingest_measured_v1(
    src: Path,
    db_path: Path,
    revision: str | None,
    recorded_at: str = "normalized-v1",
) -> int:
    rev = revision or REVISION_FROM_NAME.get(src.name)
    if not rev:
        print(f"record_evidence: need --measurement-revision for {src.name}", file=sys.stderr)
        return 4
    incoming = load_jsonl(src)
    db = load_jsonl(db_path) if db_path.exists() else []
    n = 0
    for obj in incoming:
        # hardware-ledger rows have no schema / candidate_signature.
        if obj.get("schema") != V1_SCHEMA:
            continue
        rec = normalize_v1_row(obj, rev, recorded_at)
        if rec is None:
            continue
        upsert(db, rec)
        n += 1
    write_jsonl(db_path, db)
    print(f"evidence-db ingest=measured-v1 revision={rev} rows={n} store={db_path.name}")
    print("evidence-db note identity-E")
    print("evidence-db note compiler-ne-campaign-log")
    print("evidence-db note ranking-status-measured-only")
    print("evidence-db note extras-dropped")
    print("cost=unchanged")
    return 0


def ingest_all_frozen(db_path: Path) -> int:
    if db_path.exists():
        db_path.unlink()
    order = [
        "storage-measured-v1.jsonl",
        "storage-measured-v1-4090.jsonl",
        "storage-measured-v1-910b.jsonl",
        "storage-measured-v1-hierarchy-4090.jsonl",
        "storage-measured-v1-hierarchy-910b.jsonl",
        "storage-measured-v1-ntile-4090.jsonl",
        "storage-measured-v1-ntile-910b.jsonl",
        "storage-measured-v1-loop-4090.jsonl",
        "storage-measured-v1-loop-910b.jsonl",
    ]
    for name in order:
        src = _V1_DIR / name
        if not src.exists():
            print(f"record_evidence: missing {name}", file=sys.stderr)
            return 4
        rc = ingest_measured_v1(
            src, db_path, REVISION_FROM_NAME[name], recorded_at="campaign-frozen"
        )
        if rc != 0:
            return rc
    rows = load_jsonl(db_path)
    print(f"evidence-db ingest=frozen-campaign records={len(rows)}")
    print("evidence-db note 5a-5d-frozen")
    print("evidence-db note five-e-not-opened")
    print("cost=unchanged")
    return 0


def project_v1(rec: dict[str, Any]) -> dict[str, Any]:
    measured = "yes" if ranking_eligible(rec) else "no"
    return {
        "schema": V1_SCHEMA,
        "profile": rec["profile"],
        "workload_class": rec["workload_signature"],
        "candidate_signature": rec["candidate_signature"],
        "measured_time_us": int(rec.get("cost", {}).get("measured_time_us", 0)),
        "repetitions": 5,
        "correctness": rec["correctness"],
        "source": rec.get("source") or "evidence-db",
        "measured": measured,
        "note": "Projected from s2c2.evidence.v1. Do not FileCheck microseconds.",
    }


def export_measured_v1(
    db_path: Path,
    profile: str,
    workload: str,
    revision: str,
    out: Path | None,
) -> int:
    rows = load_jsonl(db_path)
    chosen: dict[str, dict[str, Any]] = {}
    for rec in rows:
        if rec.get("schema") != SCHEMA:
            continue
        if profile and rec.get("profile") != profile:
            continue
        if workload and rec.get("workload_signature") != workload:
            continue
        if revision and rec.get("measurement_revision") != revision:
            continue
        if not ranking_eligible(rec):
            continue
        # Last matching row wins inside the slice (same as v1 loader).
        chosen[rec["candidate_signature"]] = rec
    projected = [project_v1(rec) for rec in chosen.values()]
    if out:
        write_jsonl(out, projected)
    else:
        for rec in projected:
            print(json.dumps(rec, ensure_ascii=True, separators=(",", ":")))
    print(f"evidence-db export=measured-v1 profile={profile or '*'} "
          f"workload={workload or '*'} revision={revision or '*'} "
          f"rows={len(projected)}")
    print("evidence-db note ranking-status-measured-only")
    print("evidence-db note compiler-consumes-v1-projection")
    print("evidence-db note do-not-filecheck-microseconds")
    print("cost=unchanged")
    return 0


def query_evidence(
    db_path: Path,
    profile: str,
    workload: str,
    candidate: str,
    revision: str,
) -> int:
    rows = load_jsonl(db_path)
    hits = []
    for rec in rows:
        if rec.get("schema") != SCHEMA:
            continue
        if profile and rec.get("profile") != profile:
            continue
        if workload and rec.get("workload_signature") != workload:
            continue
        if candidate and rec.get("candidate_signature") != candidate:
            continue
        if revision and rec.get("measurement_revision") != revision:
            continue
        hits.append(rec)
    eligible = [h for h in hits if ranking_eligible(h)]
    print("evidence-db query=applicability")
    print(f"evidence-db identity profile={profile or '*'} "
          f"workload={workload or '*'} candidate={candidate or '*'} "
          f"revision={revision or '*'}")
    print(f"evidence-db hits={len(hits)} ranking-eligible={len(eligible)}")
    if eligible:
        last = eligible[-1]
        print(f"evidence-db status={last['measurement_status']}")
        print(f"evidence-db ranking-eligible=yes revision={last['measurement_revision']}")
    elif hits:
        print(f"evidence-db status={hits[-1]['measurement_status']}")
        print("evidence-db ranking-eligible=no")
    else:
        print("evidence-db status=absent")
        print("evidence-db ranking-eligible=no")
    print("evidence-db note measured-ne-rewrite-license")
    print("evidence-db note five-e-not-opened")
    print("cost=unchanged")
    return 0


def check_db(db_path: Path) -> int:
    rows = load_jsonl(db_path)
    ids: set[tuple[str, str, str, str]] = set()
    n_meas = n_fix = n_other = 0
    for rec in rows:
        if rec.get("schema") != SCHEMA:
            print("record_evidence: bad schema", file=sys.stderr)
            return 4
        missing = [k for k in RECORD_FIELDS if k not in rec]
        if missing:
            print(f"record_evidence: missing keys {missing}", file=sys.stderr)
            return 4
        extra = sorted(set(rec) - set(RECORD_FIELDS))
        if extra:
            print(f"record_evidence: extra keys {extra}", file=sys.stderr)
            return 4
        if rec.get("measurement_status") not in STATUSES:
            print("record_evidence: bad measurement_status", file=sys.stderr)
            return 4
        eid = evidence_id(rec)
        if eid in ids:
            print("record_evidence: duplicate identity E", file=sys.stderr)
            return 4
        ids.add(eid)
        st = rec["measurement_status"]
        if st == "measured":
            n_meas += 1
        elif st == "fixture":
            n_fix += 1
        else:
            n_other += 1
    print(f"evidence-db check=ok records={len(rows)}")
    print(f"evidence-db measured={n_meas} fixture={n_fix} other={n_other}")
    print("evidence-db note identity-E-unique")
    print("evidence-db note ranking-status-measured-only")
    print("evidence-db note not-hardware-ledger")
    print("evidence-db note not-cap-schema-v1")
    print("cost=unchanged")
    return 0


def print_contract() -> int:
    print("evidence-db compiler-facing=yes")
    print("schema s2c2.evidence.v1")
    print("identity E=(profile,workload,candidate,measurement_revision)")
    print("status measured|inferred|fixture|pending|invalid")
    print("note ranking-status-measured-only")
    print("note compiler-consumes-v1-projection")
    print("note compiler-ne-campaign-log")
    print("note extras-cannot-expand-F")
    print("note measured-ne-rewrite-license")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note campaign-5a-5d-frozen")
    print("note not-capacity-aware")
    print("note not-hardware-ledger")
    print("note do-not-filecheck-microseconds")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Evidence DB (Phase 6B)")
    p.add_argument("--print-evidence-db-contract", action="store_true")
    p.add_argument("--ingest-measured-v1", type=Path)
    p.add_argument("--ingest-frozen-campaign", action="store_true")
    p.add_argument("--export-measured-v1", action="store_true")
    p.add_argument("--query-evidence", action="store_true")
    p.add_argument("--check-evidence-db", action="store_true")
    p.add_argument("--db", type=Path, default=_DEFAULT_DB)
    p.add_argument("--out", type=Path)
    p.add_argument("--measurement-revision", default="")
    p.add_argument("--profile", default="")
    p.add_argument("--workload-signature", default="")
    p.add_argument("--candidate-signature", default="")
    args = p.parse_args(argv)
    n = sum(
        bool(x)
        for x in (
            args.print_evidence_db_contract,
            args.ingest_measured_v1,
            args.ingest_frozen_campaign,
            args.export_measured_v1,
            args.query_evidence,
            args.check_evidence_db,
        )
    )
    if n != 1:
        print(
            "record_evidence: choose one of --print-evidence-db-contract, "
            "--ingest-measured-v1, --ingest-frozen-campaign, "
            "--export-measured-v1, --query-evidence, --check-evidence-db",
            file=sys.stderr,
        )
        return 2
    if args.print_evidence_db_contract:
        return print_contract()
    if args.ingest_measured_v1:
        return ingest_measured_v1(
            args.ingest_measured_v1, args.db, args.measurement_revision or None
        )
    if args.ingest_frozen_campaign:
        return ingest_all_frozen(args.db)
    if args.export_measured_v1:
        return export_measured_v1(
            args.db,
            args.profile,
            args.workload_signature,
            args.measurement_revision,
            args.out,
        )
    if args.query_evidence:
        return query_evidence(
            args.db,
            args.profile,
            args.workload_signature,
            args.candidate_signature,
            args.measurement_revision,
        )
    return check_db(args.db)


if __name__ == "__main__":
    sys.exit(main())
