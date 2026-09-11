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
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl --profile=fixture | FileCheck %s --check-prefix=HMEAS
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-argmin.jsonl --profile=fixture | FileCheck %s --check-prefix=HMEASARG
// RUN: not python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-one.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=HMEASONE
// RUN: not python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl 2>&1 | FileCheck %s --check-prefix=HMEASPROF
// RUN: not python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-wrong-profile.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=HMEASWPROF
// RUN: not python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-wrong-workload.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=HMEASWWL
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-cross-workload.jsonl --profile=fixture | FileCheck %s --check-prefix=HMEASCROSS
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=MEAS
// RUN: s2c2-opt %s --capacity-policy=measured-capacity-v1 --capacity=2 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl --profile=fixture --dump-capacity-plan=%t.meas.json 2>&1 | FileCheck %s --check-prefix=MEAS
// RUN: FileCheck %s --check-prefix=MEASJSON --input-file=%t.meas.json
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-argmin.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=MEASARG
// RUN: not s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-one.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=MEASONE
// RUN: not s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl 2>&1 | FileCheck %s --check-prefix=MEASPROF
// RUN: not s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-3tile-tight.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=MEASTRUNC
// RUN: not s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-wrong-profile.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=MEASWPROF
// RUN: not s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-wrong-workload.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=MEASWWL
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-cross-workload.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=MEASCROSS
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-tie.jsonl --profile=fixture | FileCheck %s --check-prefix=HMEASTIE
// RUN: not python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-dup.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=HMEASDUP
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-tie.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=MEASTIE
// RUN: not s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-dup.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=MEASDUP
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile-rtx4090.jsonl --profile=rtx4090 --schedule-policy=default-3g 2>&1 | FileCheck %s --check-prefix=MEASBOTH
// RUN: python3 %S/../../runtime/record_capacity.py --print-capacity-license-contract | FileCheck %s --check-prefix=LICENSEC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HLIC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HLICFIT
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=LIC
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=LICFIT
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=measured-capacity-v1 --measured-capacity-table=%S/../../docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl --profile=fixture 2>&1 | FileCheck %s --check-prefix=LICMEAS
// RUN: s2c2-opt %s --capacity=2 2>&1 | FileCheck %s --check-prefix=NOLIC
// RUN: python3 %S/../../runtime/record_capacity.py --print-capacity-restore-contract | FileCheck %s --check-prefix=RESTOREC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HREST
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HRESTFIT
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-transfer-restore.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HRESTYES
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=REST
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=RESTFIT
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-transfer-restore.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=RESTYES
// RUN: s2c2-opt %s --capacity=2 2>&1 | FileCheck %s --check-prefix=NOREST
// RUN: python3 %S/../../runtime/record_capacity.py --print-capacity-predicate-contract | FileCheck %s --check-prefix=PREDC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HPRED
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HPREDFIT
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-transfer-restore.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HPREDYES
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=PRED
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=PREDFIT
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-transfer-restore.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=PREDYES
// RUN: s2c2-opt %s --capacity=2 2>&1 | FileCheck %s --check-prefix=NOPRED
// RUN: python3 %S/../../runtime/record_capacity.py --print-capacity-sourcedata-contract | FileCheck %s --check-prefix=SRCC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HSRC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HSRCFIT
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-transfer-restore.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HSRCYES
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-source-data.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HSRCDATA
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=SRC
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=SRCFIT
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-transfer-restore.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=SRCYES
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-source-data.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=SRCDATA
// RUN: s2c2-opt %s --capacity=2 2>&1 | FileCheck %s --check-prefix=NOSRC
// RUN: python3 %S/../../runtime/record_capacity.py --print-capacity-ordering-contract | FileCheck %s --check-prefix=ORDC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HORD
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HORDFIT
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-transfer-restore.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HORDYES
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-source-data.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HORDDATA
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-restore-order.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HORDORD
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=ORD
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=ORDFIT
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-transfer-restore.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=ORDYES
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-source-data.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=ORDDATA
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-restore-order.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=ORDORD
// RUN: s2c2-opt %s --capacity=2 2>&1 | FileCheck %s --check-prefix=NOORD
// RUN: python3 %S/../../runtime/record_capacity.py --print-capacity-invalidation-contract | FileCheck %s --check-prefix=INVC
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HINV
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HINVFIT
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-transfer-restore.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HINVYES
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-source-data.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HINVDATA
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-restore-order.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HINVORD
// RUN: python3 %S/../../runtime/record_capacity.py --query-capacity-plan %S/../../docs/design/v3-dataset/storage-capacity-4tile-dest-invalidation.jsonl --capacity-policy=s0 | FileCheck %s --check-prefix=HINVINV
// RUN: s2c2-opt %s --query-capacity-plan --capacity=2 --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=INV
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-2tile-fit.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=INVFIT
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-transfer-restore.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=INVYES
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-source-data.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=INVDATA
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-restore-order.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=INVORD
// RUN: s2c2-opt %s --query-capacity-plan --capacity-spec=%S/../../docs/design/v3-dataset/storage-capacity-4tile-dest-invalidation.jsonl --capacity-policy=s0 2>&1 | FileCheck %s --check-prefix=INVINV
// RUN: s2c2-opt %s --capacity=2 2>&1 | FileCheck %s --check-prefix=NOINV

// Phase 6C-B diagnostics: F_capacity candidate generation.
// KEEP / EVICT / REMATERIALIZE. TRANSFER is an existing
// restore realization, not a new action. No rewrite, no
// ranking on this diagnostic path, no hardware campaign.
// 6C-F ranks enumerated F_capacity on the query consumer only.
// 6C-G prints the capacity rewrite-license gate (still no):
// selected is not a license; EVICT requires restore.
// 6C-H attaches TRANSFER restore records to EVICT objects
// (candidate semantics, not an identity-string parse).
// 6C-I classifies the structured license predicate
// (necessary vs sufficient; still rewrite-license=no).
// Closed restore is necessary, not sufficient.
// 6C-J classifies scoped source-data validity on the query
// consumer. replica-exists ≠ source-data-valid ≠ usable.
// Token = validity witness; no valid/stale/dirty FSM.
// source-data=yes is still not sufficient. 6C-K classifies
// restore ordering: source-data-valid ≠ restore-at-required-point.
// restore-ordering=yes is still dest-invalidation=no on the
// restore-order fixture. 6C-L classifies dest invalidation:
// usable ≠ dest-invalidation ≠ sufficient ≠ rewrite-license.
// dest-invalidation=yes is still rewrite-path=no.
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
// PLANJSON-DAG: "kind":"TRANSFER"
// PLANJSON-DAG: "reason":"no-source-replica"
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
// HQUERY: capacity-license selected=none rewrite-license=no
// HQUERY: capacity-license restore=n/a
// HQUERY: capacity-restore selected=none closed=n/a
// HQUERY: capacity-restore rewrite-license=no
// HQUERY: capacity-predicate selected=none necessary=no sufficient=no rewrite-license=no
// HQUERY: capacity-sourcedata selected=none source-data=n/a replica-exists=n/a usable=n/a
// HQUERY: capacity-ordering selected=none restore-ordering=n/a usable=n/a
// HQUERY: capacity-invalidation selected=none dest-invalidation=n/a usable=n/a
// HQUERY-NOT: keep{0,1,2}
// HQUERY-NOT: selected={{[0-9]}}

// HQUERYFIT: capacity-plan-query feasible=yes
// HQUERYFIT: selected=none
// HQUERYFIT: identity=keep{0,1}|evict{}|rematerialize{}
// HQUERYFIT: capacity-license restore=n/a
// HQUERYFIT-NOT: evict{0}

// HQUERYTRUNC: capacity-plan-query feasible=no enumerated=no truncated=yes legal=not-enumerated
// HQUERYTRUNC: selected=none
// HQUERYTRUNC: rewrite=no
// HQUERYTRUNC: capacity-license restore=n/a
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
// QUERY: s2c2-capacity-license selected=none rewrite-license=no
// QUERY: s2c2-capacity-license restore=n/a{{.*}}evict-closed=n/a
// QUERY: s2c2-capacity-license note selected-ne-rewrite-license
// QUERY: s2c2-capacity-license rewrite=no
// QUERY: s2c2-capacity-restore selected=none closed=n/a
// QUERY: s2c2-capacity-restore rewrite-license=no
// QUERY: s2c2-capacity-predicate selected=none necessary=no sufficient=no rewrite-license=no
// QUERY: s2c2-capacity-predicate selected-in-f=no{{.*}}capacity-proof=n/a{{.*}}evict-closed=n/a{{.*}}restore-kind=n/a
// QUERY: s2c2-capacity-sourcedata selected=none source-data=n/a replica-exists=n/a usable=n/a
// QUERY: s2c2-capacity-ordering selected=none restore-ordering=n/a usable=n/a
// QUERY: s2c2-capacity-invalidation selected=none dest-invalidation=n/a usable=n/a
// QUERY-NOT: s2c2-storage-capacity
// QUERY-NOT: evidence-bounded-schedule
// QUERY-NOT: hierarchy-global
// QUERY-NOT: s2c2-capacity-plan schema=
// QUERY-NOT: keep{0,1,2}
// QUERY-NOT: selected=0
// QUERY-NOT: rewrite-license=yes
// QUERY-NOT: sched.wait

// LICENSEC: capacity-license gate=query
// LICENSEC: schema s2c2.capacity_license.v1
// LICENSEC: rewrite-license no
// LICENSEC: restore-legal TRANSFER|REMATERIALIZE
// LICENSEC: note selected-ne-rewrite-license
// LICENSEC: note evict-requires-restore
// LICENSEC: note restore-unspecified
// LICENSEC: note rematerialize-empty-this-stage
// LICENSEC: note transfer-existing-realization
// LICENSEC: note capability-license-ne-capacity-license
// LICENSEC: note measured-ne-rewrite-license
// LICENSEC: note six-c-g-license-gate-this-cut
// LICENSEC-NOT: rewrite-license yes

// HLIC: capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=s0 rewrite-license=no
// HLIC: capacity-license selected=keep{0,1}|evict{2}|rematerialize{} rewrite-license=no
// HLIC: capacity-license restore=unspecified{{.*}}evict-closed=no
// HLIC: capacity-license rewrite=no
// HLIC: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// HLIC: capacity-restore object=2 kind=TRANSFER valid=no reason=no-source-replica
// HLIC: capacity-restore rewrite-license=no
// HLIC-NOT: rewrite-license=yes

// HLICFIT: selected=keep{0,1}|evict{}|rematerialize{} policy=s0 rewrite-license=no
// HLICFIT: capacity-license restore=unused{{.*}}evict-closed=n/a
// HLICFIT: capacity-license rewrite=no
// HLICFIT: capacity-restore selected={{.*}} closed=n/a
// HLICFIT: capacity-restore restore=unused
// HLICFIT-NOT: rewrite-license=yes

// LIC: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=s0 rewrite-license=no
// LIC: s2c2-capacity-license selected=keep{0,1}|evict{2}|rematerialize{} rewrite-license=no
// LIC: s2c2-capacity-license restore=unspecified{{.*}}evict-closed=no
// LIC: s2c2-capacity-license note evict-requires-restore
// LIC: s2c2-capacity-license rewrite=no
// LIC: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// LIC: s2c2-capacity-restore object=2 kind=TRANSFER valid=no reason=no-source-replica
// LIC: s2c2-capacity-restore rewrite-license=no
// LIC-NOT: rewrite-license=yes
// LIC-NOT: s2c2-opt: applySchedule

// LICFIT: s2c2-capacity-plan-query selected=keep{0,1}|evict{}|rematerialize{} policy=s0
// LICFIT: s2c2-capacity-license restore=unused{{.*}}evict-closed=n/a
// LICFIT: s2c2-capacity-license rewrite=no
// LICFIT: s2c2-capacity-restore selected={{.*}} closed=n/a
// LICFIT: s2c2-capacity-restore restore=unused
// LICFIT-NOT: rewrite-license=yes

// LICMEAS: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1 rewrite-license=no
// LICMEAS: s2c2-capacity-license selected=keep{0,1}|evict{2}|rematerialize{} rewrite-license=no
// LICMEAS: s2c2-capacity-license restore=unspecified
// LICMEAS: s2c2-capacity-license note measured-ne-rewrite-license
// LICMEAS: s2c2-capacity-license rewrite=no
// LICMEAS-NOT: rewrite-license=yes

// NOLIC: s2c2-capacity-plan selected=none
// NOLIC-NOT: s2c2-capacity-license
// NOLIC-NOT: s2c2-capacity-restore
// NOLIC-NOT: s2c2-capacity-predicate
// NOLIC-NOT: s2c2-capacity-sourcedata
// NOLIC-NOT: s2c2-capacity-ordering
// NOLIC-NOT: s2c2-capacity-invalidation
// NOLIC-NOT: rewrite-license=yes

// RESTOREC: capacity-restore candidate-semantics=yes
// RESTOREC: schema s2c2.capacity_restore.v1
// RESTOREC: kind TRANSFER
// RESTOREC: restore-legal TRANSFER|REMATERIALIZE
// RESTOREC: rewrite-license no
// RESTOREC: note restore-ne-identity-string
// RESTOREC: note transfer-existing-realization
// RESTOREC: note occupancy-ir-ne-restore-source
// RESTOREC: note closed-ne-rewrite-license
// RESTOREC: note six-c-g-license-gate-frozen
// RESTOREC: note six-c-h-restore-closure-this-cut
// RESTOREC-NOT: rewrite-license yes

// HREST: capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=s0 rewrite-license=no
// HREST: capacity-license restore=unspecified{{.*}}evict-closed=no
// HREST: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// HREST: capacity-restore object=2 kind=TRANSFER valid=no reason=no-source-replica
// HREST: capacity-restore rewrite-license=no
// HREST-NOT: rewrite-license=yes

// HRESTFIT: selected=keep{0,1}|evict{}|rematerialize{} policy=s0 rewrite-license=no
// HRESTFIT: capacity-restore selected={{.*}} closed=n/a
// HRESTFIT: capacity-restore restore=unused
// HRESTFIT: capacity-restore rewrite-license=no
// HRESTFIT-NOT: rewrite-license=yes

// HRESTYES: identity=keep{0,1}|evict{2}|rematerialize{}
// HRESTYES: identity=keep{1,2}|evict{0}|rematerialize{}
// HRESTYES: identity=keep{0,2}|evict{1}|rematerialize{}
// HRESTYES: capacity-license restore=unspecified{{.*}}evict-closed=no
// HRESTYES: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HRESTYES: capacity-restore object=2 kind=TRANSFER valid=yes reason=has-source-replica
// HRESTYES: capacity-restore rewrite-license=no
// HRESTYES: capacity-restore note closed-ne-rewrite-license
// HRESTYES-NOT: rewrite-license=yes
// HRESTYES-NOT: keep{0,1,2}

// REST: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=s0 rewrite-license=no
// REST: s2c2-capacity-license restore=unspecified{{.*}}evict-closed=no
// REST: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// REST: s2c2-capacity-restore object=2 kind=TRANSFER valid=no reason=no-source-replica
// REST: s2c2-capacity-restore rewrite-license=no
// REST-NOT: rewrite-license=yes
// REST-NOT: s2c2-opt: applySchedule

// RESTFIT: s2c2-capacity-plan-query selected=keep{0,1}|evict{}|rematerialize{} policy=s0
// RESTFIT: s2c2-capacity-restore selected={{.*}} closed=n/a
// RESTFIT: s2c2-capacity-restore restore=unused
// RESTFIT: s2c2-capacity-restore rewrite-license=no
// RESTFIT-NOT: rewrite-license=yes

// RESTYES: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=s0 rewrite-license=no
// RESTYES: identity=keep{0,1}|evict{2}|rematerialize{}
// RESTYES: identity=keep{1,2}|evict{0}|rematerialize{}
// RESTYES: identity=keep{0,2}|evict{1}|rematerialize{}
// RESTYES: s2c2-capacity-license restore=unspecified{{.*}}evict-closed=no
// RESTYES: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// RESTYES: s2c2-capacity-restore object=2 kind=TRANSFER valid=yes reason=has-source-replica
// RESTYES: s2c2-capacity-restore rewrite-license=no
// RESTYES: s2c2-capacity-restore note closed-ne-rewrite-license
// RESTYES-NOT: rewrite-license=yes
// RESTYES-NOT: s2c2-opt: applySchedule
// RESTYES-NOT: keep{0,1,2}

// NOREST: s2c2-capacity-plan selected=none
// NOREST-NOT: s2c2-capacity-restore
// NOREST-NOT: s2c2-capacity-license
// NOREST-NOT: s2c2-capacity-predicate
// NOREST-NOT: s2c2-capacity-sourcedata
// NOREST-NOT: s2c2-capacity-ordering
// NOREST-NOT: s2c2-capacity-invalidation
// NOREST-NOT: rewrite-license=yes

// PREDC: capacity-predicate gate=query
// PREDC: schema s2c2.capacity_predicate.v1
// PREDC: necessary selected-in-f,enumerated,capacity-proof,evict-closed,restore-kind
// PREDC: sufficient source-data,restore-ordering,dest-invalidation,rewrite-path
// PREDC: rewrite-license no
// PREDC: note necessary-ne-sufficient
// PREDC: note closed-ne-rewrite-license
// PREDC: note source-declaration-ne-data-validity
// PREDC: note six-c-h-restore-closure-frozen
// PREDC: note six-c-i-license-predicate-this-cut
// PREDC-NOT: rewrite-license yes

// HPRED: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// HPRED: capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=no sufficient=no rewrite-license=no
// HPRED: capacity-predicate selected-in-f=yes enumerated=yes capacity-proof=yes evict-closed=no restore-kind=TRANSFER
// HPRED: capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// HPRED: capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=no replica-exists=no usable=no
// HPRED: capacity-sourcedata object=2 replica=n/a witness=n/a scope=n/a replica-exists=no source-data=no usable=no reason=no-source-replica
// HPRED-NOT: rewrite-license=yes

// HPREDFIT: selected=keep{0,1}|evict{}|rematerialize{} policy=s0 rewrite-license=no
// HPREDFIT: capacity-predicate selected={{.*}} necessary=n/a sufficient=no rewrite-license=no
// HPREDFIT: capacity-predicate selected-in-f=yes{{.*}}capacity-proof=yes{{.*}}evict-closed=n/a{{.*}}restore-kind=unused
// HPREDFIT: capacity-predicate source-data=n/a restore-ordering=n/a dest-invalidation=n/a rewrite-path=no
// HPREDFIT-NOT: rewrite-license=yes

// HPREDYES: capacity-license restore=unspecified{{.*}}evict-closed=no
// HPREDYES: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HPREDYES: capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// HPREDYES: capacity-predicate selected-in-f=yes enumerated=yes capacity-proof=yes evict-closed=yes restore-kind=TRANSFER
// HPREDYES: capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// HPREDYES: capacity-predicate note necessary-ne-sufficient
// HPREDYES: capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=no replica-exists=yes usable=no
// HPREDYES: capacity-sourcedata object=2 replica=ssd witness=n/a scope=n/a replica-exists=yes source-data=no usable=no reason=no-validity-witness
// HPREDYES-NOT: rewrite-license=yes
// HPREDYES-NOT: keep{0,1,2}

// PRED: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// PRED: s2c2-capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=no sufficient=no rewrite-license=no
// PRED: s2c2-capacity-predicate selected-in-f=yes enumerated=yes capacity-proof=yes evict-closed=no restore-kind=TRANSFER
// PRED: s2c2-capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// PRED: s2c2-capacity-sourcedata object=2 replica=n/a witness=n/a scope=n/a replica-exists=no source-data=no usable=no reason=no-source-replica
// PRED-NOT: rewrite-license=yes
// PRED-NOT: s2c2-opt: applySchedule

// PREDFIT: s2c2-capacity-predicate selected={{.*}} necessary=n/a sufficient=no rewrite-license=no
// PREDFIT: s2c2-capacity-predicate selected-in-f=yes{{.*}}capacity-proof=yes{{.*}}evict-closed=n/a{{.*}}restore-kind=unused
// PREDFIT: s2c2-capacity-predicate source-data=n/a restore-ordering=n/a dest-invalidation=n/a rewrite-path=no
// PREDFIT-NOT: rewrite-license=yes

// PREDYES: s2c2-capacity-license restore=unspecified{{.*}}evict-closed=no
// PREDYES: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// PREDYES: s2c2-capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// PREDYES: s2c2-capacity-predicate selected-in-f=yes enumerated=yes capacity-proof=yes evict-closed=yes restore-kind=TRANSFER
// PREDYES: s2c2-capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// PREDYES: s2c2-capacity-predicate note source-declaration-ne-data-validity
// PREDYES: s2c2-capacity-sourcedata object=2 replica=ssd witness=n/a scope=n/a replica-exists=yes source-data=no usable=no reason=no-validity-witness
// PREDYES-NOT: rewrite-license=yes
// PREDYES-NOT: s2c2-opt: applySchedule
// PREDYES-NOT: keep{0,1,2}

// NOPRED: s2c2-capacity-plan selected=none
// NOPRED-NOT: s2c2-capacity-predicate
// NOPRED-NOT: s2c2-capacity-restore
// NOPRED-NOT: s2c2-capacity-license
// NOPRED-NOT: s2c2-capacity-sourcedata
// NOPRED-NOT: s2c2-capacity-ordering
// NOPRED-NOT: s2c2-capacity-invalidation
// NOPRED-NOT: rewrite-license=yes

// SRCC: capacity-sourcedata gate=query
// SRCC: schema s2c2.capacity_sourcedata.v1
// SRCC: source-declaration-ne-data-validity yes
// SRCC: replica-exists-ne-data-validity yes
// SRCC: source-data-ne-usable yes
// SRCC: token-eq-validity-witness yes
// SRCC: no-validity-fsm yes
// SRCC: rewrite-license no
// SRCC: note replica-exists-ne-data-validity
// SRCC: note source-declaration-ne-data-validity
// SRCC: note source-data-ne-usable
// SRCC: note token-eq-validity-witness
// SRCC: note no-validity-fsm
// SRCC: note closed-ne-data-valid
// SRCC: note unknown-ne-rewrite
// SRCC: note source-data-ne-sufficient
// SRCC: note six-c-i-license-predicate-frozen
// SRCC: note six-c-j-source-data-this-cut
// SRCC-NOT: rewrite-license yes

// HSRC: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// HSRC: capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// HSRC: capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=no replica-exists=no usable=no
// HSRC: capacity-sourcedata object=2 replica=n/a witness=n/a scope=n/a replica-exists=no source-data=no usable=no reason=no-source-replica
// HSRC: capacity-sourcedata rewrite-license=no
// HSRC: capacity-sourcedata note replica-exists-ne-data-validity
// HSRC-NOT: rewrite-license=yes

// HSRCFIT: selected=keep{0,1}|evict{}|rematerialize{} policy=s0 rewrite-license=no
// HSRCFIT: capacity-predicate source-data=n/a
// HSRCFIT: capacity-sourcedata selected={{.*}} source-data=n/a replica-exists=n/a usable=n/a
// HSRCFIT: capacity-sourcedata restore=unused
// HSRCFIT: capacity-sourcedata rewrite-license=no
// HSRCFIT-NOT: rewrite-license=yes

// HSRCYES: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HSRCYES: capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// HSRCYES: capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// HSRCYES: capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=no replica-exists=yes usable=no
// HSRCYES: capacity-sourcedata object=2 replica=ssd witness=n/a scope=n/a replica-exists=yes source-data=no usable=no reason=no-validity-witness
// HSRCYES: capacity-sourcedata note replica-exists-ne-data-validity
// HSRCYES: capacity-sourcedata note closed-ne-data-valid
// HSRCYES-NOT: rewrite-license=yes
// HSRCYES-NOT: keep{0,1,2}

// HSRCDATA: capacity-license restore=unspecified{{.*}}evict-closed=no
// HSRCDATA: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HSRCDATA: capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// HSRCDATA: capacity-predicate source-data=yes restore-ordering=no dest-invalidation=no rewrite-path=no
// HSRCDATA: capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=no
// HSRCDATA: capacity-sourcedata object=2 replica=ssd witness=spec-unmutated-cover scope=occupancy-live replica-exists=yes source-data=yes usable=no reason=witnessed-unmutated-cover
// HSRCDATA: capacity-sourcedata rewrite-license=no
// HSRCDATA: capacity-sourcedata note source-data-ne-usable
// HSRCDATA: capacity-sourcedata note no-validity-fsm
// HSRCDATA: capacity-sourcedata note source-data-ne-sufficient
// HSRCDATA-NOT: rewrite-license=yes
// HSRCDATA-NOT: keep{0,1,2}

// SRC: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// SRC: s2c2-capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// SRC: s2c2-capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=no replica-exists=no usable=no
// SRC: s2c2-capacity-sourcedata object=2 replica=n/a witness=n/a scope=n/a replica-exists=no source-data=no usable=no reason=no-source-replica
// SRC: s2c2-capacity-sourcedata rewrite-license=no
// SRC-NOT: rewrite-license=yes
// SRC-NOT: s2c2-opt: applySchedule

// SRCFIT: s2c2-capacity-predicate source-data=n/a
// SRCFIT: s2c2-capacity-sourcedata selected={{.*}} source-data=n/a replica-exists=n/a usable=n/a
// SRCFIT: s2c2-capacity-sourcedata restore=unused
// SRCFIT: s2c2-capacity-sourcedata rewrite-license=no
// SRCFIT-NOT: rewrite-license=yes

// SRCYES: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// SRCYES: s2c2-capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// SRCYES: s2c2-capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// SRCYES: s2c2-capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=no replica-exists=yes usable=no
// SRCYES: s2c2-capacity-sourcedata object=2 replica=ssd witness=n/a scope=n/a replica-exists=yes source-data=no usable=no reason=no-validity-witness
// SRCYES: s2c2-capacity-sourcedata note replica-exists-ne-data-validity
// SRCYES: s2c2-capacity-sourcedata note closed-ne-data-valid
// SRCYES-NOT: rewrite-license=yes
// SRCYES-NOT: s2c2-opt: applySchedule
// SRCYES-NOT: keep{0,1,2}

// SRCDATA: s2c2-capacity-license restore=unspecified{{.*}}evict-closed=no
// SRCDATA: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// SRCDATA: s2c2-capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// SRCDATA: s2c2-capacity-predicate source-data=yes restore-ordering=no dest-invalidation=no rewrite-path=no
// SRCDATA: s2c2-capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=no
// SRCDATA: s2c2-capacity-sourcedata object=2 replica=ssd witness=spec-unmutated-cover scope=occupancy-live replica-exists=yes source-data=yes usable=no reason=witnessed-unmutated-cover
// SRCDATA: s2c2-capacity-sourcedata rewrite-license=no
// SRCDATA: s2c2-capacity-sourcedata note source-data-ne-usable
// SRCDATA: s2c2-capacity-sourcedata note no-validity-fsm
// SRCDATA: s2c2-capacity-sourcedata note source-data-ne-sufficient
// SRCDATA-NOT: rewrite-license=yes
// SRCDATA-NOT: s2c2-opt: applySchedule
// SRCDATA-NOT: keep{0,1,2}

// NOSRC: s2c2-capacity-plan selected=none
// NOSRC-NOT: s2c2-capacity-sourcedata
// NOSRC-NOT: s2c2-capacity-ordering
// NOSRC-NOT: s2c2-capacity-invalidation
// NOSRC-NOT: s2c2-capacity-predicate
// NOSRC-NOT: rewrite-license=yes

// ORDC: capacity-ordering gate=query
// ORDC: schema s2c2.capacity_ordering.v1
// ORDC: source-data-ne-ordering yes
// ORDC: source-valid-ne-restore-at-point yes
// ORDC: restore-ordering-ne-usable yes
// ORDC: rewrite-license no
// ORDC: note source-data-ne-ordering
// ORDC: note six-c-j-source-data-frozen
// ORDC: note six-c-k-restore-ordering-this-cut
// ORDC-NOT: rewrite-license yes

// HORD: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// HORD: capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// HORD: capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=no usable=no
// HORD: capacity-ordering object=2 before=n/a witness=n/a scope=n/a restore-ordering=no usable=no reason=no-source-replica
// HORD: capacity-ordering rewrite-license=no
// HORD-NOT: rewrite-license=yes

// HORDFIT: selected=keep{0,1}|evict{}|rematerialize{} policy=s0 rewrite-license=no
// HORDFIT: capacity-predicate source-data=n/a restore-ordering=n/a
// HORDFIT: capacity-ordering selected={{.*}} restore-ordering=n/a usable=n/a
// HORDFIT: capacity-ordering restore=unused
// HORDFIT: capacity-ordering rewrite-license=no
// HORDFIT-NOT: rewrite-license=yes

// HORDYES: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HORDYES: capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// HORDYES: capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// HORDYES: capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=no usable=no
// HORDYES: capacity-ordering object=2 before=n/a witness=n/a scope=n/a restore-ordering=no usable=no reason=no-ordering-witness
// HORDYES: capacity-ordering note source-data-ne-ordering
// HORDYES-NOT: rewrite-license=yes
// HORDYES-NOT: keep{0,1,2}

// HORDDATA: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HORDDATA: capacity-predicate source-data=yes restore-ordering=no dest-invalidation=no rewrite-path=no
// HORDDATA: capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=no
// HORDDATA: capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=no usable=no
// HORDDATA: capacity-ordering object=2 before=n/a witness=n/a scope=n/a restore-ordering=no usable=no reason=no-ordering-witness
// HORDDATA: capacity-ordering note source-valid-ne-restore-at-point
// HORDDATA-NOT: rewrite-license=yes
// HORDDATA-NOT: keep{0,1,2}

// HORDORD: capacity-license restore=unspecified{{.*}}evict-closed=no
// HORDORD: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HORDORD: capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// HORDORD: capacity-predicate source-data=yes restore-ordering=yes dest-invalidation=no rewrite-path=no
// HORDORD: capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=yes
// HORDORD: capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=yes usable=yes
// HORDORD: capacity-ordering object=2 before=5 witness=spec-before-consumer scope=occupancy-live restore-ordering=yes usable=yes reason=witnessed-before-consumer
// HORDORD: capacity-ordering rewrite-license=no
// HORDORD: capacity-ordering note restore-ordering-ne-sufficient
// HORDORD: capacity-ordering note dest-invalidation-still-no
// HORDORD: capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=no usable=yes
// HORDORD: capacity-invalidation object=2 destination=n/a witness=n/a scope=n/a dest-invalidation=no usable=yes reason=no-invalidation-witness
// HORDORD-NOT: rewrite-license=yes
// HORDORD-NOT: keep{0,1,2}

// ORD: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// ORD: s2c2-capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// ORD: s2c2-capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=no usable=no
// ORD: s2c2-capacity-ordering object=2 before=n/a witness=n/a scope=n/a restore-ordering=no usable=no reason=no-source-replica
// ORD: s2c2-capacity-ordering rewrite-license=no
// ORD-NOT: rewrite-license=yes
// ORD-NOT: s2c2-opt: applySchedule

// ORDFIT: s2c2-capacity-predicate source-data=n/a restore-ordering=n/a
// ORDFIT: s2c2-capacity-ordering selected={{.*}} restore-ordering=n/a usable=n/a
// ORDFIT: s2c2-capacity-ordering restore=unused
// ORDFIT: s2c2-capacity-ordering rewrite-license=no
// ORDFIT-NOT: rewrite-license=yes

// ORDYES: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// ORDYES: s2c2-capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// ORDYES: s2c2-capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// ORDYES: s2c2-capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=no usable=no
// ORDYES: s2c2-capacity-ordering object=2 before=n/a witness=n/a scope=n/a restore-ordering=no usable=no reason=no-ordering-witness
// ORDYES: s2c2-capacity-ordering note source-data-ne-ordering
// ORDYES-NOT: rewrite-license=yes
// ORDYES-NOT: s2c2-opt: applySchedule
// ORDYES-NOT: keep{0,1,2}

// ORDDATA: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// ORDDATA: s2c2-capacity-predicate source-data=yes restore-ordering=no dest-invalidation=no rewrite-path=no
// ORDDATA: s2c2-capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=no
// ORDDATA: s2c2-capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=no usable=no
// ORDDATA: s2c2-capacity-ordering object=2 before=n/a witness=n/a scope=n/a restore-ordering=no usable=no reason=no-ordering-witness
// ORDDATA: s2c2-capacity-ordering note source-valid-ne-restore-at-point
// ORDDATA-NOT: rewrite-license=yes
// ORDDATA-NOT: s2c2-opt: applySchedule
// ORDDATA-NOT: keep{0,1,2}

// ORDORD: s2c2-capacity-license restore=unspecified{{.*}}evict-closed=no
// ORDORD: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// ORDORD: s2c2-capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// ORDORD: s2c2-capacity-predicate source-data=yes restore-ordering=yes dest-invalidation=no rewrite-path=no
// ORDORD: s2c2-capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=yes
// ORDORD: s2c2-capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=yes usable=yes
// ORDORD: s2c2-capacity-ordering object=2 before=5 witness=spec-before-consumer scope=occupancy-live restore-ordering=yes usable=yes reason=witnessed-before-consumer
// ORDORD: s2c2-capacity-ordering rewrite-license=no
// ORDORD: s2c2-capacity-ordering note restore-ordering-ne-sufficient
// ORDORD: s2c2-capacity-ordering note dest-invalidation-still-no
// ORDORD: s2c2-capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=no usable=yes
// ORDORD: s2c2-capacity-invalidation object=2 destination=n/a witness=n/a scope=n/a dest-invalidation=no usable=yes reason=no-invalidation-witness
// ORDORD-NOT: rewrite-license=yes
// ORDORD-NOT: s2c2-opt: applySchedule
// ORDORD-NOT: keep{0,1,2}

// NOORD: s2c2-capacity-plan selected=none
// NOORD-NOT: s2c2-capacity-ordering
// NOORD-NOT: s2c2-capacity-invalidation
// NOORD-NOT: s2c2-capacity-sourcedata
// NOORD-NOT: rewrite-license=yes

// INVC: capacity-invalidation gate=query
// INVC: schema s2c2.capacity_invalidation.v1
// INVC: usable-ne-dest-invalidation yes
// INVC: dest-invalidation-ne-sufficient yes
// INVC: dest-invalidation-ne-rewrite-path yes
// INVC: rewrite-license no
// INVC: note usable-ne-dest-invalidation
// INVC: note dest-invalidation-ne-sufficient
// INVC: note dest-invalidation-ne-rewrite-path
// INVC: note rewrite-path-still-no
// INVC: note unknown-ne-rewrite
// INVC: note six-c-j-source-data-frozen
// INVC: note six-c-k-restore-ordering-frozen
// INVC: note six-c-l-dest-invalidation-this-cut
// INVC-NOT: rewrite-license yes

// HINV: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// HINV: capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// HINV: capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=no usable=no
// HINV: capacity-invalidation object=2 destination=n/a witness=n/a scope=n/a dest-invalidation=no usable=no reason=no-source-replica
// HINV: capacity-invalidation rewrite-license=no
// HINV-NOT: rewrite-license=yes

// HINVFIT: selected=keep{0,1}|evict{}|rematerialize{} policy=s0 rewrite-license=no
// HINVFIT: capacity-predicate source-data=n/a restore-ordering=n/a dest-invalidation=n/a
// HINVFIT: capacity-invalidation selected={{.*}} dest-invalidation=n/a usable=n/a
// HINVFIT: capacity-invalidation restore=unused
// HINVFIT: capacity-invalidation rewrite-license=no
// HINVFIT-NOT: rewrite-license=yes

// HINVYES: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HINVYES: capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// HINVYES: capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// HINVYES: capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=no usable=no
// HINVYES: capacity-invalidation object=2 destination=n/a witness=n/a scope=n/a dest-invalidation=no usable=no reason=no-invalidation-witness
// HINVYES: capacity-invalidation note usable-ne-dest-invalidation
// HINVYES-NOT: rewrite-license=yes
// HINVYES-NOT: keep{0,1,2}

// HINVDATA: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HINVDATA: capacity-predicate source-data=yes restore-ordering=no dest-invalidation=no rewrite-path=no
// HINVDATA: capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=no
// HINVDATA: capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=no usable=no
// HINVDATA: capacity-invalidation object=2 destination=n/a witness=n/a scope=n/a dest-invalidation=no usable=no reason=no-invalidation-witness
// HINVDATA-NOT: rewrite-license=yes
// HINVDATA-NOT: keep{0,1,2}

// HINVORD: capacity-license restore=unspecified{{.*}}evict-closed=no
// HINVORD: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HINVORD: capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// HINVORD: capacity-predicate source-data=yes restore-ordering=yes dest-invalidation=no rewrite-path=no
// HINVORD: capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=yes
// HINVORD: capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=yes usable=yes
// HINVORD: capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=no usable=yes
// HINVORD: capacity-invalidation object=2 destination=n/a witness=n/a scope=n/a dest-invalidation=no usable=yes reason=no-invalidation-witness
// HINVORD: capacity-invalidation note usable-ne-dest-invalidation
// HINVORD: capacity-invalidation note dest-invalidation-ne-sufficient
// HINVORD-NOT: rewrite-license=yes
// HINVORD-NOT: keep{0,1,2}

// HINVINV: capacity-license restore=unspecified{{.*}}evict-closed=no
// HINVINV: capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// HINVINV: capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// HINVINV: capacity-predicate source-data=yes restore-ordering=yes dest-invalidation=yes rewrite-path=no
// HINVINV: capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=yes
// HINVINV: capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=yes usable=yes
// HINVINV: capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=yes usable=yes
// HINVINV: capacity-invalidation object=2 destination=hbm witness=spec-drop-stale scope=occupancy-live dest-invalidation=yes usable=yes reason=witnessed-drop-stale
// HINVINV: capacity-invalidation rewrite-license=no
// HINVINV: capacity-invalidation note dest-invalidation-ne-sufficient
// HINVINV: capacity-invalidation note dest-invalidation-ne-rewrite-path
// HINVINV: capacity-invalidation note rewrite-path-still-no
// HINVINV-NOT: rewrite-license=yes
// HINVINV-NOT: keep{0,1,2}

// INV: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=no
// INV: s2c2-capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// INV: s2c2-capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=no usable=no
// INV: s2c2-capacity-invalidation object=2 destination=n/a witness=n/a scope=n/a dest-invalidation=no usable=no reason=no-source-replica
// INV: s2c2-capacity-invalidation rewrite-license=no
// INV-NOT: rewrite-license=yes
// INV-NOT: s2c2-opt: applySchedule

// INVFIT: s2c2-capacity-predicate source-data=n/a restore-ordering=n/a dest-invalidation=n/a
// INVFIT: s2c2-capacity-invalidation selected={{.*}} dest-invalidation=n/a usable=n/a
// INVFIT: s2c2-capacity-invalidation restore=unused
// INVFIT: s2c2-capacity-invalidation rewrite-license=no
// INVFIT-NOT: rewrite-license=yes

// INVYES: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// INVYES: s2c2-capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// INVYES: s2c2-capacity-predicate source-data=no restore-ordering=no dest-invalidation=no rewrite-path=no
// INVYES: s2c2-capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=no usable=no
// INVYES: s2c2-capacity-invalidation object=2 destination=n/a witness=n/a scope=n/a dest-invalidation=no usable=no reason=no-invalidation-witness
// INVYES: s2c2-capacity-invalidation note usable-ne-dest-invalidation
// INVYES-NOT: rewrite-license=yes
// INVYES-NOT: s2c2-opt: applySchedule
// INVYES-NOT: keep{0,1,2}

// INVDATA: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// INVDATA: s2c2-capacity-predicate source-data=yes restore-ordering=no dest-invalidation=no rewrite-path=no
// INVDATA: s2c2-capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=no
// INVDATA: s2c2-capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=no usable=no
// INVDATA: s2c2-capacity-invalidation object=2 destination=n/a witness=n/a scope=n/a dest-invalidation=no usable=no reason=no-invalidation-witness
// INVDATA-NOT: rewrite-license=yes
// INVDATA-NOT: s2c2-opt: applySchedule
// INVDATA-NOT: keep{0,1,2}

// INVORD: s2c2-capacity-license restore=unspecified{{.*}}evict-closed=no
// INVORD: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// INVORD: s2c2-capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// INVORD: s2c2-capacity-predicate source-data=yes restore-ordering=yes dest-invalidation=no rewrite-path=no
// INVORD: s2c2-capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=yes
// INVORD: s2c2-capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=yes usable=yes
// INVORD: s2c2-capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=no usable=yes
// INVORD: s2c2-capacity-invalidation object=2 destination=n/a witness=n/a scope=n/a dest-invalidation=no usable=yes reason=no-invalidation-witness
// INVORD: s2c2-capacity-invalidation note usable-ne-dest-invalidation
// INVORD: s2c2-capacity-invalidation note dest-invalidation-ne-sufficient
// INVORD-NOT: rewrite-license=yes
// INVORD-NOT: s2c2-opt: applySchedule
// INVORD-NOT: keep{0,1,2}

// INVINV: s2c2-capacity-license restore=unspecified{{.*}}evict-closed=no
// INVINV: s2c2-capacity-restore selected=keep{0,1}|evict{2}|rematerialize{} closed=yes
// INVINV: s2c2-capacity-predicate selected=keep{0,1}|evict{2}|rematerialize{} necessary=yes sufficient=no rewrite-license=no
// INVINV: s2c2-capacity-predicate source-data=yes restore-ordering=yes dest-invalidation=yes rewrite-path=no
// INVINV: s2c2-capacity-sourcedata selected=keep{0,1}|evict{2}|rematerialize{} source-data=yes replica-exists=yes usable=yes
// INVINV: s2c2-capacity-ordering selected=keep{0,1}|evict{2}|rematerialize{} restore-ordering=yes usable=yes
// INVINV: s2c2-capacity-invalidation selected=keep{0,1}|evict{2}|rematerialize{} dest-invalidation=yes usable=yes
// INVINV: s2c2-capacity-invalidation object=2 destination=hbm witness=spec-drop-stale scope=occupancy-live dest-invalidation=yes usable=yes reason=witnessed-drop-stale
// INVINV: s2c2-capacity-invalidation rewrite-license=no
// INVINV: s2c2-capacity-invalidation note dest-invalidation-ne-sufficient
// INVINV: s2c2-capacity-invalidation note dest-invalidation-ne-rewrite-path
// INVINV: s2c2-capacity-invalidation note rewrite-path-still-no
// INVINV-NOT: rewrite-license=yes
// INVINV-NOT: s2c2-opt: applySchedule
// INVINV-NOT: keep{0,1,2}

// NOINV: s2c2-capacity-plan selected=none
// NOINV-NOT: s2c2-capacity-invalidation
// NOINV-NOT: s2c2-capacity-ordering
// NOINV-NOT: rewrite-license=yes

// QUERYFIT: s2c2-capacity-plan-query feasible=yes
// QUERYFIT: selected=none
// QUERYFIT: identity=keep{0,1}|evict{}|rematerialize{}
// QUERYFIT: rewrite=no
// QUERYFIT: s2c2-capacity-license restore=n/a
// QUERYFIT-NOT: s2c2-storage-capacity
// QUERYFIT-NOT: evidence-bounded-schedule
// QUERYFIT-NOT: evict{0}

// QUERYTRUNC: s2c2-capacity-plan-query feasible=no enumerated=no truncated=yes legal=not-enumerated
// QUERYTRUNC: selected=none
// QUERYTRUNC: rewrite=no
// QUERYTRUNC: s2c2-capacity-license restore=n/a
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
// HSEL: capacity-license selected=keep{0,1}|evict{2}|rematerialize{} rewrite-license=no
// HSEL: capacity-license restore=unspecified{{.*}}evict-closed=no
// HSEL-NOT: selected=none policy=s0
// HSEL-NOT: keep{0,1,2}

// HSELFIT: selected=keep{0,1}|evict{}|rematerialize{} policy=s0
// HSELFIT: rewrite-license=no
// HSELFIT: capacity-license restore=unused
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
// SEL: s2c2-capacity-license selected=keep{0,1}|evict{2}|rematerialize{} rewrite-license=no
// SEL: s2c2-capacity-license restore=unspecified{{.*}}evict-closed=no
// SEL: s2c2-capacity-license note evict-requires-restore
// SEL: s2c2-capacity-license rewrite=no
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
// SELFIT: s2c2-capacity-license restore=unused
// SELFIT: evict-closed=n/a
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
// MEASC: match profile,workload_class,candidate_identity
// MEASC: argmin scoped-measured-intersect-F
// MEASC: rewrite-license no
// MEASC: note measured-needs-two-records
// MEASC: note measured-scope-profile-workload-candidate
// MEASC: note measured-ne-cross-profile
// MEASC: note measured-ne-cross-workload
// MEASC: note measured-does-not-expand-f
// MEASC: note duplicate-measured-identity
// MEASC: note argmin-ties-earliest-F
// MEASC: note do-not-filecheck-microseconds
// MEASC: note not-hardware-campaign
// MEASC: note not-new-evidence-db
// MEASC: note six-c-f-measured-ranking-this-cut
// MEASC: cost=unchanged

// HMEAS: selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1 rewrite-license=no
// HMEAS: candidate #0 identity=keep{0,1}|evict{2}|rematerialize{}
// HMEAS: candidate #1 identity=keep{1,2}|evict{0}|rematerialize{}
// HMEAS: candidate #2 identity=keep{0,2}|evict{1}|rematerialize{}
// HMEAS: capacity-measured ranked=keep{0,1}|evict{2}|rematerialize{}{{.*}}coincide-s0=yes{{.*}}profile=fixture workload=ssd-capacity-4tile
// HMEAS: capacity-measured note measured-does-not-expand-f
// HMEAS: capacity-measured note measured-scope-profile-workload-candidate
// HMEAS: capacity-measured-candidate identity=keep{0,1}|evict{2}|rematerialize{} evidence=yes
// HMEAS: capacity-license restore=unspecified
// HMEAS: capacity-license rewrite=no
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

// HMEASPROF: requires --profile

// HMEASWPROF: measured-needs-two-records
// HMEASWPROF-NOT: 7000
// HMEASWPROF-NOT: selected=keep

// HMEASWWL: measured-needs-two-records
// HMEASWWL-NOT: 8001
// HMEASWWL-NOT: selected=keep

// HMEASCROSS: selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1
// HMEASCROSS: coincide-s0=yes
// HMEASCROSS: note measured-ne-cross-workload
// HMEASCROSS-NOT: 501
// HMEASCROSS-NOT: 4000
// HMEASCROSS-NOT: coincide-s0=no

// MEAS: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1 rewrite-license=no
// MEAS: s2c2-capacity-plan-query candidate #0 identity=keep{0,1}|evict{2}|rematerialize{}
// MEAS: s2c2-capacity-plan-query candidate #1 identity=keep{1,2}|evict{0}|rematerialize{}
// MEAS: s2c2-capacity-plan-query candidate #2 identity=keep{0,2}|evict{1}|rematerialize{}
// MEAS: s2c2-capacity-plan-query note measured-capacity-v1-ranking-only
// MEAS: s2c2-capacity-plan-query note six-c-f-measured-ranking-this-cut
// MEAS: s2c2-capacity-measured ranked=keep{0,1}|evict{2}|rematerialize{}{{.*}}coincide-s0=yes{{.*}}profile=fixture workload=ssd-capacity-4tile{{.*}}rewrite=no rewrite-license=no
// MEAS: s2c2-capacity-measured-candidate identity=keep{0,1}|evict{2}|rematerialize{} evidence=yes
// MEAS: s2c2-capacity-measured-candidate identity=keep{1,2}|evict{0}|rematerialize{} evidence=yes
// MEAS: s2c2-capacity-measured-candidate identity=keep{0,2}|evict{1}|rematerialize{} evidence=yes
// MEAS: s2c2-capacity-license selected=keep{0,1}|evict{2}|rematerialize{} rewrite-license=no
// MEAS: s2c2-capacity-license restore=unspecified
// MEAS: s2c2-capacity-license note measured-ne-rewrite-license
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

// MEASPROF: requires --profile
// MEASPROF-NOT: rewrite-license=yes

// MEASTRUNC: truncated plan cannot be selected
// MEASTRUNC-NOT: evidence-bounded-schedule

// MEASWPROF: measured-needs-two-records
// MEASWPROF-NOT: 7000
// MEASWPROF-NOT: rewrite-license=yes

// MEASWWL: measured-needs-two-records
// MEASWWL-NOT: 8001
// MEASWWL-NOT: rewrite-license=yes

// MEASCROSS: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1
// MEASCROSS: s2c2-capacity-measured {{.*}}coincide-s0=yes{{.*}}profile=fixture workload=ssd-capacity-4tile{{.*}}measured-ne-cross-workload
// MEASCROSS-NOT: 501
// MEASCROSS-NOT: 4000
// MEASCROSS-NOT: coincide-s0=no
// MEASCROSS-NOT: rewrite-license=yes

// HMEASTIE: selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1
// HMEASTIE: argmin-size=2
// HMEASTIE: coincide-s0=yes
// HMEASTIE: note argmin-ties-earliest-F
// HMEASTIE: capacity-measured-candidate identity=keep{0,1}|evict{2}|rematerialize{} evidence=yes
// HMEASTIE: capacity-measured-candidate identity=keep{1,2}|evict{0}|rematerialize{} evidence=yes
// HMEASTIE: capacity-measured-candidate identity=keep{0,2}|evict{1}|rematerialize{} evidence=no
// HMEASTIE-NOT: selected=keep{1,2}|evict{0}
// HMEASTIE-NOT: rewrite-license=yes

// HMEASDUP: duplicate-measured-identity
// HMEASDUP-NOT: selected=keep
// HMEASDUP-NOT: rewrite-license=yes

// MEASTIE: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1
// MEASTIE: s2c2-capacity-measured {{.*}}argmin-size=2{{.*}}coincide-s0=yes{{.*}}argmin-ties-earliest-F
// MEASTIE: s2c2-capacity-measured-candidate identity=keep{0,1}|evict{2}|rematerialize{} evidence=yes
// MEASTIE: s2c2-capacity-measured-candidate identity=keep{1,2}|evict{0}|rematerialize{} evidence=yes
// MEASTIE: s2c2-capacity-measured-candidate identity=keep{0,2}|evict{1}|rematerialize{} evidence=no
// MEASTIE-NOT: selected=keep{1,2}|evict{0}|rematerialize{}
// MEASTIE-NOT: rewrite-license=yes
// MEASTIE-NOT: s2c2-storage-capacity

// MEASDUP: duplicate-measured-identity
// MEASDUP-NOT: rewrite-license=yes
// MEASDUP-NOT: selected=keep

// MEASBOTH: s2c2-capacity-plan-query selected=keep{0,1}|evict{2}|rematerialize{} policy=measured-capacity-v1
// MEASBOTH: s2c2-capacity-measured {{.*}}profile=rtx4090 workload=ssd-capacity-4tile
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
