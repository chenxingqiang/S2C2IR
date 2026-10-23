#!/usr/bin/env python3
"""Require capacity dest-invalidation field names.

record_capacity.DEST_INV_FIELDS must be object, destination, witness,
and scope, in that order. Query only. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_DEST_INV_FIELDS = ("object", "destination", "witness", "scope")


def _no() -> int:
    print("q26-capdinv no")
    return 1


def print_q26_capdinv() -> int:
    try:
        sys.path.insert(0, str(_RUNTIME))
        import record_capacity
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    fields = getattr(record_capacity, "DEST_INV_FIELDS", None)
    if fields != _DEST_INV_FIELDS:
        return _no()
    print("q26-capdinv gate=query")
    for field in fields:
        print("dest-inv-field " + field)
    print("q26-capdinv yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q26-capdinv"]:
        print(
            "record_q26_capdinv: choose --print-q26-capdinv",
            file=sys.stderr,
        )
        return 2
    return print_q26_capdinv()


if __name__ == "__main__":
    sys.exit(main())
