// Checking contract-error tokens from record_realization_checking.ERROR_TOKENS.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_check_errors_bind.py --print-check-errors-bind | FileCheck %s --check-prefix=CER --implicit-check-not=can-run-plan=yes
// CER: check-errors-bind gate=query
// CER: contract-error identity-mismatch
// CER: contract-error unknown-kind
// CER: contract-error malformed-legality
// CER: contract-error invalid-schema
// CER: check-errors-bind yes
// CER: can-run-plan no
