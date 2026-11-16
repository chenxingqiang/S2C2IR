#!/usr/bin/env python3
"""Require canonical(P) and canonical(P') from the apply scenario.

Imports record_apply_scenario inside the printer. Query only.
Does not call run_analyzer. Does not add a predicate, device,
dialect, backend, or semantic cut. can-run-plan stays no.
Does not print the program texts.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_STORE = '"op":"store"'
_EVICT = '"op":"evict"'
_TRANSFER = '"op":"transfer"'
_RESTORE = '"op":"restore"'


def _no() -> int:
    print("q47-canprg no")
    return 1


def print_q47_canprg() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_apply_scenario

        source = record_apply_scenario.CANONICAL_P
        prime = record_apply_scenario.CANONICAL_P_PRIME
        if (
            not isinstance(source, str)
            or not isinstance(prime, str)
            or source == prime
            or len(source) != 206
            or len(prime) != 380
            or source.count(_STORE) != 3
            or _EVICT not in prime
            or _TRANSFER not in prime
            or _RESTORE not in prime
        ):
            return _no()
    except Exception:
        return _no()
    print("q47-canprg gate=query")
    print(f"source-len {len(source)}")
    print(f"prime-len {len(prime)}")
    print("canonical-differ yes")
    print("q47-canprg yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q47-canprg"]:
        print(
            "record_q47_canprg: choose --print-q47-canprg",
            file=sys.stderr,
        )
        return 2
    return print_q47_canprg()


if __name__ == "__main__":
    sys.exit(main())
