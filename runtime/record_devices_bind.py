#!/usr/bin/env python3
"""Require the 4090, 910B, and host device ids.

Query only. The ids are the capability constants
DEVICE_4090, DEVICE_910B, and DEVICE_HOST. This does not change
applicability or open a semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent


def print_devices_bind() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capability_applicability as capa

        device_4090 = capa.DEVICE_4090
        device_910b = capa.DEVICE_910B
        device_host = capa.DEVICE_HOST
    except (ImportError, AttributeError):
        print("devices-bind no")
        return 1
    if not (
        device_4090 == "sm89:rtx4090"
        and device_910b == "ascend910b"
        and device_host == "host"
    ):
        print("devices-bind no")
        return 1
    print("devices-bind gate=query")
    print(f"device-4090 {device_4090}")
    print(f"device-910b {device_910b}")
    print(f"device-host {device_host}")
    print("devices-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-devices-bind"]:
        print(
            "record_devices_bind: choose --print-devices-bind",
            file=sys.stderr,
        )
        return 2
    return print_devices_bind()


if __name__ == "__main__":
    sys.exit(main())
