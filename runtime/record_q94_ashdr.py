#!/usr/bin/env python3
"""Require the Ascend adapter schedule header constants.

Reads kSched, kMap, kDevice, kSync, and kHardwareId from
runtime/ascend/AdapterContract.h as constexpr strings. They must stay
npu-async, default, npu, named-nonblocking, and ascend910b:ascend.
Query only. Does not compile the header. Does not call run_analyzer.
Does not add a predicate, device, dialect, backend, or semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_HEADER = Path(__file__).resolve().parent / "ascend" / "AdapterContract.h"
_FLAG = "--print-q94-ashdr"
_NAMES = ("kSched", "kMap", "kDevice", "kSync", "kHardwareId")
_EXPECTED = {
    "kSched": "npu-async",
    "kMap": "default",
    "kDevice": "npu",
    "kSync": "named-nonblocking",
    "kHardwareId": "ascend910b:ascend",
}
_LABEL = {
    "kSched": "ascend-sched",
    "kMap": "ascend-map",
    "kDevice": "ascend-device",
    "kSync": "ascend-sync",
    "kHardwareId": "ascend-hardware",
}
_DECL = re.compile(
    r"\binline\s+constexpr\s+const\s+char\s*\*\s*"
    r"(kSched|kMap|kDevice|kSync|kHardwareId)\s*=\s*"
    r'"([^"\\\n]*)"\s*;'
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


def parse_adapter_constants(text: str) -> dict[str, str] | None:
    """Map each constexpr name to its single string literal."""
    body = _strip_comments(text)
    found: dict[str, str] = {}
    for match in _DECL.finditer(body):
        name = match.group(1)
        if name in found:
            return None
        found[name] = match.group(2)
    if set(found) != set(_NAMES):
        return None
    return found


def _no() -> int:
    print("q94-ashdr no")
    return 1


def print_q94_ashdr(text: str | None = None) -> int:
    try:
        if text is None:
            text = _HEADER.read_text(encoding="utf-8")
        found = parse_adapter_constants(text)
    except (OSError, UnicodeError, ValueError):
        return _no()
    if found is None:
        return _no()
    for name in _NAMES:
        if found[name] != _EXPECTED[name]:
            return _no()
    print("q94-ashdr gate=query")
    for name in _NAMES:
        print(f"{_LABEL[name]} {found[name]}")
    print("q94-ashdr yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q94_ashdr: choose --print-q94-ashdr",
            file=sys.stderr,
        )
        return 2
    return print_q94_ashdr()


if __name__ == "__main__":
    sys.exit(main())
