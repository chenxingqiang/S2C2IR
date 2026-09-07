//===- s2c2-cuda-adapter.cpp - host protocol (no CUDA) ----------*- C++ -*-===//
//
// Prints the frozen Pilot → CUDA binding. Does not launch kernels,
// recompute Cost, or search. Timed runs live in runtime/cuda/.
//
//===----------------------------------------------------------------------===//

#include "AdapterContract.h"

#include <cstdio>
#include <cstring>
#include <string>

using s2c2::cuda_adapter::kDevice;
using s2c2::cuda_adapter::kMap;
using s2c2::cuda_adapter::kPilotCount;
using s2c2::cuda_adapter::kPilots;
using s2c2::cuda_adapter::kSched;

static void printBind(const s2c2::cuda_adapter::PilotBind &p) {
  std::fprintf(stderr,
               "s2c2-cuda-adapter func=%s sched=%s map=%s device=%s "
               "score3_total=%d\n",
               p.func, kSched, kMap, kDevice, p.score3Total);
}

static void printMaps() {
  std::fprintf(stderr, "s2c2-cuda-adapter map stor.pack=host_pinned\n");
  std::fprintf(stderr, "s2c2-cuda-adapter map comm.stream=cudaMemcpyAsync\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter map sched.wait=cudaEventSynchronize\n");
  std::fprintf(stderr, "s2c2-cuda-adapter map sched.concurrent=two_streams\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter map sched.pipeline=stage_order_events\n");
  std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
}

static const s2c2::cuda_adapter::PilotBind *findPilot(const char *name) {
  for (int i = 0; i < kPilotCount; ++i) {
    if (std::strcmp(name, kPilots[i].id) == 0 ||
        std::strcmp(name, kPilots[i].func) == 0)
      return &kPilots[i];
  }
  return nullptr;
}

static void printMatched() {
  std::fprintf(stderr,
               "s2c2-cuda-adapter matched=seq remaining=1xHtoD+kxSiLU\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter matched=ovl remaining=1xHtoD+kxSiLU\n");
  std::fprintf(stderr, "s2c2-cuda-adapter matched=copy remaining=1xHtoD\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter matched=compute remaining=kxSiLU\n");
  std::fprintf(stderr, "s2c2-cuda-adapter matched score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-cuda-adapter matched cost=unchanged\n");
}

static void printPhase() {
  std::fprintf(stderr,
               "s2c2-cuda-adapter phase=seq remaining=1xHtoD+kxSiLU\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter phase=ovl remaining=1xHtoD+kxSiLU\n");
  std::fprintf(stderr, "s2c2-cuda-adapter phase=copy remaining=1xHtoD\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter phase=compute remaining=kxSiLU\n");
  std::fprintf(stderr, "s2c2-cuda-adapter phase axis=r=T_compute/T_copy\n");
  std::fprintf(stderr, "s2c2-cuda-adapter phase axis=size=N\n");
  std::fprintf(stderr, "s2c2-cuda-adapter phase pair=C||HtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter phase score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-cuda-adapter phase cost=unchanged\n");
}

static void printPipe() {
  std::fprintf(stderr, "s2c2-cuda-adapter pipe=d1 remaining=8tile-seq\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe=d2 remaining=8tile-double\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe=d3 remaining=8tile-triple\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe=d4 remaining=8tile-quad\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe=copy remaining=1tile-HtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe=compute remaining=1tile-SiLU\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe pair=C||HtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe tiles=8\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe cost=unchanged\n");
}

static void printPipeTiles() {
  std::fprintf(stderr, "s2c2-cuda-adapter pipe-tiles=4 remaining=C||HtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe-tiles=8 remaining=C||HtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe-tiles=16 remaining=C||HtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe-tiles=32 remaining=C||HtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe-tiles pair=C||HtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe-tiles depths=1,2,3,4\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe-tiles set=4,8,16,32\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe-tiles score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-cuda-adapter pipe-tiles cost=unchanged\n");
}

static void printCap() {
  std::fprintf(stderr, "s2c2-cuda-adapter cap=htod remaining=1xHtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap=dtoh remaining=1xDtoH\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap=htod-dtoh-seq remaining=HtoD->DtoH\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap=htod-dtoh-event remaining=HtoD->event->DtoH\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap=htod-dtoh-par remaining=HtoD||DtoH\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap=htod-htod-par remaining=HtoD||HtoD\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap=dtoh-dtoh-par remaining=DtoH||DtoH\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap=compute remaining=kxSiLU\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap=compute-htod remaining=kxSiLU||HtoD\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap=compute-dtoh remaining=kxSiLU||DtoH\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap=compute-compute remaining=kxSiLU||kxSiLU\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap=event-sync remaining=event\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap=stream-sync remaining=stream\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap=device-sync remaining=device\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap=reduction remaining=grid-reduce\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap=matmul remaining=tiled-gemm\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap cost=unchanged\n");
}

static void printCudaValMem() {
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-mem=v2\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-mem map stor.host=pinned|pageable\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-mem map stor.pinned=cudaHostAlloc\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-mem map stor.pageable=malloc\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-mem map comm.copy=cudaMemcpyAsync\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-mem map "
               "sched.concurrent=named-nonblocking-streams\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-mem cell host-pinned\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-mem cell host-pageable\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-mem cell extra-hb=pageable-host\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-mem pair=C||HtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-mem pair=C||DtoH\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-mem acceptance=storage-comm\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-mem score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-mem cost=unchanged\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-mem semantics=unchanged\n");
}

static void printSsdMlpWallclock() {
  std::fprintf(stderr, "s2c2-cuda-adapter ssd-mlp-wallclock=1\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter ssd-mlp-wallclock program-measurement=yes\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter ssd-mlp-wallclock note not-stage-ab\n");
  std::fprintf(stderr, "s2c2-cuda-adapter ssd-mlp-wallclock t-base=t-seq\n");
  std::fprintf(stderr, "s2c2-cuda-adapter ssd-mlp-wallclock t-opt=t-evi\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter ssd-mlp-wallclock n-htod=22528000\n");
  std::fprintf(stderr, "s2c2-cuda-adapter ssd-mlp-wallclock n-cc=33554432\n");
  std::fprintf(stderr, "s2c2-cuda-adapter ssd-mlp-wallclock k_ref=32\n");
  std::fprintf(stderr, "s2c2-cuda-adapter ssd-mlp-wallclock ab=seq-vs-evi\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter ssd-mlp-wallclock "
               "evi=keep-C||HtoD,serialize-licensed-C||C\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter ssd-mlp-wallclock note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter ssd-mlp-wallclock note logical-ssd-ne-disk\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter ssd-mlp-wallclock note 32M-outlier-not-cost\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter ssd-mlp-wallclock note not-cost-v04\n");
  std::fprintf(stderr, "s2c2-cuda-adapter ssd-mlp-wallclock cost=unchanged\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter ssd-mlp-wallclock semantics=unchanged\n");
  std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
}

static void printCudaValCc() {
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-cc=p0\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-cc map C_light=kxSiLU\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-cc map C_heavy=mxGEMM\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-cc map dim=1024\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-cc map "
               "sched.concurrent=named-nonblocking-streams\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-cc cell same-kind=SiLU||SiLU\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-cc cell mixed-kind=SiLU||GEMM\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-cc cell "
               "pair-relation=serial|parallel|mixed\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-cc cell "
               "observed-constraint=none|resource_contention\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-cc cell extra-hb=not-applicable\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-cc note no-overlap-not-hb\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-cc pair=C_light||C_heavy\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-cc acceptance=compute-resource\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-cc score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-cc cost=unchanged\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-cc semantics=unchanged\n");
}


static void printCapSchema() {
  std::fprintf(stderr, "s2c2-cuda-adapter cap-schema=v1\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema field=compute_domain\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema field=transfer_domain\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap-schema field=direction\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema field=source_memory_class\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema field=destination_memory_class\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema field=pair_relation\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap-schema field=size_range\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap-schema field=regime\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema field=synchronization\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema field=pipeline_depth_evidence\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema field=observed_constraint\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap-schema field=confidence\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap-schema hardware=unfilled\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema pair_relation="
               "parallel|serial|mixed|underdetermined\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema observed_constraint="
               "none|legacy_default|resource_contention|"
               "allocator_sync|copy_engine_contention\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cap-schema depth-star=not-a-law\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap-schema score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap-schema cost=unchanged\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cap-schema semantics=unchanged\n");
}

static void printCudaValAsync() {
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-async=v2p1\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-async map "
               "stor.materialize=cudaMallocAsync\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-async map "
               "stor.release=cudaFreeAsync\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-async map "
               "sched.wait=cudaStreamWaitEvent\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-async map "
               "task-event=cudaEventRecord\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-async chain "
               "materialize->write->event->wait->read->release\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-async cell alloc-sync\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-async cell alloc-async\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-async cell "
               "observed-constraint=none|allocator_sync\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-async cell extra-hb=not-applicable\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val-async note legal-wait-not-extra-hb\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-async score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-async cost=unchanged\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val-async semantics=unchanged\n");
}

static void printCudaVal() {
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val=v1\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val map stor.materialize=cudaMalloc\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val map stor.transfer=cudaMemcpyAsync\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val map comm.copy=cudaMemcpyAsync\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val map sched.wait=cudaStreamWaitEvent\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val map "
               "sched.concurrent=named-nonblocking-streams\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val map sched.pipeline=chained-events\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val map task-event=cudaEventRecord\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val cell stream-named\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val cell stream-default\n");
  std::fprintf(stderr,
               "s2c2-cuda-adapter cuda-val cell extra-hb=legacy-default\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val pair=C||HtoD\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val acceptance=HB-subset\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val score3=not-applicable\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val cost=unchanged\n");
  std::fprintf(stderr, "s2c2-cuda-adapter cuda-val semantics=unchanged\n");
}

int main(int argc, char **argv) {
  bool dryRun = false;
  bool matched = false;
  bool cap = false;
  bool phase = false;
  bool pipe = false;
  bool pipeTiles = false;
  bool cudaVal = false;
  bool cudaValMem = false;
  bool cudaValCc = false;
  bool cudaValAsync = false;
  bool capSchema = false;
  bool ssdMlp = false;
  const char *func = nullptr;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--dry-run") {
      dryRun = true;
    } else if (a == "--matched") {
      matched = true;
    } else if (a == "--cap") {
      cap = true;
    } else if (a == "--phase") {
      phase = true;
    } else if (a == "--pipe") {
      pipe = true;
    } else if (a == "--pipe-tiles") {
      pipeTiles = true;
    } else if (a == "--cuda-val-async") {
      cudaValAsync = true;
    } else if (a == "--cuda-val-cc") {
      cudaValCc = true;
    } else if (a == "--cuda-val-mem") {
      cudaValMem = true;
    } else if (a == "--cuda-val") {
      cudaVal = true;
    } else if (a == "--cap-schema") {
      capSchema = true;
    } else if (a == "--ssd-mlp-wallclock") {
      ssdMlp = true;
    } else if (a.rfind("--func=", 0) == 0) {
      func = argv[i] + 7;
    } else if (a == "--help" || a == "-h") {
      std::fprintf(stderr,
                   "s2c2-cuda-adapter --dry-run [--func=<id|name>] "
                   "[--matched] [--cap] [--phase] [--pipe] [--pipe-tiles] "
                   "[--cuda-val] [--cuda-val-mem] [--cuda-val-cc] "
                   "[--cuda-val-async] [--cap-schema] [--ssd-mlp-wallclock]\n"
                   "Host protocol only. Timed CUDA: runtime/cuda/\n");
      return 0;
    } else {
      std::fprintf(stderr, "s2c2-cuda-adapter: unknown arg %s\n", argv[i]);
      return 1;
    }
  }

  if (!dryRun) {
    std::fprintf(stderr,
                 "s2c2-cuda-adapter: this host tool is --dry-run only; "
                 "build runtime/cuda/s2c2_cuda_adapter.cu for timing\n");
    return 1;
  }

  std::fprintf(stderr, "s2c2-cuda-adapter dry-run=1\n");
  int modes = (int)matched + (int)cap + (int)phase + (int)pipe +
              (int)pipeTiles + (int)cudaVal + (int)cudaValMem +
              (int)cudaValCc + (int)cudaValAsync + (int)capSchema +
              (int)ssdMlp;
  if (modes > 1) {
    std::fprintf(stderr,
                 "s2c2-cuda-adapter: --cap-schema/--cuda-val-async/--cuda-val-cc/"
                 "--cuda-val-mem/--cuda-val/--pipe-tiles/--pipe/--phase/--cap/"
                 "--matched/--ssd-mlp-wallclock cannot combine\n");
    return 1;
  }
  if (matched) {
    printMatched();
    printMaps();
    return 0;
  }
  if (cap) {
    printCap();
    printMaps();
    return 0;
  }
  if (phase) {
    printPhase();
    printMaps();
    return 0;
  }
  if (pipe) {
    printPipe();
    printMaps();
    return 0;
  }
  if (pipeTiles) {
    printPipeTiles();
    printMaps();
    return 0;
  }
  if (cudaVal) {
    printCudaVal();
    printMaps();
    return 0;
  }
  if (cudaValMem) {
    printCudaValMem();
    printMaps();
    return 0;
  }
  if (cudaValCc) {
    printCudaValCc();
    printMaps();
    return 0;
  }
  if (cudaValAsync) {
    printCudaValAsync();
    printMaps();
    return 0;
  }
  if (capSchema) {
    printCapSchema();
    printMaps();
    return 0;
  }
  if (ssdMlp) {
    printSsdMlpWallclock();
    printMaps();
    return 0;
  }
  if (func) {
    const auto *p = findPilot(func);
    if (!p) {
      std::fprintf(stderr, "s2c2-cuda-adapter: unknown func %s\n", func);
      return 1;
    }
    printBind(*p);
  } else {
    for (int i = 0; i < kPilotCount; ++i)
      printBind(kPilots[i]);
  }
  printMaps();
  return 0;
}
