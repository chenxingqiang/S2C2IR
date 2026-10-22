#!/usr/bin/env python3
"""Require runtime/cuda/record_v3.CAL_FIELDS to stay the calibration fields.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
The tuple stays N, k, T_seq_us, T_ovl_us, T_copy_us, T_compute_us,
ratio, gain_us, ideal_us, hidden_frac, seq_over_sum, ovl_over_max.
Query only. Does not call run_analyzer. Does not add a predicate,
device, dialect, backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_CAL_FIELDS = (
    "N",
    "k",
    "T_seq_us",
    "T_ovl_us",
    "T_copy_us",
    "T_compute_us",
    "ratio",
    "gain_us",
    "ideal_us",
    "hidden_frac",
    "seq_over_sum",
    "ovl_over_max",
)
_FLAG = "--print-q77-calf"


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_calf", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def print_q77_calf() -> int:
    try:
        mod = load_record_v3()
        fields = getattr(mod, "CAL_FIELDS", None)
    except (
        OSError,
        RuntimeError,
        ValueError,
        ImportError,
        SyntaxError,
        AttributeError,
        TypeError,
    ):
        print("q77-calf no")
        return 1
    if type(fields) is not tuple or fields != _CAL_FIELDS:
        print("q77-calf no")
        return 1
    print("q77-calf gate=query")
    for name in fields:
        print(f"cal-field {name}")
    print("q77-calf yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q77_calf: choose --print-q77-calf",
            file=sys.stderr,
        )
        return 2
    return print_q77_calf()


if __name__ == "__main__":
    sys.exit(main())
