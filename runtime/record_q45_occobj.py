#!/usr/bin/env python3
"""Require occupancy and sufficiency to share object 2.

Imports record_occupancy_capability and record_sufficiency inside the
printer. OBJECT_2 stays the string 2, not the prose token O2. Query
only. Does not call run_analyzer. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_FLAG = "--print-q45-occobj"
_CANONICAL = "2"
_PROSE = "O2"


def print_q45_occobj() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_occupancy_capability
        import record_sufficiency

        occ = record_occupancy_capability.OBJECT_2
        suf = record_sufficiency.OBJECT_2
    except (
        AttributeError,
        ImportError,
        OSError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        print("q45-occobj no")
        return 1
    if (
        type(occ) is not str
        or type(suf) is not str
        or occ == _PROSE
        or suf == _PROSE
        or not (occ == suf == _CANONICAL)
    ):
        print("q45-occobj no")
        return 1
    print("q45-occobj gate=query")
    print("object-canonical " + occ)
    print("q45-occobj yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q45_occobj: choose --print-q45-occobj",
            file=sys.stderr,
        )
        return 2
    return print_q45_occobj()


if __name__ == "__main__":
    sys.exit(main())
