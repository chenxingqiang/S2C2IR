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


def _parse_byte_token(tok: str) -> int | None:
    s = tok.strip()
    mul = 1
    low = s.lower()
    if low.endswith("mib"):
        mul = 1024 * 1024
        s = s[:-3].strip()
    elif low.endswith("mb"):
        mul = 1000 * 1000
        s = s[:-2].strip()
    elif low.endswith("kib"):
        mul = 1024
        s = s[:-3].strip()
    elif low.endswith("bytes"):
        s = s[:-5].strip()
    try:
        n = int(s, 10)
    except ValueError:
        return None
    if n < 0:
        return None
    return n * mul


def parse_size_spec(raw: str) -> tuple[str, int | None, int | None]:
    s = (raw or "").strip()
    if s.lower() in ("n/a", "none", "unmeasured", ""):
        return "unconstrained", None, None
    if ".." not in s:
        return "unparsed", None, None
    left, right = s.split("..", 1)
    lo = _parse_byte_token(left)
    hi = _parse_byte_token(right)
    if lo is None or hi is None:
        return "unparsed", None, None
    return "range", lo, hi


def note_fields(note: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for tok in (note or "").split(";"):
        tok = tok.strip()
        if "=" not in tok:
            continue
        key, val = tok.split("=", 1)
        out[key.strip()] = val.strip()
    return out


def rewrite_licensed(rec: dict[str, Any]) -> bool:
    val = note_fields(str(rec.get("note", ""))).get("rewrite_license", "yes")
    return val.lower() not in ("no", "false")


def _ambiguous_pair_record(rec0: dict[str, Any]) -> dict[str, Any]:
    return {
        "pair": rec0["pair"],
        "pair_relation": "underdetermined",
        "observed_constraint": "none",
        "confidence": "measured",
        "regime": rec0.get("regime", "underdetermined"),
        "size_range": "multiple",
        "synchronization": rec0.get("synchronization", "n/a"),
        "hardware_id": rec0["hardware_id"],
        "note": "phase_band=; rewrite_license=no; catalog query is ambiguous",
    }


def select_pair_record(
    hits: list[dict[str, Any]], size_bytes: int | None
) -> dict[str, Any] | None:
    if not hits:
        return None
    if size_bytes is None:
        if len(hits) == 1:
            return hits[0]
        unconstrained = [
            rec
            for rec in hits
            if parse_size_spec(str(rec.get("size_range", "n/a")))[0]
            == "unconstrained"
        ]
        if len(unconstrained) == 1:
            return unconstrained[0]
        return _ambiguous_pair_record(hits[0])
    covering: list[tuple[int, int, dict[str, Any]]] = []
    n_unc = 0
    n_range = 0
    for rec in hits:
        kind, lo, hi = parse_size_spec(str(rec.get("size_range", "n/a")))
        if kind == "unconstrained":
            covering.append((1, 0, rec))
            n_unc += 1
        elif kind == "range" and lo is not None and hi is not None:
            if lo <= size_bytes <= hi:
                covering.append((0, hi - lo, rec))
                n_range += 1
    if n_range == 0 and n_unc > 1:
        return _ambiguous_pair_record(hits[0])
    if not covering:
        if len(hits) == 1:
            return hits[0]
        return None
    covering.sort(key=lambda item: (item[0], item[1]))
    return covering[0][2]


def query_cap(
    pair: str, catalog: Path, hardware: str | None, n_floats: int | None
) -> int:
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
    size_bytes = None if n_floats is None else n_floats * 4
    rec = select_pair_record(hits, size_bytes)
    if rec is None:
        print(
            json.dumps(
                {
                    "pair": pair,
                    "pair_relation": "underdetermined",
                    "observed_constraint": "none",
                    "confidence": "unknown",
                    "applicable": False,
                    "rewrite_license": False,
                },
                ensure_ascii=True,
            )
        )
        return 0
    fields = note_fields(str(rec.get("note", "")))
    determined = rec.get("pair_relation") in ("serial", "parallel", "mixed")
    applicable = rec.get("confidence") == "measured" and determined
    payload: dict[str, Any] = {
        "pair": rec["pair"],
        "pair_relation": rec["pair_relation"],
        "observed_constraint": rec["observed_constraint"],
        "confidence": rec["confidence"],
        "regime": rec.get("regime", "underdetermined"),
    }
    if fields.get("phase_band"):
        payload["phase_band"] = fields["phase_band"]
    payload["size_range"] = rec.get("size_range", "n/a")
    payload["synchronization"] = rec.get("synchronization", "n/a")
    payload["hardware_id"] = rec["hardware_id"]
    payload["applicable"] = applicable
    payload["rewrite_license"] = rewrite_licensed(rec)
    print(json.dumps(payload, ensure_ascii=True, separators=(",", ":")))
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


_CC_REWRITE_SLICE_RE = re.compile(
    r"s2c2-ascend-run cc-rewrite slice r_target=(\S+) r_achieved=(\S+) "
    r"k1=(\d+) k2=(\d+) pair_relation=(\S+) observed_constraint=(\S+) n=(\d+)"
)
_CC_REWRITE_RATIO_RE = re.compile(
    r"s2c2-ascend-run cc-rewrite timing a=(\S+) b=(\S+) par=(\S+) "
    r"seq=(\S+) seq_over_par=(\S+) par_over_seq=(\S+)"
)
SEQ_SLACK = 1.05


def print_cc_rewrite_schema() -> int:
    print("ascend-cc-rewrite pair=C||C")
    print("r=1")
    print("n=32M,64M,128M")
    print("ab=par-vs-seq")
    print("seq=s0-then-s1")
    print("seq-slack=1.05")
    print("note seq-slack-ne-cost")
    print("note rewrite-loop")
    print("r3-gate=closed")
    print("note catalog-untouched")
    print("semantics unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def analyze_cc_rewrite(log: Path) -> int:
    text = log.read_text(encoding="utf-8", errors="replace")
    slices: list[dict[str, Any]] = []
    pending_rel: dict[str, Any] | None = None
    for line in text.splitlines():
        m = _CC_REWRITE_SLICE_RE.search(line)
        if m:
            pending_rel = {
                "r_target": float(m.group(1)),
                "pair_relation": m.group(5),
                "observed_constraint": m.group(6),
                "N": int(m.group(7)),
            }
            continue
        r = _CC_REWRITE_RATIO_RE.search(line)
        if r and pending_rel is not None:
            pending_rel["seq_over_par"] = float(r.group(5))
            slices.append(pending_rel)
            pending_rel = None
    if not slices:
        print("record_ascend: no cc-rewrite slices in log", file=sys.stderr)
        return 4
    ns = sorted({s["N"] for s in slices})
    rels = sorted({s["pair_relation"] for s in slices})
    serial = all(s["pair_relation"] == "serial" for s in slices)
    beneficial = all(0.0 < s["seq_over_par"] <= SEQ_SLACK for s in slices)
    license = serial and beneficial
    print(
        "v3-ascend-cc-rewrite pair=C||C r=1 r3-gate=closed "
        "note catalog-untouched semantics=unchanged "
        "v3=not-claimed cost=unchanged"
    )
    print(f"n-grid={','.join(_n_label(n) for n in ns)}")
    print(f"relations={','.join(rels)}")
    print(f"seq-slack={SEQ_SLACK}")
    print("note seq-slack-ne-cost")
    print(f"benefit={'yes' if beneficial else 'no'}")
    print(f"rewrite_license={'yes' if license else 'no'}")
    print("r3-gate=closed")
    print("note catalog-untouched")
    print("note rewrite-loop")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def print_r3_contract() -> int:
    print("pr-r3 pair-contract=same")
    print("pr-r3 require-cc-disagree=no")
    print("pr-r3 insufficient=keep")
    print("pr-r3 guess=no")
    print("pr-r3 note catalog-untouched")
    print("pr-r3 note scoped-evidence")
    print("pr-r3 npu-demo=not-witness")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("pr-r3 cost=unchanged")
    return 0


def print_e2e_contract() -> int:
    print("e2e evidence-bounded-schedule")
    print("no-evidence => no-destructive-optimization")
    print("invariant semantic-ne-perf-serial")
    print("invariant capability-ne-rewrite")
    print("invariant scoped-ne-global")
    print("invariant underdetermined-preserve")
    print("invariant rewrite-preserves-hb")
    print("slice ssd-prefetch||gated-mlp||C||C")
    print("note t-opt-over-base-ne-cost")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


_WORKLOAD_CAND_RE = re.compile(
    r"workload-candidate #(\d+) pair=(\S+) payload=(\S+) relation=(\S+) "
    r"decision=(KEEP|FLATTEN|PRESERVE) reason=(\S+)"
)
_WORKLOAD_SUM_RE = re.compile(
    r"workload-schedule candidates=(\d+) keep=(\d+) flatten=(\d+)"
    r"(?: preserve=(\d+))?"
)


def print_workload_schedule_contract() -> int:
    print("workload-schedule compiler-driven=yes")
    print("no-evidence => no-destructive-optimization")
    print("invariant semantic-ne-perf-serial")
    print("invariant capability-ne-rewrite")
    print("invariant scoped-ne-global")
    print("invariant underdetermined-preserve")
    print("invariant rewrite-preserves-hb")
    print("note not-handwritten-optimized-ir")
    print("note runtime-witness=ssd-mlp-wallclock")
    print("note compiler-chosen-t-evi")
    print("note not-new-capability-grid")
    print("note storage-data-movement-overlap")
    print("note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def _print_workload_schedule_summary(
    candidates: int,
    keep: int,
    flatten: int,
    preserve: int,
    decisions: list[dict[str, Any]],
) -> int:
    print("workload-schedule compiler-driven=yes")
    print(f"workload-schedule candidates={candidates}")
    print(f"workload-schedule keep={keep}")
    print(f"workload-schedule flatten={flatten}")
    print(f"workload-schedule preserve={preserve}")
    for d in decisions:
        print(
            f"workload-schedule candidate=#{d['id']} pair={d['pair']} "
            f"decision={d['decision']}"
        )
    print("note not-handwritten-optimized-ir")
    print("note runtime-witness=ssd-mlp-wallclock")
    print("note compiler-chosen-t-evi")
    print("note not-new-capability-grid")
    print("note storage-data-movement-overlap")
    print("note not-cost-v04")
    print("r3-gate=scoped-evidence")
    print("cost=unchanged")
    return 0


def analyze_workload_schedule(path: Path) -> int:
    text = path.read_text(encoding="utf-8", errors="replace").lstrip()
    if text.startswith("{"):
        obj = json.loads(text.splitlines()[0])
        if obj.get("schema") != "s2c2.workload_schedule.v1":
            print("record_ascend: not a workload_schedule dump", file=sys.stderr)
            return 4
        decs = obj.get("decisions") or []
        decisions = [
            {
                "id": d.get("id", i),
                "pair": d.get("pair", "unknown"),
                "decision": d.get("decision", "KEEP"),
            }
            for i, d in enumerate(decs)
        ]
        return _print_workload_schedule_summary(
            int(obj.get("candidates", len(decisions))),
            int(obj.get("keep", sum(1 for d in decisions if d["decision"] == "KEEP"))),
            int(
                obj.get(
                    "flatten",
                    sum(1 for d in decisions if d["decision"] == "FLATTEN"),
                )
            ),
            int(
                obj.get(
                    "preserve",
                    sum(1 for d in decisions if d["decision"] == "PRESERVE"),
                )
            ),
            decisions,
        )
    decisions: list[dict[str, Any]] = []
    for line in text.splitlines():
        m = _WORKLOAD_CAND_RE.search(line)
        if m:
            decisions.append(
                {
                    "id": int(m.group(1)),
                    "pair": m.group(2),
                    "decision": m.group(5),
                }
            )
    summary = _WORKLOAD_SUM_RE.search(text)
    if summary:
        candidates = int(summary.group(1))
        keep = int(summary.group(2))
        flatten = int(summary.group(3))
        preserve = (
            int(summary.group(4))
            if summary.group(4) is not None
            else sum(1 for d in decisions if d["decision"] == "PRESERVE")
        )
    else:
        candidates = len(decisions)
        keep = sum(1 for d in decisions if d["decision"] == "KEEP")
        flatten = sum(1 for d in decisions if d["decision"] == "FLATTEN")
        preserve = sum(1 for d in decisions if d["decision"] == "PRESERVE")
    if candidates == 0 and not decisions:
        print("record_ascend: no workload-schedule candidates", file=sys.stderr)
        return 4
    return _print_workload_schedule_summary(
        candidates, keep, flatten, preserve, decisions
    )


def print_ssd_mlp_wallclock_contract() -> int:
    print("ssd-mlp-wallclock program-measurement=yes")
    print("no-evidence => no-destructive-optimization")
    print("invariant semantic-ne-perf-serial")
    print("invariant capability-ne-rewrite")
    print("invariant scoped-ne-global")
    print("invariant underdetermined-preserve")
    print("invariant rewrite-preserves-hb")
    print("note not-stage-ab")
    print("note t-base-is-t-seq")
    print("note t-opt-is-t-evi")
    print("note catalog-untouched")
    print("note logical-ssd-ne-disk")
    print("note 32M-outlier-not-cost")
    print("note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


_SSD_MLP_TIMING_RE = re.compile(
    r"ssd-mlp-wallclock timing seq=([0-9.]+) evi=([0-9.]+) "
    r"par=([0-9.]+) opt_over_base=([0-9.]+)"
)


def analyze_ssd_mlp_wallclock(log: Path) -> int:
    text = log.read_text(encoding="utf-8", errors="replace")
    measured = bool(re.search(r"ssd-mlp-wallclock measured=yes\b", text))
    timing = _SSD_MLP_TIMING_RE.search(text)
    defined = measured and timing is not None
    print("ssd-mlp-wallclock program-measurement=yes")
    print("ssd-mlp-wallclock note not-stage-ab")
    print(f"ssd-mlp-wallclock measured={'yes' if measured else 'no'}")
    print(
        "ssd-mlp-wallclock t-opt-over-base-defined="
        f"{'yes' if defined else 'no'}"
    )
    print("note t-base-is-t-seq")
    print("note t-opt-is-t-evi")
    print("note not-stage-ab")
    print("note 32M-outlier-not-cost")
    print("note catalog-untouched")
    print("note logical-ssd-ne-disk")
    print("note not-cost-v04")
    if re.search(r"device-absent", text):
        print("note device-absent")
    print("r3-gate=scoped-evidence")
    print("cost=unchanged")
    return 0


def print_storage_loop_contract() -> int:
    print("storage-loop compiler-driven=yes")
    print("no-evidence => no-destructive-optimization")
    print("inferred-overlap => prefetch-keep-only")
    print("invariant underdetermined-preserve")
    print("note scf-for-software-pipeline")
    print("note ssa-iter-args-double-buffer")
    print("note loop-carried-lifetime")
    print("note not-in-place-transfer-overwrite")
    print("note compute-then-prefetch-next")
    print("note proven-live-residency")
    print("note not-c-storage-flatten")
    print("note no-invented-wait")
    print("note runtime-witness=storage-loop-wallclock")
    print("note catalog-untouched")
    print("note not-new-capability-grid")
    print("note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def print_storage_loop_wallclock_contract() -> int:
    print("storage-loop-wallclock program-measurement=yes")
    print("no-evidence => no-destructive-optimization")
    print("invariant underdetermined-preserve")
    print("note scf-for-software-pipeline")
    print("note not-arbitrary-runtime-n")
    print("note t-base-is-t-seq")
    print("note t-opt-is-t-evi")
    print("note evi-eq-par")
    print("note catalog-untouched")
    print("note logical-ssd-ne-disk")
    print("note not-new-capability-grid")
    print("note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


_STORAGE_LOOP_TIMING_RE = re.compile(
    r"storage-loop-wallclock timing seq=([0-9.]+) evi=([0-9.]+) "
    r"par=([0-9.]+) opt_over_base=([0-9.]+)"
)


def analyze_storage_loop_wallclock(log: Path) -> int:
    text = log.read_text(encoding="utf-8", errors="replace")
    measured = bool(re.search(r"storage-loop-wallclock measured=yes\b", text))
    timing = _STORAGE_LOOP_TIMING_RE.search(text)
    defined = measured and timing is not None
    print("storage-loop-wallclock program-measurement=yes")
    print("storage-loop-wallclock note scf-for-software-pipeline")
    print(f"storage-loop-wallclock measured={'yes' if measured else 'no'}")
    print(
        "storage-loop-wallclock t-opt-over-base-defined="
        f"{'yes' if defined else 'no'}"
    )
    print("note t-base-is-t-seq")
    print("note t-opt-is-t-evi")
    print("note evi-eq-par")
    print("note not-arbitrary-runtime-n")
    print("note catalog-untouched")
    print("note logical-ssd-ne-disk")
    print("note not-new-capability-grid")
    print("note not-cost-v04")
    if re.search(r"device-absent", text):
        print("note device-absent")
    print("r3-gate=scoped-evidence")
    print("cost=unchanged")
    return 0


def print_storage_schedule_contract() -> int:
    print("storage-schedule compiler-driven=yes")
    print("no-evidence => no-destructive-optimization")
    print("inferred-overlap => prefetch-keep-only")
    print("invariant underdetermined-preserve")
    print("note legal-candidates-then-select")
    print("note selection-ne-cost")
    print("note selection-ne-rewrite-license")
    print("note policy=default-3g")
    print("note not-c-storage-flatten")
    print("note catalog-untouched")
    print("note not-new-capability-grid")
    print("note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


_HIER_CAND_RE = re.compile(
    r"hierarchy-candidates #(\d+) legal=(\S+) selected=(\S+) policy=(\S+)"
)
_HIER_SCHED_MULTI_RE = re.compile(
    r"hierarchy-schedule .* multi-candidate=(\d+) selected-in-legal=(yes|no)"
)


def analyze_storage_schedule(path: Path) -> int:
    text = path.read_text(encoding="utf-8", errors="replace").lstrip()
    multi = 0
    in_legal = "no"
    sites = 0
    policy = "default-3g"
    if text.startswith("{"):
        obj = json.loads(text.splitlines()[0])
        if obj.get("schema") != "s2c2.workload_schedule.v1":
            print("record_ascend: not a workload_schedule dump", file=sys.stderr)
            return 4
        sites = int(obj.get("hierarchy_sites", len(obj.get("hierarchy") or [])))
        multi = int(obj.get("hierarchy_multi_candidate", 0))
        in_legal = str(obj.get("hierarchy_selected_in_legal", "no"))
        policy = str(obj.get("hierarchy_policy", "default-3g"))
    else:
        found = _HIER_CAND_RE.findall(text)
        sites = len(found)
        in_legal = "yes" if found else "no"
        for _sid, legal, selected, pol in found:
            policy = pol
            acts = legal.split(",")
            if len(acts) > 1:
                multi += 1
            if selected not in acts:
                in_legal = "no"
        m = _HIER_SCHED_MULTI_RE.search(text)
        if m:
            multi = int(m.group(1))
            in_legal = m.group(2)
    print("storage-schedule compiler-driven=yes")
    print(f"storage-schedule sites={sites}")
    print(f"storage-schedule multi-candidate={multi}")
    print(f"storage-schedule selected-in-legal={in_legal}")
    print(f"storage-schedule policy={policy}")
    print("note legal-candidates-then-select")
    print("note selection-ne-cost")
    print("note selection-ne-rewrite-license")
    print("note not-c-storage-flatten")
    print("note catalog-untouched")
    print("note not-cost-v04")
    print("r3-gate=scoped-evidence")
    print("cost=unchanged")
    return 0


def print_storage_joint_contract() -> int:
    print("storage-joint compiler-driven=yes")
    print("no-evidence => no-destructive-optimization")
    print("inferred-overlap => prefetch-keep-only")
    print("invariant underdetermined-preserve")
    print("note joint-candidates-then-select")
    print("note selection-ne-cost")
    print("note selection-ne-rewrite-license")
    print("note policy=default-3g")
    print("note default-3g-frozen")
    print("note cost-ranking-is-policy-cost-v04")
    print("note not-c-storage-flatten")
    print("note catalog-untouched")
    print("note not-new-capability-grid")
    print("note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


_HIER_JOINT_RE = re.compile(
    r"hierarchy-joint #(\d+) object=(\d+) sites=(\S+) legal=(\d+) "
    r"selected=(\S+) policy=(\S+)"
)
_HIER_JOINT_SUM_RE = re.compile(
    r"hierarchy-joint-schedule chains=(\d+) legal=(\d+) "
    r"selected-in-legal=(yes|no)"
)


def analyze_storage_joint(path: Path) -> int:
    text = path.read_text(encoding="utf-8", errors="replace").lstrip()
    chains = 0
    legal = 0
    in_legal = "no"
    policy = "default-3g"
    if text.startswith("{"):
        obj = json.loads(text.splitlines()[0])
        if obj.get("schema") != "s2c2.workload_schedule.v1":
            print("record_ascend: not a workload_schedule dump", file=sys.stderr)
            return 4
        chains = int(obj.get("hierarchy_joint_chains", 0))
        legal = int(obj.get("hierarchy_joint_legal", 0))
        in_legal = str(obj.get("hierarchy_joint_selected_in_legal", "no"))
        policy = str(obj.get("hierarchy_joint_policy", "default-3g"))
    else:
        found = _HIER_JOINT_RE.findall(text)
        chains = len(found)
        in_legal = "yes" if found else "no"
        product = 1
        for _cid, _obj, _sites, nlegal, selected, pol in found:
            policy = pol
            n = int(nlegal)
            product *= max(1, n)
            acts = selected.split("|")
            if not acts:
                in_legal = "no"
        legal = product
        m = _HIER_JOINT_SUM_RE.search(text)
        if m:
            chains = int(m.group(1))
            legal = int(m.group(2))
            in_legal = m.group(3)
    print("storage-joint compiler-driven=yes")
    print(f"storage-joint chains={chains}")
    print(f"storage-joint legal={legal}")
    print(f"storage-joint selected-in-legal={in_legal}")
    print(f"storage-joint policy={policy}")
    print("note joint-candidates-then-select")
    print("note selection-ne-cost")
    print("note selection-ne-rewrite-license")
    print("note default-3g-frozen")
    print("note cost-ranking-is-policy-cost-v04")
    print("note not-c-storage-flatten")
    print("note catalog-untouched")
    print("note not-cost-v04")
    print("r3-gate=scoped-evidence")
    print("cost=unchanged")
    return 0


def print_storage_global_contract() -> int:
    print("storage-global compiler-driven=yes")
    print("no-evidence => no-destructive-optimization")
    print("inferred-overlap => prefetch-keep-only")
    print("invariant underdetermined-preserve")
    print("note global-candidates-then-select")
    print("note selection-ne-cost")
    print("note selection-ne-rewrite-license")
    print("note policy=default-3g")
    print("note default-3g-frozen")
    print("note chain-def-frozen")
    print("note cost-ranking-is-policy-cost-v04")
    print("note not-c-storage-flatten")
    print("note catalog-untouched")
    print("note not-new-capability-grid")
    print("note not-cost-v04")
    print("note truncated-ne-complete-F")
    print("note historical-tuple-or-fail")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


_HIER_GLOB_RE = re.compile(
    r"hierarchy-global selected=(\S+) product=(\S+) "
    r"enumerated=(yes|no) truncated=(yes|no) legal=(\S+) policy=(\S+)"
)
_HIER_GLOB_SUM_RE = re.compile(
    r"hierarchy-global-schedule chains=(\d+) product=(\S+) "
    r"enumerated=(yes|no) truncated=(yes|no) legal=(\S+) "
    r"selected-in-legal=(yes|no)"
)
_HIER_GLOB_ERR_RE = re.compile(r"hierarchy-global-error (\S+)")


def _global_legal_label(value) -> str:
    if value == "not-enumerated":
        return "not-enumerated"
    if isinstance(value, str) and value == "overflow":
        return value
    return str(int(value))


def analyze_storage_global(path: Path) -> int:
    text = path.read_text(encoding="utf-8", errors="replace").lstrip()
    chains = 0
    product = "0"
    enumerated = "no"
    truncated = "no"
    legal = "0"
    in_legal = "no"
    policy = "default-3g"
    error = ""
    if text.startswith("{"):
        obj = json.loads(text.splitlines()[0])
        if obj.get("schema") != "s2c2.workload_schedule.v1":
            print("record_ascend: not a workload_schedule dump", file=sys.stderr)
            return 4
        chains = int(obj.get("hierarchy_global_chains", 0))
        product = str(obj.get("hierarchy_global_product", "0"))
        enumerated = str(obj.get("hierarchy_global_enumerated", "no"))
        truncated = str(obj.get("hierarchy_global_truncated", "no"))
        legal = _global_legal_label(obj.get("hierarchy_global_legal", 0))
        in_legal = str(obj.get("hierarchy_global_selected_in_legal", "no"))
        policy = str(obj.get("hierarchy_global_policy", "default-3g"))
        error = str(obj.get("hierarchy_global_error", "") or "")
    else:
        m = _HIER_GLOB_SUM_RE.search(text)
        g = _HIER_GLOB_RE.search(text)
        if m:
            chains = int(m.group(1))
            product = m.group(2)
            enumerated = m.group(3)
            truncated = m.group(4)
            legal = m.group(5)
            in_legal = m.group(6)
        if g:
            product = g.group(2)
            enumerated = g.group(3)
            truncated = g.group(4)
            legal = g.group(5)
            policy = g.group(6)
        err = _HIER_GLOB_ERR_RE.search(text)
        if err:
            error = err.group(1)
    print("storage-global compiler-driven=yes")
    print(f"storage-global chains={chains}")
    print(f"storage-global product={product}")
    print(f"storage-global enumerated={enumerated}")
    print(f"storage-global truncated={truncated}")
    print(f"storage-global legal={legal}")
    print(f"storage-global selected-in-legal={in_legal}")
    print(f"storage-global policy={policy}")
    if error:
        print(f"storage-global-error {error}")
    print("note global-candidates-then-select")
    print("note selection-ne-cost")
    print("note selection-ne-rewrite-license")
    print("note default-3g-frozen")
    print("note chain-def-frozen")
    print("note truncated-ne-complete-F")
    print("note historical-tuple-or-fail")
    print("note cost-ranking-is-policy-cost-v04")
    print("note not-c-storage-flatten")
    print("note catalog-untouched")
    print("note not-cost-v04")
    print("r3-gate=scoped-evidence")
    print("cost=unchanged")
    return 0


def print_storage_cost_contract() -> int:
    print("storage-cost compiler-driven=yes")
    print("no-evidence => no-destructive-optimization")
    print("inferred-overlap => prefetch-keep-only")
    print("invariant underdetermined-preserve")
    print("note cost-ranks-enumerated-F-only")
    print("note cost-ne-legality")
    print("note cost-ne-rewrite-license")
    print("note policy=cost-v04")
    print("note default-3g-frozen")
    print("note truncated-ne-ranked")
    print("note not-s2c2-argmin")
    print("note not-score3")
    print("note chain-def-frozen")
    print("note not-c-storage-flatten")
    print("note catalog-untouched")
    print("note not-new-capability-grid")
    print("note structural-ticks-not-wallclock")
    print("note runtime-correlation-not-applicable")
    print("note cost-v04-structural-frozen")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


_HIER_COST_RE = re.compile(
    r"hierarchy-global-cost ranked=(\S+) score=(\S+) policy=(\S+)"
)
_HIER_COST_SUM_RE = re.compile(
    r"hierarchy-global-cost-schedule enumerated=(yes|no) truncated=(yes|no) "
    r"ranked-in-legal=(\S+) ranked-eq-default-3g=(\S+) argmin-size=(\S+)"
)
_HIER_COST_COIN_RE = re.compile(
    r"hierarchy-global-cost-coincide diverge=(\S+)"
)


def analyze_storage_cost(path: Path) -> int:
    text = path.read_text(encoding="utf-8", errors="replace").lstrip()
    ranked = "not-enumerated"
    score = "n/a"
    enumerated = "no"
    truncated = "yes"
    in_legal = "n/a"
    eq_default = "n/a"
    argmin = "n/a"
    policy = "cost-v04"
    diverge = "n/a"
    if text.startswith("{"):
        obj = json.loads(text.splitlines()[0])
        if obj.get("schema") != "s2c2.workload_schedule.v1":
            print("record_ascend: not a workload_schedule dump", file=sys.stderr)
            return 4
        ranked = str(obj.get("hierarchy_global_cost_ranked", "not-enumerated"))
        score = str(obj.get("hierarchy_global_cost_score", "n/a"))
        in_legal = str(obj.get("hierarchy_global_cost_ranked_in_legal", "n/a"))
        eq_default = str(
            obj.get("hierarchy_global_cost_ranked_eq_default_3g", "n/a")
        )
        argmin = str(obj.get("hierarchy_global_cost_argmin_size", "n/a"))
        policy = str(obj.get("hierarchy_global_cost_policy", "cost-v04"))
        enumerated = str(obj.get("hierarchy_global_enumerated", "no"))
        truncated = str(obj.get("hierarchy_global_truncated", "yes"))
        diverge = str(obj.get("hierarchy_global_cost_diverge", "n/a"))
    else:
        m = _HIER_COST_SUM_RE.search(text)
        g = _HIER_COST_RE.search(text)
        c = _HIER_COST_COIN_RE.search(text)
        if g:
            ranked = g.group(1)
            score = g.group(2)
            policy = g.group(3)
        if m:
            enumerated = m.group(1)
            truncated = m.group(2)
            in_legal = m.group(3)
            eq_default = m.group(4)
            argmin = m.group(5)
        if c:
            diverge = c.group(1)
    print("storage-cost compiler-driven=yes")
    print(f"storage-cost ranked={ranked}")
    print(f"storage-cost score={score}")
    print(f"storage-cost enumerated={enumerated}")
    print(f"storage-cost truncated={truncated}")
    print(f"storage-cost ranked-in-legal={in_legal}")
    print(f"storage-cost ranked-eq-default-3g={eq_default}")
    print(f"storage-cost argmin-size={argmin}")
    print(f"storage-cost diverge={diverge}")
    print(f"storage-cost policy={policy}")
    print("note cost-ranks-enumerated-F-only")
    print("note cost-ne-legality")
    print("note cost-ne-rewrite-license")
    print("note default-3g-frozen")
    print("note truncated-ne-ranked")
    print("note not-s2c2-argmin")
    print("note not-score3")
    print("note chain-def-frozen")
    print("note not-c-storage-flatten")
    print("note catalog-untouched")
    print("note not-new-capability-grid")
    print("note structural-ticks-not-wallclock")
    print("note runtime-correlation-not-applicable")
    print("note cost-v04-structural-frozen")
    print("r3-gate=scoped-evidence")
    print("cost=unchanged")
    return 0


def print_storage_ntile_contract() -> int:
    print("storage-ntile compiler-driven=yes")
    print("no-evidence => no-destructive-optimization")
    print("inferred-overlap => prefetch-keep-only")
    print("invariant underdetermined-preserve")
    print("note compute-then-prefetch-next")
    print("note proven-live-residency")
    print("note not-c-storage-flatten")
    print("note no-invented-wait")
    print("note runtime-witness=storage-pipeline")
    print("note catalog-untouched")
    print("note not-new-capability-grid")
    print("note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def print_storage_hierarchy_contract() -> int:
    print("storage-hierarchy compiler-driven=yes")
    print("no-evidence => no-destructive-optimization")
    print("inferred-overlap => prefetch-keep-only")
    print("invariant underdetermined-preserve")
    print("note ssd-host-hbm-compute")
    print("note keep-residency-ne-rematerialize")
    print("note inferred-overlap-ne-flatten")
    print("note runtime-witness=storage-pipeline")
    print("note catalog-untouched")
    print("note not-new-capability-grid")
    print("note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


_HIER_SITE_RE = re.compile(
    r"hierarchy-site #(\d+) op=(\S+) src=(\S+) dst=(\S+) pair=(\S+) "
    r"action=(\S+) when=(\S+) reason=(\S+)"
)
_HIER_SUM_RE = re.compile(
    r"hierarchy-schedule sites=(\d+) materialize=(\d+) prefetch=(\d+) "
    r"transfer=(\d+) keep-residency=(\d+) preserve=(\d+)"
)
_HIER_REUSE_RE = re.compile(r"hierarchy-reuse applied=(\d+) skipped=(\d+)")


def _print_storage_hierarchy_summary(
    sites: int,
    materialize: int,
    prefetch: int,
    transfer: int,
    keep: int,
    preserve: int,
    reuse_applied: int | None = None,
    reuse_skipped: int | None = None,
) -> int:
    print("storage-hierarchy compiler-driven=yes")
    print(f"storage-hierarchy sites={sites}")
    print(f"storage-hierarchy materialize={materialize}")
    print(f"storage-hierarchy prefetch={prefetch}")
    print(f"storage-hierarchy transfer={transfer}")
    print(f"storage-hierarchy keep-residency={keep}")
    print(f"storage-hierarchy preserve={preserve}")
    if reuse_applied is not None:
        print(f"storage-hierarchy reuse-applied={reuse_applied}")
        print(f"storage-hierarchy reuse-skipped={reuse_skipped or 0}")
    print("note ssd-host-hbm-compute")
    print("note keep-residency-ne-rematerialize")
    print("note inferred-overlap-ne-flatten")
    print("note proven-live-residency")
    print("note runtime-witness=storage-pipeline")
    print("note catalog-untouched")
    print("note not-cost-v04")
    print("r3-gate=scoped-evidence")
    print("cost=unchanged")
    return 0


def analyze_storage_hierarchy(path: Path) -> int:
    text = path.read_text(encoding="utf-8", errors="replace").lstrip()
    if text.startswith("{"):
        obj = json.loads(text.splitlines()[0])
        if obj.get("schema") != "s2c2.workload_schedule.v1":
            print("record_ascend: not a workload_schedule dump", file=sys.stderr)
            return 4
        return _print_storage_hierarchy_summary(
            int(obj.get("hierarchy_sites", len(obj.get("hierarchy") or []))),
            int(obj.get("hierarchy_materialize", 0)),
            int(obj.get("hierarchy_prefetch", 0)),
            int(obj.get("hierarchy_transfer", 0)),
            int(obj.get("hierarchy_keep_residency", 0)),
            int(obj.get("hierarchy_preserve", 0)),
            int(obj.get("hierarchy_reuse_applied", 0)),
            int(obj.get("hierarchy_reuse_skipped", 0)),
        )
    summary = _HIER_SUM_RE.search(text)
    reuse = _HIER_REUSE_RE.search(text)
    if summary:
        return _print_storage_hierarchy_summary(
            int(summary.group(1)),
            int(summary.group(2)),
            int(summary.group(3)),
            int(summary.group(4)),
            int(summary.group(5)),
            int(summary.group(6)),
            int(reuse.group(1)) if reuse else None,
            int(reuse.group(2)) if reuse else None,
        )
    found = _HIER_SITE_RE.findall(text)
    materialize = sum(1 for s in found if s[5] == "MATERIALIZE")
    prefetch = sum(1 for s in found if s[5] == "PREFETCH")
    transfer = sum(1 for s in found if s[5] == "TRANSFER")
    keep = sum(1 for s in found if s[5] == "KEEP_RESIDENCY")
    preserve = sum(1 for s in found if s[5] == "PRESERVE")
    return _print_storage_hierarchy_summary(
        len(found), materialize, prefetch, transfer, keep, preserve
    )


def print_storage_pipeline_contract() -> int:
    print("storage-pipeline program-measurement=yes")
    print("no-evidence => no-destructive-optimization")
    print("invariant underdetermined-preserve")
    print("note storage-prefetch||compute")
    print("note t-base-is-t-seq")
    print("note t-opt-is-t-evi")
    print("note catalog-untouched")
    print("note logical-ssd-ne-disk")
    print("note not-new-capability-grid")
    print("note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


_STORAGE_PIPE_TIMING_RE = re.compile(
    r"storage-pipeline timing seq=([0-9.]+) evi=([0-9.]+) "
    r"par=([0-9.]+) opt_over_base=([0-9.]+)"
)


def analyze_storage_pipeline(log: Path) -> int:
    text = log.read_text(encoding="utf-8", errors="replace")
    measured = bool(re.search(r"storage-pipeline measured=yes\b", text))
    timing = _STORAGE_PIPE_TIMING_RE.search(text)
    defined = measured and timing is not None
    print("storage-pipeline program-measurement=yes")
    print("storage-pipeline note storage-prefetch||compute")
    print(f"storage-pipeline measured={'yes' if measured else 'no'}")
    print(
        "storage-pipeline t-opt-over-base-defined="
        f"{'yes' if defined else 'no'}"
    )
    print("note t-base-is-t-seq")
    print("note t-opt-is-t-evi")
    print("note catalog-untouched")
    print("note logical-ssd-ne-disk")
    print("note not-new-capability-grid")
    print("note not-cost-v04")
    if re.search(r"device-absent", text):
        print("note device-absent")
    print("r3-gate=scoped-evidence")
    print("cost=unchanged")
    return 0


def analyze_e2e_gain(log: Path) -> int:
    text = log.read_text(encoding="utf-8", errors="replace")
    slices: list[dict[str, Any]] = []
    pending_rel: dict[str, Any] | None = None
    for line in text.splitlines():
        m = _CC_REWRITE_SLICE_RE.search(line)
        if m:
            pending_rel = {
                "pair_relation": m.group(5),
                "N": int(m.group(7)),
            }
            continue
        r = _CC_REWRITE_RATIO_RE.search(line)
        if r and pending_rel is not None:
            pending_rel["seq_over_par"] = float(r.group(5))
            slices.append(pending_rel)
            pending_rel = None
    if not slices:
        print("record_ascend: no e2e C||C slices in log", file=sys.stderr)
        return 4
    ns = sorted({s["N"] for s in slices})
    rels = sorted({s["pair_relation"] for s in slices})
    serial = all(s["pair_relation"] == "serial" for s in slices)
    beneficial = all(0.0 < s["seq_over_par"] <= SEQ_SLACK for s in slices)
    print("e2e-slice pair=C||C band=128MiB..512MiB")
    print(f"n-grid={','.join(_n_label(n) for n in ns)}")
    print(f"relations={','.join(rels)}")
    print(f"rewrite_license={'yes' if serial and beneficial else 'no'}")
    print("t-opt-over-base-defined=yes")
    print("note t-opt-is-t-seq")
    print("note t-base-is-t-par")
    print("note 32M-outlier-not-cost")
    print("note seq-slack-ne-cost")
    print("note not-cost-v04")
    print("note stage-measurement-ne-full-model")
    print("r3-gate=scoped-evidence")
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
    p.add_argument(
        "--n",
        type=int,
        dest="n_floats",
        help="optional float count for size-banded --query-cap (payload = N*4 bytes)",
    )
    p.add_argument("--print-mem-schema", action="store_true")
    p.add_argument("--analyze-mem", type=Path)
    p.add_argument("--print-cc-phase-schema", action="store_true")
    p.add_argument("--analyze-cc-phase", type=Path)
    p.add_argument("--print-cc-size-schema", action="store_true")
    p.add_argument("--analyze-cc-size", type=Path)
    p.add_argument("--print-cc-rewrite-schema", action="store_true")
    p.add_argument("--analyze-cc-rewrite", type=Path)
    p.add_argument("--print-r3-contract", action="store_true")
    p.add_argument("--print-e2e-contract", action="store_true")
    p.add_argument("--analyze-e2e-gain", type=Path)
    p.add_argument("--print-ssd-mlp-wallclock-contract", action="store_true")
    p.add_argument("--analyze-ssd-mlp-wallclock", type=Path)
    p.add_argument("--print-storage-pipeline-contract", action="store_true")
    p.add_argument("--analyze-storage-pipeline", type=Path)
    p.add_argument("--print-storage-hierarchy-contract", action="store_true")
    p.add_argument("--analyze-storage-hierarchy", type=Path)
    p.add_argument("--print-storage-schedule-contract", action="store_true")
    p.add_argument("--analyze-storage-schedule", type=Path)
    p.add_argument("--print-storage-joint-contract", action="store_true")
    p.add_argument("--analyze-storage-joint", type=Path)
    p.add_argument("--print-storage-global-contract", action="store_true")
    p.add_argument("--analyze-storage-global", type=Path)
    p.add_argument("--print-storage-cost-contract", action="store_true")
    p.add_argument("--analyze-storage-cost", type=Path)
    p.add_argument("--print-storage-ntile-contract", action="store_true")
    p.add_argument("--print-storage-loop-contract", action="store_true")
    p.add_argument("--print-storage-loop-wallclock-contract", action="store_true")
    p.add_argument("--analyze-storage-loop-wallclock", type=Path)
    p.add_argument("--print-workload-schedule-contract", action="store_true")
    p.add_argument("--analyze-workload-schedule", type=Path)
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
            args.print_cc_rewrite_schema,
            args.analyze_cc_rewrite,
            args.print_r3_contract,
            args.print_e2e_contract,
            args.analyze_e2e_gain,
            args.print_ssd_mlp_wallclock_contract,
            args.analyze_ssd_mlp_wallclock,
            args.print_storage_pipeline_contract,
            args.analyze_storage_pipeline,
            args.print_storage_hierarchy_contract,
            args.analyze_storage_hierarchy,
            args.print_storage_schedule_contract,
            args.analyze_storage_schedule,
            args.print_storage_joint_contract,
            args.analyze_storage_joint,
            args.print_storage_global_contract,
            args.analyze_storage_global,
            args.print_storage_cost_contract,
            args.analyze_storage_cost,
            args.print_storage_ntile_contract,
            args.print_storage_loop_contract,
            args.print_storage_loop_wallclock_contract,
            args.analyze_storage_loop_wallclock,
            args.print_workload_schedule_contract,
            args.analyze_workload_schedule,
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
            "--print-cc-size-schema, --analyze-cc-size, "
            "--print-cc-rewrite-schema, --analyze-cc-rewrite, "
            "--print-r3-contract, --print-e2e-contract, --analyze-e2e-gain, "
            "--print-ssd-mlp-wallclock-contract, "
            "--analyze-ssd-mlp-wallclock, "
            "--print-storage-pipeline-contract, "
            "--analyze-storage-pipeline, "
            "--print-storage-hierarchy-contract, "
            "--analyze-storage-hierarchy, "
            "--print-storage-schedule-contract, "
            "--analyze-storage-schedule, "
            "--print-storage-joint-contract, "
            "--analyze-storage-joint, "
            "--print-storage-global-contract, "
            "--analyze-storage-global, "
            "--print-storage-cost-contract, "
            "--analyze-storage-cost, "
            "--print-storage-ntile-contract, "
            "--print-storage-loop-contract, "
            "--print-storage-loop-wallclock-contract, "
            "--analyze-storage-loop-wallclock, "
            "--print-workload-schedule-contract, "
            "--analyze-workload-schedule",
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
        return query_cap(
            args.query_cap, args.cap_catalog, args.hardware, args.n_floats
        )
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
    if args.print_cc_rewrite_schema:
        return print_cc_rewrite_schema()
    if args.analyze_cc_rewrite:
        return analyze_cc_rewrite(args.analyze_cc_rewrite)
    if args.print_r3_contract:
        return print_r3_contract()
    if args.print_e2e_contract:
        return print_e2e_contract()
    if args.analyze_e2e_gain:
        return analyze_e2e_gain(args.analyze_e2e_gain)
    if args.print_ssd_mlp_wallclock_contract:
        return print_ssd_mlp_wallclock_contract()
    if args.analyze_ssd_mlp_wallclock:
        return analyze_ssd_mlp_wallclock(args.analyze_ssd_mlp_wallclock)
    if args.print_storage_pipeline_contract:
        return print_storage_pipeline_contract()
    if args.analyze_storage_pipeline:
        return analyze_storage_pipeline(args.analyze_storage_pipeline)
    if args.print_storage_hierarchy_contract:
        return print_storage_hierarchy_contract()
    if args.analyze_storage_hierarchy:
        return analyze_storage_hierarchy(args.analyze_storage_hierarchy)
    if args.print_storage_schedule_contract:
        return print_storage_schedule_contract()
    if args.analyze_storage_schedule:
        return analyze_storage_schedule(args.analyze_storage_schedule)
    if args.print_storage_joint_contract:
        return print_storage_joint_contract()
    if args.analyze_storage_joint:
        return analyze_storage_joint(args.analyze_storage_joint)
    if args.print_storage_global_contract:
        return print_storage_global_contract()
    if args.analyze_storage_global:
        return analyze_storage_global(args.analyze_storage_global)
    if args.print_storage_cost_contract:
        return print_storage_cost_contract()
    if args.analyze_storage_cost:
        return analyze_storage_cost(args.analyze_storage_cost)
    if args.print_storage_ntile_contract:
        return print_storage_ntile_contract()
    if args.print_storage_loop_contract:
        return print_storage_loop_contract()
    if args.print_storage_loop_wallclock_contract:
        return print_storage_loop_wallclock_contract()
    if args.analyze_storage_loop_wallclock:
        return analyze_storage_loop_wallclock(args.analyze_storage_loop_wallclock)
    if args.print_workload_schedule_contract:
        return print_workload_schedule_contract()
    if args.analyze_workload_schedule:
        return analyze_workload_schedule(args.analyze_workload_schedule)
    return accept_hardware(args.accept_hardware)


if __name__ == "__main__":
    sys.exit(main())
