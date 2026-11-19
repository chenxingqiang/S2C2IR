// RUN: python3 %S/../../runtime/record_q90_schedop.py --print-q90-schedop | FileCheck %s --check-prefix=Q90 --implicit-check-not=can-run-plan=yes
// Q90: q90-schedop gate=query
// Q90: sched-op yield
// Q90: sched-op wait
// Q90: sched-op task
// Q90: sched-op concurrent
// Q90: sched-op overlap
// Q90: sched-op pipeline
// Q90: sched-op stage
// Q90: q90-schedop yes
// Q90: can-run-plan no
