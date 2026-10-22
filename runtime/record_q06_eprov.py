#!/usr/bin/env python3
"""Require capability entry provenance to extend the provenance values.

ENTRY_PROVENANCE stays PROVENANCE_VALUES plus missing:
catalog, occupancy-query, unknown, missing. Query only.
No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_EXPECTED = ("catalog", "occupancy-query", "unknown", "missing")


def _no() -> int:
    print("q06-eprov no")
    return 1


def print_q06_eprov() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capability_profile as prof
        import record_capability_applicability as capa

        entry = prof.ENTRY_PROVENANCE
        extended = capa.PROVENANCE_VALUES + ("missing",)
        if type(entry) is not tuple or entry != extended or entry != _EXPECTED:
            return _no()
        line = "entry-provenance " + ",".join(entry)
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    print("q06-eprov gate=query")
    print(line)
    print("q06-eprov yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q06-eprov"]:
        print(
            "record_q06_eprov: choose --print-q06-eprov",
            file=sys.stderr,
        )
        return 2
    return print_q06_eprov()


if __name__ == "__main__":
    sys.exit(main())
