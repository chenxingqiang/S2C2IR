#!/usr/bin/env python3
"""Require the loaded ledger to have 31 rows on rtx4090 and ascend910b.

Imports record_hw_ledger and calls load_ledger on its ledger path.
Query only. Does not call run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_hw_ledger


def print_ledger_rows_bind() -> int:
    try:
        rows = record_hw_ledger.load_ledger(record_hw_ledger._LEDGER_PATH)
        hardware = {row["hardware"] for row in rows}
        count = len(rows)
        if count != 31 or hardware != set(record_hw_ledger.LEDGER_HARDWARE):
            print("ledger-rows-bind no")
            return 1
        names = sorted(hardware, key=record_hw_ledger.LEDGER_HARDWARE.index)
    except (
        OSError,
        ValueError,
        json.JSONDecodeError,
        AttributeError,
        TypeError,
        KeyError,
    ):
        print("ledger-rows-bind no")
        return 1
    print("ledger-rows-bind gate=query")
    print(f"ledger-records {count}")
    print(f"ledger-hardware {','.join(names)}")
    print("ledger-rows-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Hardware ledger row bind",
        add_help=False,
    )
    parser.add_argument("--print-ledger-rows-bind", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        if not isinstance(code, int) or code == 0:
            return 2
        return code
    if extra or not args.print_ledger_rows_bind:
        print(
            "record_ledger_rows_bind: choose --print-ledger-rows-bind",
            file=sys.stderr,
        )
        return 2
    return print_ledger_rows_bind()


if __name__ == "__main__":
    sys.exit(main())
