#!/usr/bin/env python3
"""Require ACTION_V01 on the three storage hosts.

record_authorization, record_storage_rewrite, and record_storage_apply
must each expose ACTION_V01 as the same string storage-rewrite.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

_ACTION = "storage-rewrite"


def _no() -> int:
    print("action-v01-bind no")
    return 1


def print_action_v01_bind() -> int:
    try:
        import record_authorization as auth
        import record_storage_apply as apply
        import record_storage_rewrite as rew
    except ImportError:
        return _no()
    try:
        auth_action = auth.ACTION_V01
        rew_action = rew.ACTION_V01
        apply_action = apply.ACTION_V01
    except AttributeError:
        return _no()
    if (
        type(auth_action) is not str
        or type(rew_action) is not str
        or type(apply_action) is not str
    ):
        return _no()
    if (auth_action, rew_action, apply_action) != (_ACTION, _ACTION, _ACTION):
        return _no()
    # The printed action is the live constant, not a second copy of _ACTION.
    print("action-v01-bind gate=query")
    print("action " + auth.ACTION_V01)
    print("action-v01-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-action-v01-bind"]:
        print(
            "record_action_v01_bind: choose --print-action-v01-bind",
            file=sys.stderr,
        )
        return 2
    return print_action_v01_bind()


if __name__ == "__main__":
    sys.exit(main())
