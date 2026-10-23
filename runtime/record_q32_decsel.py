#!/usr/bin/env python3
"""Require decision and sufficiency to share S0 and S1 selections.

record_decision and record_sufficiency must both expose
SELECTED_S0 as keep{0,1}|evict{2}|rematerialize{} and
SELECTED_S1 as keep{1,2}|evict{0}|rematerialize{}.
Query only. No predicate, device, dialect, backend, or semantic cut.
Does not call run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_S0 = "keep{0,1}|evict{2}|rematerialize{}"
_S1 = "keep{1,2}|evict{0}|rematerialize{}"


def _no() -> int:
    print("q32-decsel no")
    return 1


def print_q32_decsel() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_decision as decision
        import record_sufficiency as sufficiency
    except ImportError:
        return _no()
    try:
        decision_s0 = decision.SELECTED_S0
        decision_s1 = decision.SELECTED_S1
        sufficiency_s0 = sufficiency.SELECTED_S0
        sufficiency_s1 = sufficiency.SELECTED_S1
    except AttributeError:
        return _no()
    if not (
        decision_s0 == sufficiency_s0 == _S0
        and decision_s1 == sufficiency_s1 == _S1
    ):
        return _no()
    print("q32-decsel gate=query")
    print("selected-s0 " + decision.SELECTED_S0)
    print("selected-s1 " + decision.SELECTED_S1)
    print("q32-decsel yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q32-decsel"]:
        print(
            "record_q32_decsel: choose --print-q32-decsel",
            file=sys.stderr,
        )
        return 2
    return print_q32_decsel()


if __name__ == "__main__":
    sys.exit(main())
