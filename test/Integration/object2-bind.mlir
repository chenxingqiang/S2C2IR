// Object 2 matches across sufficiency, authorization, rewrite, and apply.
// The canonical object is the string 2, not the prose token O2.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_object2_bind.py --print-object2-bind | FileCheck %s --check-prefix=OB2
// OB2: object2-bind gate=query
// OB2: object-canonical 2
// OB2: object2-bind yes
// OB2: can-run-plan no
