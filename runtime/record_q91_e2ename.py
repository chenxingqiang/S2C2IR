#!/usr/bin/env python3
"""Require the realization-checking e2e case names.

Imports record_realization_checking_e2e inside the query after the
runtime directory is on sys.path. The first element of each _cases()
row stays legal-claim, unsatisfied-claim, identity-mismatch, and the
list length stays 3. Does not call run_analyzer. Does not add a case,
predicate, device, dialect, backend, or semantic cut. Query only.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_NAMES = ("legal-claim", "unsatisfied-claim", "identity-mismatch")
_FLAG = "--print-q91-e2ename"


def print_q91_e2ename() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_realization_checking_e2e

        rows = record_realization_checking_e2e._cases()
        names = tuple(row[0] for row in rows)
    except (
        AttributeError,
        ImportError,
        IndexError,
        KeyError,
        OSError,
        RuntimeError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        print("q91-e2ename no")
        return 1
    if len(rows) != 3 or names != _NAMES:
        print("q91-e2ename no")
        return 1
    print("q91-e2ename gate=query")
    for name in names:
        print(f"e2e-case {name}")
    print("q91-e2ename yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q91_e2ename: choose --print-q91-e2ename",
            file=sys.stderr,
        )
        return 2
    return print_q91_e2ename()


if __name__ == "__main__":
    sys.exit(main())
