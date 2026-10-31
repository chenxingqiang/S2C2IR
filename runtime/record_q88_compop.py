#!/usr/bin/env python3
"""Require Comp_Op mnemonics in ComputeOps.td to stay the query set.

Reads include/s2c2/Compute/ComputeOps.td from the repo root. Extracts
Comp_Op<"mnemonic" definitions in file order. The mnemonics must be
exactly matmul, elemwise, gated_mlp. Does not add an op, predicate,
device, dialect, backend, or semantic cut. Query only. can-run-plan
stays no.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_TD = _ROOT / "include" / "s2c2" / "Compute" / "ComputeOps.td"
_MNEMONICS = ("matmul", "elemwise", "gated_mlp")
_FLAG = "--print-q88-compop"
_OP = re.compile(r'Comp_Op<"([^"]+)"')


def comp_mnemonics(text: str) -> tuple[str, ...]:
    """Comp_Op mnemonics in the order they appear in the TableGen file."""
    return tuple(_OP.findall(text))


def print_q88_compop() -> int:
    try:
        names = comp_mnemonics(_TD.read_text(encoding="utf-8"))
    except (OSError, UnicodeError):
        print("q88-compop no")
        return 1
    if names != _MNEMONICS:
        print("q88-compop no")
        return 1
    print("q88-compop gate=query")
    for name in names:
        print(f"comp-op {name}")
    print("q88-compop yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q88_compop: choose --print-q88-compop",
            file=sys.stderr,
        )
        return 2
    return print_q88_compop()


if __name__ == "__main__":
    sys.exit(main())
