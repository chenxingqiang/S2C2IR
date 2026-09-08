// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-loop-wallclock-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-loop-wallclock %S/../Pilot/storage-loop-wallclock-yes-fixture.log | FileCheck %s --check-prefix=YES
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-loop-wallclock %S/../Pilot/storage-loop-wallclock-no-fixture.log | FileCheck %s --check-prefix=NO
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-loop-wallclock %S/../Pilot/storage-loop-wallclock-device-absent.log | FileCheck %s --check-prefix=ABSENT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-loop-wallclock %S/../../docs/design/v3-dataset/storage-loop-wallclock.log | FileCheck %s --check-prefix=HW
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-loop-wallclock %S/../../docs/design/v3-dataset/storage-loop-wallclock-4090.log | FileCheck %s --check-prefix=HW4090
// RUN: s2c2-ascend-adapter --dry-run --storage-loop-wallclock 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: s2c2-cuda-adapter --dry-run --storage-loop-wallclock 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: not s2c2-ascend-adapter --dry-run --storage-loop-wallclock --storage-loop 2>&1 | FileCheck %s --check-prefix=EXCL
// RUN: not s2c2-cuda-adapter --dry-run --storage-loop-wallclock --ssd-mlp-wallclock 2>&1 | FileCheck %s --check-prefix=EXCL
// RUN: s2c2-opt %S/storage-loop.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-schedule|loop-pipeline' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %S/storage-loop.mlir --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-schedule|loop-pipeline' | FileCheck %s --check-prefix=NPU-LOG
// RUN: s2c2-opt %S/storage-loop.mlir --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-schedule|loop-pipeline' | FileCheck %s --check-prefix=UNK-LOG
// RUN: s2c2-opt %S/storage-loop.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER

// Phase 3J: program-level wall-clock of the 3I scf.for software
// pipeline. T_evi / T_seq. Static trip=2 after prologue. Not an
// arbitrary runtime-N scheduler. Analyzer: NO / ABSENT / HW are
// disjoint files. Do not FileCheck microseconds. Not Cost.

// CONTRACT: storage-loop-wallclock program-measurement=yes
// CONTRACT: no-evidence => no-destructive-optimization
// CONTRACT: invariant underdetermined-preserve
// CONTRACT: note scf-for-software-pipeline
// CONTRACT: note not-arbitrary-runtime-n
// CONTRACT: note t-base-is-t-seq
// CONTRACT: note t-opt-is-t-evi
// CONTRACT: note evi-eq-par
// CONTRACT: note catalog-untouched
// CONTRACT: note logical-ssd-ne-disk
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password
// CONTRACT-NOT: arbitrary runtime-N

// YES: storage-loop-wallclock program-measurement=yes
// YES: storage-loop-wallclock measured=yes
// YES: storage-loop-wallclock t-opt-over-base-defined=yes
// YES: note t-base-is-t-seq
// YES: note t-opt-is-t-evi
// YES: note evi-eq-par
// YES: note catalog-untouched
// YES: cost=unchanged
// YES-NOT: Cost v0.4
// YES-NOT: password

// NO: storage-loop-wallclock measured=no
// NO: storage-loop-wallclock t-opt-over-base-defined=no
// NO: cost=unchanged
// NO-NOT: Cost v0.4

// ABSENT: storage-loop-wallclock measured=no
// ABSENT: storage-loop-wallclock t-opt-over-base-defined=no
// ABSENT: note catalog-untouched
// ABSENT: note device-absent
// ABSENT: cost=unchanged
// ABSENT-NOT: Cost v0.4
// ABSENT-NOT: password

// HW: storage-loop-wallclock program-measurement=yes
// HW: storage-loop-wallclock measured=no
// HW: storage-loop-wallclock t-opt-over-base-defined=no
// HW: note catalog-untouched
// HW: note device-absent
// HW: cost=unchanged
// HW-NOT: Cost v0.4
// HW-NOT: password

// HW4090: storage-loop-wallclock program-measurement=yes
// HW4090: storage-loop-wallclock measured=yes
// HW4090: storage-loop-wallclock t-opt-over-base-defined=yes
// HW4090: note t-base-is-t-seq
// HW4090: note t-opt-is-t-evi
// HW4090: note catalog-untouched
// HW4090-NOT: measured=no
// HW4090-NOT: note device-absent
// HW4090: cost=unchanged
// HW4090-NOT: Cost v0.4
// HW4090-NOT: password

// ASCEND: s2c2-ascend-adapter storage-loop-wallclock=1
// ASCEND: s2c2-ascend-adapter storage-loop-wallclock program-measurement=yes
// ASCEND: s2c2-ascend-adapter storage-loop-wallclock note scf-for-software-pipeline
// ASCEND: s2c2-ascend-adapter storage-loop-wallclock note not-arbitrary-runtime-n
// ASCEND: s2c2-ascend-adapter storage-loop-wallclock t-base=t-seq
// ASCEND: s2c2-ascend-adapter storage-loop-wallclock t-opt=t-evi
// ASCEND: s2c2-ascend-adapter storage-loop-wallclock note evi-eq-par
// ASCEND: s2c2-ascend-adapter storage-loop-wallclock note catalog-untouched
// ASCEND: s2c2-ascend-adapter storage-loop-wallclock note logical-ssd-ne-disk
// ASCEND: s2c2-ascend-adapter storage-loop-wallclock cost=unchanged
// ASCEND-NOT: Cost v0.4
// ASCEND-NOT: password

// CUDA: s2c2-cuda-adapter storage-loop-wallclock=1
// CUDA: s2c2-cuda-adapter storage-loop-wallclock program-measurement=yes
// CUDA: s2c2-cuda-adapter storage-loop-wallclock note scf-for-software-pipeline
// CUDA: s2c2-cuda-adapter storage-loop-wallclock note not-arbitrary-runtime-n
// CUDA: s2c2-cuda-adapter storage-loop-wallclock t-base=t-seq
// CUDA: s2c2-cuda-adapter storage-loop-wallclock t-opt=t-evi
// CUDA: s2c2-cuda-adapter storage-loop-wallclock note evi-eq-par
// CUDA: s2c2-cuda-adapter storage-loop-wallclock note catalog-untouched
// CUDA: s2c2-cuda-adapter storage-loop-wallclock note logical-ssd-ne-disk
// CUDA: s2c2-cuda-adapter storage-loop-wallclock cost=unchanged
// CUDA-NOT: Cost v0.4

// EXCL: cannot combine

// GPU-LOG: hierarchy-schedule sites=11 materialize=5 prefetch=1
// GPU-LOG: loop-pipeline op=scf.for trip=2
// NPU-LOG: hierarchy-schedule sites=11 materialize=5 prefetch=1
// NPU-LOG: loop-pipeline op=scf.for trip=2
// UNK-LOG: hierarchy-schedule sites=11 materialize=5 prefetch=0
// UNK-LOG-SAME: preserve=1
// UNK-LOG: loop-pipeline op=scf.for trip=2

// LOWER: scf.for
// LOWER: scf.if
// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
