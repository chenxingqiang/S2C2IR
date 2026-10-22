#!/usr/bin/env python3
"""Bind CUDA adapter schedule, map, and device header constants.

Reads kSched, kMap, kDevice, and kPilotCount from
runtime/cuda/AdapterContract.h. Requires gpu-async, default, gpu,
and 3. Query only. This does not change the adapter, Cost, or a
semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import NamedTuple

_ROOT = Path(__file__).resolve().parents[1]
_HEADER = _ROOT / "runtime" / "cuda" / "AdapterContract.h"

_SCHED = "gpu-async"
_MAP = "default"
_DEVICE = "gpu"
_PILOT_COUNT = 3

_STRING = re.compile(
    r"\binline\s+constexpr\s+const\s+char\s*\*\s*"
    r"(kSched|kMap|kDevice)\s*=\s*\"([^\"\\]*)\"\s*;"
)
_COUNT = re.compile(
    r"\binline\s+constexpr\s+int\s+kPilotCount\s*=\s*([+-]?\d+)\s*;"
)


class CudaSchedHeader(NamedTuple):
    sched: str
    mapping: str
    device: str
    pilot_count: int


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


def parse_cuda_sched_header(text: str) -> CudaSchedHeader | None:
    """kSched, kMap, kDevice, and kPilotCount from AdapterContract.h."""
    try:
        body = _strip_comments(text)
    except ValueError:
        return None
    found: dict[str, str] = {}
    for match in _STRING.finditer(body):
        name = match.group(1)
        if name in found:
            return None
        found[name] = match.group(2)
    if set(found) != {"kSched", "kMap", "kDevice"}:
        return None
    counts = [int(item, 10) for item in _COUNT.findall(body)]
    if len(counts) != 1:
        return None
    return CudaSchedHeader(
        found["kSched"],
        found["kMap"],
        found["kDevice"],
        counts[0],
    )


def header_bound(header: CudaSchedHeader | None) -> bool:
    """True when the header constants are gpu-async, default, gpu, and 3."""
    if header is None:
        return False
    return (
        header.sched == _SCHED
        and header.mapping == _MAP
        and header.device == _DEVICE
        and header.pilot_count == _PILOT_COUNT
        and type(header.pilot_count) is int
    )


def print_cuda_sched_header(text: str | None = None) -> int:
    try:
        if text is None:
            text = _HEADER.read_text(encoding="utf-8")
        header = parse_cuda_sched_header(text)
    except (OSError, ValueError):
        print("cuda-sched-header no")
        return 1
    if not header_bound(header) or header is None:
        print("cuda-sched-header no")
        return 1
    count = header.pilot_count
    sys.stdout.write(
        "cuda-sched-header gate=query\n"
        f"cuda-sched {header.sched}\n"
        f"cuda-map {header.mapping}\n"
        f"cuda-device {header.device}\n"
        f"cuda-pilot-count {count}\n"
        "cuda-sched-header-bound yes\n"
        "can-run-plan no\n"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="CUDA schedule header bind",
        add_help=False,
    )
    parser.add_argument("--print-cuda-sched-header", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else 2
    if extra or not args.print_cuda_sched_header:
        print(
            "record_cuda_sched_header: choose --print-cuda-sched-header",
            file=sys.stderr,
        )
        return 2
    return print_cuda_sched_header()


if __name__ == "__main__":
    sys.exit(main())
