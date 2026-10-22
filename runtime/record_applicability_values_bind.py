#!/usr/bin/env python3
"""Bind applicability, provenance, and occupancy-usable value sets.

APPLICABILITY_VALUES, PROVENANCE_VALUES, and OCCUPANCY_USABLE_VALUES
stay ("yes", "no", "n/a"), ("catalog", "occupancy-query", "unknown"),
and ("yes", "no", "n/a"). Query only. No semantic cut. can-run-plan
stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

APPLICABILITY_VALUES = ("yes", "no", "n/a")
PROVENANCE_VALUES = ("catalog", "occupancy-query", "unknown")
OCCUPANCY_USABLE_VALUES = ("yes", "no", "n/a")

_FLAG = "--print-applicability-values-bind"


def _exact(got: object, expected: tuple[str, ...]) -> bool:
    """True when got is that tuple of str, in that order."""
    if type(got) is not tuple or len(got) != len(expected):
        return False
    for item, want in zip(got, expected):
        if type(item) is not str or item != want:
            return False
    return True


def _joined(values: tuple[str, ...]) -> str:
    return ",".join(values)


def _no() -> int:
    print("applicability-values-bind no")
    return 1


def print_applicability_values_bind() -> int:
    try:
        import record_capability_applicability as capa

        applicability = capa.APPLICABILITY_VALUES
        provenance = capa.PROVENANCE_VALUES
        occupancy_usable = capa.OCCUPANCY_USABLE_VALUES
    except Exception:
        return _no()
    if not (
        _exact(applicability, APPLICABILITY_VALUES)
        and _exact(provenance, PROVENANCE_VALUES)
        and _exact(occupancy_usable, OCCUPANCY_USABLE_VALUES)
    ):
        return _no()
    print("applicability-values-bind gate=query")
    print("applicability " + _joined(applicability))
    print("provenance " + _joined(provenance))
    print("occupancy-usable " + _joined(occupancy_usable))
    print("applicability-values-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args != [_FLAG]:
        print(
            "record_applicability_values_bind: choose "
            "--print-applicability-values-bind",
            file=sys.stderr,
        )
        return 2
    return print_applicability_values_bind()


if __name__ == "__main__":
    sys.exit(main())
