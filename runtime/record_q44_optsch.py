#!/usr/bin/env python3
"""Require the optimum, authorization, and decision schemas to stay distinct.

Imports record_optimum_authorization and record_authorization inside
the query. Does not call run_analyzer. Does not change the frozen 7A
evaluator. Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_OPTIMUM_SCHEMA = "s2c2.optimum_authorization.v1"
_AUTH_SCHEMA = "s2c2.authorization.v1"
_DECISION_SCHEMA = "s2c2.decision.v1"
_FLAG = "--print-q44-optsch"


def _no() -> int:
    print("q44-optsch no")
    return 1


def print_q44_optsch() -> int:
    sys.path.insert(0, str(_RUNTIME))
    try:
        import record_optimum_authorization
        import record_authorization

        optimum = record_optimum_authorization.SCHEMA
        authorization = record_authorization.AUTH_SCHEMA
        decision = record_authorization.DECISION_SCHEMA
    except (
        AttributeError,
        ImportError,
        OSError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        return _no()
    if (
        type(optimum) is not str
        or type(authorization) is not str
        or type(decision) is not str
        or optimum != _OPTIMUM_SCHEMA
        or authorization != _AUTH_SCHEMA
        or decision != _DECISION_SCHEMA
        or optimum == authorization
        or optimum == decision
        or authorization == decision
    ):
        return _no()
    print("q44-optsch gate=query")
    print("optimum-schema " + optimum)
    print("authorization-schema " + authorization)
    print("decision-schema " + decision)
    print("q44-optsch yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q44_optsch: choose --print-q44-optsch",
            file=sys.stderr,
        )
        return 2
    return print_q44_optsch()


if __name__ == "__main__":
    sys.exit(main())
