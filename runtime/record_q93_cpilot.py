#!/usr/bin/env python3
"""Require AdapterContract.h kPilots to match runtime/cuda/record_v3.CASES.

Parses the three kPilots rows from runtime/cuda/AdapterContract.h as
text and loads runtime/cuda/record_v3.py with importlib. Query only.
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent
_HEADER = _ROOT / "cuda" / "AdapterContract.h"
_RECORD = _ROOT / "cuda" / "record_v3.py"
_CASES = (
    ("a", "pilot_a_ssd_hbm_compute", 130),
    ("b", "pilot_b_compute_par_comm", 128),
    ("c", "pilot_c_pipeline_three_stage", 163),
)
_FLAG = "--print-q93-cpilot"
_PILOTS = re.compile(r"kPilots\[\]\s*=\s*\{(.*?)\};", re.S)
_TRIPLE = re.compile(
    r'\{\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*(-?\d+)\s*\}'
)


def _string_end(text: str, open_quote: int) -> int:
    j = open_quote + 1
    n = len(text)
    while j < n:
        if text[j] == "\\":
            j += 2
            continue
        if text[j] == '"':
            return j + 1
        j += 1
    raise ValueError("string")


def _strip_comments(text: str) -> str:
    """Drop // and /* */ comments. Leave string literals intact."""
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("//", i):
            nl = text.find("\n", i)
            if nl < 0:
                break
            out.append("\n")
            i = nl + 1
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise ValueError("comment")
            out.append(" ")
            i = end + 2
            continue
        if text[i] == '"':
            j = _string_end(text, i)
            out.append(text[i:j])
            i = j
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def parse_kpilots(text: str) -> tuple | None:
    """Ordered (id, func, score3Total) rows from the kPilots initializer."""
    try:
        body = _strip_comments(text)
    except ValueError:
        return None
    blocks = list(_PILOTS.finditer(body))
    if len(blocks) != 1:
        return None
    chunk = blocks[0].group(1)
    rows: list[tuple[str, str, int]] = []
    for item in _TRIPLE.finditer(chunk):
        rows.append((item.group(1), item.group(2), int(item.group(3))))
    if len(rows) != 3:
        return None
    rest = _TRIPLE.sub(" ", chunk)
    if rest.strip(" \t\r\n,") != "":
        return None
    return tuple(rows)


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_cpilot", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _case_tuple(rows: object) -> bool:
    if type(rows) is not tuple or len(rows) != 3:
        return False
    for row in rows:
        if type(row) is not tuple or len(row) != 3:
            return False
        cid, func, score = row
        if type(cid) is not str or type(func) is not str or type(score) is not int:
            return False
    return rows == _CASES


def print_q93_cpilot() -> int:
    try:
        text = _HEADER.read_text(encoding="utf-8")
        pilots = parse_kpilots(text)
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
        print("q93-cpilot no")
        return 1
    if not _case_tuple(pilots) or not _case_tuple(cases) or cases != pilots:
        print("q93-cpilot no")
        return 1
    print("q93-cpilot gate=query")
    for cid, func, score in cases:
        print(f"pilot {cid} {func} {score}")
    print("q93-cpilot yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q93_cpilot: choose --print-q93-cpilot",
            file=sys.stderr,
        )
        return 2
    return print_q93_cpilot()


if __name__ == "__main__":
    sys.exit(main())
