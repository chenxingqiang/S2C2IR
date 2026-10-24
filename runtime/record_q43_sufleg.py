#!/usr/bin/env python3
"""Require the sufficiency schema to stay distinct from realization legality.

Imports record_sufficiency and record_realization_legality inside the
query. SUFFICIENCY_SCHEMA stays s2c2.sufficiency.v1.
LEGALITY_SCHEMA stays s2c2.realization_legality.v1. The two schema
ids differ. Query only. Does not call run_analyzer. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_SUFFICIENCY = "s2c2.sufficiency.v1"
_LEGALITY = "s2c2.realization_legality.v1"
_FLAG = "--print-q43-sufleg"


def _no() -> int:
    print("q43-sufleg no")
    return 1


def print_q43_sufleg() -> int:
    try:
        sys.path.insert(0, str(_RUNTIME))
        import record_sufficiency
        import record_realization_legality

        sufficiency = record_sufficiency.SUFFICIENCY_SCHEMA
        legality = record_realization_legality.LEGALITY_SCHEMA
    except Exception:
        return _no()
    if (
        type(sufficiency) is not str
        or type(legality) is not str
        or sufficiency != _SUFFICIENCY
        or legality != _LEGALITY
        or sufficiency == legality
    ):
        return _no()
    print("q43-sufleg gate=query")
    print(f"sufficiency-schema {sufficiency}")
    print(f"legality-schema {legality}")
    print("q43-sufleg yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q43_sufleg: choose --print-q43-sufleg",
            file=sys.stderr,
        )
        return 2
    return print_q43_sufleg()


if __name__ == "__main__":
    sys.exit(main())
