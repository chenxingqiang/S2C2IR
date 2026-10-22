#!/usr/bin/env python3
"""Require one SELECTED_S0 and one SELECTED_S1 across four hosts.

suf, auth, rew, and apply must carry the same SELECTED_S0,
keep{0,1}|evict{2}|rematerialize{}, and the same SELECTED_S1,
keep{1,2}|evict{0}|rematerialize{}. Query only. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_S0 = "keep{0,1}|evict{2}|rematerialize{}"
_S1 = "keep{1,2}|evict{0}|rematerialize{}"


def _no() -> int:
    print("selected-s0-bind no")
    return 1


def _selection(module, name: str) -> str:
    value = getattr(module, name)
    if type(value) is not str:
        raise TypeError(name)
    return value


def print_selected_s0_bind() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_authorization as auth
        import record_storage_apply as apply
        import record_storage_rewrite as rew
        import record_sufficiency as suf

        hosts = (suf, auth, rew, apply)
        selected_s0 = tuple(_selection(module, "SELECTED_S0") for module in hosts)
        selected_s1 = tuple(_selection(module, "SELECTED_S1") for module in hosts)
    except (ImportError, AttributeError, TypeError):
        return _no()
    if selected_s0 != (_S0, _S0, _S0, _S0):
        return _no()
    if selected_s1 != (_S1, _S1, _S1, _S1):
        return _no()
    print("selected-s0-bind gate=query")
    print("selected-s0 " + suf.SELECTED_S0)
    print("selected-s1 " + suf.SELECTED_S1)
    print("selected-s0-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-selected-s0-bind"]:
        print(
            "record_selected_s0_bind: choose --print-selected-s0-bind",
            file=sys.stderr,
        )
        return 2
    return print_selected_s0_bind()


if __name__ == "__main__":
    sys.exit(main())
