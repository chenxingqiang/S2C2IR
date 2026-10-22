#!/usr/bin/env python3
"""Bind REWRITE_REASON_TOKENS to the rewrite. namespace.

Query only. Every entry must start with "rewrite." and the tuple
must be non-empty. This does not add tokens or open a semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))


def _rewrite_reason_tokens():
    import record_storage_rewrite as rew

    return rew.REWRITE_REASON_TOKENS


def _namespace_bound(tokens) -> bool:
    """True when tokens is a non-empty tuple of rewrite. strings."""
    if type(tokens) is not tuple or len(tokens) == 0:
        return False
    for token in tokens:
        if type(token) is not str or not token.startswith("rewrite."):
            return False
    return True


def print_rewrite_reasons_bind() -> int:
    try:
        tokens = _rewrite_reason_tokens()
    except Exception:
        print("rewrite-reasons-bind no")
        return 1
    if not _namespace_bound(tokens):
        print("rewrite-reasons-bind no")
        return 1
    count = len(tokens)
    print("rewrite-reasons-bind gate=query")
    print(f"rewrite-reason-count {count}")
    print("rewrite-reasons-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-rewrite-reasons-bind"]:
        print(
            "record_rewrite_reasons_bind: choose --print-rewrite-reasons-bind",
            file=sys.stderr,
        )
        return 2
    return print_rewrite_reasons_bind()


if __name__ == "__main__":
    sys.exit(main())
