#!/usr/bin/env python3
"""Require object 2 to match across sufficiency, authorization, rewrite, and apply.

suf.OBJECT_2, auth.OBJECT_2, rew.OBJECT_2, and apply.OBJECT_2 stay the
same string, 2, and not the prose token O2. Query only. No semantic
cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent


def _shared_object() -> str | None:
    if str(_RUNTIME) not in sys.path:
        sys.path.insert(0, str(_RUNTIME))
    import record_sufficiency as suf
    import record_authorization as auth
    import record_storage_rewrite as rew
    import record_storage_apply as apply

    values = (suf.OBJECT_2, auth.OBJECT_2, rew.OBJECT_2, apply.OBJECT_2)
    if any(type(value) is not str for value in values):
        return None
    if any(value == "O2" for value in values):
        return None
    canonical = suf.OBJECT_2
    if canonical != "2" or any(value != canonical for value in values):
        return None
    return canonical


def print_object2_bind() -> int:
    try:
        canonical = _shared_object()
    except (ImportError, AttributeError, SyntaxError, OSError, TypeError):
        print("object2-bind no")
        return 1
    if canonical is None:
        print("object2-bind no")
        return 1
    print("object2-bind gate=query")
    print("object-canonical " + canonical)
    print("object2-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-object2-bind"]:
        print(
            "record_object2_bind: choose --print-object2-bind",
            file=sys.stderr,
        )
        return 2
    return print_object2_bind()


if __name__ == "__main__":
    sys.exit(main())
