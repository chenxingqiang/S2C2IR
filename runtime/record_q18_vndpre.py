#!/usr/bin/env python3
"""Require the ledger vendor-key prefixes.

VENDOR_KEY_PREFIX on record_hw_ledger must stay
("acl_", "davinci_", "cube_", "vectorcore_").
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_REQUIRED = ("acl_", "davinci_", "cube_", "vectorcore_")


def _no() -> int:
    print("q18-vndpre no")
    return 1


def print_q18_vndpre() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_hw_ledger

        prefixes = record_hw_ledger.VENDOR_KEY_PREFIX
        if prefixes != _REQUIRED:
            return _no()
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    print("q18-vndpre gate=query")
    for prefix in prefixes:
        print("vendor-prefix " + prefix)
    print("q18-vndpre yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q18-vndpre"]:
        print(
            "record_q18_vndpre: choose --print-q18-vndpre",
            file=sys.stderr,
        )
        return 2
    return print_q18_vndpre()


if __name__ == "__main__":
    sys.exit(main())
