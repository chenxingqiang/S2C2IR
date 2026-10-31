#!/usr/bin/env python3
"""Require Comm_Op mnemonics in CommOps.td to stay copy, stream, barrier.

Reads include/s2c2/Comm/CommOps.td from the repo root and extracts
Comm_Op<"mnemonic" definitions in file order. Query only. Does not add
an op, predicate, device, dialect, backend, or semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
_COMM_OPS = _ROOT / "include" / "s2c2" / "Comm" / "CommOps.td"
_MNEMONICS = ("copy", "stream", "barrier")
_FLAG = "--print-q89-commop"
_OP = re.compile(r'Comm_Op<"([^"]+)"')


def comm_mnemonics(text: str) -> tuple[str, ...]:
    """Return Comm_Op<"mnemonic" names in the order they appear."""
    return tuple(_OP.findall(text))


def print_q89_commop() -> int:
    try:
        text = _COMM_OPS.read_text(encoding="utf-8")
        names = comm_mnemonics(text)
    except (OSError, UnicodeError, ValueError):
        print("q89-commop no")
        return 1
    if names != _MNEMONICS:
        print("q89-commop no")
        return 1
    print("q89-commop gate=query")
    for name in names:
        print(f"comm-op {name}")
    print("q89-commop yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q89_commop: choose --print-q89-commop",
            file=sys.stderr,
        )
        return 2
    return print_q89_commop()


if __name__ == "__main__":
    sys.exit(main())
