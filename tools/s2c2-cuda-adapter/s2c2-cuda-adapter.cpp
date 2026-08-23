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

int main(int argc, char **argv) {
  bool dryRun = false;
  bool matched = false;
  const char *func = nullptr;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--dry-run") {
      dryRun = true;
    } else if (a == "--matched") {
      matched = true;
    } else if (a.rfind("--func=", 0) == 0) {
      func = argv[i] + 7;
    } else if (a == "--help" || a == "-h") {
      std::fprintf(stderr,
                   "s2c2-cuda-adapter --dry-run [--func=<id|name>] [--matched]\n"
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
  if (matched) {
    printMatched();
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
