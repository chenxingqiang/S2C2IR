#!/usr/bin/env python3
"""Require Sched_Op mnemonics in ScheduleOps.td to stay the seven schedule ops.

Reads include/s2c2/Schedule/ScheduleOps.td from the repo root and extracts
Sched_Op<"mnemonic"> definitions in file order. Query only. Does not add
an op, predicate, device, dialect, backend, or semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_TD = _ROOT / "include" / "s2c2" / "Schedule" / "ScheduleOps.td"
_OPS = (
    "yield",
    "wait",
    "task",
    "concurrent",
    "overlap",
    "pipeline",
    "stage",
)
_FLAG = "--print-q90-schedop"
_PATTERN = re.compile(r'Sched_Op<"([^"]+)"')


def sched_mnemonics(text: str) -> tuple[str, ...]:
    """Sched_Op mnemonics in the order they appear in the TableGen file."""
    return tuple(_PATTERN.findall(text))


def print_q90_schedop() -> int:
    try:
        ops = sched_mnemonics(_TD.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, re.error):
        print("q90-schedop no")
        return 1
    if ops != _OPS:
        print("q90-schedop no")
        return 1
    print("q90-schedop gate=query")
    for name in ops:
        print(f"sched-op {name}")
    print("q90-schedop yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q90_schedop: choose --print-q90-schedop",
            file=sys.stderr,
        )
        return 2
    return print_q90_schedop()


if __name__ == "__main__":
    sys.exit(main())
