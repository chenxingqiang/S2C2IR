#!/usr/bin/env python3
"""Require the xid case target column.

Reads record_realization_checking_xid._cases(). Each row is
(name, records, target, device, claim). The target column stays
cuda, ascend, cpu, ascend, and the set of those targets stays
cuda, ascend, and cpu. Does not add a case. Does not call
run_analyzer. Does not add a predicate, device, dialect, backend,
or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_TARGETS = ("cuda", "ascend", "cpu", "ascend")
_TARGET_SET = {"cuda", "ascend", "cpu"}
_FLAG = "--print-q100-xidtgt"


def print_q100_xidtgt() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_realization_checking_xid as xid

        targets = tuple(
            target
            for _name, _records, target, _device, _claim in xid._cases()
        )
    except (
        AttributeError,
        ImportError,
        OSError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        print("q100-xidtgt no")
        return 1
    if targets != _TARGETS or set(targets) != _TARGET_SET:
        print("q100-xidtgt no")
        return 1
    print("q100-xidtgt gate=query")
    for target in targets:
        print(f"xid-target {target}")
    print("q100-xidtgt yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q100_xidtgt: choose --print-q100-xidtgt",
            file=sys.stderr,
        )
        return 2
    return print_q100_xidtgt()


if __name__ == "__main__":
    sys.exit(main())
