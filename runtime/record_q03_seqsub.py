#!/usr/bin/env python3
"""Require SEQUENCE_SUBJECT to stay rewrite-sequence.

Imports record_storage_rewrite inside the query. Query only.
No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_SUBJECT = "rewrite-sequence"


def _no() -> int:
    print("q03-seqsub no")
    return 1


def print_q03_seqsub() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_storage_rewrite as rew

        subject = rew.SEQUENCE_SUBJECT
        if type(subject) is not str or subject != _SUBJECT:
            return _no()
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    print("q03-seqsub gate=query")
    print("sequence-subject " + subject)
    print("q03-seqsub yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q03-seqsub"]:
        print(
            "record_q03_seqsub: choose --print-q03-seqsub",
            file=sys.stderr,
        )
        return 2
    return print_q03_seqsub()


if __name__ == "__main__":
    sys.exit(main())
