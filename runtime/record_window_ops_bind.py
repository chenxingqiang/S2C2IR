#!/usr/bin/env python3
"""Require the apply window forbidden and allowed op sets.

Imports record_storage_apply. FORBIDDEN and ALLOWED_OTHER are
disjoint. MACHINERY is a subset of FORBIDDEN. The forbidden,
allowed, and machinery names are exactly the host tuples.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_FORBIDDEN = (
    "prefetch",
    "preserve",
    "rematerialize",
    "evict",
    "transfer",
    "restore",
)
_ALLOWED_OTHER = ("compute", "load")
_MACHINERY = ("evict", "transfer")


def _str_tuple(value: object) -> tuple[str, ...] | None:
    if type(value) is not tuple:
        return None
    if any(type(item) is not str for item in value):
        return None
    return value


def window_ops_bound(apply) -> bool:
    """True when the imported window op sets meet the bind."""
    forbidden = _str_tuple(getattr(apply, "FORBIDDEN", None))
    allowed = _str_tuple(getattr(apply, "ALLOWED_OTHER", None))
    machinery = _str_tuple(getattr(apply, "MACHINERY", None))
    if forbidden is None or allowed is None or machinery is None:
        return False
    if not set(forbidden).isdisjoint(allowed):
        return False
    if not set(machinery) <= set(forbidden):
        return False
    if forbidden != _FORBIDDEN:
        return False
    if allowed != _ALLOWED_OTHER:
        return False
    if machinery != _MACHINERY:
        return False
    return True


def _no() -> int:
    print("window-ops-bind no")
    return 1


def print_window_ops_bind() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_storage_apply as apply

        if not window_ops_bound(apply):
            return _no()
        forbidden_count = len(apply.FORBIDDEN)
        allowed_other_count = len(apply.ALLOWED_OTHER)
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    print("window-ops-bind gate=query")
    print(f"forbidden-count {forbidden_count}")
    print(f"allowed-other-count {allowed_other_count}")
    print("window-ops-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-window-ops-bind"]:
        print(
            "record_window_ops_bind: choose --print-window-ops-bind",
            file=sys.stderr,
        )
        return 2
    return print_window_ops_bind()


if __name__ == "__main__":
    sys.exit(main())
