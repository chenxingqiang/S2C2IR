#!/usr/bin/env python3
"""Require the four Ascend storage-loop tails to stay the query set.

Loads runtime/ascend/record_ascend.py with importlib from Path(__file__).
_LOOP_TAILS must be the four PREFETCH and PRESERVE loop tails, in order.
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "ascend" / "record_ascend.py"
_LOOP_TAILS = (
    "PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE",
    "PREFETCH//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE",
    "PRESERVE//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE",
    "PRESERVE//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE",
)
_FLAG = "--print-q85-ltail"


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "s2c2_ascend_q85_ltail", path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-ascend-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q85-ltail no")
    return 1


def print_q85_ltail() -> int:
    try:
        tails = _load(_RECORD)._LOOP_TAILS
    except (Exception, SystemExit):
        return _no()
    if type(tails) is not tuple or tails != _LOOP_TAILS:
        return _no()
    print("q85-ltail gate=query")
    for tail in tails:
        print(f"loop-tail {tail}")
    print("q85-ltail yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q85_ltail: choose --print-q85-ltail",
            file=sys.stderr,
        )
        return 2
    return print_q85_ltail()


if __name__ == "__main__":
    sys.exit(main())
