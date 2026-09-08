#!/usr/bin/env python3
"""Index and batch-check hardware measurement artifacts.

Does not move logs, overwrite #69, FileCheck microseconds, or open Cost v0.4.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[1]
_LEDGER_PATH = _REPO_ROOT / "docs/design/v3-dataset/hardware-ledger.jsonl"
_CATALOG_69 = _REPO_ROOT / "docs/design/v3-dataset/ascend910b/capability.jsonl"
_ASCEND = _REPO_ROOT / "runtime/ascend/record_ascend.py"
_CUDA = _REPO_ROOT / "runtime/cuda/record_v3.py"

LEDGER_FIELDS = (
    "id",
    "hardware",
    "kind",
    "status",
    "path",
    "tool",
    "analyze",
    "catalog_role",
    "note",
    "cost",
    "semantics",
)
LEDGER_HARDWARE = ("rtx4090", "ascend910b")
LEDGER_KIND = ("catalog", "overlay", "campaign", "program")
LEDGER_STATUS = ("measured", "device-absent")
LEDGER_TOOL = ("cuda", "ascend", "none")
LEDGER_ROLE = (
    "catalog-69",
    "overlay",
    "compiler-4090",
    "campaign",
    "pending-program",
    "program",
)
FORBIDDEN = ("password",)
VENDOR_KEY_PREFIX = ("acl_", "davinci_", "cube_", "vectorcore_")

CUDA_ANALYZE = {
    "cap-schema": "--analyze-cap-schema",
    "cap": "--analyze-cap",
    "phase": "--analyze-phase",
    "pipe": "--analyze-pipe",
    "pipe-tiles": "--analyze-pipe-tiles",
    "cuda-val": "--analyze-cuda-val",
    "cuda-val-mem": "--analyze-cuda-val-mem",
    "cuda-val-cc": "--analyze-cuda-val-cc",
    "cuda-val-async": "--analyze-cuda-val-async",
    "matched": "--analyze-matched",
    "ratio": "--analyze-ratio",
}
ASCEND_ANALYZE = {
    "cap-schema": "--analyze-cap-schema",
    "mem": "--analyze-mem",
    "cc-phase": "--analyze-cc-phase",
    "cc-size": "--analyze-cc-size",
    "cc-rewrite": "--analyze-cc-rewrite",
    "ssd-mlp-wallclock": "--analyze-ssd-mlp-wallclock",
    "e2e-gain": "--analyze-e2e-gain",
}


def print_contract() -> int:
    print("hw-ledger batch-check=yes")
    print("hw-ledger note keep-original-path")
    print("hw-ledger note not-cap-schema-v1")
    print("hw-ledger note catalog-untouched")
    print("hw-ledger note npu-demo=not-ledger")
    print("hw-ledger note pending=device-absent")
    print("hw-ledger note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def load_ledger(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        rec = json.loads(line)
        if not isinstance(rec, dict):
            raise ValueError("ledger row is not an object")
        extra = [k for k in rec if k not in LEDGER_FIELDS]
        vendor = [k for k in rec if k.startswith(VENDOR_KEY_PREFIX)]
        if extra or vendor:
            raise ValueError(f"ledger extra keys {extra or vendor}")
        missing = [k for k in LEDGER_FIELDS if k not in rec]
        if missing:
            raise ValueError(f"ledger missing keys {missing}")
        if rec["hardware"] not in LEDGER_HARDWARE:
            raise ValueError(f"ledger hardware {rec['hardware']}")
        if rec["kind"] not in LEDGER_KIND:
            raise ValueError(f"ledger kind {rec['kind']}")
        if rec["status"] not in LEDGER_STATUS:
            raise ValueError(f"ledger status {rec['status']}")
        if rec["tool"] not in LEDGER_TOOL:
            raise ValueError(f"ledger tool {rec['tool']}")
        if rec["catalog_role"] not in LEDGER_ROLE:
            raise ValueError(f"ledger catalog_role {rec['catalog_role']}")
        if rec["cost"] != "unchanged" or rec["semantics"] != "unchanged":
            raise ValueError("ledger cost/semantics must stay unchanged")
        rows.append(rec)
    if not rows:
        raise ValueError("empty ledger")
    ids = [r["id"] for r in rows]
    if len(ids) != len(set(ids)):
        raise ValueError("ledger duplicate id")
    return rows


def scan_secrets(text: str) -> list[str]:
    hits: list[str] = []
    lower = text.lower()
    for tok in FORBIDDEN:
        if tok in lower:
            hits.append(tok)
    return hits


def run_analyzer(rec: dict[str, Any], artifact: Path) -> None:
    analyze = rec["analyze"]
    tool = rec["tool"]
    if not analyze or tool == "none":
        return
    if analyze == "ssd-mlp-wallclock":
        flag = "--analyze-ssd-mlp-wallclock"
        script = _ASCEND
    elif analyze == "storage-pipeline":
        flag = "--analyze-storage-pipeline"
        script = _ASCEND
    elif analyze == "storage-loop-wallclock":
        flag = "--analyze-storage-loop-wallclock"
        script = _ASCEND
    elif tool == "cuda":
        flag = CUDA_ANALYZE.get(analyze)
        script = _CUDA
    elif tool == "ascend":
        flag = ASCEND_ANALYZE.get(analyze)
        script = _ASCEND
    else:
        raise ValueError(f"ledger tool {tool}")
    if not flag:
        raise ValueError(f"ledger analyze {analyze}")
    proc = subprocess.run(
        [sys.executable, str(script), flag, str(artifact)],
        cwd=_REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(
            f"analyzer failed id={rec['id']} rc={proc.returncode} {err}"
        )


def query_catalog_69() -> str:
    proc = subprocess.run(
        [
            sys.executable,
            str(_ASCEND),
            "--query-cap",
            "C||C",
            "--cap-catalog",
            str(_CATALOG_69),
        ],
        cwd=_REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"query #69 failed: {proc.stderr}")
    if '"pair_relation":"underdetermined"' not in proc.stdout:
        raise RuntimeError("#69 C||C is not underdetermined")
    return "underdetermined"


def check_ledger(path: Path) -> int:
    try:
        rows = load_ledger(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"record_hw_ledger: {exc}", file=sys.stderr)
        return 4
    n_measured = 0
    n_absent = 0
    pending_id = ""
    try:
        for rec in rows:
            artifact = _REPO_ROOT / rec["path"]
            if not artifact.is_file():
                raise RuntimeError(f"missing path id={rec['id']} {rec['path']}")
            secrets = scan_secrets(artifact.read_text(encoding="utf-8", errors="replace"))
            if secrets:
                raise RuntimeError(f"secrets id={rec['id']} {secrets}")
            run_analyzer(rec, artifact)
            if rec["status"] == "measured":
                n_measured += 1
            else:
                n_absent += 1
                pending_id = rec["id"]
            print(f"hw-ledger id={rec['id']} status={rec['status']} files=ok")
        cat69 = query_catalog_69()
    except RuntimeError as exc:
        print(f"record_hw_ledger: {exc}", file=sys.stderr)
        return 4
    print(f"hw-ledger records={len(rows)}")
    print(f"hw-ledger measured={n_measured}")
    print(f"hw-ledger device-absent={n_absent}")
    print(f"hw-ledger catalog-69={cat69}")
    print("hw-ledger catalog-untouched=yes")
    print("hw-ledger secrets=0")
    print("hw-ledger analyzers=ok")
    print("hw-ledger npu-demo=not-ledger")
    if pending_id:
        print(f"hw-ledger {pending_id}=device-absent")
    print("hw-ledger note keep-original-path")
    print("hw-ledger note not-cost-v04")
    print("semantics=unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Hardware measurement ledger")
    p.add_argument("--print-hw-ledger-contract", action="store_true")
    p.add_argument("--check-hw-ledger", nargs="?", const=_LEDGER_PATH, type=Path)
    args = p.parse_args()
    n = sum(bool(x) for x in (args.print_hw_ledger_contract, args.check_hw_ledger))
    if n != 1:
        print(
            "record_hw_ledger: choose one of --print-hw-ledger-contract, "
            "--check-hw-ledger",
            file=sys.stderr,
        )
        return 2
    if args.print_hw_ledger_contract:
        return print_contract()
    return check_ledger(args.check_hw_ledger)


if __name__ == "__main__":
    sys.exit(main())
