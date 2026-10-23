#!/usr/bin/env python3
"""Query the frozen scenario-corpus identity pins.

Reads CORPUS_ID, BASELINE, and EXPECTED_FINGERPRINT from
record_scenario_corpus. Does not edit that module. No semantic cut.
can-run-plan stays no. Query only.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_FLAG = "--print-q11-corpin"
_CORPUS_ID = "w0-3-2-scenario-corpus-v1"
_BASELINE = "71a6880dbaaac929bac837af0b7fbcad78708bb4"
_FINGERPRINT = "52bf4be9680046a725f9f79c7abf2d045efbd7d03b3cb87a355419b67a7a0d00"


def print_q11_corpin() -> int:
    if str(_RUNTIME) not in sys.path:
        sys.path.insert(0, str(_RUNTIME))
    import record_scenario_corpus as corpus

    corpus_id = corpus.CORPUS_ID
    baseline = corpus.BASELINE
    fingerprint = corpus.EXPECTED_FINGERPRINT
    if (
        corpus_id != _CORPUS_ID
        or baseline != _BASELINE
        or fingerprint != _FINGERPRINT
        or len(fingerprint) != 64
    ):
        print("q11-corpin no")
        return 1
    print("q11-corpin gate=query")
    print("corpus-id " + corpus_id)
    print("corpus-baseline " + baseline)
    print("corpus-fingerprint " + fingerprint)
    print("q11-corpin yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q11_corpin: choose --print-q11-corpin",
            file=sys.stderr,
        )
        return 2
    return print_q11_corpin()


if __name__ == "__main__":
    sys.exit(main())
