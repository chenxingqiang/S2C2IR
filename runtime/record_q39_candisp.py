#!/usr/bin/env python3
"""Query canonical unknown-scope against the occupancy printer.

record_decision.CANONICAL_FROM_DISPLAY has 13 entries. unknown-scope
stays evidence.unknown-scope. The occupancy printer pair for
unknown-scope stays evidence.scope-mismatch. Those algebra strings
differ. Query only. No semantic cut. can-run-plan stays no.
Does not call run_analyzer.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_CANONICAL = "evidence.unknown-scope"
_PRINTER = "evidence.scope-mismatch"
_FLAG = "--print-q39-candisp"


def _no() -> int:
    print("q39-candisp no")
    return 1


def print_q39_candisp() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_decision

        canonical_map = record_decision.CANONICAL_FROM_DISPLAY
        printer_hits = [
            algebra
            for display, algebra in record_decision.OCCUPANCY_PRINTER_MAP
            if display == "unknown-scope"
        ]
        canonical = canonical_map["unknown-scope"]
    except (
        AttributeError,
        ImportError,
        KeyError,
        OSError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        return _no()
    if len(canonical_map) != 13:
        return _no()
    if len(printer_hits) != 1:
        return _no()
    printer = printer_hits[0]
    if type(canonical) is not str or type(printer) is not str:
        return _no()
    if canonical != _CANONICAL or printer != _PRINTER or canonical == printer:
        return _no()
    print("q39-candisp gate=query")
    print(f"canonical-display-count {len(canonical_map)}")
    print("canonical-unknown-scope " + canonical)
    print("printer-unknown-scope " + printer)
    print("canonical-ne-printer yes")
    print("q39-candisp yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q39_candisp: choose --print-q39-candisp",
            file=sys.stderr,
        )
        return 2
    return print_q39_candisp()


if __name__ == "__main__":
    sys.exit(main())
