#!/usr/bin/env python3
"""Require runtime/ascend/record_ascend.SEQ_SLACK to stay 1.05.

Loads runtime/ascend/record_ascend.py with importlib from Path(__file__).
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_ASCEND = Path(__file__).resolve().parent / "ascend" / "record_ascend.py"
_FLAG = "--print-q81-slack"
_SEQ_SLACK = 1.05


def _load_record_ascend() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "s2c2_ascend_q81_slack", _ASCEND
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-ascend-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q81_slack() -> int:
    try:
        slack = _load_record_ascend().SEQ_SLACK
    except (Exception, SystemExit):
        print("q81-slack no")
        return 1
    if type(slack) is not float or slack != _SEQ_SLACK:
        print("q81-slack no")
        return 1
    print("q81-slack gate=query")
    print("seq-slack 1.05")
    print("q81-slack yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q81_slack: choose --print-q81-slack",
            file=sys.stderr,
        )
        return 2
    return print_q81_slack()


if __name__ == "__main__":
    sys.exit(main())
