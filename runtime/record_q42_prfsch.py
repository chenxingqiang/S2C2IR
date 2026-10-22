#!/usr/bin/env python3
"""Require the capability profile schema to stay distinct from applicability.

record_capability_profile.PROFILE_SCHEMA stays s2c2.capability_profile.v1
and record_capability_applicability.SCHEMA stays
s2c2.capability_applicability.v1. Query only. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_PROFILE = "s2c2.capability_profile.v1"
_APPLICABILITY = "s2c2.capability_applicability.v1"


def _no() -> int:
    print("q42-prfsch no")
    return 1


def print_q42_prfsch() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capability_profile
        import record_capability_applicability

        profile = record_capability_profile.PROFILE_SCHEMA
        applicability = record_capability_applicability.SCHEMA
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    if (
        type(profile) is not str
        or type(applicability) is not str
        or profile != _PROFILE
        or applicability != _APPLICABILITY
        or profile == applicability
    ):
        return _no()
    print("q42-prfsch gate=query")
    print("profile-schema " + profile)
    print("applicability-schema " + applicability)
    print("q42-prfsch yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q42-prfsch"]:
        print(
            "record_q42_prfsch: choose --print-q42-prfsch",
            file=sys.stderr,
        )
        return 2
    return print_q42_prfsch()


if __name__ == "__main__":
    sys.exit(main())
