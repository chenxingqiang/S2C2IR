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

// Phase 6C-B diagnostics: F_capacity candidate generation.
// KEEP / EVICT / REMATERIALIZE. TRANSFER is an existing
// restore realization, not a new action. No rewrite, no
// ranking, no measured-capacity-v1, no hardware campaign.
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
// CONTRACT: note six-c-diagnostics-this-cut
// CONTRACT: note compiler-emits-f-capacity
// CONTRACT: note compiler-ne-rewrite
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
// OPT4: s2c2-storage-capacity note six-c-diagnostics-this-cut
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

// BADCAP: invalid --capacity=

// NOSPACE: no constrained-space residencies

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
