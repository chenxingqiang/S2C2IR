#!/usr/bin/env python3
"""Compare the authorization schema with the decision schema.

Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_authorization as auth

_AUTH_SCHEMA = "s2c2.authorization.v1"
_DECISION_SCHEMA = "s2c2.decision.v1"


def print_auth_schema_bind() -> int:
    try:
        authorization_schema = auth.AUTH_SCHEMA
        decision_schema = auth.DECISION_SCHEMA
    except AttributeError:
        print("auth-schema-bind no")
        return 1
    if (
        authorization_schema == decision_schema
        or authorization_schema != _AUTH_SCHEMA
        or decision_schema != _DECISION_SCHEMA
    ):
        print("auth-schema-bind no")
        return 1
    print("auth-schema-bind gate=query")
    print(f"authorization-schema {authorization_schema}")
    print(f"decision-schema {decision_schema}")
    print("auth-schema-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-auth-schema-bind"]:
        print(
            "record_auth_schema_bind: choose --print-auth-schema-bind",
            file=sys.stderr,
        )
        return 2
    return print_auth_schema_bind()


if __name__ == "__main__":
    sys.exit(main())
