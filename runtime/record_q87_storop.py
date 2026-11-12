#!/usr/bin/env python3
"""Require Stor_Op mnemonics in StorageOps.td to stay the seven storage ops.

Reads include/s2c2/Storage/StorageOps.td from the repo root and extracts
Stor_Op<"mnemonic"> definitions in file order. Query only. Does not add
an op, predicate, device, dialect, backend, or semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_TD = _ROOT / "include" / "s2c2" / "Storage" / "StorageOps.td"
_OPS = (
    "object",
    "materialize",
    "transfer",
    "alloc",
    "dealloc",
    "pack",
    "unpack",
)
_FLAG = "--print-q87-storop"
_PATTERN = re.compile(r'Stor_Op<"([^"]+)"')


def stor_mnemonics(text: str) -> tuple[str, ...]:
    """Stor_Op mnemonics in the order they appear in the TableGen file."""
    return tuple(_PATTERN.findall(text))


def print_q87_storop() -> int:
    try:
        ops = stor_mnemonics(_TD.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, re.error):
        print("q87-storop no")
        return 1
    if ops != _OPS:
        print("q87-storop no")
        return 1
    print("q87-storop gate=query")
    for name in ops:
        print(f"stor-op {name}")
    print("q87-storop yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q87_storop: choose --print-q87-storop",
            file=sys.stderr,
        )
        return 2
    return print_q87_storop()


if __name__ == "__main__":
    sys.exit(main())
