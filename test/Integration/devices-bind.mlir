// Device ids required by the capability constants. Query only.
// No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_devices_bind.py --print-devices-bind | FileCheck %s --check-prefix=DEV
// DEV: devices-bind gate=query
// DEV: device-4090 sm89:rtx4090
// DEV: device-910b ascend910b
// DEV: device-host host
// DEV: devices-bind yes
// DEV: can-run-plan no
