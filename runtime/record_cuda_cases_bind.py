#!/usr/bin/env python3
"""Require runtime/cuda/record_v3.CASES to stay the pilot table.

Query only. Scores stay 130, 128, and 163. This does not change
the adapter, Cost, or a semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_RECORD = _ROOT / "runtime" / "cuda" / "record_v3.py"
_CASES = (
    ("a", "pilot_a_ssd_hbm_compute", 130),
    ("b", "pilot_b_compute_par_comm", 128),
    ("c", "pilot_c_pipeline_three_stage", 163),
)


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_cases", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def pilot_case_count(cases: object) -> int | None:
    """len(CASES) when the table is the three pilot scores."""
    if not isinstance(cases, tuple):
        return None
    count = len(cases)
    if cases != _CASES or count != 3:
        return None
    return count


def print_cuda_cases_bind() -> int:
    try:
        mod = load_record_v3()
        cases = getattr(mod, "CASES", None)
    except (
        OSError,
        RuntimeError,
        ValueError,
        ImportError,
        SyntaxError,
        AttributeError,
        TypeError,
    ):
        print("cuda-cases-bind no")
        return 1
    count = pilot_case_count(cases)
    if count is None:
        print("cuda-cases-bind no")
        return 1
    sys.stdout.write(
        "cuda-cases-bind gate=query\n"
        f"cuda-case-count {count}\n"
        "cuda-cases-bind yes\n"
        "can-run-plan no\n"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-cuda-cases-bind"]:
        print(
            "record_cuda_cases_bind: choose --print-cuda-cases-bind",
            file=sys.stderr,
        )
        return 2
    return print_cuda_cases_bind()


if __name__ == "__main__":
    sys.exit(main())
