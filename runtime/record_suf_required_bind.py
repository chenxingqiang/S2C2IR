#!/usr/bin/env python3
"""Require the sufficiency required predicates and ignored extras.

Counts and joins come from the sufficiency tuples. This printer
does not add predicates or open a semantic cut. can-run-plan
stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_sufficiency as suf

_REQUIRED = (
    "usable",
    "restore-ordering",
    "dest-invalidation",
    "capacity-legal",
)
_IGNORED_EXTRA = ("applicable", "authorized")
_RESULTS = ("yes", "no", "n/a")


def print_suf_required_bind() -> int:
    try:
        required = suf.REQUIRED
        ignored = suf.IGNORED_EXTRA
        results = suf.RESULTS
    except AttributeError:
        print("suf-required-bind no")
        return 1
    if (
        required != _REQUIRED
        or ignored != _IGNORED_EXTRA
        or results != _RESULTS
    ):
        print("suf-required-bind no")
        return 1
    try:
        required_count = len(required)
        ignored_extra = ",".join(ignored)
        result_text = ",".join(results)
    except TypeError:
        print("suf-required-bind no")
        return 1
    print("suf-required-bind gate=query")
    print(f"required-count {required_count}")
    print(f"ignored-extra {ignored_extra}")
    print(f"results {result_text}")
    print("suf-required-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-suf-required-bind"]:
        print(
            "record_suf_required_bind: choose --print-suf-required-bind",
            file=sys.stderr,
        )
        return 2
    return print_suf_required_bind()


if __name__ == "__main__":
    sys.exit(main())
