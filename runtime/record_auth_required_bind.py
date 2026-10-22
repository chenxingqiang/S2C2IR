#!/usr/bin/env python3
"""Require the authorization required inputs and policy id.

Reads record_authorization.REQUIRED, POLICY_V01, and LICENSE_SUBJECT.
REQUIRED stays (sufficient, policy-match, provenance, action-match).
POLICY_V01 stays authorization-policy-v0.1. LICENSE_SUBJECT stays
rewrite-license. Query only. Does not add required inputs and does
not open a semantic cut. can-run-plan stays no. Do not print
authorization=yes or rewrite-license=yes.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_REQUIRED = (
    "sufficient",
    "policy-match",
    "provenance",
    "action-match",
)
_POLICY = "authorization-policy-v0.1"
_LICENSE = "rewrite-license"


def print_auth_required_bind() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_authorization as auth

        required = auth.REQUIRED
        policy = auth.POLICY_V01
        license_subject = auth.LICENSE_SUBJECT
    except (ImportError, AttributeError, OSError, SyntaxError):
        print("auth-required-bind no")
        return 1
    if (
        type(required) is not tuple
        or required != _REQUIRED
        or len(required) != 4
        or type(policy) is not str
        or policy != _POLICY
        or type(license_subject) is not str
        or license_subject != _LICENSE
    ):
        print("auth-required-bind no")
        return 1
    # Count, policy, and license subject are the host constants.
    print("auth-required-bind gate=query")
    print(f"required-count {len(auth.REQUIRED)}")
    print(f"policy {auth.POLICY_V01}")
    print(f"license-subject {auth.LICENSE_SUBJECT}")
    print("auth-required-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-auth-required-bind"]:
        print(
            "record_auth_required_bind: choose --print-auth-required-bind",
            file=sys.stderr,
        )
        return 2
    return print_auth_required_bind()


if __name__ == "__main__":
    sys.exit(main())
