#!/usr/bin/env python3
"""Require REVISION_FROM_NAME to stay the measured-storage revision map.

Reads record_evidence.REVISION_FROM_NAME in insertion order. Query only.
Does not add a predicate, device, dialect, backend, or semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_REVISION_FROM_NAME = {
    "storage-measured-v1.jsonl": "fixture-v1",
    "storage-measured-v1-4090.jsonl": "5a-pipeline-4090",
    "storage-measured-v1-910b.jsonl": "5a-pipeline-910b",
    "storage-measured-v1-hierarchy-4090.jsonl": "5b-hierarchy-4090",
    "storage-measured-v1-hierarchy-910b.jsonl": "5b-hierarchy-910b",
    "storage-measured-v1-ntile-4090.jsonl": "5c-ntile-4090",
    "storage-measured-v1-ntile-910b.jsonl": "5c-ntile-910b",
    "storage-measured-v1-loop-4090.jsonl": "5d-loop-4090",
    "storage-measured-v1-loop-910b.jsonl": "5d-loop-910b",
}


def _no() -> int:
    print("q49-revmap no")
    return 1


def print_q49_revmap() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_evidence

        revmap = record_evidence.REVISION_FROM_NAME
        pairs = list(revmap.items())
    except (ImportError, AttributeError, OSError, SyntaxError, TypeError):
        return _no()
    expected = list(_REVISION_FROM_NAME.items())
    if revmap != _REVISION_FROM_NAME or pairs != expected:
        return _no()
    print("q49-revmap gate=query")
    for name, revision in pairs:
        print(f"revision {name} {revision}")
    print("q49-revmap yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q49-revmap"]:
        print(
            "record_q49_revmap: choose --print-q49-revmap",
            file=sys.stderr,
        )
        return 2
    return print_q49_revmap()


if __name__ == "__main__":
    sys.exit(main())
