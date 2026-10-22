#!/usr/bin/env python3
"""Require the capacity source, order, and dest scopes.

Query only. SOURCE_SCOPE, ORDER_SCOPE, and DEST_SCOPE on
record_capacity each stay occupancy-live. This does not add a
capacity predicate, device, dialect, backend, or semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_SCOPE = "occupancy-live"


def print_q28_capscop() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capacity

        source = record_capacity.SOURCE_SCOPE
        order = record_capacity.ORDER_SCOPE
        dest = record_capacity.DEST_SCOPE
    except (ImportError, AttributeError):
        print("q28-capscop no")
        return 1
    if source != _SCOPE or order != _SCOPE or dest != _SCOPE:
        print("q28-capscop no")
        return 1
    print("q28-capscop gate=query")
    print(f"source-scope {source}")
    print(f"order-scope {order}")
    print(f"dest-scope {dest}")
    print("q28-capscop yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q28-capscop"]:
        print(
            "record_q28_capscop: choose --print-q28-capscop",
            file=sys.stderr,
        )
        return 2
    return print_q28_capscop()


if __name__ == "__main__":
    sys.exit(main())
