#!/usr/bin/env python3
"""Require the twelve authorization reason tokens to stay in the authorization namespace.

Reads record_authorization.AUTHORIZATION_REASON_TOKENS. Every entry
must start with "authorization." and the length must be 12. The tuple
must contain authorization.action-mismatch and
authorization.rewrite-license-missing. Does not add tokens.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

_PREFIX = "authorization."
_COUNT = 12
_ACTION_MISMATCH = "authorization.action-mismatch"
_LICENSE_MISSING = "authorization.rewrite-license-missing"


def _auth_reason_tokens():
    import record_authorization as auth

    return auth.AUTHORIZATION_REASON_TOKENS


def _namespace_bound(tokens) -> bool:
    """True when tokens is the twelve-entry authorization. tuple."""
    if type(tokens) is not tuple or len(tokens) != _COUNT:
        return False
    for token in tokens:
        if type(token) is not str or not token.startswith(_PREFIX):
            return False
    if _ACTION_MISMATCH not in tokens or _LICENSE_MISSING not in tokens:
        return False
    return True


def print_auth_reasons_bind() -> int:
    try:
        tokens = _auth_reason_tokens()
    except Exception:
        print("auth-reasons-bind no")
        return 1
    if not _namespace_bound(tokens):
        print("auth-reasons-bind no")
        return 1
    count = len(tokens)
    print("auth-reasons-bind gate=query")
    print(f"auth-reason-count {count}")
    print("auth-reasons-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-auth-reasons-bind"]:
        print(
            "record_auth_reasons_bind: choose --print-auth-reasons-bind",
            file=sys.stderr,
        )
        return 2
    return print_auth_reasons_bind()


if __name__ == "__main__":
    sys.exit(main())
