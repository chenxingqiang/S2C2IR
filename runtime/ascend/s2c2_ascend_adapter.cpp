//===- s2c2_ascend_adapter.cpp - AscendCL capability harness ----*- C++ -*-===//
//
// Times three S²C² pairs on Ascend 910B. Not a compiler backend. Not Cost.
// Workload semantic = elemwise / host_to_device / device_to_host.
// T_pair = host wall-clock over completion(s0, s1).
//
//   source $ASCEND_TOOLKIT_HOME/bin/setenv.bash
//   g++ -O2 -std=c++17 runtime/ascend/s2c2_ascend_adapter.cpp \
//       -I$ASCEND_TOOLKIT_HOME/include -L$ASCEND_TOOLKIT_HOME/lib64 \
//       -lascendcl -lnnopbase -lopapi -o s2c2-ascend-run
//
//===----------------------------------------------------------------------===//

#include "AdapterContract.h"

#include "acl/acl.h"
#include "aclnnop/aclnn_add.h"
#include "aclnnop/aclnn_mul.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

using s2c2::ascend_adapter::classifyPair;
using s2c2::ascend_adapter::inferConstraint;
using s2c2::ascend_adapter::kHardwareId;
using s2c2::ascend_adapter::kMap;
using s2c2::ascend_adapter::kSched;
using s2c2::ascend_adapter::kSync;

#define ACL_OK(expr)                                                           \
  do {                                                                         \
    aclError _e = (expr);                                                      \
    if (_e != ACL_SUCCESS) {                                                   \
      std::fprintf(stderr, "s2c2-ascend-run: ACL %d at %s:%d\n", (int)_e,      \
                   __FILE__, __LINE__);                                        \
      std::exit(1);                                                            \
    }                                                                          \
  } while (0)

#define ACLNN_OK(expr)                                                         \
  do {                                                                         \
    aclnnStatus _e = (expr);                                                   \
    if (_e != ACL_SUCCESS) {                                                   \
      std::fprintf(stderr, "s2c2-ascend-run: aclnn %d at %s:%d\n", (int)_e,    \
                   __FILE__, __LINE__);                                        \
      std::exit(1);                                                            \
    }                                                                          \
  } while (0)

static float hostElemwise(float x, int k) {
  float v = x;
  for (int t = 0; t < k; ++t)
    v = v * 2.f + 1.f;
  return v;
}

static void fillHost(float *p, int n, int seed) {
  for (int i = 0; i < n; ++i)
    p[i] = 0.001f * static_cast<float>(((i + seed) % 1000) + 1);
}

enum class Arm { Compute, HtoD, DtoH, ComputeHtoD, ComputeCompute, HtoDDtoH };

static const char *armName(Arm a) {
  switch (a) {
  case Arm::Compute:
    return "compute";
  case Arm::HtoD:
    return "htod";
  case Arm::DtoH:
    return "dtoh";
  case Arm::ComputeHtoD:
    return "compute-htod";
  case Arm::ComputeCompute:
    return "compute-compute";
  case Arm::HtoDDtoH:
    return "htod-dtoh";
  }
  return "off";
}

struct Buf {
  float *host0 = nullptr;
  float *host1 = nullptr;
  float *hostPage = nullptr;
  float *check = nullptr;
  void *dev0 = nullptr;
  void *dev1 = nullptr;
  void *dev2 = nullptr;
  void *dev3 = nullptr;
  void *workspace0 = nullptr;
  void *workspace1 = nullptr;
  uint64_t workspaceCap0 = 0;
  uint64_t workspaceCap1 = 0;
  std::vector<void *> staleWorkspace;
  int n = 0;
  aclrtStream s0 = nullptr;
  aclrtStream s1 = nullptr;

  void alloc(int n_, bool withPageable = false) {
    n = n_;
    size_t bytes = sizeof(float) * static_cast<size_t>(n);
    ACL_OK(aclrtMallocHost(reinterpret_cast<void **>(&host0), bytes));
    ACL_OK(aclrtMallocHost(reinterpret_cast<void **>(&host1), bytes));
    ACL_OK(aclrtMallocHost(reinterpret_cast<void **>(&check), bytes));
    ACL_OK(aclrtMalloc(&dev0, bytes, ACL_MEM_MALLOC_HUGE_FIRST));
    ACL_OK(aclrtMalloc(&dev1, bytes, ACL_MEM_MALLOC_HUGE_FIRST));
    ACL_OK(aclrtMalloc(&dev2, bytes, ACL_MEM_MALLOC_HUGE_FIRST));
    ACL_OK(aclrtMalloc(&dev3, bytes, ACL_MEM_MALLOC_HUGE_FIRST));
    ACL_OK(aclrtCreateStream(&s0));
    ACL_OK(aclrtCreateStream(&s1));
    fillHost(host0, n, 1);
    fillHost(host1, n, 2);
    if (withPageable) {
      hostPage = static_cast<float *>(std::malloc(bytes));
      if (!hostPage) {
        std::fprintf(stderr, "s2c2-ascend-run: pageable malloc failed\n");
        std::exit(1);
      }
      fillHost(hostPage, n, 3);
    }
  }

  int streamSlot(aclrtStream s) const { return s == s0 ? 0 : 1; }

  void *workspaceFor(aclrtStream s) const {
    return streamSlot(s) == 0 ? workspace0 : workspace1;
  }

  void ensureWorkspace(uint64_t bytes, aclrtStream s) {
    void **ws = streamSlot(s) == 0 ? &workspace0 : &workspace1;
    uint64_t *cap = streamSlot(s) == 0 ? &workspaceCap0 : &workspaceCap1;
    if (bytes <= *cap)
      return;
    // Keep the old buffer until the stream that still holds it completes.
    if (*ws)
      staleWorkspace.push_back(*ws);
    *ws = nullptr;
    if (bytes == 0)
      return;
    ACL_OK(aclrtMalloc(ws, bytes, ACL_MEM_MALLOC_HUGE_FIRST));
    *cap = bytes;
  }

  void reapStaleWorkspace() {
    for (void *p : staleWorkspace)
      aclrtFree(p);
    staleWorkspace.clear();
  }

  void freeAll() {
    if (s1)
      aclrtDestroyStream(s1);
    if (s0)
      aclrtDestroyStream(s0);
    if (workspace1)
      aclrtFree(workspace1);
    if (workspace0)
      aclrtFree(workspace0);
    reapStaleWorkspace();
    aclrtFree(dev3);
    aclrtFree(dev2);
    aclrtFree(dev1);
    aclrtFree(dev0);
    aclrtFreeHost(check);
    aclrtFreeHost(host1);
    aclrtFreeHost(host0);
    if (hostPage)
      std::free(hostPage);
  }

  size_t bytes() const { return sizeof(float) * static_cast<size_t>(n); }
};

static aclTensor *makeTensor(void *data, int n) {
  int64_t dims[1] = {n};
  int64_t stride[1] = {1};
  aclTensor *t = aclCreateTensor(dims, 1, ACL_FLOAT, stride, 0, ACL_FORMAT_ND,
                                 dims, 1, data);
  if (!t) {
    std::fprintf(stderr, "s2c2-ascend-run: aclCreateTensor failed\n");
    std::exit(1);
  }
  return t;
}

static void elemwiseLaunch(Buf &b, void *x, void *y, int k, aclrtStream s) {
  float two = 2.f;
  float one = 1.f;
  aclScalar *sTwo = aclCreateScalar(&two, ACL_FLOAT);
  aclScalar *sOne = aclCreateScalar(&one, ACL_FLOAT);
  if (!sTwo || !sOne) {
    std::fprintf(stderr, "s2c2-ascend-run: aclCreateScalar failed\n");
    std::exit(1);
  }
  void *src = x;
  for (int t = 0; t < k; ++t) {
    aclTensor *in = makeTensor(src, b.n);
    aclTensor *out = makeTensor(y, b.n);
    uint64_t ws = 0;
    aclOpExecutor *exec = nullptr;
    ACLNN_OK(aclnnMulsGetWorkspaceSize(in, sTwo, out, &ws, &exec));
    b.ensureWorkspace(ws, s);
    ACLNN_OK(aclnnMuls(b.workspaceFor(s), ws, exec, s));
    aclDestroyTensor(in);
    aclDestroyTensor(out);
    in = makeTensor(y, b.n);
    out = makeTensor(y, b.n);
    ws = 0;
    exec = nullptr;
    ACLNN_OK(aclnnAddsGetWorkspaceSize(in, sOne, sOne, out, &ws, &exec));
    b.ensureWorkspace(ws, s);
    ACLNN_OK(aclnnAdds(b.workspaceFor(s), ws, exec, s));
    aclDestroyTensor(in);
    aclDestroyTensor(out);
    src = y;
  }
  aclDestroyScalar(sTwo);
  aclDestroyScalar(sOne);
}

static void provision(Buf &b, Arm arm) {
  size_t bytes = b.bytes();
  if (arm == Arm::HtoD)
    return;
  ACL_OK(aclrtMemcpyAsync(b.dev0, bytes, b.host0, bytes,
                          ACL_MEMCPY_HOST_TO_DEVICE, b.s0));
  ACL_OK(aclrtMemcpyAsync(b.dev1, bytes, b.host1, bytes,
                          ACL_MEMCPY_HOST_TO_DEVICE, b.s0));
  ACL_OK(aclrtSynchronizeStream(b.s0));
}

// Launch only. Completion is timeArm's aclrtSynchronizeStream on s0 and s1.
static void runArm(Buf &b, Arm arm, int k) {
  size_t bytes = b.bytes();
  switch (arm) {
  case Arm::Compute:
    elemwiseLaunch(b, b.dev0, b.dev2, k, b.s0);
    break;
  case Arm::HtoD:
    ACL_OK(aclrtMemcpyAsync(b.dev0, bytes, b.host0, bytes,
                            ACL_MEMCPY_HOST_TO_DEVICE, b.s0));
    break;
  case Arm::DtoH:
    ACL_OK(aclrtMemcpyAsync(b.host1, bytes, b.dev0, bytes,
                            ACL_MEMCPY_DEVICE_TO_HOST, b.s0));
    break;
  case Arm::ComputeHtoD:
    elemwiseLaunch(b, b.dev1, b.dev2, k, b.s0);
    ACL_OK(aclrtMemcpyAsync(b.dev0, bytes, b.host0, bytes,
                            ACL_MEMCPY_HOST_TO_DEVICE, b.s1));
    break;
  case Arm::ComputeCompute:
    elemwiseLaunch(b, b.dev0, b.dev2, k, b.s0);
    elemwiseLaunch(b, b.dev1, b.dev3, k, b.s1);
    break;
  case Arm::HtoDDtoH:
    ACL_OK(aclrtMemcpyAsync(b.dev0, bytes, b.host0, bytes,
                            ACL_MEMCPY_HOST_TO_DEVICE, b.s0));
    ACL_OK(aclrtMemcpyAsync(b.host1, bytes, b.dev1, bytes,
                            ACL_MEMCPY_DEVICE_TO_HOST, b.s1));
    break;
  }
}

static bool closeEnough(float a, float b) {
  float d = std::fabs(a - b);
  return d <= 1e-3f * (1.f + std::fabs(b));
}

static bool checkArm(Buf &b, Arm arm, int k) {
  size_t bytes = b.bytes();
  switch (arm) {
  case Arm::Compute:
    ACL_OK(
        aclrtMemcpy(b.check, bytes, b.dev2, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], hostElemwise(b.host0[i], k)))
        return false;
    }
    return true;
  case Arm::HtoD:
    ACL_OK(
        aclrtMemcpy(b.check, bytes, b.dev0, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], b.host0[i]))
        return false;
    }
    return true;
  case Arm::DtoH:
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.host1[i], b.host0[i]))
        return false;
    }
    return true;
  case Arm::ComputeHtoD:
    ACL_OK(
        aclrtMemcpy(b.check, bytes, b.dev2, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], hostElemwise(b.host1[i], k)))
        return false;
    }
    ACL_OK(
        aclrtMemcpy(b.check, bytes, b.dev0, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], b.host0[i]))
        return false;
    }
    return true;
  case Arm::ComputeCompute:
    ACL_OK(
        aclrtMemcpy(b.check, bytes, b.dev2, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], hostElemwise(b.host0[i], k)))
        return false;
    }
    ACL_OK(
        aclrtMemcpy(b.check, bytes, b.dev3, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], hostElemwise(b.host1[i], k)))
        return false;
    }
    return true;
  case Arm::HtoDDtoH:
    ACL_OK(
        aclrtMemcpy(b.check, bytes, b.dev0, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], b.host0[i]))
        return false;
    }
    ACL_OK(
        aclrtMemcpy(b.check, bytes, b.dev1, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.host1[i], b.check[i]))
        return false;
    }
    return true;
  }
  return false;
}

static double medianUs(std::vector<double> &s) {
  std::sort(s.begin(), s.end());
  return s[s.size() / 2];
}

// T_pair = host wall-clock over launch + completion(s0, s1).
// Do not use an event recorded on the default stream as the pair timer.
static double timeArm(Buf &b, Arm arm, int warmup, int reps, int k) {
  auto body = [&]() { runArm(b, arm, k); };
  for (int i = 0; i < warmup; ++i) {
    fillHost(b.host0, b.n, i + 3);
    fillHost(b.host1, b.n, i + 7);
    provision(b, arm);
    body();
    ACL_OK(aclrtSynchronizeStream(b.s0));
    ACL_OK(aclrtSynchronizeStream(b.s1));
    b.reapStaleWorkspace();
  }
  std::vector<double> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    fillHost(b.host0, b.n, i + 11);
    fillHost(b.host1, b.n, i + 19);
    provision(b, arm);
    ACL_OK(aclrtSynchronizeStream(b.s0));
    ACL_OK(aclrtSynchronizeStream(b.s1));
    auto start = std::chrono::steady_clock::now();
    body();
    ACL_OK(aclrtSynchronizeStream(b.s0));
    ACL_OK(aclrtSynchronizeStream(b.s1));
    auto stop = std::chrono::steady_clock::now();
    b.reapStaleWorkspace();
    samples.push_back(
        std::chrono::duration<double, std::micro>(stop - start).count());
    if (!checkArm(b, arm, k)) {
      std::fprintf(stderr, "s2c2-ascend-run correctness=0 arm=%s\n",
                   armName(arm));
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static void printRecord(const char *pair, const char *relation,
                        const char *constraint, const char *sizeRange) {
  const char *compute = "none";
  const char *transfer = "none";
  const char *direction = "none";
  const char *src = "none";
  const char *dst = "none";
  const char *regime = "underdetermined";
  if (std::strcmp(pair, "C||HtoD") == 0) {
    compute = "ascend_ai_core";
    transfer = "copy_engine";
    direction = "host_to_device";
    src = "pinned_host";
    dst = "device_memory";
    regime = "bandwidth";
  } else if (std::strcmp(pair, "C||C") == 0) {
    compute = "ascend_ai_core";
    src = "device_memory";
    dst = "device_memory";
    regime = "occupancy";
  } else if (std::strcmp(pair, "HtoD||DtoH") == 0) {
    transfer = "copy_engine";
    direction = "host_to_device";
    src = "pinned_host";
    dst = "device_memory";
    regime = "bandwidth";
  }
  std::fprintf(stderr,
               "{\"schema_version\":\"1\",\"record_kind\":\"pair\","
               "\"hardware_id\":\"%s\",\"compute_domain\":\"%s\","
               "\"transfer_domain\":\"%s\",\"direction\":\"%s\","
               "\"source_memory_class\":\"%s\","
               "\"destination_memory_class\":\"%s\",\"pair\":\"%s\","
               "\"pair_relation\":\"%s\",\"regime\":\"%s\","
               "\"size_range\":\"%s\",\"synchronization\":\"%s\","
               "\"pipeline_depth_evidence\":\"n/a\","
               "\"observed_constraint\":\"%s\",\"confidence\":\"measured\","
               "\"note\":\"Ascend 910B pair measurement; topology only\","
               "\"evidence_refs\":\"backend-adapter-ascend.md,v3-dataset/ascend910b\","
               "\"v3\":\"not-claimed\",\"cost\":\"unchanged\","
               "\"semantics\":\"unchanged\"}\n",
               kHardwareId, compute, transfer, direction, src, dst, pair,
               relation, regime, sizeRange, kSync, constraint);
}

enum class MemKind { HtoD, DtoH, Compute, OvlHtoD, OvlDtoH };
enum class MemRes { Pinned, Pageable, Device };

static const char *memCase(MemKind kind, MemRes res) {
  if (kind == MemKind::Compute)
    return "compute";
  if (kind == MemKind::HtoD)
    return res == MemRes::Pinned ? "htod-pinned" : "htod-pageable";
  if (kind == MemKind::DtoH)
    return res == MemRes::Pinned ? "dtoh-pinned" : "dtoh-pageable";
  if (kind == MemKind::OvlHtoD)
    return res == MemRes::Pinned ? "ovl-htod-pin" : "ovl-htod-page";
  return res == MemRes::Pinned ? "ovl-dtoh-pin" : "ovl-dtoh-page";
}

static float *memHost(Buf &b, MemRes res) {
  return res == MemRes::Pageable ? b.hostPage : b.host0;
}

static void runMem(Buf &b, MemKind kind, MemRes res, int k) {
  size_t bytes = b.bytes();
  float *h = memHost(b, res == MemRes::Device ? MemRes::Pinned : res);
  switch (kind) {
  case MemKind::HtoD:
    ACL_OK(aclrtMemcpyAsync(b.dev0, bytes, h, bytes, ACL_MEMCPY_HOST_TO_DEVICE,
                            b.s0));
    break;
  case MemKind::DtoH:
    ACL_OK(aclrtMemcpyAsync(h, bytes, b.dev0, bytes, ACL_MEMCPY_DEVICE_TO_HOST,
                            b.s0));
    break;
  case MemKind::Compute:
    elemwiseLaunch(b, b.dev1, b.dev2, k, b.s0);
    break;
  case MemKind::OvlHtoD:
    elemwiseLaunch(b, b.dev1, b.dev2, k, b.s0);
    ACL_OK(aclrtMemcpyAsync(b.dev0, bytes, h, bytes, ACL_MEMCPY_HOST_TO_DEVICE,
                            b.s1));
    break;
  case MemKind::OvlDtoH:
    elemwiseLaunch(b, b.dev1, b.dev2, k, b.s0);
    ACL_OK(aclrtMemcpyAsync(h, bytes, b.dev0, bytes, ACL_MEMCPY_DEVICE_TO_HOST,
                            b.s1));
    break;
  }
}

static bool checkMem(Buf &b, MemKind kind, MemRes res, int k) {
  size_t bytes = b.bytes();
  float *h = memHost(b, res == MemRes::Device ? MemRes::Pinned : res);
  if (kind == MemKind::HtoD || kind == MemKind::OvlHtoD) {
    ACL_OK(aclrtMemcpy(b.check, bytes, b.dev0, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], h[i]))
        return false;
    }
  }
  if (kind == MemKind::DtoH || kind == MemKind::OvlDtoH) {
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(h[i], b.host1[i]))
        return false;
    }
  }
  if (kind == MemKind::Compute || kind == MemKind::OvlHtoD ||
      kind == MemKind::OvlDtoH) {
    ACL_OK(aclrtMemcpy(b.check, bytes, b.dev2, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], hostElemwise(b.host1[i], k)))
        return false;
    }
  }
  return true;
}

static void provisionMem(Buf &b, MemKind kind, MemRes res) {
  size_t bytes = b.bytes();
  if (kind == MemKind::HtoD)
    return;
  // Device compute src from pinned host1; DtoH src from host1 into dest0.
  ACL_OK(aclrtMemcpyAsync(b.dev1, bytes, b.host1, bytes,
                          ACL_MEMCPY_HOST_TO_DEVICE, b.s0));
  if (kind != MemKind::Compute)
    ACL_OK(aclrtMemcpyAsync(b.dev0, bytes, b.host1, bytes,
                            ACL_MEMCPY_HOST_TO_DEVICE, b.s0));
  ACL_OK(aclrtSynchronizeStream(b.s0));
  (void)res;
}

static double timeMem(Buf &b, MemKind kind, MemRes res, int warmup, int reps,
                      int k) {
  auto body = [&]() { runMem(b, kind, res, k); };
  for (int i = 0; i < warmup; ++i) {
    fillHost(b.host0, b.n, i + 3);
    fillHost(b.host1, b.n, i + 7);
    if (b.hostPage)
      fillHost(b.hostPage, b.n, i + 11);
    provisionMem(b, kind, res);
    if (kind == MemKind::DtoH || kind == MemKind::OvlDtoH)
      fillHost(memHost(b, res), b.n, 7919);
    body();
    ACL_OK(aclrtSynchronizeStream(b.s0));
    ACL_OK(aclrtSynchronizeStream(b.s1));
    b.reapStaleWorkspace();
  }
  std::vector<double> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    fillHost(b.host0, b.n, i + 13);
    fillHost(b.host1, b.n, i + 17);
    if (b.hostPage)
      fillHost(b.hostPage, b.n, i + 19);
    provisionMem(b, kind, res);
    if (kind == MemKind::DtoH || kind == MemKind::OvlDtoH)
      fillHost(memHost(b, res), b.n, 7919);
    ACL_OK(aclrtSynchronizeStream(b.s0));
    ACL_OK(aclrtSynchronizeStream(b.s1));
    auto start = std::chrono::steady_clock::now();
    body();
    ACL_OK(aclrtSynchronizeStream(b.s0));
    ACL_OK(aclrtSynchronizeStream(b.s1));
    auto stop = std::chrono::steady_clock::now();
    b.reapStaleWorkspace();
    samples.push_back(
        std::chrono::duration<double, std::micro>(stop - start).count());
    if (!checkMem(b, kind, res, k)) {
      std::fprintf(stderr, "s2c2-ascend-run correctness=0 mem=%s\n",
                   memCase(kind, res));
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static void printMemSlice(const char *pair, const char *res, double copyUs,
                          double computeUs, double ovlUs, int n, int k) {
  double mx = copyUs > computeUs ? copyUs : computeUs;
  double sum = copyUs + computeUs;
  double pmax = mx > 0 ? ovlUs / mx : 0;
  double psum = sum > 0 ? ovlUs / sum : 0;
  const char *rel = classifyPair(pmax, psum);
  const char *extra = "none";
  if (std::strcmp(res, "pageable") == 0 && rel[0] == 's')
    extra = "pageable-host";
  std::fprintf(stderr,
               "s2c2-ascend-run mem slice pair=%s residency=%s "
               "pair_relation=%s extra_hb=%s ovl_over_max=%.3f "
               "ovl_over_sum=%.3f n=%d k=%d\n",
               pair, res, rel, extra, pmax, psum, n, k);
  std::fprintf(stderr,
               "s2c2-ascend-run mem timing pair=%s residency=%s copy=%.1f "
               "compute=%.1f ovl=%.1f\n",
               pair, res, copyUs, computeUs, ovlUs);
}

static int runMemP0(int n, int kReq, int warmup, int reps) {
  Buf b;
  b.alloc(n, true);
  fillHost(b.host0, b.n, 1);
  fillHost(b.host1, b.n, 2);
  fillHost(b.hostPage, b.n, 3);
  provisionMem(b, MemKind::Compute, MemRes::Pinned);
  elemwiseLaunch(b, b.dev1, b.dev2, 1, b.s0);
  elemwiseLaunch(b, b.dev1, b.dev2, 1, b.s1);
  ACL_OK(aclrtSynchronizeStream(b.s0));
  ACL_OK(aclrtSynchronizeStream(b.s1));
  b.reapStaleWorkspace();

  int k = kReq;
  if (k <= 0) {
    double tCopy = timeMem(b, MemKind::HtoD, MemRes::Pinned, warmup, reps, 1);
    double tC1 = timeMem(b, MemKind::Compute, MemRes::Device, warmup, reps, 1);
    k = tC1 > 0 ? static_cast<int>(std::llround(tCopy / tC1)) : 1;
    if (k < 1)
      k = 1;
    std::fprintf(stderr, "s2c2-ascend-run mem calibrate n=%d k=%d\n", n, k);
  }

  double tHPin = timeMem(b, MemKind::HtoD, MemRes::Pinned, warmup, reps, k);
  double tHPage = timeMem(b, MemKind::HtoD, MemRes::Pageable, warmup, reps, k);
  double tDPin = timeMem(b, MemKind::DtoH, MemRes::Pinned, warmup, reps, k);
  double tDPage = timeMem(b, MemKind::DtoH, MemRes::Pageable, warmup, reps, k);
  double tC = timeMem(b, MemKind::Compute, MemRes::Device, warmup, reps, k);
  double tOvlHPin =
      timeMem(b, MemKind::OvlHtoD, MemRes::Pinned, warmup, reps, k);
  double tOvlHPage =
      timeMem(b, MemKind::OvlHtoD, MemRes::Pageable, warmup, reps, k);
  double tOvlDPin =
      timeMem(b, MemKind::OvlDtoH, MemRes::Pinned, warmup, reps, k);
  double tOvlDPage =
      timeMem(b, MemKind::OvlDtoH, MemRes::Pageable, warmup, reps, k);
  b.freeAll();

  std::fprintf(stderr, "s2c2-ascend-run mem=r4 correctness=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-run mem case=htod-pinned n=%d k=%d us=%.1f\n", n, k,
               tHPin);
  std::fprintf(stderr,
               "s2c2-ascend-run mem case=htod-pageable n=%d k=%d us=%.1f\n", n,
               k, tHPage);
  std::fprintf(stderr,
               "s2c2-ascend-run mem case=dtoh-pinned n=%d k=%d us=%.1f\n", n, k,
               tDPin);
  std::fprintf(stderr,
               "s2c2-ascend-run mem case=dtoh-pageable n=%d k=%d us=%.1f\n", n,
               k, tDPage);
  std::fprintf(stderr, "s2c2-ascend-run mem case=compute n=%d k=%d us=%.1f\n",
               n, k, tC);
  printMemSlice("C||HtoD", "pinned", tHPin, tC, tOvlHPin, n, k);
  printMemSlice("C||HtoD", "pageable", tHPage, tC, tOvlHPage, n, k);
  printMemSlice("C||DtoH", "pinned", tDPin, tC, tOvlDPin, n, k);
  printMemSlice("C||DtoH", "pageable", tDPage, tC, tOvlDPage, n, k);
  std::fprintf(stderr,
               "s2c2-ascend-run mem acceptance=storage-comm extra-hb="
               "pageable-host cost=unchanged semantics=unchanged "
               "v3=not-claimed\n");
  return 0;
}

static void usage() {
  std::fprintf(
      stderr,
      "s2c2-ascend-run --pairs|--mem [--n=N] [--k=K|--k=0] "
      "[--warmup=W] [--reps=R]\n"
      "--k=0 calibrates k from pinned HtoD / compute(k=1). "
      "Do not FileCheck microseconds.\n");
}

int main(int argc, char **argv) {
  int n = 1 << 20;
  int k = 8;
  int warmup = 1;
  int reps = 3;
  bool pairs = false;
  bool mem = false;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--pairs") {
      pairs = true;
    } else if (a == "--mem" || a == "--mem=p0") {
      mem = true;
    } else if (a.rfind("--n=", 0) == 0) {
      n = std::atoi(argv[i] + 4);
    } else if (a.rfind("--k=", 0) == 0) {
      k = std::atoi(argv[i] + 4);
    } else if (a.rfind("--warmup=", 0) == 0) {
      warmup = std::atoi(argv[i] + 9);
    } else if (a.rfind("--reps=", 0) == 0) {
      reps = std::atoi(argv[i] + 7);
    } else if (a == "--help" || a == "-h") {
      usage();
      return 0;
    } else {
      std::fprintf(stderr, "s2c2-ascend-run: unknown arg %s\n", argv[i]);
      return 1;
    }
  }
  if (pairs == mem) {
    usage();
    return 1;
  }
  if (pairs && k <= 0) {
    std::fprintf(stderr, "s2c2-ascend-run: --pairs needs k > 0\n");
    return 1;
  }
  if (n <= 0 || k < 0) {
    std::fprintf(stderr, "s2c2-ascend-run: n must be positive; k >= 0\n");
    return 1;
  }

  ACL_OK(aclInit(nullptr));
  ACL_OK(aclrtSetDevice(0));
  aclrtContext ctx = nullptr;
  ACL_OK(aclrtCreateContext(&ctx, 0));

  std::fprintf(stderr,
               "s2c2-ascend-run hardware_id=%s sched=%s map=%s "
               "device=%s sync=%s\n",
               kHardwareId, kSched, kMap, "npu", kSync);
  std::fprintf(stderr, "s2c2-ascend-run workload compute=elemwise\n");
  std::fprintf(stderr, "s2c2-ascend-run workload transfer=host_to_device|"
                       "device_to_host\n");
  std::fprintf(stderr,
               "s2c2-ascend-run note workload-semantic-ne-kernel-backend\n");
  std::fprintf(stderr, "s2c2-ascend-run timing=host-wall-clock\n");
  std::fprintf(stderr, "s2c2-ascend-run timing completion=s0,s1\n");

  int rc = 0;
  if (mem) {
    std::fprintf(stderr, "s2c2-ascend-run mem=r4\n");
    rc = runMemP0(n, k, warmup, reps);
  } else {
  std::fprintf(stderr, "s2c2-ascend-run n=%d k=%d bytes=%zu\n", n, k,
               sizeof(float) * static_cast<size_t>(n));

  Buf b;
  b.alloc(n);
  fillHost(b.host0, b.n, 1);
  fillHost(b.host1, b.n, 2);
  provision(b, Arm::Compute);
  // Prime aclnn executors on both streams so timed samples are not compile.
  elemwiseLaunch(b, b.dev0, b.dev2, 1, b.s0);
  elemwiseLaunch(b, b.dev1, b.dev3, 1, b.s1);
  ACL_OK(aclrtSynchronizeStream(b.s0));
  ACL_OK(aclrtSynchronizeStream(b.s1));
  b.reapStaleWorkspace();
  double tC = timeArm(b, Arm::Compute, warmup, reps, k);
  double tH = timeArm(b, Arm::HtoD, warmup, reps, k);
  double tD = timeArm(b, Arm::DtoH, warmup, reps, k);
  double tR1 = timeArm(b, Arm::ComputeHtoD, warmup, reps, k);
  double tR2 = timeArm(b, Arm::ComputeCompute, warmup, reps, k);
  double tR3 = timeArm(b, Arm::HtoDDtoH, warmup, reps, k);
  b.freeAll();

  struct Cell {
    const char *pair;
    double a, b, par;
  } cells[] = {
      {"C||HtoD", tC, tH, tR1},
      {"C||C", tC, tC, tR2},
      {"HtoD||DtoH", tH, tD, tR3},
  };
  std::fprintf(stderr, "s2c2-ascend-run correctness=1\n");
  std::fprintf(stderr, "s2c2-ascend-run score3=not-applicable cost=unchanged "
                       "semantics=unchanged v3=not-claimed\n");
  char sizeRange[32];
  int mib = static_cast<int>((sizeof(float) * static_cast<size_t>(n)) /
                             (1024u * 1024u));
  if (mib <= 0)
    std::snprintf(sizeRange, sizeof(sizeRange), "%zuB",
                  sizeof(float) * static_cast<size_t>(n));
  else
    std::snprintf(sizeRange, sizeof(sizeRange), "%dMiB", mib);
  for (const auto &c : cells) {
    double mx = c.a > c.b ? c.a : c.b;
    double sum = c.a + c.b;
    double pmax = mx > 0 ? c.par / mx : 0;
    double psum = sum > 0 ? c.par / sum : 0;
    const char *rel = classifyPair(pmax, psum);
    const char *cons = inferConstraint(c.pair, rel);
    std::fprintf(stderr,
                 "s2c2-ascend-run pair=%s pair_relation=%s "
                 "observed_constraint=%s confidence=measured\n",
                 c.pair, rel, cons);
    std::fprintf(stderr,
                 "s2c2-ascend-run timing pair=%s a=%.1f b=%.1f par=%.1f "
                 "par_over_max=%.3f par_over_sum=%.3f n=%d k=%d\n",
                 c.pair, c.a, c.b, c.par, pmax, psum, n, k);
    printRecord(c.pair, rel, cons, sizeRange);
  }
  }

  aclrtDestroyContext(ctx);
  aclrtResetDevice(0);
  aclFinalize();
  return rc;
}
