#!/usr/bin/env python3
"""Require USABLE_KINDS to stay source-data then restore-ordering.

Query only. Reads record_decision.USABLE_KINDS. Does not add a
predicate, device, dialect, backend, or semantic cut.
can-run-plan stays no. Leaves authorization unchanged.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_FLAG = "--print-q31-usekind"


def print_q31_usekind() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_decision

        kinds = record_decision.USABLE_KINDS
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError):
        print("q31-usekind no")
        return 1
    if kinds != ("source-data", "restore-ordering"):
        print("q31-usekind no")
        return 1
    print("q31-usekind gate=query")
    for kind in kinds:
        print(f"usable-kind {kind}")
    print("q31-usekind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q31_usekind: choose --print-q31-usekind",
            file=sys.stderr,
        )
        return 2
    return print_q31_usekind()


if __name__ == "__main__":
    sys.exit(main())
