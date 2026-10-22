#!/usr/bin/env python3
"""Require the checking result set and the constraint-to-result map.

Reads record_realization_checking.RESULTS and _RESULT_FOR. Does not
edit the checking module. No semantic cut. can-run-plan stays no.
Query only. Do not FileCheck microseconds.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_RESULTS = ("satisfy", "violate", "unproven")
_RESULT_FOR = {
    "allowed": "satisfy",
    "forbidden": "violate",
    "not-applicable": "violate",
    "unproven": "unproven",
}


def _no() -> int:
    print("check-results-bind no")
    return 1


def print_check_results_bind() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_realization_checking as chk

        if chk.RESULTS != _RESULTS or chk._RESULT_FOR != _RESULT_FOR:
            return _no()
        if tuple(chk._RESULT_FOR.items()) != tuple(_RESULT_FOR.items()):
            return _no()
    except Exception:
        return _no()
    print("check-results-bind gate=query")
    for result in chk.RESULTS:
        print(f"result {result}")
    for constraint, mapped in chk._RESULT_FOR.items():
        print(f"{constraint}-maps {mapped}")
    print("check-results-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-check-results-bind"]:
        print(
            "record_check_results_bind: choose --print-check-results-bind",
            file=sys.stderr,
        )
        return 2
    return print_check_results_bind()


if __name__ == "__main__":
    sys.exit(main())
