// CAP_SYNC_ARMS stays cap-event-sync, cap-stream-sync, and cap-device-sync.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q59_csync.py --print-q59-csync | FileCheck %s --check-prefix=Q59 --implicit-check-not=can-run-plan=yes
// Q59: q59-csync gate=query
// Q59: sync-arm cap-event-sync
// Q59: sync-arm cap-stream-sync
// Q59: sync-arm cap-device-sync
// Q59: q59-csync yes
// Q59: can-run-plan no
