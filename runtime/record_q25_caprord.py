#!/usr/bin/env python3
"""Require the capacity restore-order field tuple.

Query only. The tuple is record_capacity.RESTORE_ORDER_FIELDS, which
stays object, before, witness, scope. This does not add a capacity
predicate, device, dialect, backend, or semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent


def print_q25_caprord() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capacity

        fields = record_capacity.RESTORE_ORDER_FIELDS
    except (ImportError, AttributeError):
        print("q25-caprord no")
        return 1
    if not (fields == ("object", "before", "witness", "scope")):
        print("q25-caprord no")
        return 1
    print("q25-caprord gate=query")
    for field in fields:
        print(f"restore-order-field {field}")
    print("q25-caprord yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q25-caprord"]:
        print(
            "record_q25_caprord: choose --print-q25-caprord",
            file=sys.stderr,
        )
        return 2
    return print_q25_caprord()


if __name__ == "__main__":
    sys.exit(main())
