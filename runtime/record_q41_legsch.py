#!/usr/bin/env python3
"""Require the legality schema to stay distinct from profile and checking.

Imports record_realization_legality, record_capability_profile, and
record_realization_checking inside the query. Does not call
run_analyzer. Does not add a predicate, device, dialect, backend, or
semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_LEGALITY_SCHEMA = "s2c2.realization_legality.v1"
_PROFILE_SCHEMA = "s2c2.capability_profile.v1"
_CHECKING_SCHEMA = "s2c2.realization_checking.v1"
_FLAG = "--print-q41-legsch"


def print_q41_legsch() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_realization_legality
        import record_capability_profile
        import record_realization_checking

        legality = record_realization_legality.LEGALITY_SCHEMA
        profile = record_capability_profile.PROFILE_SCHEMA
        checking = record_realization_checking.CHECKING_SCHEMA
    except (
        AttributeError,
        ImportError,
        OSError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        print("q41-legsch no")
        return 1
    if (
        type(legality) is not str
        or type(profile) is not str
        or type(checking) is not str
        or legality != _LEGALITY_SCHEMA
        or legality == profile
        or legality == checking
        or profile != _PROFILE_SCHEMA
        or checking != _CHECKING_SCHEMA
    ):
        print("q41-legsch no")
        return 1
    print("q41-legsch gate=query")
    print("legality-schema " + legality)
    print("profile-schema " + profile)
    print("checking-schema " + checking)
    print("q41-legsch yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q41_legsch: choose --print-q41-legsch",
            file=sys.stderr,
        )
        return 2
    return print_q41_legsch()


if __name__ == "__main__":
    sys.exit(main())
