#!/usr/bin/env python3
"""Require the hardware ledger role tuple to stay the six catalog roles.

Query only. Does not add a role or open a semantic cut. Does not call
run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_FLAG = "--print-q15-ledrole"
_ROLES = (
    "catalog-69",
    "overlay",
    "compiler-4090",
    "campaign",
    "pending-program",
    "program",
)


def print_q15_ledrole() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_hw_ledger

        roles = record_hw_ledger.LEDGER_ROLE
    except (ImportError, AttributeError):
        print("q15-ledrole no")
        return 1
    if roles != _ROLES:
        print("q15-ledrole no")
        return 1
    print("q15-ledrole gate=query")
    for role in roles:
        print(f"ledger-role {role}")
    print("q15-ledrole yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q15_ledrole: choose --print-q15-ledrole",
            file=sys.stderr,
        )
        return 2
    return print_q15_ledrole()


if __name__ == "__main__":
    sys.exit(main())
