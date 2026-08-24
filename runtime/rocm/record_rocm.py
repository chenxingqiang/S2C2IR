#!/usr/bin/env python3
"""ROCm capability recorder (host). Same Schema v1 as CUDA. No hip_* keys."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[2]
_SCHEMA_PATH = _REPO_ROOT / "docs/design/v3-capability-schema.v1.json"

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
FORBIDDEN_KEYS = ("hip_", "amdgpu_", "password", "localhost")


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
    print("no-extra-key hip_amdgpu")
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
    return any(tok in s for tok in ("4090", "sm89", "rtx", "cuda"))


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
        compute, transfer, direction = "rocm_cu", "copy_engine", "host_to_device"
        src, dst = "pinned_host", "device_memory"
    elif pair == "C||C":
        compute = "rocm_cu"
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
        "evidence_refs": "backend-adapter-rocm.md",
        "v3": "not-claimed",
        "cost": "unchanged",
        "semantics": "unchanged",
    }


def check_schema_identity() -> int:
    if not _SCHEMA_PATH.is_file():
        print(f"record_rocm: missing {_SCHEMA_PATH}", file=sys.stderr)
        return 4
    schema = json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))
    required = tuple(schema.get("required", []))
    if required != CAP_SCHEMA_FIELDS:
        print(
            f"record_rocm: field mismatch {required} vs {CAP_SCHEMA_FIELDS}",
            file=sys.stderr,
        )
        return 4
    if schema.get("additionalProperties") is not False:
        print("record_rocm: schema must forbid extra keys", file=sys.stderr)
        return 4
    props = schema.get("properties", {})
    extra = [k for k in props if k.startswith("hip_") or k.startswith("amdgpu_")]
    if extra:
        print(f"record_rocm: schema grew vendor keys {extra}", file=sys.stderr)
        return 4
    print(
        "schema-identity v1 fields=21 additionalProperties=false "
        "no-extra-key=hip_amdgpu vendor=rocm-or-cuda "
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
        print("record_rocm: empty cap-schema", file=sys.stderr)
        return 4
    for rec in rows:
        errors = validate_cap_schema_v1(rec)
        if errors:
            print(f"record_rocm: invalid cap-schema {errors}", file=sys.stderr)
            return 4
    print(
        f"v3-cap-schema v1 records={len(rows)} hardware=rocm-scope "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    for rec in rows:
        print(
            f"pair\t{rec['pair']}\t{rec['pair_relation']}\t"
            f"{rec['observed_constraint']}\t{rec['confidence']}"
        )
    print("depth-star not-a-law")
    print("no-extra-key hip_amdgpu")
    print("semantics unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def accept_hardware(hid: str) -> int:
    if is_foreign_hardware(hid):
        print(f"record_rocm foreign-hardware=rejected id={hid}")
        print("record_rocm note capability-4090-ne-capability-amd")
        return 1
    print(f"record_rocm hardware-scope=this-profile id={hid}")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="ROCm CapabilityRecord host tools")
    p.add_argument("--print-cap-schema-v1", action="store_true")
    p.add_argument("--print-workload-contract", action="store_true")
    p.add_argument("--check-schema-identity", action="store_true")
    p.add_argument("--analyze-cap-schema", type=Path)
    p.add_argument("--emit-record", metavar="PAIR")
    p.add_argument("--classify", metavar="TA:TB:TPAR")
    p.add_argument("--accept-hardware", metavar="ID")
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
        )
    )
    if n != 1:
        print(
            "record_rocm: choose one of --print-cap-schema-v1, "
            "--print-workload-contract, --check-schema-identity, "
            "--analyze-cap-schema, --emit-record, --classify, "
            "--accept-hardware",
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
            print(f"record_rocm: unknown pair {args.emit_record}", file=sys.stderr)
            return 2
        rec = blank_cap_record(args.emit_record)
        errors = validate_cap_schema_v1(rec)
        if errors:
            print(f"record_rocm: invalid emit {errors}", file=sys.stderr)
            return 4
        print(json.dumps(rec, ensure_ascii=True, separators=(",", ":")))
        print(
            f"record_rocm emit-record pair={args.emit_record} "
            "confidence=unknown pair_relation=underdetermined"
        )
        return 0
    if args.classify:
        parts = args.classify.split(":")
        if len(parts) != 3:
            print("record_rocm: classify wants ta:tb:tpar", file=sys.stderr)
            return 2
        ta, tb, tpar = (float(x) for x in parts)
        rel = classify(ta, tb, tpar)
        print(f"record_rocm classify pair_relation={rel}")
        print("record_rocm classify cost=unchanged")
        return 0
    return accept_hardware(args.accept_hardware)


if __name__ == "__main__":
    sys.exit(main())
