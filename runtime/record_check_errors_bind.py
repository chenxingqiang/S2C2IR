#!/usr/bin/env python3
"""Require the four checking contract-error tokens.

Reads record_realization_checking.ERROR_TOKENS. Does not edit the
checking module or add cases. No semantic cut. can-run-plan stays no.
Query only. Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_realization_checking as chk

_TOKENS = (
    "identity-mismatch",
    "unknown-kind",
    "malformed-legality",
    "invalid-schema",
)


def print_check_errors_bind() -> int:
    try:
        tokens = chk.ERROR_TOKENS
    except AttributeError:
        print("check-errors-bind no")
        return 1
    if tokens != _TOKENS or len(tokens) != 4:
        print("check-errors-bind no")
        return 1
    print("check-errors-bind gate=query")
    for token in tokens:
        print(f"contract-error {token}")
    print("check-errors-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Require the four checking contract-error tokens.",
        add_help=False,
        allow_abbrev=False,
    )
    parser.add_argument("--print-check-errors-bind", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else 2
    if extra or not args.print_check_errors_bind:
        print(
            "record_check_errors_bind: choose --print-check-errors-bind",
            file=sys.stderr,
        )
        return 2
    return print_check_errors_bind()


if __name__ == "__main__":
    sys.exit(main())
