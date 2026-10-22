#!/usr/bin/env python3
"""Require the capacity restore-legal pair.

Query only. The pair is record_capacity.RESTORE_LEGAL, which stays
TRANSFER,REMATERIALIZE. This does not add capacity predicates, does
not print rewrite-license=yes, and does not open a semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent


def print_restore_legal_bind() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capacity

        restore_legal = record_capacity.RESTORE_LEGAL
    except (ImportError, AttributeError):
        print("restore-legal-bind no")
        return 1
    if not (record_capacity.RESTORE_LEGAL == "TRANSFER,REMATERIALIZE"):
        print("restore-legal-bind no")
        return 1
    print("restore-legal-bind gate=query")
    print(f"restore-legal {restore_legal}")
    print("restore-legal-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-restore-legal-bind"]:
        print(
            "record_restore_legal_bind: choose --print-restore-legal-bind",
            file=sys.stderr,
        )
        return 2
    return print_restore_legal_bind()


if __name__ == "__main__":
    sys.exit(main())
