#!/usr/bin/env python3
"""Ascend capability recorder (host). Same Schema v1 as CUDA. No acl_* keys."""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[2]
_SCHEMA_PATH = _REPO_ROOT / "docs/design/v3-capability-schema.v1.json"
_CATALOG_PATH = _REPO_ROOT / "docs/design/v3-dataset/ascend910b/capability.jsonl"

CAP_SCHEMA_VERSION = "1"
CAP_SCHEMA_KINDS = ("pair", "depth", "memory", "sync")
CAP_SCHEMA_RELATION = ("serial", "parallel", "mixed", "underdetermined")
CAP_SCHEMA_REGIME = ("bandwidth", "latency", "occupancy", "underdetermined")
CAP_SCHEMA_CONSTRAINT = (
    "none",
    "legacy_default",
    "resource_contention",
    "allocator_sync",
    "copy_engine_contention",
)
CAP_SCHEMA_CONFIDENCE = ("measured", "inferred", "arm_specific", "unknown")
CAP_SCHEMA_FIELDS = (
    "schema_version",
    "record_kind",
    "hardware_id",
    "compute_domain",
    "transfer_domain",
    "direction",
    "source_memory_class",
    "destination_memory_class",
    "pair",
    "pair_relation",
    "regime",
    "size_range",
    "synchronization",
    "pipeline_depth_evidence",
    "observed_constraint",
    "confidence",
    "note",
    "evidence_refs",
    "v3",
    "cost",
    "semantics",
)

PAIRS = ("C||HtoD", "C||C", "HtoD||DtoH")
FORBIDDEN_KEYS = (
    "acl_",
    "davinci_",
    "cube_",
    "vectorcore_",
    "password",
    "localhost",
)


def print_cap_schema_v1() -> int:
    print("cap-schema v1")
    print(
        "field compute_domain transfer_domain direction "
        "source_memory_class destination_memory_class pair_relation "
        "size_range regime synchronization pipeline_depth_evidence "
        "observed_constraint confidence"
    )
    print(
        "transfer_domain copy_engine dma on_chip_bus host_to_device "
        "device_to_host device_to_device device_to_local device_to_array none"
    )
    print(
        "direction host_to_device device_to_host device_to_device "
        "device_to_local device_to_array none"
    )
    print(
        "memory_class pinned_host pageable_host device_memory "
        "global_memory local_buffer dram cim_array none"
    )
    print("pair_relation parallel serial mixed underdetermined")
    print(
        "observed_constraint none legacy_default resource_contention "
        "allocator_sync copy_engine_contention"
    )
    print("confidence measured inferred arm_specific unknown")
    print("hardware unfilled")
    print("depth-star not-a-law")
    print("no-extra-key acl_davinci")
    print("semantics unchanged")
    print("score3 not-applicable")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def print_workload_contract() -> int:
    print("workload-contract v1")
    print("compute semantic=elemwise")
    print("transfer semantic=host_to_device device_to_host")
    print("pair R1 C||HtoD")
    print("pair R2 C||C")
    print("pair R3 HtoD||DtoH")
    print("note workload-semantic-ne-kernel-backend")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def classify(ta: float, tb: float, tpar: float) -> str:
    mx = max(ta, tb)
    sm = ta + tb
    pmax = (tpar / mx) if mx > 0 else 0.0
    psum = (tpar / sm) if sm > 0 else 0.0
    if psum >= 0.90:
        return "serial"
    if pmax <= 1.15 and psum <= 0.75:
        return "parallel"
    return "mixed"


def infer_constraint(pair: str, relation: str) -> str:
    if relation != "serial":
        return "none"
    if pair == "C||C":
        return "resource_contention"
    return "copy_engine_contention"


def is_foreign_hardware(hid: str) -> bool:
    s = hid.lower()
    return any(
        tok in s
        for tok in ("4090", "sm89", "rtx", "cuda", "gfx", "amd", "hip", "rocm")
    )


def validate_cap_schema_v1(rec: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    extra = sorted(set(rec) - set(CAP_SCHEMA_FIELDS))
    if extra:
        errors.append(f"extra {' '.join(extra)}")
    for key in CAP_SCHEMA_FIELDS:
        if key not in rec:
            errors.append(f"missing {key}")
    if rec.get("schema_version") != CAP_SCHEMA_VERSION:
        errors.append("schema_version")
    if rec.get("record_kind") not in CAP_SCHEMA_KINDS:
        errors.append("record_kind")
    for open_key in (
        "hardware_id",
        "compute_domain",
        "transfer_domain",
        "direction",
        "source_memory_class",
        "destination_memory_class",
        "pair",
        "size_range",
        "synchronization",
        "pipeline_depth_evidence",
        "note",
        "evidence_refs",
    ):
        val = rec.get(open_key)
        if not isinstance(val, str) or not val:
            errors.append(open_key)
    if rec.get("pair_relation") not in CAP_SCHEMA_RELATION:
        errors.append("pair_relation")
    if rec.get("regime") not in CAP_SCHEMA_REGIME:
        errors.append("regime")
    if rec.get("observed_constraint") not in CAP_SCHEMA_CONSTRAINT:
        errors.append("observed_constraint")
    if rec.get("confidence") not in CAP_SCHEMA_CONFIDENCE:
        errors.append("confidence")
    if rec.get("v3") != "not-claimed":
        errors.append("v3")
    if rec.get("cost") != "unchanged":
        errors.append("cost")
    if rec.get("semantics") != "unchanged":
        errors.append("semantics")
    hid = str(rec.get("hardware_id", ""))
    if is_foreign_hardware(hid):
        errors.append("foreign-hardware")
    blob = json.dumps(rec, ensure_ascii=True)
    low = blob.lower()
    for tok in FORBIDDEN_KEYS:
        if tok in low:
            errors.append(tok.rstrip("_"))
    return errors


def blank_cap_record(pair: str = "C||HtoD") -> dict[str, Any]:
    compute, transfer, direction, src, dst = "none", "none", "none", "none", "none"
    if pair == "C||HtoD":
        compute, transfer, direction = "ascend_ai_core", "copy_engine", "host_to_device"
        src, dst = "pinned_host", "device_memory"
    elif pair == "C||C":
        compute = "ascend_ai_core"
        src, dst = "device_memory", "device_memory"
    elif pair == "HtoD||DtoH":
        transfer, direction = "copy_engine", "host_to_device"
        src, dst = "pinned_host", "device_memory"
    return {
        "schema_version": CAP_SCHEMA_VERSION,
        "record_kind": "pair",
        "hardware_id": "unfilled",
        "compute_domain": compute,
        "transfer_domain": transfer,
        "direction": direction,
        "source_memory_class": src,
        "destination_memory_class": dst,
        "pair": pair,
        "pair_relation": "underdetermined",
        "regime": "underdetermined",
        "size_range": "n/a",
        "synchronization": "named-nonblocking",
        "pipeline_depth_evidence": "n/a",
        "observed_constraint": "none",
        "confidence": "unknown",
        "note": "host emit-record; not measured",
        "evidence_refs": "backend-adapter-ascend.md",
        "v3": "not-claimed",
        "cost": "unchanged",
        "semantics": "unchanged",
    }


def check_schema_identity() -> int:
    if not _SCHEMA_PATH.is_file():
        print(f"record_ascend: missing {_SCHEMA_PATH}", file=sys.stderr)
        return 4
    schema = json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))
    required = tuple(schema.get("required", []))
    if required != CAP_SCHEMA_FIELDS:
        print(
            f"record_ascend: field mismatch {required} vs {CAP_SCHEMA_FIELDS}",
            file=sys.stderr,
        )
        return 4
    if schema.get("additionalProperties") is not False:
        print("record_ascend: schema must forbid extra keys", file=sys.stderr)
        return 4
    props = schema.get("properties", {})
    extra = [
        k
        for k in props
        if k.startswith(("acl_", "davinci_", "cube_", "vectorcore_"))
    ]
    if extra:
        print(f"record_ascend: schema grew vendor keys {extra}", file=sys.stderr)
        return 4
    print(
        "schema-identity v1 fields=21 additionalProperties=false "
        "no-extra-key=acl_davinci vendor=ascend-or-cuda "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    return 0


def analyze_records(jsonl: Path) -> int:
    rows = [
        json.loads(line)
        for line in jsonl.read_text(encoding="utf-8").splitlines()
        if line
    ]
    if not rows:
        print("record_ascend: empty cap-schema", file=sys.stderr)
        return 4
    for rec in rows:
        errors = validate_cap_schema_v1(rec)
        if errors:
            print(f"record_ascend: invalid cap-schema {errors}", file=sys.stderr)
            return 4
    print(
        f"v3-cap-schema v1 records={len(rows)} hardware=ascend-scope "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    for rec in rows:
        print(
            f"pair\t{rec['pair']}\t{rec['pair_relation']}\t"
            f"{rec['observed_constraint']}\t{rec['confidence']}"
        )
    print("depth-star not-a-law")
    print("no-extra-key acl_davinci")
    print("semantics unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def accept_hardware(hid: str) -> int:
    if is_foreign_hardware(hid):
        print(f"record_ascend foreign-hardware=rejected id={hid}")
        print("record_ascend note capability-4090-ne-capability-910b")
        return 1
    print(f"record_ascend hardware-scope=this-profile id={hid}")
    return 0


_PAIR_RE = re.compile(
    r"s2c2-ascend-run pair=(\S+) pair_relation=(\S+) "
    r"observed_constraint=(\S+) confidence=(\S+)"
)
_TIMING_RE = re.compile(
    r"s2c2-ascend-run timing pair=(\S+) a=([0-9.]+) b=([0-9.]+) "
    r"par=([0-9.]+) par_over_max=([0-9.]+) par_over_sum=([0-9.]+) "
    r"n=(\d+) k=(\d+)"
)


def _mib(n: int) -> int:
    return (n * 4) // (1024 * 1024)


def parse_pair_log(log: Path) -> list[dict[str, Any]]:
    text = log.read_text(encoding="utf-8", errors="replace")
    rows: list[dict[str, Any]] = []
    pending: dict[str, dict[str, Any]] = {}
    for line in text.splitlines():
        m = _PAIR_RE.search(line)
        if m:
            pending[m.group(1)] = {
                "pair": m.group(1),
                "pair_relation": m.group(2),
                "observed_constraint": m.group(3),
                "confidence": m.group(4),
            }
            continue
        m = _TIMING_RE.search(line)
        if m:
            pair = m.group(1)
            rec = pending.get(pair, {"pair": pair})
            rec.update(
                {
                    "A_us": float(m.group(2)),
                    "B_us": float(m.group(3)),
                    "par_us": float(m.group(4)),
                    "par_over_max": float(m.group(5)),
                    "par_over_sum": float(m.group(6)),
                    "N": int(m.group(7)),
                    "k": int(m.group(8)),
                }
            )
            rows.append(rec)
            continue
        if line.startswith("{") and '"record_kind":"pair"' in line:
            rec = json.loads(line)
            # JSON is printed after timing; attach to last matching row.
            for row in reversed(rows):
                if row["pair"] == rec.get("pair") and "json" not in row:
                    row["json"] = rec
                    break
    return rows


def project_pairs(log: Path, out_dir: Path) -> int:
    rows = parse_pair_log(log)
    if not rows:
        print("record_ascend: no pair rows in log", file=sys.stderr)
        return 4
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "pairs.csv"
    jsonl_path = out_dir / "capability.jsonl"
    fields = [
        "N",
        "k",
        "pair",
        "A_us",
        "B_us",
        "par_us",
        "par_over_max",
        "par_over_sum",
        "verdict",
        "observed_constraint",
    ]
    with csv_path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for row in rows:
            w.writerow(
                {
                    "N": row.get("N", ""),
                    "k": row.get("k", ""),
                    "pair": row["pair"],
                    "A_us": f"{row.get('A_us', 0):.1f}",
                    "B_us": f"{row.get('B_us', 0):.1f}",
                    "par_us": f"{row.get('par_us', 0):.1f}",
                    "par_over_max": f"{row.get('par_over_max', 0):.3f}",
                    "par_over_sum": f"{row.get('par_over_sum', 0):.3f}",
                    "verdict": row.get("pair_relation", ""),
                    "observed_constraint": row.get("observed_constraint", ""),
                }
            )

    by_pair: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        by_pair[row["pair"]].append(row)

    projected: list[dict[str, Any]] = []
    for pair in PAIRS:
        group = by_pair.get(pair, [])
        if not group:
            print(f"record_ascend: missing pair {pair}", file=sys.stderr)
            return 4
        rels = {r["pair_relation"] for r in group}
        ns = sorted(int(r["N"]) for r in group if "N" in r)
        lo, hi = _mib(ns[0]), _mib(ns[-1])
        size = f"{lo}MiB" if lo == hi else f"{lo}MiB..{hi}MiB"
        template = dict(group[-1].get("json") or blank_cap_record(pair))
        if len(rels) == 1:
            relation = next(iter(rels))
            constraint = group[-1]["observed_constraint"]
            note = (
                "Ascend 910B measured pair; topology only. "
                "Do not compare microseconds to 4090."
            )
        else:
            relation = "underdetermined"
            constraint = "none"
            note = (
                "Ascend 910B sizes disagree on pair_relation "
                f"({', '.join(sorted(rels))}); topology underdetermined."
            )
        template.update(
            {
                "hardware_id": "ascend910b:ascend",
                "pair": pair,
                "pair_relation": relation,
                "observed_constraint": constraint,
                "confidence": "measured",
                "size_range": size,
                "note": note,
                "evidence_refs": "backend-adapter-ascend.md,v3-dataset/ascend910b",
                "v3": "not-claimed",
                "cost": "unchanged",
                "semantics": "unchanged",
            }
        )
        errors = validate_cap_schema_v1(template)
        if errors:
            print(f"record_ascend: invalid projection {pair} {errors}", file=sys.stderr)
            return 4
        projected.append(template)

    with jsonl_path.open("w", encoding="utf-8") as fh:
        for rec in projected:
            fh.write(json.dumps(rec, ensure_ascii=True, separators=(",", ":")) + "\n")

    print(f"record_ascend project-pairs rows={len(rows)} cells={len(projected)}")
    for rec in projected:
        print(
            f"pair\t{rec['pair']}\t{rec['pair_relation']}\t"
            f"{rec['observed_constraint']}\t{rec['confidence']}\t"
            f"{rec['size_range']}"
        )
    print("v3=not-claimed")
    print("cost=unchanged")
    print("note topology-only")
    return 0


def query_cap(pair: str, catalog: Path, hardware: str | None) -> int:
    if pair not in PAIRS:
        print(f"record_ascend: unknown pair {pair}", file=sys.stderr)
        return 2
    if not catalog.is_file():
        print(f"record_ascend: missing {catalog}", file=sys.stderr)
        return 4
    rows = [
        json.loads(line)
        for line in catalog.read_text(encoding="utf-8").splitlines()
        if line
    ]
    hits = []
    for rec in rows:
        errors = validate_cap_schema_v1(rec)
        if errors:
            print(f"record_ascend: invalid cap-schema {errors}", file=sys.stderr)
            return 4
        if rec.get("record_kind") != "pair" or rec.get("pair") != pair:
            continue
        hid = str(rec.get("hardware_id", ""))
        if hardware and hardware not in hid:
            continue
        hits.append(rec)
    if not hits:
        print(
            json.dumps(
                {
                    "pair": pair,
                    "pair_relation": "underdetermined",
                    "observed_constraint": "none",
                    "confidence": "unknown",
                    "applicable": False,
                },
                ensure_ascii=True,
            )
        )
        return 0
    rec = hits[0]
    print(
        json.dumps(
            {
                "pair": rec["pair"],
                "pair_relation": rec["pair_relation"],
                "observed_constraint": rec["observed_constraint"],
                "confidence": rec["confidence"],
                "regime": rec.get("regime", "underdetermined"),
                "size_range": rec.get("size_range", "n/a"),
                "synchronization": rec.get("synchronization", "n/a"),
                "hardware_id": rec["hardware_id"],
                "applicable": rec.get("confidence") == "measured"
                and rec.get("pair_relation") in ("serial", "parallel", "mixed"),
            },
            ensure_ascii=True,
            separators=(",", ":"),
        )
    )
    print(
        f"record_ascend query-cap pair={pair} "
        f"pair_relation={rec['pair_relation']} "
        f"confidence={rec['confidence']}"
    )
    return 0


_CASE_RE = re.compile(
    r"s2c2-ascend-run mem case=(\S+) n=(\d+) k=(\d+) us=([0-9.]+)"
)
_SLICE_RE = re.compile(
    r"s2c2-ascend-run mem slice pair=(\S+) residency=(\S+) "
    r"pair_relation=(\S+) extra_hb=(\S+) ovl_over_max=([0-9.]+) "
    r"ovl_over_sum=([0-9.]+) n=(\d+) k=(\d+)"
)


def _mem_size_range(ns: list[int]) -> tuple[str, str]:
    """Schema v1 size_range is payload bytes: N floats * sizeof(float)."""
    mibs = [_mib(n) for n in ns]
    size_range = (
        f"{mibs[0]}MiB" if mibs[0] == mibs[-1] else f"{mibs[0]}MiB..{mibs[-1]}MiB"
    )
    measured = ",".join(f"{x}MiB" for x in mibs)
    return size_range, measured


def print_mem_schema() -> int:
    print("ascend-mem r4")
    print("pair C||HtoD C||DtoH")
    print("host pinned pageable")
    print("acceptance storage-comm")
    print("extra-hb none|pageable-host")
    print("note residency-ne-extra-hb")
    print("size_range payload-bytes")
    print("note size_range-ne-N-label")
    print("semantics unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def analyze_mem(log: Path) -> int:
    text = log.read_text(encoding="utf-8", errors="replace")
    cases: list[dict[str, Any]] = []
    slices: list[dict[str, Any]] = []
    for line in text.splitlines():
        m = _CASE_RE.search(line)
        if m:
            cases.append(
                {
                    "case": m.group(1),
                    "N": int(m.group(2)),
                    "k": int(m.group(3)),
                    "us": float(m.group(4)),
                }
            )
            continue
        m = _SLICE_RE.search(line)
        if m:
            slices.append(
                {
                    "pair": m.group(1),
                    "residency": m.group(2),
                    "verdict": m.group(3),
                    "extra_hb": m.group(4),
                    "ovl_over_max": float(m.group(5)),
                    "ovl_over_sum": float(m.group(6)),
                    "N": int(m.group(7)),
                    "k": int(m.group(8)),
                }
            )
    if not slices:
        print("record_ascend: no mem slices in log", file=sys.stderr)
        return 4
    ns = sorted({s["N"] for s in slices})
    size_range, measured = _mem_size_range(ns)
    print(
        "v3-ascend-mem r4 pair=C||HtoD,C||DtoH acceptance=storage-comm "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    print(f"size_range={size_range}")
    print(f"measured sizes = {measured}")
    hits = 0
    unbalanced = 0
    bw_only = 0
    for n in ns:
        by_case = {c["case"]: c for c in cases if c["N"] == n}
        for direction, pin_k, page_k in (
            ("HtoD", "htod-pinned", "htod-pageable"),
            ("DtoH", "dtoh-pinned", "dtoh-pageable"),
        ):
            pin_row = by_case.get(pin_k)
            page_row = by_case.get(page_k)
            if pin_row and page_row:
                ratio = (page_row["us"] / pin_row["us"]) if pin_row["us"] else 0.0
                print(f"bandwidth\tN={n}\tpair={direction}\tpage/pin={ratio:.3f}")
        for pair in ("C||HtoD", "C||DtoH"):
            pinned = next(
                (
                    s
                    for s in slices
                    if s["N"] == n and s["pair"] == pair and s["residency"] == "pinned"
                ),
                None,
            )
            pageable = next(
                (
                    s
                    for s in slices
                    if s["N"] == n
                    and s["pair"] == pair
                    and s["residency"] == "pageable"
                ),
                None,
            )
            if not pinned or not pageable:
                continue
            if pinned["verdict"] == "parallel" and pageable["verdict"] == "serial":
                hits += 1
                print(
                    f"counterexample\tN={n}\tpair={pair}\t"
                    f"pinned=parallel\tpageable=serial\t"
                    "extra-hb=pageable-host"
                )
            elif (
                pinned["verdict"] == "parallel"
                and pageable["verdict"] == "mixed"
                and pageable["ovl_over_max"] <= 1.15
            ):
                unbalanced += 1
                print(
                    f"max-like-unbalanced\tN={n}\tpair={pair}\t"
                    f"pinned=parallel\tpageable=mixed"
                )
            elif pageable["verdict"] == pinned["verdict"]:
                pin_t = by_case.get(
                    "htod-pinned" if pair.endswith("HtoD") else "dtoh-pinned"
                )
                page_t = by_case.get(
                    "htod-pageable" if pair.endswith("HtoD") else "dtoh-pageable"
                )
                if pin_t and page_t and page_t["us"] > pin_t["us"]:
                    bw_only += 1
                    print(
                        f"bandwidth-only\tN={n}\tpair={pair}\t"
                        f"pageable={pageable['verdict']}"
                    )
    print(f"counterexamples={hits}")
    print(f"max-like-unbalanced={unbalanced}")
    print(f"bandwidth-only={bw_only}")
    print("note residency-ne-extra-hb")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


_CC_SLICE_RE = re.compile(
    r"s2c2-ascend-run cc-phase slice r_target=(\S+) r_achieved=(\S+) "
    r"k1=(\d+) k2=(\d+) pair_relation=(\S+) observed_constraint=(\S+) n=(\d+)"
)


def print_cc_phase_schema() -> int:
    print("ascend-cc-phase pair=C||C")
    print("r=T_C1/T_C2")
    print("r_target=0.5,0.75,1,1.5,2")
    print("n=4M,16M,64M")
    print("r3-gate=closed")
    print("note catalog-untouched")
    print("semantics unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def analyze_cc_phase(log: Path) -> int:
    text = log.read_text(encoding="utf-8", errors="replace")
    slices: list[dict[str, Any]] = []
    for line in text.splitlines():
        m = _CC_SLICE_RE.search(line)
        if not m:
            continue
        slices.append(
            {
                "r_target": float(m.group(1)),
                "r_achieved": float(m.group(2)),
                "k1": int(m.group(3)),
                "k2": int(m.group(4)),
                "pair_relation": m.group(5),
                "observed_constraint": m.group(6),
                "N": int(m.group(7)),
            }
        )
    if not slices:
        print("record_ascend: no cc-phase slices in log", file=sys.stderr)
        return 4
    rels = sorted({s["pair_relation"] for s in slices})
    unique = "yes" if len(rels) == 1 else "no"
    print(
        "v3-ascend-cc-phase pair=C||C r3-gate=closed "
        "note catalog-untouched semantics=unchanged "
        "v3=not-claimed cost=unchanged"
    )
    print(f"relations={','.join(rels)}")
    print(f"unique={unique}")
    print(f"slices={len(slices)}")
    print("r3-gate=closed")
    print("note catalog-untouched")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def _n_label(n: int) -> str:
    if n % (1024 * 1024) == 0:
        return f"{n // (1024 * 1024)}M"
    return str(n)


def print_cc_size_schema() -> int:
    print("ascend-cc-size pair=C||C")
    print("r=1")
    print("n=4M,8M,12M,16M,32M,64M,128M")
    print("note size-boundary")
    print("r3-gate=closed")
    print("note catalog-untouched")
    print("semantics unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def analyze_cc_size(log: Path) -> int:
    text = log.read_text(encoding="utf-8", errors="replace")
    slices: list[dict[str, Any]] = []
    for line in text.splitlines():
        m = _CC_SLICE_RE.search(line)
        if not m:
            continue
        slices.append(
            {
                "r_target": float(m.group(1)),
                "pair_relation": m.group(5),
                "observed_constraint": m.group(6),
                "N": int(m.group(7)),
            }
        )
    if not slices:
        print("record_ascend: no cc-size slices in log", file=sys.stderr)
        return 4
    matched = [s for s in slices if abs(s["r_target"] - 1.0) <= 0.05]
    if matched:
        slices = matched
    by_n: dict[int, str] = {}
    for s in slices:
        by_n[s["N"]] = s["pair_relation"]
    ns = sorted(by_n)
    rels = [by_n[n] for n in ns]
    uniq = sorted(set(rels))
    last_mixed = next((n for n in reversed(ns) if by_n[n] == "mixed"), None)
    first_serial = next((n for n in ns if by_n[n] == "serial"), None)
    saw_serial = False
    nonmono = False
    for rel in rels:
        if rel == "serial":
            saw_serial = True
        elif saw_serial and rel != "serial":
            nonmono = True
    if nonmono:
        trans = "underdetermined"
    elif last_mixed is not None and first_serial is not None and last_mixed < first_serial:
        trans = f"mixed-to-serial {_n_label(last_mixed)}..{_n_label(first_serial)}"
    elif all(r == "mixed" for r in rels):
        trans = "none-all-mixed"
    elif all(r == "serial" for r in rels):
        trans = "none-all-serial"
    else:
        trans = "underdetermined"
    print(
        "v3-ascend-cc-size pair=C||C r=1 r3-gate=closed "
        "note catalog-untouched semantics=unchanged "
        "v3=not-claimed cost=unchanged"
    )
    print(f"n-grid={','.join(_n_label(n) for n in ns)}")
    print(f"relations={','.join(uniq)}")
    print(f"transition={trans}")
    print("r3-gate=closed")
    print("note catalog-untouched")
    print("note size-boundary")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Ascend CapabilityRecord host tools")
    p.add_argument("--print-cap-schema-v1", action="store_true")
    p.add_argument("--print-workload-contract", action="store_true")
    p.add_argument("--check-schema-identity", action="store_true")
    p.add_argument("--analyze-cap-schema", type=Path)
    p.add_argument("--emit-record", metavar="PAIR")
    p.add_argument("--classify", metavar="TA:TB:TPAR")
    p.add_argument("--accept-hardware", metavar="ID")
    p.add_argument("--project-pairs", type=Path)
    p.add_argument("--out", type=Path, default=_CATALOG_PATH.parent)
    p.add_argument("--query-cap", metavar="PAIR")
    p.add_argument("--cap-catalog", type=Path, default=_CATALOG_PATH)
    p.add_argument("--print-mem-schema", action="store_true")
    p.add_argument("--analyze-mem", type=Path)
    p.add_argument("--print-cc-phase-schema", action="store_true")
    p.add_argument("--analyze-cc-phase", type=Path)
    p.add_argument("--print-cc-size-schema", action="store_true")
    p.add_argument("--analyze-cc-size", type=Path)
    p.add_argument("--hardware", default="ascend910b")
    args = p.parse_args()
    n = sum(
        bool(x)
        for x in (
            args.print_cap_schema_v1,
            args.print_workload_contract,
            args.check_schema_identity,
            args.analyze_cap_schema,
            args.emit_record,
            args.classify,
            args.accept_hardware,
            args.project_pairs,
            args.query_cap,
            args.print_mem_schema,
            args.analyze_mem,
            args.print_cc_phase_schema,
            args.analyze_cc_phase,
            args.print_cc_size_schema,
            args.analyze_cc_size,
        )
    )
    if n != 1:
        print(
            "record_ascend: choose one of --print-cap-schema-v1, "
            "--print-workload-contract, --check-schema-identity, "
            "--analyze-cap-schema, --emit-record, --classify, "
            "--accept-hardware, --project-pairs, --query-cap, "
            "--print-mem-schema, --analyze-mem, "
            "--print-cc-phase-schema, --analyze-cc-phase, "
            "--print-cc-size-schema, --analyze-cc-size",
            file=sys.stderr,
        )
        return 2
    if args.print_cap_schema_v1:
        return print_cap_schema_v1()
    if args.print_workload_contract:
        return print_workload_contract()
    if args.check_schema_identity:
        return check_schema_identity()
    if args.analyze_cap_schema:
        return analyze_records(args.analyze_cap_schema)
    if args.emit_record:
        if args.emit_record not in PAIRS:
            print(f"record_ascend: unknown pair {args.emit_record}", file=sys.stderr)
            return 2
        rec = blank_cap_record(args.emit_record)
        errors = validate_cap_schema_v1(rec)
        if errors:
            print(f"record_ascend: invalid emit {errors}", file=sys.stderr)
            return 4
        print(json.dumps(rec, ensure_ascii=True, separators=(",", ":")))
        print(
            f"record_ascend emit-record pair={args.emit_record} "
            "confidence=unknown pair_relation=underdetermined"
        )
        return 0
    if args.classify:
        parts = args.classify.split(":")
        if len(parts) != 3:
            print("record_ascend: classify wants ta:tb:tpar", file=sys.stderr)
            return 2
        ta, tb, tpar = (float(x) for x in parts)
        rel = classify(ta, tb, tpar)
        print(f"record_ascend classify pair_relation={rel}")
        print("record_ascend classify cost=unchanged")
        return 0
    if args.project_pairs:
        return project_pairs(args.project_pairs, args.out)
    if args.query_cap:
        return query_cap(args.query_cap, args.cap_catalog, args.hardware)
    if args.print_mem_schema:
        return print_mem_schema()
    if args.analyze_mem:
        return analyze_mem(args.analyze_mem)
    if args.print_cc_phase_schema:
        return print_cc_phase_schema()
    if args.analyze_cc_phase:
        return analyze_cc_phase(args.analyze_cc_phase)
    if args.print_cc_size_schema:
        return print_cc_size_schema()
    if args.analyze_cc_size:
        return analyze_cc_size(args.analyze_cc_size)
    return accept_hardware(args.accept_hardware)


if __name__ == "__main__":
    sys.exit(main())
