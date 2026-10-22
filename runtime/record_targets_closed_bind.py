#!/usr/bin/env python3
"""Require the closed capability targets to stay the seven names.

Reads record_capability_applicability.TARGETS. Does not edit the
applicability module or add targets. No semantic cut. can-run-plan
stays no. Query only.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_capability_applicability as capa

_TARGETS = ("cpu", "cuda", "rocm", "sycl", "ascend", "npu", "cim")


def print_targets_closed_bind() -> int:
    try:
        targets = capa.TARGETS
        closed = targets == _TARGETS and len(targets) == 7
    except (AttributeError, TypeError):
        print("targets-closed-bind no")
        return 1
    if not closed:
        print("targets-closed-bind no")
        return 1
    print("gate=query")
    for name in targets:
        print(f"target {name}")
    print("targets-closed-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Require the closed capability targets to stay the seven names.",
        add_help=False,
        allow_abbrev=False,
    )
    parser.add_argument("--print-targets-closed-bind", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else 2
    if extra or not args.print_targets_closed_bind:
        print(
            "record_targets_closed_bind: choose --print-targets-closed-bind",
            file=sys.stderr,
        )
        return 2
    return print_targets_closed_bind()


if __name__ == "__main__":
    sys.exit(main())
