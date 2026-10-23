#!/usr/bin/env python3
"""Require CUDA record_v3 KS and PROVS to stay the host pair.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
KS must stay (1, 8) and PROVS must stay (0, 1). Query only. Does not
edit record_v3. Does not add a predicate, device, dialect, backend,
or semantic cut. Does not call run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_KS = (1, 8)
_PROVS = (0, 1)


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_q57_cuks", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q57_cuks() -> int:
    try:
        module = load_record_v3()
        ks = module.KS
        provs = module.PROVS
    except (Exception, SystemExit):
        print("q57-cuks no")
        return 1
    if ks != _KS or provs != _PROVS:
        print("q57-cuks no")
        return 1
    print("q57-cuks gate=query")
    for k in ks:
        print(f"cuda-k {k}")
    for prov in provs:
        print(f"cuda-prov {prov}")
    print("q57-cuks yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q57-cuks"]:
        print(
            "record_q57_cuks: choose --print-q57-cuks",
            file=sys.stderr,
        )
        return 2
    return print_q57_cuks()


if __name__ == "__main__":
    sys.exit(main())
