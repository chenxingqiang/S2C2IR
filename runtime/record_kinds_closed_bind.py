#!/usr/bin/env python3
"""Require the closed capability kinds to stay the three named kinds.

Query only. Does not add kinds. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_CLOSED = ("concurrent-pair", "named-nonblocking", "staged-dma")
_FLAG = "--print-kinds-closed-bind"


def _kinds() -> tuple:
    """Return capa.KINDS when it is exactly the closed three-kind tuple."""
    if str(_RUNTIME) not in sys.path:
        sys.path.insert(0, str(_RUNTIME))
    import record_capability_applicability as capa

    kinds = capa.KINDS
    if kinds != _CLOSED or len(kinds) != 3:
        raise RuntimeError("kinds")
    return kinds


def print_kinds_closed_bind() -> int:
    try:
        kinds = _kinds()
    except Exception:
        print("kinds-closed-bind no")
        return 1
    print("kinds-closed-bind gate=query")
    for kind in kinds:
        print(f"kind {kind}")
    print("kinds-closed-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_kinds_closed_bind: choose --print-kinds-closed-bind",
            file=sys.stderr,
        )
        return 2
    return print_kinds_closed_bind()


if __name__ == "__main__":
    sys.exit(main())
