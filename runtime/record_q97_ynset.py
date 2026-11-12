#!/usr/bin/env python3
"""Require the shared yes, no, n/a query value set.

record_sufficiency.RESULTS, APPLICABILITY_VALUES, and
OCCUPANCY_USABLE_VALUES stay ("yes", "no", "n/a"). Query only.
Does not call run_analyzer. Does not add a predicate, device,
dialect, backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_FLAG = "--print-q97-ynset"
_EXPECTED = ("yes", "no", "n/a")


def print_q97_ynset() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_sufficiency
        import record_capability_applicability

        ok = (
            record_sufficiency.RESULTS
            == record_capability_applicability.APPLICABILITY_VALUES
            == record_capability_applicability.OCCUPANCY_USABLE_VALUES
            == _EXPECTED
        )
    except (ImportError, AttributeError, OSError, RuntimeError, TypeError):
        print("q97-ynset no")
        return 1
    if not ok:
        print("q97-ynset no")
        return 1
    print("q97-ynset gate=query")
    print("value-set " + ",".join(_EXPECTED))
    print("q97-ynset yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q97_ynset: choose --print-q97-ynset",
            file=sys.stderr,
        )
        return 2
    return print_q97_ynset()


if __name__ == "__main__":
    sys.exit(main())
