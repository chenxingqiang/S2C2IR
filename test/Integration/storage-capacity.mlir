// RUN: python3 %S/../../runtime/record_capacity.py --print-storage-capacity-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/record_capacity.py --analyze-storage-capacity %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl | FileCheck %s --check-prefix=F4
// RUN: python3 %S/../../runtime/record_capacity.py --analyze-storage-capacity %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl | FileCheck %s --check-prefix=FIT
// RUN: python3 %S/../../runtime/record_capacity.py --analyze-storage-capacity %S/../../docs/design/v3-dataset/storage-capacity-3tile-tight.jsonl | FileCheck %s --check-prefix=TRUNC
// RUN: sed 's/}$/,"extra_key":"no"}/' %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl > %t.extra.jsonl
// RUN: not python3 %S/../../runtime/record_capacity.py --analyze-storage-capacity %t.extra.jsonl 2>&1 | FileCheck %s --check-prefix=EXTRA
// RUN: python3 %S/../../runtime/record_evidence.py --print-stable-baseline-contract | FileCheck %s --check-prefix=BASE
// RUN: python3 %S/../../runtime/record_evidence.py --check-evidence-db | FileCheck %s --check-prefix=DB
// RUN: s2c2-opt %s --capacity=2 2>&1 | grep s2c2-storage-capacity | FileCheck %s --check-prefix=OPT4
// RUN: s2c2-opt %s --capacity=hbm:2 2>&1 | grep s2c2-storage-capacity | FileCheck %s --check-prefix=OPT4
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule="capacity=2" 2>&1 | grep s2c2-storage-capacity | FileCheck %s --check-prefix=OPT4
// RUN: s2c2-opt %s --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl 2>&1 | grep s2c2-storage-capacity | FileCheck %s --check-prefix=OPT4
// RUN: s2c2-opt %s --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl 2>&1 | grep s2c2-storage-capacity | FileCheck %s --check-prefix=OPTFIT
// RUN: s2c2-opt %s --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-3tile-tight.jsonl 2>&1 | grep s2c2-storage-capacity | FileCheck %s --check-prefix=OPTTRUNC
// RUN: not s2c2-opt %s --capacity-spec=%t.extra.jsonl 2>&1 | FileCheck %s --check-prefix=OPTEXTRA
// RUN: s2c2-opt %s 2>&1 | FileCheck %s --check-prefix=NOFLAG
// RUN: not s2c2-opt %s --capacity=abc 2>&1 | FileCheck %s --check-prefix=BADCAP
// RUN: not s2c2-opt %s --capacity=0 2>&1 | FileCheck %s --check-prefix=BADCAP
// RUN: not s2c2-opt %s --capacity=ssd:2 2>&1 | FileCheck %s --check-prefix=NOSPACE
// RUN: python3 %S/../../runtime/record_capacity.py --print-capacity-plan-contract | FileCheck %s --check-prefix=PLANC
// RUN: python3 %S/../../runtime/record_capacity.py --analyze-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl | FileCheck %s --check-prefix=HPLAN
// RUN: python3 %S/../../runtime/record_capacity.py --analyze-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl | FileCheck %s --check-prefix=HPLANFIT
// RUN: python3 %S/../../runtime/record_capacity.py --analyze-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-3tile-tight.jsonl | FileCheck %s --check-prefix=HPLANTRUNC
// RUN: s2c2-opt %s --capacity=2 2>&1 | grep s2c2-capacity-plan | FileCheck %s --check-prefix=PLAN
// RUN: s2c2-opt %s --capacity=2 --dump-capacity-plan=%t.plan.json 2>&1 | grep s2c2-capacity-plan | FileCheck %s --check-prefix=PLAN
// RUN: FileCheck %s --check-prefix=PLANJSON --input-file=%t.plan.json
// RUN: s2c2-opt %s --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl 2>&1 | grep s2c2-capacity-plan | FileCheck %s --check-prefix=PLANFIT
// RUN: s2c2-opt %s --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-3tile-tight.jsonl 2>&1 | grep s2c2-capacity-plan | FileCheck %s --check-prefix=PLANTRUNC
// RUN: not s2c2-opt %s --dump-capacity-plan=%t.ncap.json 2>&1 | FileCheck %s --check-prefix=NODUMP
// RUN: python3 %S/../../runtime/record_capacity.py --print-capacity-plan-query-contract | FileCheck %s --check-prefix=QUERYC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl | FileCheck %s --check-prefix=HQUERY
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl | FileCheck %s --check-prefix=HQUERYFIT
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-3tile-tight.jsonl | FileCheck %s --check-prefix=HQUERYTRUNC
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 2>&1 | FileCheck %s --check-prefix=QUERY
// RUN: s2c2-opt %s --query-capacity-plan --capacity=hbm:2 2>&1 | FileCheck %s --check-prefix=QUERY
// RUN: s2c2-opt %s --s2c2-capacity-plan-query="capacity=2" 2>&1 | FileCheck %s --check-prefix=QUERY
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl 2>&1 | FileCheck %s --check-prefix=QUERY
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --dump-capacity-plan=%t.qplan.json 2>&1 | FileCheck %s --check-prefix=QUERY
// RUN: FileCheck %s --check-prefix=PLANJSON --input-file=%t.qplan.json
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl 2>&1 | FileCheck %s --check-prefix=QUERYFIT
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-3tile-tight.jsonl 2>&1 | FileCheck %s --check-prefix=QUERYTRUNC
// RUN: not s2c2-opt %s --query-capacity-plan 2>&1 | FileCheck %s --check-prefix=NOQCAP
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --profile=rtx4090 --schedule-policy=default-3g 2>&1 | FileCheck %s --check-prefix=QBOTH
// RUN: python3 %S/../../runtime/record_capacity.py --print-capacity-policy-contract | FileCheck %s --check-prefix=POLC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HSEL
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HSELFIT
// RUN: not python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-3tile-tight.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=HSELTRUNC
// RUN: not python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=invented 2>&1 | FileCheck %s --check-prefix=HSELBAD
// RUN: not python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 2>&1 | FileCheck %s --check-prefix=HSELMEAS
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=SEL
// RUN: s2c2-opt %s --capacity-policy=s0 --capacity=2 2>&1 | FileCheck %s --check-prefix=SEL
// RUN: s2c2-opt %s --s2c2-capacity-plan-query="capacity=2 capacity-policy=s0" 2>&1 | FileCheck %s --check-prefix=SEL
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=s0 --dump-capacity-plan=%t.sel.json 2>&1 | FileCheck %s --check-prefix=SEL
// RUN: FileCheck %s --check-prefix=SELJSON --input-file=%t.sel.json
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=SELFIT
// RUN: not s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-3tile-tight.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=SELTRUNC
// RUN: not s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=invented 2>&1 | FileCheck %s --check-prefix=SELBAD
// RUN: not s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 2>&1 | FileCheck %s --check-prefix=SELMEAS
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=none 2>&1 | FileCheck %s --check-prefix=QUERY
// RUN: s2c2-opt %s --capacity-policy=s0 --capacity=2 --profile=rtx4090 --schedule-policy=default-3g 2>&1 | FileCheck %s --check-prefix=SELBOTH
// RUN: python3 %S/../../runtime/record_capacity.py --print-measured-capacity-contract | FileCheck %s --check-prefix=MEASC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl | FileCheck %s --check-prefix=HMEAS
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-argmin.jsonl | FileCheck %s --check-prefix=HMEASARG
// RUN: not python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-one.jsonl 2>&1 | FileCheck %s --check-prefix=HMEASONE
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl 2>&1 | FileCheck %s --check-prefix=MEAS
// RUN: s2c2-opt %s --capacity-policy=measured-capacity-v1 --capacity=2 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl --dump-capacity-plan=%t.meas.json 2>&1 | FileCheck %s --check-prefix=MEAS
// RUN: FileCheck %s --check-prefix=MEASJSON --input-file=%t.meas.json
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-argmin.jsonl 2>&1 | FileCheck %s --check-prefix=MEASARG
// RUN: not s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-one.jsonl 2>&1 | FileCheck %s --check-prefix=MEASONE
// RUN: not s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-3tile-tight.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl 2>&1 | FileCheck %s --check-prefix=MEASTRUNC
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl --profile=rtx4090 --schedule-policy=default-3g 2>&1 | FileCheck %s --check-prefix=MEASBOTH

// Phase 6C-B diagnostics: F_capacity candidate generation.
// KEEP / EVICT / REMATERIALIZE. TRANSFER is an existing
// restore realization, not a new action. No rewrite, no
// ranking on this diagnostic path, no hardware campaign.
// 6C-F ranks enumerated F_capacity on the query consumer only.
// 5A-6B stay frozen. Do not FileCheck microseconds.

// CONTRACT: storage-capacity compiler-driven=yes
// CONTRACT: action KEEP|EVICT|REMATERIALIZE
// CONTRACT: restore-legal TRANSFER|REMATERIALIZE
// CONTRACT: note f-capacity-ne-f-program
// CONTRACT: note keep-ne-keep-residency
// CONTRACT: note capacity-exceeded-ne-must-evict
// CONTRACT: note evict-ne-rewrite
// CONTRACT: note transfer-existing-realization
// CONTRACT: note first-conflict-only
// CONTRACT: note single-evict-or-truncated
// CONTRACT: note restore-unspecified
// CONTRACT: note selection-ne-rewrite-license
// CONTRACT: note rewrite=no
// CONTRACT: note default-3g-frozen
// CONTRACT: note cost-v04-structural-frozen
// CONTRACT: note evidence-db-identity-frozen
// CONTRACT: note five-e-not-opened
// CONTRACT: note measured-capacity-v1-not-opened
// CONTRACT: note not-new-capability-grid
// CONTRACT: note not-hardware-campaign
// CONTRACT: note stable-baseline
// CONTRACT: note six-c-design-this-cut
// CONTRACT: note six-c-diagnostics-frozen
// CONTRACT: note compiler-emits-f-capacity
// CONTRACT: note compiler-ne-rewrite
// CONTRACT: note tile-count-occupancy
// CONTRACT: note ir-discovery-ne-alias-analysis
// CONTRACT: cost=unchanged
// CONTRACT-NOT: password
// CONTRACT-NOT: 223.72
// CONTRACT-NOT: 106.75
// CONTRACT-NOT: Cost v0.4

// F4: storage-capacity space=hbm capacity=2 peak-live=3
// F4: storage-capacity capacity-conflict=yes
// F4: storage-capacity enumerated=yes truncated=no legal=3
// F4: storage-capacity candidate #0 keep=0,1 evict=2 action=EVICT
// F4-SAME: restore-legal=TRANSFER,REMATERIALIZE restore=unspecified
// F4: storage-capacity candidate #1 keep=1,2 evict=0 action=EVICT
// F4: storage-capacity candidate #2 keep=0,2 evict=1 action=EVICT
// F4: storage-capacity rewrite=no
// F4: storage-capacity note f-capacity-ne-f-program
// F4: storage-capacity note capacity-exceeded-ne-must-evict
// F4: storage-capacity note evict-ne-rewrite
// F4: storage-capacity note measured-capacity-v1-not-opened
// F4-NOT: keep=0,1,2
// F4-NOT: evict=3
// F4-NOT: ranked=
// F4-NOT: sched.wait

// FIT: storage-capacity capacity-conflict=no
// FIT: storage-capacity candidate #0 keep=0,1 action=KEEP
// FIT: storage-capacity rewrite=no
// FIT-NOT: action=EVICT

// TRUNC: storage-capacity enumerated=no truncated=yes legal=not-enumerated
// TRUNC: storage-capacity candidate-count=0
// TRUNC: storage-capacity rewrite=no
// TRUNC-NOT: candidate #0

// EXTRA: extra keys
// EXTRA-NOT: candidate #

// BASE: stack 5A-5D|6A|6B
// BASE: note six-c-not-opened
// BASE: cost=unchanged

// DB: evidence-db check=ok records=38
// DB: evidence-db note identity-E-unique
// DB-NOT: 8495

// OPT4: s2c2-storage-capacity space=hbm capacity=2 peak-live=3
// OPT4: s2c2-storage-capacity capacity-conflict=yes
// OPT4: s2c2-storage-capacity enumerated=yes truncated=no legal=3
// OPT4: s2c2-storage-capacity candidate #0 keep=0,1 evict=2 action=EVICT
// OPT4-SAME: restore-legal=TRANSFER,REMATERIALIZE restore=unspecified
// OPT4: s2c2-storage-capacity candidate #1 keep=1,2 evict=0 action=EVICT
// OPT4: s2c2-storage-capacity candidate #2 keep=0,2 evict=1 action=EVICT
// OPT4: s2c2-storage-capacity rewrite=no
// OPT4: s2c2-storage-capacity note compiler-emits-f-capacity
// OPT4: s2c2-storage-capacity note compiler-ne-rewrite
// OPT4: s2c2-storage-capacity note tile-count-occupancy
// OPT4: s2c2-storage-capacity note ir-discovery-ne-alias-analysis
// OPT4: s2c2-storage-capacity note six-c-diagnostics-frozen
// OPT4-NOT: keep=0,1,2
// OPT4-NOT: evict=3
// OPT4-NOT: rewrite=yes
// OPT4-NOT: sched.wait

// OPTFIT: s2c2-storage-capacity capacity-conflict=no
// OPTFIT: s2c2-storage-capacity candidate #0 keep=0,1 action=KEEP
// OPTFIT: s2c2-storage-capacity rewrite=no
// OPTFIT-NOT: action=EVICT

// OPTTRUNC: s2c2-storage-capacity enumerated=no truncated=yes legal=not-enumerated
// OPTTRUNC: s2c2-storage-capacity candidate-count=0
// OPTTRUNC: s2c2-storage-capacity rewrite=no
// OPTTRUNC-NOT: candidate #0

// OPTEXTRA: extra keys
// OPTEXTRA-NOT: candidate #

// NOFLAG-NOT: s2c2-storage-capacity
// NOFLAG-NOT: s2c2-capacity-plan
// NOFLAG-NOT: s2c2-capacity-plan-query

// BADCAP: invalid --capacity=

// NOSPACE: no constrained-space residencies

// PLANC: capacity-plan compiler-visible=yes
// PLANC: schema s2c2.capacity_plan.v1
// PLANC: selected none
// PLANC: policy none
// PLANC: rewrite-license no
// PLANC: note f-capacity-subseteq-f-residency
// PLANC: note six-c-b-diagnostics-frozen
// PLANC: note six-c-c-candidate-object-this-cut
// PLANC: note measured-capacity-v1-not-opened
// PLANC: note evidence-db-identity-frozen
// PLANC: cost=unchanged

// HPLAN: capacity-plan space=hbm capacity=2 peak-live=3
// HPLAN: capacity-plan feasible=yes enumerated=yes truncated=no legal=3
// HPLAN: capacity-plan selected=none policy=none rewrite-license=no
// HPLAN: capacity-plan candidate #0 identity=keep{0,1}|evict{2}|rematerialize{}
// HPLAN: capacity-plan candidate #1 identity=keep{1,2}|evict{0}|rematerialize{}
// HPLAN: capacity-plan candidate #2 identity=keep{0,2}|evict{1}|rematerialize{}
// HPLAN: capacity-plan subseteq-residency=yes
// HPLAN: capacity-plan rewrite=no
// HPLAN-NOT: selected={{[0-9]}}
// HPLAN-NOT: keep{0,1,2}

// HPLANFIT: capacity-plan feasible=yes
// HPLANFIT: selected=none
// HPLANFIT: identity=keep{0,1}|evict{}|rematerialize{}
// HPLANFIT-NOT: evict{0}

// HPLANTRUNC: capacity-plan feasible=no enumerated=no truncated=yes legal=not-enumerated
// HPLANTRUNC: selected=none
// HPLANTRUNC: rewrite=no
// HPLANTRUNC-NOT: candidate #0

// PLAN: s2c2-capacity-plan schema=s2c2.capacity_plan.v1
// PLAN: s2c2-capacity-plan space=hbm capacity=2 peak-live=3
// PLAN: s2c2-capacity-plan feasible=yes enumerated=yes truncated=no legal=3
// PLAN: s2c2-capacity-plan selected=none policy=none rewrite-license=no
// PLAN: s2c2-capacity-plan candidate #0 identity=keep{0,1}|evict{2}|rematerialize{} keep=0,1 evict=2 rematerialize=
// PLAN: s2c2-capacity-plan candidate #1 identity=keep{1,2}|evict{0}|rematerialize{} keep=1,2 evict=0 rematerialize=
// PLAN: s2c2-capacity-plan candidate #2 identity=keep{0,2}|evict{1}|rematerialize{} keep=0,2 evict=1 rematerialize=
// PLAN: s2c2-capacity-plan subseteq-residency=yes
// PLAN: s2c2-capacity-plan rewrite=no
// PLAN: s2c2-capacity-plan note f-capacity-subseteq-f-residency
// PLAN: s2c2-capacity-plan note selected-none
// PLAN: s2c2-capacity-plan note six-c-c-candidate-object-this-cut
// PLAN-NOT: keep{0,1,2}
// PLAN-NOT: selected=0
// PLAN-NOT: rewrite-license=yes
// PLAN-NOT: sched.wait

// PLANJSON-DAG: "schema":"s2c2.capacity_plan.v1"
// PLANJSON-DAG: "selected":"none"
// PLANJSON-DAG: "policy":"none"
// PLANJSON-DAG: "rewrite":"no"
// PLANJSON-DAG: "rewrite_license":"no"
// PLANJSON-DAG: "identity":"keep{0,1}|evict{2}|rematerialize{}"
// PLANJSON-DAG: "identity":"keep{1,2}|evict{0}|rematerialize{}"
// PLANJSON-DAG: "identity":"keep{0,2}|evict{1}|rematerialize{}"
// PLANJSON-NOT: keep{0,1,2}

// PLANFIT: s2c2-capacity-plan feasible=yes
// PLANFIT: selected=none
// PLANFIT: identity=keep{0,1}|evict{}|rematerialize{}
// PLANFIT: rewrite=no

// PLANTRUNC: s2c2-capacity-plan feasible=no enumerated=no truncated=yes legal=not-enumerated
// PLANTRUNC: selected=none
// PLANTRUNC: rewrite=no
// PLANTRUNC-NOT: candidate #0

// NODUMP: --dump-capacity-plan requires

// QUERYC: capacity-plan-query consumer-api=yes
// QUERYC: schema s2c2.capacity_plan.v1
// QUERYC: selected none
// QUERYC: policy none
// QUERYC: rewrite-license no
// QUERYC: note not-schedule-pass
// QUERYC: note consumer-api
// QUERYC: note six-c-b-diagnostics-frozen
// QUERYC: note six-c-c-candidate-object-frozen
// QUERYC: note six-c-d-query-this-cut
// QUERYC: note measured-capacity-v1-not-opened
// QUERYC: note evidence-db-identity-frozen
// QUERYC: cost=unchanged

// HQUERY: capacity-plan-query space=hbm capacity=2 peak-live=3
// HQUERY: capacity-plan-query feasible=yes enumerated=yes truncated=no legal=3
// HQUERY: capacity-plan-query selected=none policy=none rewrite-license=no
// HQUERY: capacity-plan-query candidate #0 identity=keep{0,1}|evict{2}|rematerialize{}
// HQUERY: capacity-plan-query candidate #1 identity=keep{1,2}|evict{0}|rematerialize{}
// HQUERY: capacity-plan-query candidate #2 identity=keep{0,2}|evict{1}|rematerialize{}
// HQUERY: capacity-plan-query {{.*}}"schema":"s2c2.capacity_plan.v1"
// HQUERY: capacity-plan-query rewrite=no
// HQUERY: capacity-plan-query note not-schedule-pass
// HQUERY: capacity-plan-query note consumer-api
// HQUERY-NOT: keep{0,1,2}
// HQUERY-NOT: selected={{[0-9]}}

// HQUERYFIT: capacity-plan-query feasible=yes
// HQUERYFIT: selected=none
// HQUERYFIT: identity=keep{0,1}|evict{}|rematerialize{}
// HQUERYFIT-NOT: evict{0}

// HQUERYTRUNC: capacity-plan-query feasible=no enumerated=no truncated=yes legal=not-enumerated
// HQUERYTRUNC: selected=none
// HQUERYTRUNC: rewrite=no
// HQUERYTRUNC-NOT: candidate #0

// QUERY: s2c2-capacity-plan-query schema=s2c2.capacity_plan.v1
// QUERY: s2c2-capacity-plan-query space=hbm capacity=2 peak-live=3
// QUERY: s2c2-capacity-plan-query feasible=yes enumerated=yes truncated=no legal=3
// QUERY: s2c2-capacity-plan-query selected=none policy=none rewrite-license=no
// QUERY: s2c2-capacity-plan-query candidate #0 identity=keep{0,1}|evict{2}|rematerialize{}
// QUERY: s2c2-capacity-plan-query candidate #1 identity=keep{1,2}|evict{0}|rematerialize{}
// QUERY: s2c2-capacity-plan-query candidate #2 identity=keep{0,2}|evict{1}|rematerialize{}
// QUERY: s2c2-capacity-plan-query {{.*}}"schema":"s2c2.capacity_plan.v1"{{.*}}"selected":"none"
// QUERY: s2c2-capacity-plan-query rewrite=no
// QUERY: s2c2-capacity-plan-query note not-schedule-pass
// QUERY: s2c2-capacity-plan-query note selected-none
// QUERY: s2c2-capacity-plan-query note consumer-api
// QUERY: s2c2-capacity-plan-query note measured-capacity-v1-not-opened
// QUERY: s2c2-capacity-plan-query note six-c-d-query-this-cut
// QUERY-NOT: s2c2-storage-capacity
// QUERY-NOT: evidence-bounded-schedule
// QUERY-NOT: hierarchy-global
// QUERY-NOT: s2c2-capacity-plan schema=
// QUERY-NOT: keep{0,1,2}
// QUERY-NOT: selected=0
// QUERY-NOT: rewrite-license=yes
// QUERY-NOT: sched.wait

// QUERYFIT: s2c2-capacity-plan-query feasible=yes
// QUERYFIT: selected=none
// QUERYFIT: identity=keep{0,1}|evict{}|rematerialize{}
// QUERYFIT: rewrite=no
// QUERYFIT-NOT: s2c2-storage-capacity
// QUERYFIT-NOT: evidence-bounded-schedule
// QUERYFIT-NOT: evict{0}

// QUERYTRUNC: s2c2-capacity-plan-query feasible=no enumerated=no truncated=yes legal=not-enumerated
// QUERYTRUNC: selected=none
// QUERYTRUNC: rewrite=no
// QUERYTRUNC-NOT: candidate #0
// QUERYTRUNC-NOT: s2c2-storage-capacity
// QUERYTRUNC-NOT: evidence-bounded-schedule

// NOQCAP: --query-capacity-plan requires
// NOQCAP-NOT: evidence-bounded-schedule

// QBOTH: s2c2-capacity-plan-query selected=none
// QBOTH: s2c2-storage-capacity rewrite=no
// QBOTH: evidence-bounded-schedule
// QBOTH: s2c2-schedule-policy name=default-3g{{.*}}rewrite=no
// QBOTH-NOT: rewrite-license=yes

// POLC: capacity-policy consumer=query
// POLC: policy none|s0|measured-capacity-v1
// POLC: s0 first(F_capacity)
// POLC: rewrite-license no
// POLC: note selection-ne-rewrite-license
// POLC: note s0-ne-must-evict
// POLC: note truncated-ne-select
// POLC: note measured-capacity-v1-ranking-only
// POLC: note six-c-d-query-frozen
// POLC: note six-c-e-selection-frozen
// POLC: note six-c-f-measured-ranking-this-cut
// POLC: cost=unchanged

// HSEL: capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=s0 rewrite-license=no
// HSEL: capacity-plan-query candidate #0 identity=keep{0,1}|evict{2}|rematerialize{}
// HSEL: capacity-plan-query candidate #1 identity=keep{1,2}|evict{0}|rematerialize{}
// HSEL: capacity-plan-query candidate #2 identity=keep{0,2}|evict{1}|rematerialize{}
// HSEL: capacity-plan-query note selected-in-f-capacity
// HSEL: capacity-plan-query note s0-ne-must-evict
// HSEL: capacity-policy name=s0 selected=keep{0,1}|evict{2}|rematerialize{}
// HSEL: capacity-policy note selection-ne-rewrite-license
// HSEL-NOT: selected=none policy=s0
// HSEL-NOT: keep{0,1,2}

// HSELFIT: selected=keep{0,1}|evict{}|rematerialize{} policy=s0
// HSELFIT: rewrite-license=no
// HSELFIT-NOT: evict{0}

// HSELTRUNC: truncated plan cannot be selected
// HSELTRUNC-NOT: selected=keep

// HSELBAD: unknown --capacity-policy=
// HSELMEAS: requires --measured-capacity-table

// SEL: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=s0 rewrite-license=no
// SEL: s2c2-capacity-plan-query candidate #0 identity=keep{0,1}|evict{2}|rematerialize{}
// SEL: s2c2-capacity-plan-query candidate #1 identity=keep{1,2}|evict{0}|rematerialize{}
// SEL: s2c2-capacity-plan-query candidate #2 identity=keep{0,2}|evict{1}|rematerialize{}
// SEL: s2c2-capacity-plan-query note selected-in-f-capacity
// SEL: s2c2-capacity-plan-query note s0-ne-must-evict
// SEL: s2c2-capacity-plan-query note six-c-e-selection-this-cut
// SEL: s2c2-capacity-policy name=s0 selected=keep{0,1}|evict{2}|rematerialize{}{{.*}}rewrite=no rewrite-license=no{{.*}}note selection-ne-rewrite-license{{.*}}note s0-ne-must-evict
// SEL-NOT: s2c2-storage-capacity
// SEL-NOT: evidence-bounded-schedule
// SEL-NOT: hierarchy-global
// SEL-NOT: s2c2-capacity-plan schema=
// SEL-NOT: rewrite-license=yes
// SEL-NOT: sched.wait
// SEL-NOT: keep{0,1,2}

// SELJSON-DAG: "schema":"s2c2.capacity_plan.v1"
// SELJSON-DAG: "selected":"keep{0,1}|evict{2}|rematerialize{}"
// SELJSON-DAG: "policy":"s0"
// SELJSON-DAG: "rewrite":"no"
// SELJSON-DAG: "rewrite_license":"no"
// SELJSON-DAG: "identity":"keep{1,2}|evict{0}|rematerialize{}"
// SELJSON-DAG: "identity":"keep{0,2}|evict{1}|rematerialize{}"
// SELJSON-NOT: "selected":"none"

// SELFIT: s2c2-capacity-plan-query selected=keep{0,1}|evict{}|rematerialize{} policy=s0
// SELFIT: rewrite-license=no
// SELFIT-NOT: s2c2-storage-capacity
// SELFIT-NOT: evidence-bounded-schedule
// SELFIT-NOT: evict{0}

// SELTRUNC: truncated plan cannot be selected
// SELTRUNC-NOT: evidence-bounded-schedule
// SELTRUNC-NOT: rewrite-license=yes

// SELBAD: unknown --capacity-policy=
// SELMEAS: requires --measured-capacity-table

// SELBOTH: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=s0
// SELBOTH: s2c2-capacity-plan selected=none
// SELBOTH: s2c2-schedule-policy name=default-3g{{.*}}rewrite=no
// SELBOTH-NOT: rewrite-license=yes

// MEASC: measured-capacity-v1 ranking-only=yes
// MEASC: schema s2c2.measured_capacity_cost.v1
// MEASC: argmin measured-intersect-F
// MEASC: rewrite-license no
// MEASC: note measured-needs-two-records
// MEASC: note measured-does-not-expand-f
// MEASC: note do-not-filecheck-microseconds
// MEASC: note not-hardware-campaign
// MEASC: note not-new-evidence-db
// MEASC: note six-c-f-measured-ranking-this-cut
// MEASC: cost=unchanged

// HMEAS: selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1 rewrite-license=no
// HMEAS: candidate #0 identity=keep{0,1}|evict{2}|rematerialize{}
// HMEAS: candidate #1 identity=keep{1,2}|evict{0}|rematerialize{}
// HMEAS: candidate #2 identity=keep{0,2}|evict{1}|rematerialize{}
// HMEAS: capacity-measured ranked=keep{0,1}|evict{2}|rematerialize{}{{.*}}coincide-s0=yes
// HMEAS: capacity-measured note measured-does-not-expand-f
// HMEAS: capacity-measured-candidate identity=keep{0,1}|evict{2}|rematerialize{} evidence=yes
// HMEAS-NOT: keep{9}
// HMEAS-NOT: 12401
// HMEAS-NOT: 18881
// HMEAS-NOT: 17771
// HMEAS-NOT: 1001

// HMEASARG: selected=keep{1,2}|evict{0}|rematerialize{} policy=measured-capacity-v1
// HMEASARG: coincide-s0=no
// HMEASARG: rewrite-license=no
// HMEASARG-NOT: 11011
// HMEASARG-NOT: 28881
// HMEASARG-NOT: 19991

// HMEASONE: measured-needs-two-records

// MEAS: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1 rewrite-license=no
// MEAS: s2c2-capacity-plan-query candidate #0 identity=keep{0,1}|evict{2}|rematerialize{}
// MEAS: s2c2-capacity-plan-query candidate #1 identity=keep{1,2}|evict{0}|rematerialize{}
// MEAS: s2c2-capacity-plan-query candidate #2 identity=keep{0,2}|evict{1}|rematerialize{}
// MEAS: s2c2-capacity-plan-query note measured-capacity-v1-ranking-only
// MEAS: s2c2-capacity-plan-query note six-c-f-measured-ranking-this-cut
// MEAS: s2c2-capacity-measured ranked=keep{0,1}|evict{2}|rematerialize{}{{.*}}coincide-s0=yes{{.*}}rewrite=no rewrite-license=no
// MEAS: s2c2-capacity-measured-candidate identity=keep{0,1}|evict{2}|rematerialize{} evidence=yes
// MEAS: s2c2-capacity-measured-candidate identity=keep{1,2}|evict{0}|rematerialize{} evidence=yes
// MEAS: s2c2-capacity-measured-candidate identity=keep{0,2}|evict{1}|rematerialize{} evidence=yes
// MEAS-NOT: s2c2-storage-capacity
// MEAS-NOT: evidence-bounded-schedule
// MEAS-NOT: keep{9}
// MEAS-NOT: 12401
// MEAS-NOT: 18881
// MEAS-NOT: 17771
// MEAS-NOT: 1001
// MEAS-NOT: rewrite-license=yes
// MEAS-NOT: sched.wait

// MEASJSON-DAG: "schema":"s2c2.capacity_plan.v1"
// MEASJSON-DAG: "selected":"keep{0,1}|evict{2}|rematerialize{}"
// MEASJSON-DAG: "policy":"measured-capacity-v1"
// MEASJSON-DAG: "rewrite_license":"no"
// MEASJSON-NOT: "selected":"none"
// MEASJSON-NOT: 12401

// MEASARG: s2c2-capacity-plan-query selected=keep{1,2}|evict{0}|rematerialize{} policy=measured-capacity-v1
// MEASARG: s2c2-capacity-measured {{.*}}coincide-s0=no
// MEASARG: rewrite-license=no
// MEASARG-NOT: 11011
// MEASARG-NOT: 28881
// MEASARG-NOT: 19991
// MEASARG-NOT: s2c2-storage-capacity

// MEASONE: measured-needs-two-records
// MEASONE-NOT: rewrite-license=yes

// MEASTRUNC: truncated plan cannot be selected
// MEASTRUNC-NOT: evidence-bounded-schedule

// MEASBOTH: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1
// MEASBOTH: s2c2-capacity-plan selected=none
// MEASBOTH: s2c2-schedule-policy name=default-3g{{.*}}rewrite=no
// MEASBOTH-NOT: rewrite-license=yes

module {
  // Four HBM tiles, capacity=2. Unpack tile0 after tile2 is
  // defined so the first conflict live set is {0,1,2}.
  // Tile 3 is not in R_t*. rewrite=no.
  func.func @four_tile_hbm() {
    %o0 = stor.object : !stor.object<tensor<8xf32>>
    %t0 = stor.materialize %o0 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    %o1 = stor.object : !stor.object<tensor<8xf32>>
    %t1 = stor.materialize %o1 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    %o2 = stor.object : !stor.object<tensor<8xf32>>
    %t2 = stor.materialize %o2 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    %u0 = stor.unpack %t0 : !stor.buffer<tensor<8xf32>, hbm> -> tensor<8xf32>
    %u1 = stor.unpack %t1 : !stor.buffer<tensor<8xf32>, hbm> -> tensor<8xf32>
    %u2 = stor.unpack %t2 : !stor.buffer<tensor<8xf32>, hbm> -> tensor<8xf32>
    %o3 = stor.object : !stor.object<tensor<8xf32>>
    %t3 = stor.materialize %o3 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    %u3 = stor.unpack %t3 : !stor.buffer<tensor<8xf32>, hbm> -> tensor<8xf32>
    return
  }
}
