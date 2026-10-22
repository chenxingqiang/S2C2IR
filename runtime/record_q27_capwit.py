#!/usr/bin/env python3
"""Require the capacity source, order, and dest witnesses.

Query only. The witnesses are record_capacity.SOURCE_WITNESS,
ORDER_WITNESS, and DEST_WITNESS. This does not add a capacity
predicate, device, dialect, backend, or semantic cut. Does not
call run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent


def print_q27_capwit() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capacity

        source = record_capacity.SOURCE_WITNESS
        order = record_capacity.ORDER_WITNESS
        dest = record_capacity.DEST_WITNESS
    except (ImportError, AttributeError):
        print("q27-capwit no")
        return 1
    if not (
        source == "spec-unmutated-cover"
        and order == "spec-before-consumer"
        and dest == "spec-drop-stale"
    ):
        print("q27-capwit no")
        return 1
    print("q27-capwit gate=query")
    print(f"source-witness {source}")
    print(f"order-witness {order}")
    print(f"dest-witness {dest}")
    print("q27-capwit yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q27-capwit"]:
        print(
            "record_q27_capwit: choose --print-q27-capwit",
            file=sys.stderr,
        )
        return 2
    return print_q27_capwit()


if __name__ == "__main__":
    sys.exit(main())
