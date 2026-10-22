#!/usr/bin/env python3
"""Compare the Ascend workload header triples with the three Phase 3B roles.

Reads kWorkloads from runtime/ascend/AdapterContract.h as ordered
(id, role, semantic) triples. The printed count is len of that list.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import NamedTuple

_RUNTIME = Path(__file__).resolve().parent
_HEADER = _RUNTIME / "ascend" / "AdapterContract.h"

_COUNT = 3
_MEMBERS = ("id", "role", "semantic")


class Workload(NamedTuple):
    id: str
    role: str
    semantic: str


_PHASE_3B = (
    Workload("compute", "compute", "elemwise"),
    Workload("htod", "transfer", "host_to_device"),
    Workload("dtoh", "transfer", "device_to_host"),
)


class _HeaderParseError(ValueError):
    """AdapterContract.h did not yield the ordered workload triples."""


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
    raise _HeaderParseError("string")


def _strip_comments(text: str) -> str:
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
                raise _HeaderParseError("comment")
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


def _initializer_body(text: str, symbol: str) -> str:
    match = re.search(
        rf"\b{re.escape(symbol)}\s*\[\s*\]\s*=\s*\{{",
        text,
    )
    if match is None:
        raise _HeaderParseError(symbol)
    start = match.end()
    depth = 1
    i = start
    while i < len(text) and depth:
        if text[i] == '"':
            i = _string_end(text, i)
            continue
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    if depth != 0:
        raise _HeaderParseError(symbol)
    return text[start : i - 1]


def _quoted_strings(body: str) -> list[str]:
    return re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', body)


def _workload_members(text: str) -> list[str]:
    match = re.search(
        r"\bstruct\s+WorkloadContract\s*\{([^}]*)\}",
        text,
        re.S,
    )
    if match is None:
        raise _HeaderParseError("WorkloadContract")
    members = re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*;", match.group(1))
    if not members:
        raise _HeaderParseError("WorkloadContract")
    return members


def _top_level_rows(body: str) -> list[str]:
    rows: list[str] = []
    depth = 0
    start = -1
    i = 0
    while i < len(body):
        if body[i] == '"':
            i = _string_end(body, i)
            continue
        if body[i] == "{":
            if depth == 0:
                start = i + 1
            depth += 1
        elif body[i] == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                rows.append(body[start:i])
                start = -1
            if depth < 0:
                raise _HeaderParseError("kWorkloads")
        i += 1
    if depth != 0:
        raise _HeaderParseError("kWorkloads")
    return rows


def parse_k_workloads(text: str) -> list[Workload]:
    """Ordered (id, role, semantic) triples from the kWorkloads initializer."""
    members = _workload_members(text)
    if any(name not in members for name in _MEMBERS):
        raise _HeaderParseError("WorkloadContract")
    indexes = tuple(members.index(name) for name in _MEMBERS)
    rows = _top_level_rows(_initializer_body(text, "kWorkloads"))
    if not rows:
        raise _HeaderParseError("kWorkloads")
    workloads: list[Workload] = []
    for row in rows:
        strings = _quoted_strings(row)
        if len(strings) != len(members) or max(indexes) >= len(strings):
            raise _HeaderParseError("kWorkloads")
        workloads.append(Workload(*(strings[index] for index in indexes)))
    return workloads


def _no() -> int:
    print("ascend-workload-header no")
    return 1


def report(header_text: str) -> int:
    """Print the bound query, or the mismatch line."""
    try:
        workloads = parse_k_workloads(_strip_comments(header_text))
    except _HeaderParseError:
        return _no()
    count = len(workloads)
    if count != _COUNT or tuple(workloads) != _PHASE_3B:
        return _no()
    print("ascend-workload-header gate=query")
    print(f"ascend-workload-count {count}")
    print("ascend-workload-header-bound yes")
    print("can-run-plan no")
    return 0


def print_ascend_workload_header() -> int:
    try:
        header_text = _HEADER.read_text(encoding="utf-8")
    except OSError:
        return _no()
    return report(header_text)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compare the Ascend workload header triples "
            "with the three Phase 3B roles."
        ),
        add_help=False,
    )
    parser.add_argument("--print-ascend-workload-header", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit:
        return 2
    if extra or not args.print_ascend_workload_header:
        print(
            "record_ascend_workload_header: choose --print-ascend-workload-header",
            file=sys.stderr,
        )
        return 2
    return print_ascend_workload_header()


if __name__ == "__main__":
    sys.exit(main())
