#!/usr/bin/env python3
"""Require Ascend seq-slack to stay the text 1.05.

Parses kSeqSlack from runtime/ascend/AdapterContract.h as the text
1.05. Loads runtime/ascend/record_ascend.py with importlib and requires
SEQ_SLACK == 1.05. Prints the literal text seq-slack 1.05. Query only.
Does not call run_analyzer. Does not compile the header. Does not add a
predicate, device, dialect, backend, or semantic cut. Leaves the Ascend
header and recorder unchanged. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path
from types import ModuleType

_ROOT = Path(__file__).resolve().parent
_HEADER = _ROOT / "ascend" / "AdapterContract.h"
_RECORD = _ROOT / "ascend" / "record_ascend.py"
_SLACK_TEXT = "1.05"
_FLAG = "--print-q96-aslck"
_DECL = re.compile(
    r"\binline\s+constexpr\s+double\s+kSeqSlack\s*=\s*(\S+)\s*;"
)
_LINES = (
    "q96-aslck gate=query",
    "header-slack 1.05",
    "python-slack 1.05",
    "q96-aslck yes",
    "can-run-plan no",
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


def parse_k_seq_slack(text: str) -> str:
    """kSeqSlack initializer as source text. Requires the text 1.05."""
    found = _DECL.findall(_strip_comments(text))
    if len(found) != 1 or found[0] != _SLACK_TEXT:
        raise ValueError("kSeqSlack")
    return found[0]


def _load_record_ascend(path: Path) -> ModuleType:
    """Load runtime/ascend/record_ascend.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_ascend_q96_aslck", path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-ascend-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q96-aslck no")
    return 1


def print_q96_aslck() -> int:
    try:
        header = parse_k_seq_slack(_HEADER.read_text(encoding="utf-8"))
        record = _load_record_ascend(_RECORD)
        seq_slack = record.SEQ_SLACK
    except (Exception, SystemExit):
        return _no()
    if header != _SLACK_TEXT:
        return _no()
    if type(seq_slack) is not float or not (seq_slack == 1.05):
        return _no()
    for line in _LINES:
        print(line)
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q96_aslck: choose --print-q96-aslck",
            file=sys.stderr,
        )
        return 2
    return print_q96_aslck()


if __name__ == "__main__":
    sys.exit(main())
