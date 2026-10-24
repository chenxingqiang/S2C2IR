#!/usr/bin/env python3
"""Require scenario-corpus YES and NO to stay yes and no.

Imports record_scenario_corpus inside the printer after inserting
the runtime directory on sys.path. Query only. Does not edit
record_scenario_corpus or record_authorization. Does not call
run_analyzer. Does not add a predicate, device, dialect, backend,
or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_FLAG = "--print-q99-yesno"


def print_q99_yesno() -> int:
    if str(_RUNTIME) not in sys.path:
        sys.path.insert(0, str(_RUNTIME))
    import record_scenario_corpus

    yes = record_scenario_corpus.YES
    no = record_scenario_corpus.NO
    if yes != "yes" or no != "no" or yes == no:
        print("q99-yesno no")
        return 1
    print("q99-yesno gate=query")
    print("corpus-yes " + yes)
    print("corpus-no " + no)
    print("q99-yesno yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q99_yesno: choose --print-q99-yesno",
            file=sys.stderr,
        )
        return 2
    return print_q99_yesno()


if __name__ == "__main__":
    sys.exit(main())
