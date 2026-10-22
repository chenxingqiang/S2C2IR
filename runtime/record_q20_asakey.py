#!/usr/bin/env python3
"""Require the Ascend analyze map to stay the seven ledger flags.

ASCEND_ANALYZE on record_hw_ledger must stay the seven keys in
insertion order. Query only. No semantic cut. can-run-plan stays no.
Does not call run_analyzer.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_REQUIRED = {
    "cap-schema": "--analyze-cap-schema",
    "mem": "--analyze-mem",
    "cc-phase": "--analyze-cc-phase",
    "cc-size": "--analyze-cc-size",
    "cc-rewrite": "--analyze-cc-rewrite",
    "ssd-mlp-wallclock": "--analyze-ssd-mlp-wallclock",
    "e2e-gain": "--analyze-e2e-gain",
}


def _no() -> int:
    print("q20-asakey no")
    return 1


def print_q20_asakey() -> int:
    try:
        sys.path.insert(0, str(_RUNTIME))
        import record_hw_ledger

        analyze = record_hw_ledger.ASCEND_ANALYZE
        ordered = list(analyze.items())
        if analyze != _REQUIRED or ordered != list(_REQUIRED.items()):
            return _no()
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    print("q20-asakey gate=query")
    for name, flag in ordered:
        print(f"analyze {name} {flag}")
    print("q20-asakey yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q20-asakey"]:
        print(
            "record_q20_asakey: choose --print-q20-asakey",
            file=sys.stderr,
        )
        return 2
    return print_q20_asakey()


if __name__ == "__main__":
    sys.exit(main())
