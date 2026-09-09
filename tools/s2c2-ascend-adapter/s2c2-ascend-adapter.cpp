//===- s2c2-ascend-adapter.cpp - host protocol (no ACL) ---------*- C++ -*-===//
//
// Prints the Ascend capability-adapter contract. Does not launch kernels,
// recompute Cost, or search. Timed runs live in runtime/ascend/.
//
//===----------------------------------------------------------------------===//

#include "AdapterContract.h"

#include <cstdio>
#include <cstring>
#include <string>

using s2c2::ascend_adapter::classifyPair;
using s2c2::ascend_adapter::kPairCount;
using s2c2::ascend_adapter::kPairs;
using s2c2::ascend_adapter::kSchemaFieldCount;
using s2c2::ascend_adapter::kSchemaFields;
using s2c2::ascend_adapter::kSync;
using s2c2::ascend_adapter::kWorkloadCount;
using s2c2::ascend_adapter::kWorkloads;

static void printMaps() {
  std::fprintf(stderr, "s2c2-ascend-adapter map stor.pack=host_pinned\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter map comm.stream=aclrtMemcpyAsync\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter map sched.wait="
               "aclrtRecordEvent+aclrtStreamWaitEvent\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter map event=submitted-work-on-stream\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter map sched.concurrent=two_streams\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter map comp.elemwise=ascend_unary_op\n");
  std::fprintf(
      stderr, "s2c2-ascend-adapter note workload-semantic-ne-kernel-backend\n");
  std::fprintf(stderr, "s2c2-ascend-adapter score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cost=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter semantics=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter v3=not-claimed\n");
}

static void printWorkloads() {
  std::fprintf(stderr, "s2c2-ascend-adapter workload-contract=v1\n");
  for (int i = 0; i < kWorkloadCount; ++i) {
    std::fprintf(stderr,
                 "s2c2-ascend-adapter workload id=%s role=%s semantic=%s\n",
                 kWorkloads[i].id, kWorkloads[i].role, kWorkloads[i].semantic);
  }
  std::fprintf(stderr, "s2c2-ascend-adapter workload compute=elemwise\n");
  std::fprintf(stderr, "s2c2-ascend-adapter workload transfer=host_to_device|"
                       "device_to_host\n");
}

static void printPairs() {
  std::fprintf(stderr, "s2c2-ascend-adapter pairs=3\n");
  for (int i = 0; i < kPairCount; ++i) {
    std::fprintf(stderr,
                 "s2c2-ascend-adapter pair id=%s name=%s left=%s right=%s\n",
                 kPairs[i].id, kPairs[i].pair, kPairs[i].left, kPairs[i].right);
  }
  std::fprintf(stderr, "s2c2-ascend-adapter pair=C||HtoD\n");
  std::fprintf(stderr, "s2c2-ascend-adapter pair=C||C\n");
  std::fprintf(stderr, "s2c2-ascend-adapter pair=HtoD||DtoH\n");
  std::fprintf(stderr, "s2c2-ascend-adapter timing=host-wall-clock\n");
  std::fprintf(stderr, "s2c2-ascend-adapter timing completion=s0,s1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter correctness=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cost=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter semantics=unchanged\n");
}

static void printMem() {
  std::fprintf(stderr, "s2c2-ascend-adapter mem=r4\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter mem map stor.host=pinned|pageable\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter mem map stor.pinned=aclrtMallocHost\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem map stor.pageable=malloc\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter mem map comm.copy=aclrtMemcpyAsync\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem map "
                       "sched.concurrent=named-nonblocking\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem cell host-pinned\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem cell host-pageable\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter mem cell extra-hb=pageable-host\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem pair=C||HtoD\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem pair=C||DtoH\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem acceptance=storage-comm\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem note residency-ne-extra-hb\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem timing=host-wall-clock\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem cost=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter mem semantics=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter v3=not-claimed\n");
}

static void printCCPhase() {
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase pair=C||C\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase r=T_C1/T_C2\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase r_target=0.5,0.75,1,1.5,2\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase n=4M,16M,64M\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase k_ref=C2\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase timing=host-wall-clock\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase completion=s0,s1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase r3-gate=closed\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase note catalog-untouched\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase cost=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-phase semantics=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter v3=not-claimed\n");
}

static void printSsdMlpWallclock() {
  std::fprintf(stderr, "s2c2-ascend-adapter ssd-mlp-wallclock=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock program-measurement=yes\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock note not-stage-ab\n");
  std::fprintf(stderr, "s2c2-ascend-adapter ssd-mlp-wallclock t-base=t-seq\n");
  std::fprintf(stderr, "s2c2-ascend-adapter ssd-mlp-wallclock t-opt=t-evi\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock n-htod=22528000\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock n-cc=33554432\n");
  std::fprintf(stderr, "s2c2-ascend-adapter ssd-mlp-wallclock k_ref=32\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock ab=seq-vs-evi\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock "
               "evi=keep-C||HtoD,serialize-licensed-C||C\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock "
               "note logical-ssd-ne-disk\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock "
               "note 32M-outlier-not-cost\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock note not-cost-v04\n");
  std::fprintf(stderr, "s2c2-ascend-adapter ssd-mlp-wallclock cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter ssd-mlp-wallclock semantics=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter v3=not-claimed\n");
}

static void printStorageLoop() {
  std::fprintf(stderr, "s2c2-ascend-adapter storage-loop=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-loop source=s2c2-opt\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop "
               "note scf-for-software-pipeline\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop "
               "note loop-carried-lifetime\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop "
               "note not-c-storage-flatten\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop note no-invented-wait\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop "
               "runtime-witness=storage-loop-wallclock\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop note not-cost-v04\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-loop cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop semantics=unchanged\n");
}

static void printStorageLoopWallclock() {
  std::fprintf(stderr, "s2c2-ascend-adapter storage-loop-wallclock=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock "
               "program-measurement=yes\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock "
               "note scf-for-software-pipeline\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock "
               "note not-arbitrary-runtime-n\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock t-base=t-seq\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock t-opt=t-evi\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock "
               "note evi-eq-par\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock "
               "evi=keep-C||Storage\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock n-tile=4194304\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock tiles=3\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock trip=2\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock k_ref=32\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock "
               "note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock "
               "note logical-ssd-ne-disk\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock note not-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-loop-wallclock "
               "semantics=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter v3=not-claimed\n");
}

static void printStorageNtile() {
  std::fprintf(stderr, "s2c2-ascend-adapter storage-ntile=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-ntile source=s2c2-opt\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-ntile "
               "note compute-then-prefetch-next\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-ntile "
               "note proven-live-residency\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-ntile "
               "note not-c-storage-flatten\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-ntile note no-invented-wait\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-ntile "
               "runtime-witness=storage-pipeline\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-ntile note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-ntile note not-cost-v04\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-ntile cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-ntile semantics=unchanged\n");
}

static void printStorageHierarchy() {
  std::fprintf(stderr, "s2c2-ascend-adapter storage-hierarchy=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-hierarchy source=s2c2-opt\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-hierarchy "
               "note ssd-host-hbm-compute\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-hierarchy "
               "note inferred-overlap-ne-flatten\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-hierarchy "
               "note keep-residency-ne-rematerialize\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-hierarchy "
               "runtime-witness=storage-pipeline\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-hierarchy note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-hierarchy note not-cost-v04\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-hierarchy cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-hierarchy semantics=unchanged\n");
}

static void printStorageSchedule() {
  std::fprintf(stderr, "s2c2-ascend-adapter storage-schedule=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-schedule source=s2c2-opt\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-schedule "
               "note legal-candidates-then-select\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-schedule "
               "note selection-ne-cost\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-schedule "
               "note selection-ne-rewrite-license\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-schedule policy=default-3g\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-schedule "
               "note not-c-storage-flatten\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-schedule note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-schedule note not-cost-v04\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-schedule cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-schedule semantics=unchanged\n");
}

static void printStorageJoint() {
  std::fprintf(stderr, "s2c2-ascend-adapter storage-joint=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-joint source=s2c2-opt\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-joint "
               "note joint-candidates-then-select\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-joint note selection-ne-cost\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-joint "
               "note selection-ne-rewrite-license\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-joint policy=default-3g\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-joint note default-3g-frozen\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-joint "
               "note cost-ranking-is-policy-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-joint "
               "note not-c-storage-flatten\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-joint note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-joint note not-cost-v04\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-joint cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-joint semantics=unchanged\n");
}

static void printStorageGlobal() {
  std::fprintf(stderr, "s2c2-ascend-adapter storage-global=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-global source=s2c2-opt\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global "
               "note global-candidates-then-select\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global note selection-ne-cost\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global "
               "note selection-ne-rewrite-license\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global policy=default-3g\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global note default-3g-frozen\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global note chain-def-frozen\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global "
               "note truncated-ne-complete-F\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global "
               "note historical-tuple-or-fail\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global "
               "note cost-ranking-is-policy-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global "
               "note not-c-storage-flatten\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global note not-cost-v04\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-global cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-global semantics=unchanged\n");
}

static void printStorageCost() {
  std::fprintf(stderr, "s2c2-ascend-adapter storage-cost=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-cost source=s2c2-opt\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost "
               "note cost-ranks-enumerated-F-only\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost note cost-ne-legality\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost "
               "note cost-ne-rewrite-license\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost policy=cost-v04\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost note default-3g-frozen\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost note truncated-ne-ranked\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost note not-s2c2-argmin\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost note not-score3\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost "
               "note not-new-capability-grid\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost "
               "note cost-v04-structural-frozen\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost "
               "note not-c-storage-flatten\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost note chain-def-frozen\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-cost cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-cost semantics=unchanged\n");
}

static void printStorageMeasured() {
  std::fprintf(stderr, "s2c2-ascend-adapter storage-measured=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-measured source=s2c2-opt\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-measured "
               "policy=measured-storage-v1\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-measured "
               "note measured-ne-legality\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-measured "
               "note measured-ne-rewrite-license\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-measured note default-3g-frozen\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-measured "
               "note cost-v04-structural-frozen\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-measured "
               "note not-new-capability-grid\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-measured "
               "note do-not-filecheck-microseconds\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-measured "
               "note runtime-validation-pending\n");
  std::fprintf(stderr, "s2c2-ascend-adapter storage-measured cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter storage-measured semantics=unchanged\n");
}

static void printWorkloadSchedule() {
  std::fprintf(stderr, "s2c2-ascend-adapter workload-schedule=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter workload-schedule source=s2c2-opt\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter workload-schedule "
               "note not-handwritten-optimized-ir\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter workload-schedule "
               "runtime-witness=ssd-mlp-wallclock\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter workload-schedule "
               "note compiler-chosen-t-evi\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter workload-schedule "
               "note not-new-capability-grid\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter workload-schedule "
               "note storage-data-movement-overlap\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter workload-schedule note not-cost-v04\n");
  std::fprintf(stderr, "s2c2-ascend-adapter workload-schedule cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter workload-schedule semantics=unchanged\n");
}

static void printCCRewrite() {
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite pair=C||C\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite r=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter cc-rewrite n=32M,64M,128M\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite k_ref=32\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite ab=par-vs-seq\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite seq=s0-then-s1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite seq-slack=1.05\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter cc-rewrite note seq-slack-ne-cost\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite note rewrite-loop\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite r3-gate=closed\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter cc-rewrite note catalog-untouched\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite cost=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-rewrite semantics=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter v3=not-claimed\n");
}

static void printCCSize() {
  std::fprintf(stderr, "s2c2-ascend-adapter cc-size=1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-size pair=C||C\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-size r=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter cc-size n=4M,8M,12M,16M,32M,64M,128M\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-size note size-boundary\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-size r3-gate=closed\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-size note catalog-untouched\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-size cost=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cc-size semantics=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter v3=not-claimed\n");
}

static void printCapSchema() {
  std::fprintf(stderr, "s2c2-ascend-adapter cap-schema=v1\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter cap-schema transfer_domain=copy_engine\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter cap-schema direction=host_to_device\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter note transfer_domain-ne-direction\n");
  for (int i = 0; i < kSchemaFieldCount; ++i)
    std::fprintf(stderr, "s2c2-ascend-adapter cap-schema field=%s\n",
                 kSchemaFields[i]);
  std::fprintf(stderr, "s2c2-ascend-adapter cap-schema hardware=unfilled\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cap-schema pair_relation="
                       "parallel|serial|mixed|underdetermined\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cap-schema observed_constraint="
                       "none|legacy_default|resource_contention|"
                       "allocator_sync|copy_engine_contention\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter cap-schema no-extra-key=acl_davinci\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cap-schema depth-star=not-a-law\n");
  std::fprintf(stderr,
               "s2c2-ascend-adapter cap-schema score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cap-schema cost=unchanged\n");
  std::fprintf(stderr, "s2c2-ascend-adapter cap-schema semantics=unchanged\n");
}

static void printClassify(double ta, double tb, double tpar) {
  double mx = ta > tb ? ta : tb;
  double sum = ta + tb;
  double pmax = mx > 0.0 ? tpar / mx : 0.0;
  double psum = sum > 0.0 ? tpar / sum : 0.0;
  const char *rel = classifyPair(pmax, psum);
  std::fprintf(stderr, "s2c2-ascend-adapter classify protocol=v1\n");
  std::fprintf(stderr, "s2c2-ascend-adapter classify pair_relation=%s\n", rel);
  std::fprintf(stderr,
               "s2c2-ascend-adapter classify rule=par/sum>=0.90->serial\n");
  std::fprintf(stderr, "s2c2-ascend-adapter classify "
                       "rule=par/max<=1.15,par/sum<=0.75->parallel\n");
  std::fprintf(stderr, "s2c2-ascend-adapter classify else=mixed\n");
  std::fprintf(stderr, "s2c2-ascend-adapter classify cost=unchanged\n");
}

static bool isForeignHardware(const char *hid) {
  if (!hid)
    return false;
  std::string s(hid);
  for (char &c : s) {
    if (c >= 'A' && c <= 'Z')
      c = static_cast<char>(c - 'A' + 'a');
  }
  return s.find("4090") != std::string::npos ||
         s.find("sm89") != std::string::npos ||
         s.find("rtx") != std::string::npos ||
         s.find("cuda") != std::string::npos ||
         s.find("gfx") != std::string::npos ||
         s.find("amd") != std::string::npos ||
         s.find("hip") != std::string::npos ||
         s.find("rocm") != std::string::npos;
}

static int emitRecord(const char *pair) {
  const s2c2::ascend_adapter::PairContract *found = nullptr;
  for (int i = 0; i < kPairCount; ++i) {
    if (std::strcmp(pair, kPairs[i].pair) == 0)
      found = &kPairs[i];
  }
  if (!found) {
    std::fprintf(stderr, "s2c2-ascend-adapter: unknown pair %s\n", pair);
    return 1;
  }
  const char *compute = "none";
  const char *transfer = "none";
  const char *direction = "none";
  const char *src = "none";
  const char *dst = "none";
  if (std::strcmp(found->pair, "C||HtoD") == 0) {
    compute = "ascend_ai_core";
    transfer = "copy_engine";
    direction = "host_to_device";
    src = "pinned_host";
    dst = "device_memory";
  } else if (std::strcmp(found->pair, "C||C") == 0) {
    compute = "ascend_ai_core";
    src = "device_memory";
    dst = "device_memory";
  } else if (std::strcmp(found->pair, "HtoD||DtoH") == 0) {
    transfer = "copy_engine";
    direction = "host_to_device";
    src = "pinned_host";
    dst = "device_memory";
  }
  std::fprintf(stderr,
               "{\"schema_version\":\"1\",\"record_kind\":\"pair\","
               "\"hardware_id\":\"unfilled\",\"compute_domain\":\"%s\","
               "\"transfer_domain\":\"%s\",\"direction\":\"%s\","
               "\"source_memory_class\":\"%s\","
               "\"destination_memory_class\":\"%s\",\"pair\":\"%s\","
               "\"pair_relation\":\"underdetermined\","
               "\"regime\":\"underdetermined\",\"size_range\":\"n/a\","
               "\"synchronization\":\"%s\","
               "\"pipeline_depth_evidence\":\"n/a\","
               "\"observed_constraint\":\"none\",\"confidence\":\"unknown\","
               "\"note\":\"host emit-record; not measured\","
               "\"evidence_refs\":\"backend-adapter-ascend.md\","
               "\"v3\":\"not-claimed\",\"cost\":\"unchanged\","
               "\"semantics\":\"unchanged\"}\n",
               compute, transfer, direction, src, dst, found->pair, kSync);
  std::fprintf(stderr,
               "s2c2-ascend-adapter emit-record pair=%s "
               "confidence=unknown pair_relation=underdetermined\n",
               found->pair);
  return 0;
}

static void usage() {
  std::fprintf(stderr,
               "s2c2-ascend-adapter --dry-run [--pairs] [--workload] "
               "[--cap-schema] [--mem] [--cc-phase] [--cc-size] "
               "[--cc-rewrite] [--ssd-mlp-wallclock] [--storage-hierarchy] "
               "[--storage-schedule] [--storage-joint] [--storage-global] "
               "[--storage-cost] [--storage-measured] "
               "[--storage-ntile] [--storage-loop] "
               "[--storage-loop-wallclock] [--workload-schedule] "
               "[--classify=ta:tb:tpar] "
               "[--emit-record=<pair>] [--accept-hardware=<id>]\n"
               "Host protocol only. Timed AscendCL: runtime/ascend/\n");
}

int main(int argc, char **argv) {
  bool dryRun = false;
  bool pairs = false;
  bool workload = false;
  bool capSchema = false;
  bool mem = false;
  bool ccPhase = false;
  bool ccSize = false;
  bool ccRewrite = false;
  bool ssdMlp = false;
  bool storageHier = false;
  bool storageSched = false;
  bool storageJoint = false;
  bool storageGlobal = false;
  bool storageCost = false;
  bool storageMeasured = false;
  bool storageNtile = false;
  bool storageLoop = false;
  bool storageLoopWc = false;
  bool workloadSched = false;
  const char *classify = nullptr;
  const char *emit = nullptr;
  const char *acceptHw = nullptr;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--dry-run") {
      dryRun = true;
    } else if (a == "--pairs") {
      pairs = true;
    } else if (a == "--workload") {
      workload = true;
    } else if (a == "--cap-schema") {
      capSchema = true;
    } else if (a == "--mem") {
      mem = true;
    } else if (a == "--cc-phase") {
      ccPhase = true;
    } else if (a == "--cc-size") {
      ccSize = true;
    } else if (a == "--cc-rewrite") {
      ccRewrite = true;
    } else if (a == "--ssd-mlp-wallclock") {
      ssdMlp = true;
    } else if (a == "--storage-hierarchy") {
      storageHier = true;
    } else if (a == "--storage-schedule") {
      storageSched = true;
    } else if (a == "--storage-joint") {
      storageJoint = true;
    } else if (a == "--storage-global") {
      storageGlobal = true;
    } else if (a == "--storage-cost") {
      storageCost = true;
    } else if (a == "--storage-measured") {
      storageMeasured = true;
    } else if (a == "--storage-ntile") {
      storageNtile = true;
    } else if (a == "--storage-loop") {
      storageLoop = true;
    } else if (a == "--storage-loop-wallclock") {
      storageLoopWc = true;
    } else if (a == "--workload-schedule") {
      workloadSched = true;
    } else if (a.rfind("--classify=", 0) == 0) {
      classify = argv[i] + 11;
    } else if (a.rfind("--emit-record=", 0) == 0) {
      emit = argv[i] + 14;
    } else if (a.rfind("--accept-hardware=", 0) == 0) {
      acceptHw = argv[i] + 18;
    } else if (a == "--help" || a == "-h") {
      usage();
      return 0;
    } else {
      std::fprintf(stderr, "s2c2-ascend-adapter: unknown arg %s\n", argv[i]);
      return 1;
    }
  }

  if (!dryRun) {
    std::fprintf(stderr,
                 "s2c2-ascend-adapter: this host tool is --dry-run only; "
                 "build runtime/ascend/s2c2_ascend_adapter.cpp for timing\n");
    return 1;
  }

  std::fprintf(stderr, "s2c2-ascend-adapter dry-run=1\n");
  int modes = (int)pairs + (int)workload + (int)capSchema + (int)mem +
              (int)ccPhase + (int)ccSize + (int)ccRewrite + (int)ssdMlp +
              (int)storageHier + (int)storageSched + (int)storageJoint +
              (int)storageGlobal + (int)storageCost + (int)storageMeasured +
              (int)storageNtile + (int)storageLoop +
              (int)storageLoopWc + (int)workloadSched +
              (int)(classify != nullptr) + (int)(emit != nullptr) +
              (int)(acceptHw != nullptr);
  if (modes > 1) {
    std::fprintf(stderr,
                 "s2c2-ascend-adapter: --cap-schema/--pairs/--workload/--mem/"
                 "--cc-phase/--cc-size/--cc-rewrite/--ssd-mlp-wallclock/"
                 "--storage-hierarchy/--storage-schedule/--storage-joint/"
                 "--storage-global/--storage-cost/--storage-measured/"
                 "--storage-ntile/"
                 "--storage-loop/"
                 "--storage-loop-wallclock/--workload-schedule/"
                 "--classify/--emit-record/"
                 "--accept-hardware cannot combine\n");
    return 1;
  }

  if (acceptHw) {
    if (isForeignHardware(acceptHw)) {
      std::fprintf(stderr,
                   "s2c2-ascend-adapter foreign-hardware=rejected id=%s\n",
                   acceptHw);
      std::fprintf(stderr, "s2c2-ascend-adapter note "
                           "capability-4090-ne-capability-910b\n");
      return 1;
    }
    std::fprintf(stderr,
                 "s2c2-ascend-adapter hardware-scope=this-profile id=%s\n",
                 acceptHw);
    return 0;
  }

  if (classify) {
    double ta = 0, tb = 0, tpar = 0;
    if (std::sscanf(classify, "%lf:%lf:%lf", &ta, &tb, &tpar) != 3) {
      std::fprintf(stderr, "s2c2-ascend-adapter: classify wants ta:tb:tpar\n");
      return 1;
    }
    printClassify(ta, tb, tpar);
    return 0;
  }

  if (emit)
    return emitRecord(emit);

  if (mem) {
    printMem();
    return 0;
  }
  if (ccPhase) {
    printCCPhase();
    return 0;
  }
  if (ccSize) {
    printCCSize();
    return 0;
  }
  if (ccRewrite) {
    printCCRewrite();
    return 0;
  }
  if (ssdMlp) {
    printSsdMlpWallclock();
    return 0;
  }
  if (storageHier) {
    printStorageHierarchy();
    return 0;
  }
  if (storageSched) {
    printStorageSchedule();
    return 0;
  }
  if (storageJoint) {
    printStorageJoint();
    return 0;
  }
  if (storageGlobal) {
    printStorageGlobal();
    return 0;
  }
  if (storageCost) {
    printStorageCost();
    return 0;
  }
  if (storageMeasured) {
    printStorageMeasured();
    return 0;
  }
  if (storageNtile) {
    printStorageNtile();
    return 0;
  }
  if (storageLoop) {
    printStorageLoop();
    return 0;
  }
  if (storageLoopWc) {
    printStorageLoopWallclock();
    return 0;
  }
  if (workloadSched) {
    printWorkloadSchedule();
    return 0;
  }
  if (capSchema) {
    printCapSchema();
    printMaps();
    return 0;
  }
  if (workload) {
    printWorkloads();
    printMaps();
    return 0;
  }
  if (pairs) {
    printPairs();
    printMaps();
    return 0;
  }

  printWorkloads();
  printPairs();
  printMaps();
  return 0;
}
