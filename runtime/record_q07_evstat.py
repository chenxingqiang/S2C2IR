#!/usr/bin/env python3
"""Query the evidence measurement statuses.

Imports record_evidence inside the printer and requires STATUSES to
stay measured, inferred, fixture, pending, invalid. Query only.
No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_STATUSES = ("measured", "inferred", "fixture", "pending", "invalid")


def print_q07_evstat() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_evidence

        if record_evidence.STATUSES != _STATUSES:
            print("q07-evstat no")
            return 1
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        print("q07-evstat no")
        return 1
    print("q07-evstat gate=query")
    for status in record_evidence.STATUSES:
        print("evidence-status " + status)
    print("q07-evstat yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q07-evstat"]:
        print(
            "record_q07_evstat: choose --print-q07-evstat",
            file=sys.stderr,
        )
        return 2
    return print_q07_evstat()


if __name__ == "__main__":
    sys.exit(main())
