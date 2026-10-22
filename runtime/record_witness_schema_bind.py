#!/usr/bin/env python3
"""Bind the apply witness schema apart from the apply chain schemas.

Reads the apply module constants. Query only. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_WITNESS = "s2c2.apply_legality_witness.v1"


def _load_apply():
    if str(_RUNTIME) not in sys.path:
        sys.path.insert(0, str(_RUNTIME))
    import record_storage_apply as apply

    return apply


def witness_distinct(apply) -> bool:
    """True when the witness schema is the required literal and not a chain schema."""
    try:
        witness = apply.WITNESS_SCHEMA
        chain = (
            apply.APPLY_SCHEMA,
            apply.REWRITE_SCHEMA,
            apply.AUTH_SCHEMA,
            apply.DECISION_SCHEMA,
        )
    except AttributeError:
        return False
    if type(witness) is not str or witness != _WITNESS:
        return False
    return all(type(schema) is str and schema != witness for schema in chain)


def _no() -> int:
    print("witness-schema-bind no")
    return 1


def print_witness_schema_bind() -> int:
    try:
        apply = _load_apply()
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError):
        return _no()
    if not witness_distinct(apply):
        return _no()
    witness = apply.WITNESS_SCHEMA
    apply_schema = apply.APPLY_SCHEMA
    print("witness-schema-bind gate=query")
    print(f"witness-schema {witness}")
    print(f"apply-schema {apply_schema}")
    print("witness-schema-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Apply witness schema bind",
        add_help=False,
    )
    parser.add_argument("--print-witness-schema-bind", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        if not isinstance(code, int) or code == 0:
            return 2
        return code
    if extra or not args.print_witness_schema_bind:
        print(
            "record_witness_schema_bind: choose --print-witness-schema-bind",
            file=sys.stderr,
        )
        return 2
    return print_witness_schema_bind()


if __name__ == "__main__":
    sys.exit(main())
