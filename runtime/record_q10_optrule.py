#!/usr/bin/env python3
"""Query the optimum authorization schema and rule.

Reads SCHEMA and RULE from record_optimum_authorization and
AUTH_SCHEMA from record_authorization. Query only. No semantic
cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_SCHEMA = "s2c2.optimum_authorization.v1"
_RULE = "unique-minimum-cost"


def _no() -> int:
    print("q10-optrule no")
    return 1


def print_q10_optrule() -> int:
    sys.path.insert(0, str(_RUNTIME))
    try:
        import record_optimum_authorization as optimum
        import record_authorization as auth
    except ImportError:
        return _no()
    try:
        schema = optimum.SCHEMA
        rule = optimum.RULE
        auth_schema = auth.AUTH_SCHEMA
    except AttributeError:
        return _no()
    if schema != _SCHEMA or rule != _RULE or schema == auth_schema:
        return _no()
    print("q10-optrule gate=query")
    print("optimum-schema " + schema)
    print("optimum-rule " + rule)
    print("q10-optrule yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q10-optrule"]:
        print(
            "record_q10_optrule: choose --print-q10-optrule",
            file=sys.stderr,
        )
        return 2
    return print_q10_optrule()


if __name__ == "__main__":
    sys.exit(main())
