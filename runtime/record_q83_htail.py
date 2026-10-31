#!/usr/bin/env python3
"""Require the eight Ascend hierarchy tails to stay the query set.

Loads runtime/ascend/record_ascend.py with importlib from Path(__file__).
_HIER_TAILS must be the eight PREFETCH and PRESERVE hierarchy tails, in order.
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "ascend" / "record_ascend.py"
_HIER_TAILS = (
    "PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY",
    "PREFETCH|TRANSFER|KEEP_RESIDENCY|TRANSFER",
    "PREFETCH|TRANSFER|TRANSFER|KEEP_RESIDENCY",
    "PREFETCH|TRANSFER|TRANSFER|TRANSFER",
    "PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY",
    "PRESERVE|TRANSFER|KEEP_RESIDENCY|TRANSFER",
    "PRESERVE|TRANSFER|TRANSFER|KEEP_RESIDENCY",
    "PRESERVE|TRANSFER|TRANSFER|TRANSFER",
)
_FLAG = "--print-q83-htail"


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "s2c2_ascend_q83_htail", path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-ascend-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q83-htail no")
    return 1


def print_q83_htail() -> int:
    try:
        tails = _load(_RECORD)._HIER_TAILS
    except (Exception, SystemExit):
        return _no()
    if type(tails) is not tuple or tails != _HIER_TAILS:
        return _no()
    print("q83-htail gate=query")
    for tail in tails:
        print(f"hier-tail {tail}")
    print("q83-htail yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q83_htail: choose --print-q83-htail",
            file=sys.stderr,
        )
        return 2
    return print_q83_htail()


if __name__ == "__main__":
    sys.exit(main())
