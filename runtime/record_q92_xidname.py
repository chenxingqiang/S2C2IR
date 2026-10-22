#!/usr/bin/env python3
"""Require the cross-identity case names.

Imports record_realization_checking_xid inside the query after the
runtime directory is on sys.path. The first element of each _cases()
row stays cuda-legal, ascend-dma, cpu-na, cross-target, and the list
length stays 4. Does not call run_analyzer. Does not add a case,
predicate, device, dialect, backend, or semantic cut. Query only.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_NAMES = ("cuda-legal", "ascend-dma", "cpu-na", "cross-target")
_FLAG = "--print-q92-xidname"


def print_q92_xidname() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_realization_checking_xid

        rows = record_realization_checking_xid._cases()
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
        print("q92-xidname no")
        return 1
    if len(rows) != 4 or names != _NAMES:
        print("q92-xidname no")
        return 1
    print("q92-xidname gate=query")
    for name in names:
        print(f"xid-case {name}")
    print("q92-xidname yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q92_xidname: choose --print-q92-xidname",
            file=sys.stderr,
        )
        return 2
    return print_q92_xidname()


if __name__ == "__main__":
    sys.exit(main())
