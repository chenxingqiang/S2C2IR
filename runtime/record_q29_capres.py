#!/usr/bin/env python3
"""Require capacity residency fields to stay the eight RES_FIELDS names.

Reads record_capacity.RES_FIELDS. The tuple stays
(id, object, space, size, live, producer, consumer, reuse_distance).
Query only. Does not add a capacity predicate, device, dialect,
backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_RES_FIELDS = (
    "id",
    "object",
    "space",
    "size",
    "live",
    "producer",
    "consumer",
    "reuse_distance",
)


def print_q29_capres() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capacity

        fields = record_capacity.RES_FIELDS
    except (ImportError, AttributeError, OSError, SyntaxError):
        print("q29-capres no")
        return 1
    if fields != _RES_FIELDS:
        print("q29-capres no")
        return 1
    print("q29-capres gate=query")
    for name in fields:
        print(f"res-field {name}")
    print("q29-capres yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q29-capres"]:
        print(
            "record_q29_capres: choose --print-q29-capres",
            file=sys.stderr,
        )
        return 2
    return print_q29_capres()


if __name__ == "__main__":
    sys.exit(main())
