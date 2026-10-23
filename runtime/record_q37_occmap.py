#!/usr/bin/env python3
"""Query the occupancy printer map size and the unknown-scope target.

Reads OCCUPANCY_PRINTER_MAP and EVIDENCE_REASON_TOKENS from record_decision.
Does not edit that module. Does not print the map. No semantic cut.
can-run-plan stays no. Query only.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_FLAG = "--print-q37-occmap"
_UNKNOWN_SCOPE = ("unknown-scope", "evidence.scope-mismatch")


def print_q37_occmap() -> int:
    if str(_RUNTIME) not in sys.path:
        sys.path.insert(0, str(_RUNTIME))
    import record_decision

    occmap = record_decision.OCCUPANCY_PRINTER_MAP
    tokens = record_decision.EVIDENCE_REASON_TOKENS
    targets_ok = all(algebra in tokens for _, algebra in occmap)
    if len(occmap) != 13 or not targets_ok or _UNKNOWN_SCOPE not in occmap:
        print("q37-occmap no")
        return 1
    print("q37-occmap gate=query")
    print("occupancy-map-count 13")
    print("unknown-scope-maps evidence.scope-mismatch")
    print("q37-occmap yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q37_occmap: choose --print-q37-occmap",
            file=sys.stderr,
        )
        return 2
    return print_q37_occmap()


if __name__ == "__main__":
    sys.exit(main())
