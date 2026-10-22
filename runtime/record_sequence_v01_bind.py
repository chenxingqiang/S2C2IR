#!/usr/bin/env python3
"""Require the v0.1 rewrite sequence to match across rewrite and apply.

Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))


def print_sequence_v01_bind() -> int:
    try:
        import record_storage_apply as apply
        import record_storage_rewrite as rew

        rewrite_sequence = rew.SEQUENCE_V01
        apply_sequence = apply.SEQUENCE_V01
    except (AttributeError, ImportError):
        print("sequence-v01-bind no")
        return 1
    if not (
        rewrite_sequence
        == apply_sequence
        == ("KEEP", "EVICT", "TRANSFER", "RESTORE")
    ):
        print("sequence-v01-bind no")
        return 1
    print("sequence-v01-bind gate=query")
    print("sequence " + ",".join(rewrite_sequence))
    print("sequence-v01-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Bind the v0.1 rewrite sequence across rewrite and apply.",
        add_help=False,
    )
    parser.add_argument("--print-sequence-v01-bind", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else 2
    if extra or not args.print_sequence_v01_bind:
        print(
            "record_sequence_v01_bind: choose --print-sequence-v01-bind",
            file=sys.stderr,
        )
        return 2
    return print_sequence_v01_bind()


if __name__ == "__main__":
    sys.exit(main())
