#!/usr/bin/env python3
"""Require the claim schema and the checking schema to stay distinct.

Reads record_realization_checking.CLAIM_SCHEMA and CHECKING_SCHEMA.
Does not edit the checking module. No semantic cut. can-run-plan stays no.
Query only. Do not FileCheck microseconds.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_CLAIM_SCHEMA = "s2c2.realization_claim.v1"
_CHECKING_SCHEMA = "s2c2.realization_checking.v1"


def _no() -> int:
    print("q40-clmsch no")
    return 1


def print_q40_clmsch() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_realization_checking as chk

        claim_schema = chk.CLAIM_SCHEMA
        checking_schema = chk.CHECKING_SCHEMA
        if (
            claim_schema != _CLAIM_SCHEMA
            or checking_schema != _CHECKING_SCHEMA
            or claim_schema == checking_schema
        ):
            return _no()
    except Exception:
        return _no()
    print("q40-clmsch gate=query")
    print(f"claim-schema {claim_schema}")
    print(f"checking-schema {checking_schema}")
    print("q40-clmsch yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q40-clmsch"]:
        print(
            "record_q40_clmsch: choose --print-q40-clmsch",
            file=sys.stderr,
        )
        return 2
    return print_q40_clmsch()


if __name__ == "__main__":
    sys.exit(main())
