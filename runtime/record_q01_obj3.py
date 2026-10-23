#!/usr/bin/env python3
"""Require OBJECT_3 on the three storage hosts.

record_authorization, record_storage_rewrite, and record_storage_apply
must each expose OBJECT_3 as the string 3.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent


def _no() -> int:
    print("q01-obj3 no")
    return 1


def print_q01_obj3() -> int:
    if str(_RUNTIME) not in sys.path:
        sys.path.insert(0, str(_RUNTIME))
    try:
        import record_authorization as auth
        import record_storage_rewrite as rew
        import record_storage_apply as apply
    except ImportError:
        return _no()
    try:
        auth_object = auth.OBJECT_3
        rew_object = rew.OBJECT_3
        apply_object = apply.OBJECT_3
    except AttributeError:
        return _no()
    if (
        type(auth_object) is not str
        or type(rew_object) is not str
        or type(apply_object) is not str
    ):
        return _no()
    if (auth_object, rew_object, apply_object) != ("3", "3", "3"):
        return _no()
    print("q01-obj3 gate=query")
    print("object-3 " + auth.OBJECT_3)
    print("q01-obj3 yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q01-obj3"]:
        print(
            "record_q01_obj3: choose --print-q01-obj3",
            file=sys.stderr,
        )
        return 2
    return print_q01_obj3()


if __name__ == "__main__":
    sys.exit(main())
