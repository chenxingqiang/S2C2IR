#!/usr/bin/env python3
"""Require TRANSFORMATION_V01 on rewrite and apply.

record_storage_rewrite and record_storage_apply must each expose
TRANSFORMATION_V01 as the string keep-evict-transfer-restore.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_TRANSFORMATION = "keep-evict-transfer-restore"


def _no() -> int:
    print("q02-xform no")
    return 1


def print_q02_xform() -> int:
    runtime = str(Path(__file__).resolve().parent)
    sys.path.insert(0, runtime)
    try:
        import record_storage_rewrite
        import record_storage_apply

        rewrite_transformation = record_storage_rewrite.TRANSFORMATION_V01
        apply_transformation = record_storage_apply.TRANSFORMATION_V01
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    if (
        type(rewrite_transformation) is not str
        or type(apply_transformation) is not str
        or (rewrite_transformation, apply_transformation)
        != (_TRANSFORMATION, _TRANSFORMATION)
    ):
        return _no()
    # The printed transformation is the live constant.
    print("q02-xform gate=query")
    print("transformation " + record_storage_rewrite.TRANSFORMATION_V01)
    print("q02-xform yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q02-xform"]:
        print(
            "record_q02_xform: choose --print-q02-xform",
            file=sys.stderr,
        )
        return 2
    return print_q02_xform()


if __name__ == "__main__":
    sys.exit(main())
