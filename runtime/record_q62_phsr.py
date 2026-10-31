#!/usr/bin/env python3
"""Require the v3 phase ratios and k max to stay the query set.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
PHASE_R must equal (0.01, 0.03, 0.1, 0.3, 1.0, 3.0, 10.0, 30.0) by
== against those literals. PHASE_K_MAX must equal 4096. Prints the
ratio text, not a binary repr. Does not call run_analyzer. Does not
add a predicate, device, dialect, backend, or semantic cut. Query
only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_PHASE_R = (0.01, 0.03, 0.1, 0.3, 1.0, 3.0, 10.0, 30.0)
_PHASE_R_TEXT = ("0.01", "0.03", "0.1", "0.3", "1.0", "3.0", "10.0", "30.0")
_PHASE_K_MAX = 4096
_FLAG = "--print-q62-phsr"


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location("s2c2_cuda_q62_phsr", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q62-phsr no")
    return 1


def _ratios_match(phase_r: object) -> bool:
    if type(phase_r) is not tuple or len(phase_r) != len(_PHASE_R):
        return False
    for got, expect in zip(phase_r, _PHASE_R):
        if type(got) is not float or not (got == expect):
            return False
    return phase_r == _PHASE_R


def print_q62_phsr() -> int:
    try:
        record = _load(_RECORD)
        phase_r = record.PHASE_R
        phase_k_max = record.PHASE_K_MAX
    except (Exception, SystemExit):
        return _no()
    if not _ratios_match(phase_r):
        return _no()
    if type(phase_k_max) is not int or phase_k_max != _PHASE_K_MAX:
        return _no()
    print("q62-phsr gate=query")
    for text in _PHASE_R_TEXT:
        print(f"phase-r {text}")
    print(f"phase-k-max {_PHASE_K_MAX}")
    print("q62-phsr yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q62_phsr: choose --print-q62-phsr",
            file=sys.stderr,
        )
        return 2
    return print_q62_phsr()


if __name__ == "__main__":
    sys.exit(main())
