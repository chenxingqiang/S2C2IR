#!/usr/bin/env python3
"""Require CUDA_ANALYZE to stay the ledger key and flag map.

Reads record_hw_ledger.CUDA_ANALYZE. Compares equality and items()
order. Query only. Does not call run_analyzer. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_CUDA_ANALYZE = {
    "cap-schema": "--analyze-cap-schema",
    "cap": "--analyze-cap",
    "phase": "--analyze-phase",
    "pipe": "--analyze-pipe",
    "pipe-tiles": "--analyze-pipe-tiles",
    "cuda-val": "--analyze-cuda-val",
    "cuda-val-mem": "--analyze-cuda-val-mem",
    "cuda-val-cc": "--analyze-cuda-val-cc",
    "cuda-val-async": "--analyze-cuda-val-async",
    "matched": "--analyze-matched",
    "ratio": "--analyze-ratio",
}


def _no() -> int:
    print("q19-cuakey no")
    return 1


def print_q19_cuakey() -> int:
    try:
        sys.path.insert(0, str(_RUNTIME))
        import record_hw_ledger

        cuda = record_hw_ledger.CUDA_ANALYZE
        if cuda != _CUDA_ANALYZE:
            return _no()
        if tuple(cuda.items()) != tuple(_CUDA_ANALYZE.items()):
            return _no()
    except Exception:
        return _no()
    print("q19-cuakey gate=query")
    for name, flag in cuda.items():
        print(f"analyze {name} {flag}")
    print("q19-cuakey yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q19-cuakey"]:
        print(
            "record_q19_cuakey: choose --print-q19-cuakey",
            file=sys.stderr,
        )
        return 2
    return print_q19_cuakey()


if __name__ == "__main__":
    sys.exit(main())
