#!/usr/bin/env python3
"""Require the TableGen op counts to match the goal-alignment check.

Counts Stor_Op, Comp_Op, Comm_Op, and Sched_Op definitions in
include/s2c2 with the same TableGen pattern record_goal_alignment
uses, then calls record_goal_alignment.check(). The four counts
must agree and each must be at least 1. Query only. No semantic
cut. can-run-plan stays no. next_cut stays NOT OPENED.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_INCLUDE = _RUNTIME.parent / "include" / "s2c2"

# Same prefix map and `{Prefix}_Op<"mnemonic"` pattern as
# record_goal_alignment.dialect_surface.
_DIALECT = {
    "Stor": "stor",
    "Comp": "comp",
    "Comm": "comm",
    "Sched": "sched",
}
_KEYS = ("stor", "comp", "comm", "sched")


def _td_text() -> str:
    parts = []
    for path in sorted(_INCLUDE.rglob("*.td")):
        parts.append(path.read_text(encoding="utf-8"))
    return "\n".join(parts)


def tablegen_counts(td: str) -> dict[str, int]:
    """Unique mnemonics per dialect, using the goal checker's pattern."""
    counts: dict[str, int] = {}
    for prefix, dialect in _DIALECT.items():
        names = set(re.findall(rf'{prefix}_Op<"([^"]+)"', td))
        counts[dialect] = len(names)
    return counts


def _no() -> int:
    print("dialect-count-bind no")
    return 1


def print_dialect_count_bind() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_goal_alignment

        scanned = tablegen_counts(_td_text())
        checked = record_goal_alignment.check()
    except Exception:
        return _no()
    if not isinstance(checked, dict):
        return _no()
    agreed: dict[str, int] = {}
    for key in _KEYS:
        live = scanned.get(key)
        claimed = checked.get(key)
        if type(live) is not int or type(claimed) is not int:
            return _no()
        if live != claimed or live < 1:
            return _no()
        agreed[key] = live
    print("dialect-count-bind gate=query")
    print(f"stor-ops {agreed['stor']}")
    print(f"comp-ops {agreed['comp']}")
    print(f"comm-ops {agreed['comm']}")
    print(f"sched-ops {agreed['sched']}")
    print("dialect-count-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-dialect-count-bind"]:
        print(
            "record_dialect_count_bind: choose --print-dialect-count-bind",
            file=sys.stderr,
        )
        return 2
    return print_dialect_count_bind()


if __name__ == "__main__":
    sys.exit(main())
