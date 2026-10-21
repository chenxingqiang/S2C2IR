// RUN: python3 %S/../../runtime/record_compiler_spine.py --print-compiler-spine | FileCheck %s --check-prefix=HOST
// HOST: can-run-plan no
// HOST: spine-host apply record_storage_apply
// HOST: apply-called yes
