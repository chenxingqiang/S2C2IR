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
#include <map>
#include <string>
#include <vector>

using s2c2::ascend_adapter::classifyPair;
using s2c2::ascend_adapter::inferConstraint;
using s2c2::ascend_adapter::kHardwareId;
using s2c2::ascend_adapter::kMap;
using s2c2::ascend_adapter::kSched;
using s2c2::ascend_adapter::kSeqSlack;
using s2c2::ascend_adapter::kSync;
using s2c2::ascend_adapter::sequentialBeneficial;

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

static void runCC(Buf &b, int k0, int k1) {
  elemwiseLaunch(b, b.dev0, b.dev2, k0, b.s0);
  elemwiseLaunch(b, b.dev1, b.dev3, k1, b.s1);
}

static bool checkCC(Buf &b, int k0, int k1) {
  size_t bytes = b.bytes();
  ACL_OK(aclrtMemcpy(b.check, bytes, b.dev2, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
  for (int i = 0; i < b.n; ++i) {
    if (!closeEnough(b.check[i], hostElemwise(b.host0[i], k0)))
      return false;
  }
  ACL_OK(aclrtMemcpy(b.check, bytes, b.dev3, bytes, ACL_MEMCPY_DEVICE_TO_HOST));
  for (int i = 0; i < b.n; ++i) {
    if (!closeEnough(b.check[i], hostElemwise(b.host1[i], k1)))
      return false;
  }
  return true;
}

static double timeCC(Buf &b, int k0, int k1, int warmup, int reps) {
  auto body = [&]() { runCC(b, k0, k1); };
  for (int i = 0; i < warmup; ++i) {
    fillHost(b.host0, b.n, i + 3);
    fillHost(b.host1, b.n, i + 7);
    provision(b, Arm::ComputeCompute);
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
    provision(b, Arm::ComputeCompute);
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
    if (!checkCC(b, k0, k1)) {
      std::fprintf(stderr, "s2c2-ascend-run correctness=0 arm=cc-phase\n");
      std::exit(1);
    }
  }
  return medianUs(samples);
}

// Sequential realization of C||C: complete C1 on s0, then C2 on s1.
// Matches compiler flatten (parent IR order). Not a sibling wait op.
static double timeCCSeq(Buf &b, int k0, int k1, int warmup, int reps) {
  auto body = [&]() {
    elemwiseLaunch(b, b.dev0, b.dev2, k0, b.s0);
    ACL_OK(aclrtSynchronizeStream(b.s0));
    elemwiseLaunch(b, b.dev1, b.dev3, k1, b.s1);
  };
  for (int i = 0; i < warmup; ++i) {
    fillHost(b.host0, b.n, i + 3);
    fillHost(b.host1, b.n, i + 7);
    provision(b, Arm::ComputeCompute);
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
    provision(b, Arm::ComputeCompute);
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
    if (!checkCC(b, k0, k1)) {
      std::fprintf(stderr, "s2c2-ascend-run correctness=0 arm=cc-rewrite\n");
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static std::vector<double> parseRList(const char *raw) {
  std::vector<double> out;
  const char *p = raw;
  while (*p) {
    char *end = nullptr;
    double v = std::strtod(p, &end);
    if (end == p)
      break;
    if (v > 0.0)
      out.push_back(v);
    p = end;
    if (*p == ',')
      ++p;
  }
  return out;
}

static int runCCPhase(int n, int kRef, const std::vector<double> &rs,
                      int warmup, int reps) {
  Buf b;
  b.alloc(n);
  fillHost(b.host0, b.n, 1);
  fillHost(b.host1, b.n, 2);
  provision(b, Arm::ComputeCompute);
  elemwiseLaunch(b, b.dev0, b.dev2, 1, b.s0);
  elemwiseLaunch(b, b.dev1, b.dev3, 1, b.s1);
  ACL_OK(aclrtSynchronizeStream(b.s0));
  ACL_OK(aclrtSynchronizeStream(b.s1));
  b.reapStaleWorkspace();

  std::map<int, double> solo;
  auto timeSolo = [&](int kk) {
    auto it = solo.find(kk);
    if (it != solo.end())
      return it->second;
    double t = timeArm(b, Arm::Compute, warmup, reps, kk);
    solo[kk] = t;
    return t;
  };

  std::fprintf(stderr, "s2c2-ascend-run cc-phase=1 pair=C||C\n");
  std::fprintf(stderr, "s2c2-ascend-run cc-phase n=%d k_ref=%d\n", n, kRef);
  for (double rTarget : rs) {
    int k2 = kRef;
    int k1 = static_cast<int>(std::llround(rTarget * static_cast<double>(k2)));
    if (k1 < 1)
      k1 = 1;
    double t1 = timeSolo(k1);
    double t2 = timeSolo(k2);
    double tpar = timeCC(b, k1, k2, warmup, reps);
    double mx = t1 > t2 ? t1 : t2;
    double sum = t1 + t2;
    double pmax = mx > 0 ? tpar / mx : 0;
    double psum = sum > 0 ? tpar / sum : 0;
    double rAch = t2 > 0 ? t1 / t2 : 0;
    const char *rel = classifyPair(pmax, psum);
    const char *cons = inferConstraint("C||C", rel);
    std::fprintf(stderr,
                 "s2c2-ascend-run cc-phase slice r_target=%.3f "
                 "r_achieved=%.3f k1=%d k2=%d pair_relation=%s "
                 "observed_constraint=%s n=%d\n",
                 rTarget, rAch, k1, k2, rel, cons, n);
    std::fprintf(stderr,
                 "s2c2-ascend-run cc-phase timing a=%.1f b=%.1f par=%.1f "
                 "par_over_max=%.3f par_over_sum=%.3f\n",
                 t1, t2, tpar, pmax, psum);
  }
  b.freeAll();
  std::fprintf(stderr, "s2c2-ascend-run cc-phase correctness=1 "
                       "cost=unchanged semantics=unchanged v3=not-claimed\n");
  std::fprintf(stderr, "s2c2-ascend-run cc-phase r3-gate=closed "
                       "note catalog-untouched\n");
  return 0;
}

static int runCCRewrite(int n, int kRef, double rTarget, int warmup, int reps) {
  Buf b;
  b.alloc(n);
  fillHost(b.host0, b.n, 1);
  fillHost(b.host1, b.n, 2);
  provision(b, Arm::ComputeCompute);
  elemwiseLaunch(b, b.dev0, b.dev2, 1, b.s0);
  elemwiseLaunch(b, b.dev1, b.dev3, 1, b.s1);
  ACL_OK(aclrtSynchronizeStream(b.s0));
  ACL_OK(aclrtSynchronizeStream(b.s1));
  b.reapStaleWorkspace();

  int k2 = kRef;
  int k1 = static_cast<int>(std::llround(rTarget * static_cast<double>(k2)));
  if (k1 < 1)
    k1 = 1;
  double t1 = timeArm(b, Arm::Compute, warmup, reps, k1);
  double t2 = timeArm(b, Arm::Compute, warmup, reps, k2);
  double tpar = timeCC(b, k1, k2, warmup, reps);
  double tseq = timeCCSeq(b, k1, k2, warmup, reps);
  double mx = t1 > t2 ? t1 : t2;
  double sum = t1 + t2;
  double pmax = mx > 0 ? tpar / mx : 0;
  double psum = sum > 0 ? tpar / sum : 0;
  double rAch = t2 > 0 ? t1 / t2 : 0;
  double seqOverPar = tpar > 0 ? tseq / tpar : 0;
  double parOverSeq = tseq > 0 ? tpar / tseq : 0;
  const char *rel = classifyPair(pmax, psum);
  const char *cons = inferConstraint("C||C", rel);
  bool benefit = sequentialBeneficial(seqOverPar);
  bool license = std::strcmp(rel, "serial") == 0 && benefit;
  std::fprintf(stderr, "s2c2-ascend-run cc-rewrite=1 pair=C||C\n");
  std::fprintf(stderr, "s2c2-ascend-run cc-rewrite n=%d k_ref=%d r=1\n", n,
               kRef);
  std::fprintf(stderr, "s2c2-ascend-run cc-rewrite seq-slack=%.2f "
                       "note seq-slack-ne-cost\n",
               kSeqSlack);
  std::fprintf(stderr,
               "s2c2-ascend-run cc-rewrite slice r_target=%.3f "
               "r_achieved=%.3f k1=%d k2=%d pair_relation=%s "
               "observed_constraint=%s n=%d\n",
               rTarget, rAch, k1, k2, rel, cons, n);
  std::fprintf(stderr,
               "s2c2-ascend-run cc-rewrite timing a=%.1f b=%.1f par=%.1f "
               "seq=%.1f seq_over_par=%.3f par_over_seq=%.3f\n",
               t1, t2, tpar, tseq, seqOverPar, parOverSeq);
  std::fprintf(stderr, "s2c2-ascend-run cc-rewrite benefit=%s\n",
               benefit ? "yes" : "no");
  std::fprintf(stderr, "s2c2-ascend-run cc-rewrite rewrite_license=%s\n",
               license ? "yes" : "no");
  b.freeAll();
  std::fprintf(stderr, "s2c2-ascend-run cc-rewrite correctness=1 "
                       "cost=unchanged semantics=unchanged v3=not-claimed\n");
  std::fprintf(stderr, "s2c2-ascend-run cc-rewrite r3-gate=closed "
                       "note catalog-untouched\n");
  return 0;
}

enum class ProgArm { Seq, Evi, Par };

static void runSsdMlpProgram(Buf &prefetch, Buf &cc, int kMlp, int kCc,
                             ProgArm arm) {
  if (arm == ProgArm::Seq) {
    runArm(prefetch, Arm::HtoD, kMlp);
    ACL_OK(aclrtSynchronizeStream(prefetch.s0));
    runArm(prefetch, Arm::Compute, kMlp);
    ACL_OK(aclrtSynchronizeStream(prefetch.s0));
    elemwiseLaunch(cc, cc.dev0, cc.dev2, kCc, cc.s0);
    ACL_OK(aclrtSynchronizeStream(cc.s0));
    elemwiseLaunch(cc, cc.dev1, cc.dev3, kCc, cc.s1);
    ACL_OK(aclrtSynchronizeStream(cc.s1));
    return;
  }
  runArm(prefetch, Arm::ComputeHtoD, kMlp);
  ACL_OK(aclrtSynchronizeStream(prefetch.s0));
  ACL_OK(aclrtSynchronizeStream(prefetch.s1));
  if (arm == ProgArm::Evi) {
    elemwiseLaunch(cc, cc.dev0, cc.dev2, kCc, cc.s0);
    ACL_OK(aclrtSynchronizeStream(cc.s0));
    elemwiseLaunch(cc, cc.dev1, cc.dev3, kCc, cc.s1);
    ACL_OK(aclrtSynchronizeStream(cc.s1));
    return;
  }
  runArm(cc, Arm::ComputeCompute, kCc);
  ACL_OK(aclrtSynchronizeStream(cc.s0));
  ACL_OK(aclrtSynchronizeStream(cc.s1));
}

static bool checkSsdMlp(Buf &prefetch, Buf &cc, int kMlp, int kCc,
                        ProgArm arm) {
  if (arm == ProgArm::Seq) {
    if (!checkArm(prefetch, Arm::Compute, kMlp))
      return false;
  } else if (!checkArm(prefetch, Arm::ComputeHtoD, kMlp)) {
    return false;
  }
  return checkCC(cc, kCc, kCc);
}

static double timeSsdMlp(Buf &prefetch, Buf &cc, int kMlp, int kCc, int warmup,
                         int reps, ProgArm arm) {
  auto prep = [&](int seedA, int seedB) {
    fillHost(prefetch.host0, prefetch.n, seedA);
    fillHost(prefetch.host1, prefetch.n, seedB);
    fillHost(cc.host0, cc.n, seedA + 1);
    fillHost(cc.host1, cc.n, seedB + 1);
    provision(prefetch, arm == ProgArm::Seq ? Arm::HtoD : Arm::ComputeHtoD);
    provision(cc, Arm::ComputeCompute);
    ACL_OK(aclrtSynchronizeStream(prefetch.s0));
    ACL_OK(aclrtSynchronizeStream(prefetch.s1));
    ACL_OK(aclrtSynchronizeStream(cc.s0));
    ACL_OK(aclrtSynchronizeStream(cc.s1));
  };
  for (int i = 0; i < warmup; ++i) {
    prep(i + 3, i + 7);
    runSsdMlpProgram(prefetch, cc, kMlp, kCc, arm);
    prefetch.reapStaleWorkspace();
    cc.reapStaleWorkspace();
  }
  std::vector<double> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    prep(i + 11, i + 19);
    auto start = std::chrono::steady_clock::now();
    runSsdMlpProgram(prefetch, cc, kMlp, kCc, arm);
    auto stop = std::chrono::steady_clock::now();
    prefetch.reapStaleWorkspace();
    cc.reapStaleWorkspace();
    samples.push_back(
        std::chrono::duration<double, std::micro>(stop - start).count());
    if (!checkSsdMlp(prefetch, cc, kMlp, kCc, arm)) {
      std::fprintf(stderr,
                   "s2c2-ascend-run correctness=0 arm=ssd-mlp-wallclock\n");
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static int runSsdMlpWallclock(int nHtod, int nCc, int kRef, int warmup,
                              int reps) {
  Buf prefetch;
  Buf cc;
  prefetch.alloc(nHtod);
  cc.alloc(nCc);
  fillHost(prefetch.host0, prefetch.n, 1);
  fillHost(prefetch.host1, prefetch.n, 2);
  fillHost(cc.host0, cc.n, 1);
  fillHost(cc.host1, cc.n, 2);
  provision(prefetch, Arm::ComputeHtoD);
  provision(cc, Arm::ComputeCompute);
  elemwiseLaunch(prefetch, prefetch.dev1, prefetch.dev2, 1, prefetch.s0);
  elemwiseLaunch(cc, cc.dev0, cc.dev2, 1, cc.s0);
  elemwiseLaunch(cc, cc.dev1, cc.dev3, 1, cc.s1);
  ACL_OK(aclrtSynchronizeStream(prefetch.s0));
  ACL_OK(aclrtSynchronizeStream(cc.s0));
  ACL_OK(aclrtSynchronizeStream(cc.s1));
  prefetch.reapStaleWorkspace();
  cc.reapStaleWorkspace();

  double tSeq = timeSsdMlp(prefetch, cc, kRef, kRef, warmup, reps, ProgArm::Seq);
  double tEvi = timeSsdMlp(prefetch, cc, kRef, kRef, warmup, reps, ProgArm::Evi);
  double tPar = timeSsdMlp(prefetch, cc, kRef, kRef, warmup, reps, ProgArm::Par);
  double ratio = tSeq > 0.0 ? tEvi / tSeq : 0.0;

  std::fprintf(stderr, "s2c2-ascend-run ssd-mlp-wallclock=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-run ssd-mlp-wallclock program-measurement=yes\n");
  std::fprintf(stderr,
               "s2c2-ascend-run ssd-mlp-wallclock note not-stage-ab\n");
  std::fprintf(stderr,
               "s2c2-ascend-run ssd-mlp-wallclock n-htod=%d n-cc=%d k_ref=%d\n",
               nHtod, nCc, kRef);
  std::fprintf(stderr, "s2c2-ascend-run ssd-mlp-wallclock measured=yes\n");
  std::fprintf(stderr,
               "s2c2-ascend-run ssd-mlp-wallclock timing seq=%.1f evi=%.1f "
               "par=%.1f opt_over_base=%.3f\n",
               tSeq, tEvi, tPar, ratio);
  std::fprintf(stderr, "s2c2-ascend-run ssd-mlp-wallclock correctness=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-run ssd-mlp-wallclock note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-run ssd-mlp-wallclock note 32M-outlier-not-cost\n");
  std::fprintf(stderr,
               "s2c2-ascend-run ssd-mlp-wallclock note logical-ssd-ne-disk\n");
  std::fprintf(stderr, "s2c2-ascend-run ssd-mlp-wallclock note not-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-ascend-run ssd-mlp-wallclock cost=unchanged "
               "semantics=unchanged v3=not-claimed\n");
  prefetch.freeAll();
  cc.freeAll();
  return 0;
}

// 3I scf.for realization wall-clock. Logical SSD is pageable host.
// T_evi keeps C||Storage. T_par is the same schedule. Not Cost v0.4.
static void ssdPrefetchTile(Buf &t) {
  std::memcpy(t.host0, t.hostPage, t.bytes());
}

static void tileHtoDAscend(Buf &t) {
  ACL_OK(aclrtMemcpyAsync(t.dev0, t.bytes(), t.host0, t.bytes(),
                          ACL_MEMCPY_HOST_TO_DEVICE, t.s0));
}

static void runStorageLoopProgram(Buf t[3], int k, ProgArm arm) {
  ssdPrefetchTile(t[0]);
  tileHtoDAscend(t[0]);
  ACL_OK(aclrtSynchronizeStream(t[0].s0));
  for (int i = 0; i < 2; ++i) {
    int next = i + 1;
    if (arm == ProgArm::Seq) {
      elemwiseLaunch(t[i], t[i].dev0, t[i].dev2, k, t[i].s0);
      ACL_OK(aclrtSynchronizeStream(t[i].s0));
      ssdPrefetchTile(t[next]);
      tileHtoDAscend(t[next]);
      ACL_OK(aclrtSynchronizeStream(t[next].s0));
    } else {
      elemwiseLaunch(t[i], t[i].dev0, t[i].dev2, k, t[i].s0);
      ssdPrefetchTile(t[next]);
      ACL_OK(aclrtSynchronizeStream(t[i].s0));
      tileHtoDAscend(t[next]);
      ACL_OK(aclrtSynchronizeStream(t[next].s0));
    }
  }
}

static bool checkStorageLoopProgram(Buf t[3], int k) {
  int step = t[0].n > 4096 ? t[0].n / 4096 : 1;
  size_t bytes = t[0].bytes();
  for (int tile = 0; tile < 2; ++tile) {
    ACL_OK(aclrtMemcpy(t[tile].check, bytes, t[tile].dev2, bytes,
                       ACL_MEMCPY_DEVICE_TO_HOST));
    for (int i = 0; i < t[tile].n; i += step) {
      if (!closeEnough(t[tile].check[i],
                       hostElemwise(t[tile].hostPage[i], k)))
        return false;
    }
  }
  ACL_OK(aclrtMemcpy(t[2].check, bytes, t[2].dev0, bytes,
                     ACL_MEMCPY_DEVICE_TO_HOST));
  for (int i = 0; i < t[2].n; i += step) {
    if (!closeEnough(t[2].check[i], t[2].hostPage[i]))
      return false;
  }
  return true;
}

static double timeStorageLoopProgram(Buf t[3], int k, int warmup, int reps,
                                     ProgArm arm) {
  auto prep = [&](int seed) {
    for (int i = 0; i < 3; ++i)
      fillHost(t[i].hostPage, t[i].n, seed + i);
  };
  for (int i = 0; i < warmup; ++i) {
    prep(i + 3);
    runStorageLoopProgram(t, k, arm);
    for (int j = 0; j < 3; ++j)
      t[j].reapStaleWorkspace();
  }
  std::vector<double> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    prep(i + 11);
    auto start = std::chrono::steady_clock::now();
    runStorageLoopProgram(t, k, arm);
    auto stop = std::chrono::steady_clock::now();
    for (int j = 0; j < 3; ++j)
      t[j].reapStaleWorkspace();
    samples.push_back(
        std::chrono::duration<double, std::micro>(stop - start).count());
    if (!checkStorageLoopProgram(t, k)) {
      std::fprintf(stderr,
                   "s2c2-ascend-run correctness=0 arm=storage-loop-wallclock\n");
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static int runStorageLoopWallclock(int nTile, int kRef, int warmup, int reps) {
  Buf t[3];
  for (int i = 0; i < 3; ++i) {
    t[i].alloc(nTile, true);
    fillHost(t[i].hostPage, t[i].n, i + 1);
  }
  elemwiseLaunch(t[0], t[0].dev0, t[0].dev2, 1, t[0].s0);
  ACL_OK(aclrtSynchronizeStream(t[0].s0));
  t[0].reapStaleWorkspace();

  double tSeq =
      timeStorageLoopProgram(t, kRef, warmup, reps, ProgArm::Seq);
  double tEvi =
      timeStorageLoopProgram(t, kRef, warmup, reps, ProgArm::Evi);
  double tPar =
      timeStorageLoopProgram(t, kRef, warmup, reps, ProgArm::Par);
  double ratio = tSeq > 0.0 ? tEvi / tSeq : 0.0;

  std::fprintf(stderr, "s2c2-ascend-run storage-loop-wallclock=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock "
               "program-measurement=yes\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock "
               "note scf-for-software-pipeline\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock "
               "note not-arbitrary-runtime-n\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock "
               "note compute-then-prefetch-next\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock n-tile=%d tiles=3 "
               "trip=2 k_ref=%d\n",
               nTile, kRef);
  std::fprintf(stderr, "s2c2-ascend-run storage-loop-wallclock measured=yes\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock timing seq=%.1f "
               "evi=%.1f par=%.1f opt_over_base=%.3f\n",
               tSeq, tEvi, tPar, ratio);
  std::fprintf(stderr, "s2c2-ascend-run storage-loop-wallclock correctness=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock evi=keep-C||Storage\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock note evi-eq-par\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock "
               "note logical-ssd-ne-disk\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock note not-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-loop-wallclock cost=unchanged "
               "semantics=unchanged v3=not-claimed\n");
  for (int i = 0; i < 3; ++i)
    t[i].freeAll();
  return 0;
}

// Two-tile storage-aware pipeline wall-clock. Logical SSD is a
// pageable host buffer, not NVMe. T_evi keeps C||Storage overlap
// and flattens licensed C||C. Same F(program) signatures as the
// 4090 --storage-pipeline: evi → S0 PREFETCH, seq → S1 PRESERVE.
// par is not in F. Not Cost v0.4. Do not FileCheck microseconds.
static void ssdPrefetchPipe(Buf &t) {
  std::memcpy(t.host0, t.hostPage, t.bytes());
}

static void tileHtoDPipe(Buf &t) {
  ACL_OK(aclrtMemcpyAsync(t.dev0, t.bytes(), t.host0, t.bytes(),
                          ACL_MEMCPY_HOST_TO_DEVICE, t.s0));
}

static void runStoragePipeline(Buf &t0, Buf &t1, Buf &cc16, Buf &cc128,
                               int kTile, int kCc, ProgArm arm) {
  if (arm == ProgArm::Seq) {
    ssdPrefetchPipe(t0);
    tileHtoDPipe(t0);
    ACL_OK(aclrtSynchronizeStream(t0.s0));
    elemwiseLaunch(t0, t0.dev0, t0.dev2, kTile, t0.s0);
    ACL_OK(aclrtSynchronizeStream(t0.s0));
    ssdPrefetchPipe(t1);
    tileHtoDPipe(t1);
    ACL_OK(aclrtSynchronizeStream(t1.s0));
    elemwiseLaunch(cc16, cc16.dev0, cc16.dev2, kCc, cc16.s0);
    ACL_OK(aclrtSynchronizeStream(cc16.s0));
    elemwiseLaunch(cc16, cc16.dev1, cc16.dev3, kCc, cc16.s1);
    ACL_OK(aclrtSynchronizeStream(cc16.s1));
    elemwiseLaunch(cc128, cc128.dev0, cc128.dev2, kCc, cc128.s0);
    ACL_OK(aclrtSynchronizeStream(cc128.s0));
    elemwiseLaunch(cc128, cc128.dev1, cc128.dev3, kCc, cc128.s1);
    ACL_OK(aclrtSynchronizeStream(cc128.s1));
    return;
  }
  ssdPrefetchPipe(t0);
  tileHtoDPipe(t0);
  ACL_OK(aclrtSynchronizeStream(t0.s0));
  elemwiseLaunch(t0, t0.dev0, t0.dev2, kTile, t0.s0);
  ssdPrefetchPipe(t1);
  ACL_OK(aclrtSynchronizeStream(t0.s0));
  tileHtoDPipe(t1);
  ACL_OK(aclrtSynchronizeStream(t1.s0));
  if (arm == ProgArm::Evi) {
    elemwiseLaunch(cc16, cc16.dev0, cc16.dev2, kCc, cc16.s0);
    ACL_OK(aclrtSynchronizeStream(cc16.s0));
    elemwiseLaunch(cc16, cc16.dev1, cc16.dev3, kCc, cc16.s1);
    ACL_OK(aclrtSynchronizeStream(cc16.s1));
    elemwiseLaunch(cc128, cc128.dev0, cc128.dev2, kCc, cc128.s0);
    ACL_OK(aclrtSynchronizeStream(cc128.s0));
    elemwiseLaunch(cc128, cc128.dev1, cc128.dev3, kCc, cc128.s1);
    ACL_OK(aclrtSynchronizeStream(cc128.s1));
    return;
  }
  runArm(cc16, Arm::ComputeCompute, kCc);
  ACL_OK(aclrtSynchronizeStream(cc16.s0));
  ACL_OK(aclrtSynchronizeStream(cc16.s1));
  runArm(cc128, Arm::ComputeCompute, kCc);
  ACL_OK(aclrtSynchronizeStream(cc128.s0));
  ACL_OK(aclrtSynchronizeStream(cc128.s1));
}

static bool checkStoragePipeline(Buf &t0, Buf &t1, Buf &cc16, Buf &cc128,
                                 int kTile, int kCc) {
  size_t bytes0 = t0.bytes();
  int step = t0.n > 4096 ? t0.n / 4096 : 1;
  ACL_OK(aclrtMemcpy(t0.check, bytes0, t0.dev2, bytes0,
                     ACL_MEMCPY_DEVICE_TO_HOST));
  for (int i = 0; i < t0.n; i += step) {
    if (!closeEnough(t0.check[i], hostElemwise(t0.hostPage[i], kTile)))
      return false;
  }
  ACL_OK(aclrtMemcpy(t1.check, t1.bytes(), t1.dev0, t1.bytes(),
                     ACL_MEMCPY_DEVICE_TO_HOST));
  for (int i = 0; i < t1.n; i += step) {
    if (!closeEnough(t1.check[i], t1.hostPage[i]))
      return false;
  }
  return checkCC(cc16, kCc, kCc) && checkCC(cc128, kCc, kCc);
}

static double timeStoragePipeline(Buf &t0, Buf &t1, Buf &cc16, Buf &cc128,
                                  int kTile, int kCc, int warmup, int reps,
                                  ProgArm arm) {
  auto prep = [&](int seed) {
    fillHost(t0.hostPage, t0.n, seed);
    fillHost(t1.hostPage, t1.n, seed + 1);
    fillHost(cc16.host0, cc16.n, seed + 2);
    fillHost(cc16.host1, cc16.n, seed + 3);
    fillHost(cc128.host0, cc128.n, seed + 4);
    fillHost(cc128.host1, cc128.n, seed + 5);
    provision(cc16, Arm::ComputeCompute);
    provision(cc128, Arm::ComputeCompute);
  };
  for (int i = 0; i < warmup; ++i) {
    prep(i + 3);
    runStoragePipeline(t0, t1, cc16, cc128, kTile, kCc, arm);
    t0.reapStaleWorkspace();
    t1.reapStaleWorkspace();
    cc16.reapStaleWorkspace();
    cc128.reapStaleWorkspace();
  }
  std::vector<double> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    prep(i + 11);
    auto start = std::chrono::steady_clock::now();
    runStoragePipeline(t0, t1, cc16, cc128, kTile, kCc, arm);
    auto stop = std::chrono::steady_clock::now();
    t0.reapStaleWorkspace();
    t1.reapStaleWorkspace();
    cc16.reapStaleWorkspace();
    cc128.reapStaleWorkspace();
    samples.push_back(
        std::chrono::duration<double, std::micro>(stop - start).count());
    if (!checkStoragePipeline(t0, t1, cc16, cc128, kTile, kCc)) {
      std::fprintf(stderr,
                   "s2c2-ascend-run correctness=0 arm=storage-pipeline\n");
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static int runStoragePipelineWallclock(int nTile, int nCc, int kRef, int warmup,
                                       int reps) {
  Buf t0;
  Buf t1;
  Buf cc16;
  Buf cc128;
  t0.alloc(nTile, true);
  t1.alloc(nTile, true);
  cc16.alloc(nTile);
  cc128.alloc(nCc);
  fillHost(t0.hostPage, t0.n, 1);
  fillHost(t1.hostPage, t1.n, 2);
  fillHost(cc16.host0, cc16.n, 1);
  fillHost(cc16.host1, cc16.n, 2);
  fillHost(cc128.host0, cc128.n, 1);
  fillHost(cc128.host1, cc128.n, 2);
  provision(cc16, Arm::ComputeCompute);
  provision(cc128, Arm::ComputeCompute);
  elemwiseLaunch(t0, t0.dev0, t0.dev2, 1, t0.s0);
  elemwiseLaunch(cc16, cc16.dev0, cc16.dev2, 1, cc16.s0);
  elemwiseLaunch(cc128, cc128.dev0, cc128.dev2, 1, cc128.s0);
  ACL_OK(aclrtSynchronizeStream(t0.s0));
  ACL_OK(aclrtSynchronizeStream(cc16.s0));
  ACL_OK(aclrtSynchronizeStream(cc128.s0));
  t0.reapStaleWorkspace();
  cc16.reapStaleWorkspace();
  cc128.reapStaleWorkspace();

  double tSeq = timeStoragePipeline(t0, t1, cc16, cc128, kRef, kRef, warmup,
                                    reps, ProgArm::Seq);
  double tEvi = timeStoragePipeline(t0, t1, cc16, cc128, kRef, kRef, warmup,
                                    reps, ProgArm::Evi);
  double tPar = timeStoragePipeline(t0, t1, cc16, cc128, kRef, kRef, warmup,
                                    reps, ProgArm::Par);
  double ratio = tSeq > 0.0 ? tEvi / tSeq : 0.0;

  std::fprintf(stderr, "s2c2-ascend-run storage-pipeline=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-pipeline program-measurement=yes\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-pipeline "
               "note storage-prefetch||compute\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-pipeline n-tile=%d n-cc16=%d "
               "n-cc128=%d k_ref=%d\n",
               nTile, nTile, nCc, kRef);
  std::fprintf(stderr, "s2c2-ascend-run storage-pipeline measured=yes\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-pipeline timing seq=%.1f evi=%.1f "
               "par=%.1f opt_over_base=%.3f\n",
               tSeq, tEvi, tPar, ratio);
  std::fprintf(stderr, "s2c2-ascend-run storage-pipeline correctness=1\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-pipeline evi=keep-C||Storage,"
               "serialize-licensed-C||C\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-pipeline note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-pipeline note logical-ssd-ne-disk\n");
  std::fprintf(stderr, "s2c2-ascend-run storage-pipeline note not-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-pipeline cost=unchanged "
               "semantics=unchanged v3=not-claimed\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-measured note "
               "evi-is-S0-prefetch seq-is-S1-preserve\n");
  std::fprintf(stderr, "s2c2-ascend-run storage-measured note par-not-in-F\n");
  std::fprintf(stderr,
               "s2c2-ascend-run storage-measured "
               "note do-not-filecheck-microseconds\n");
  std::fprintf(stderr, "s2c2-ascend-run storage-measured cost=unchanged\n");
  t0.freeAll();
  t1.freeAll();
  cc16.freeAll();
  cc128.freeAll();
  return 0;
}

static void usage() {
  std::fprintf(
      stderr,
      "s2c2-ascend-run --pairs|--mem|--cc-phase|--cc-rewrite|"
      "--ssd-mlp-wallclock|--storage-loop-wallclock|--storage-pipeline "
      "[--n=N] [--n-cc=N] "
      "[--k=K|--k=0] [--r=r1,r2,...] [--warmup=W] [--reps=R]\n"
      "--k=0 calibrates k from pinned HtoD / compute(k=1) (mem only). "
      "--cc-phase uses k as k_ref for C2. "
      "--cc-rewrite A/B concurrent vs sequential C||C at r≈1. "
      "--ssd-mlp-wallclock times T_evi/T_seq of the complete "
      "SSD+MLP program (not the stage A/B). "
      "--storage-loop-wallclock times T_evi/T_seq of the 3I "
      "scf.for software pipeline (static trip=2; not runtime-N). "
      "--storage-pipeline times T_evi/T_seq of the two-tile "
      "SSD prefetch||compute program (evi=S0 seq=S1). "
      "Do not FileCheck microseconds.\n");
}

int main(int argc, char **argv) {
  int n = 1 << 20;
  int k = 8;
  bool kSet = false;
  int warmup = 1;
  int reps = 3;
  bool pairs = false;
  bool mem = false;
  bool ccPhase = false;
  bool ccRewrite = false;
  bool ssdMlp = false;
  bool storageLoop = false;
  bool storagePipe = false;
  int nHtod = 22528000;
  int nCc = 33554432;
  std::vector<double> rs = {0.5, 0.75, 1.0, 1.5, 2.0};
  bool rsSet = false;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--pairs") {
      pairs = true;
    } else if (a == "--mem" || a == "--mem=p0") {
      mem = true;
    } else if (a == "--cc-phase") {
      ccPhase = true;
    } else if (a == "--cc-rewrite") {
      ccRewrite = true;
    } else if (a == "--ssd-mlp-wallclock") {
      ssdMlp = true;
    } else if (a == "--storage-loop-wallclock") {
      storageLoop = true;
    } else if (a == "--storage-pipeline") {
      storagePipe = true;
    } else if (a.rfind("--n-cc=", 0) == 0) {
      nCc = std::atoi(argv[i] + 7);
    } else if (a.rfind("--n=", 0) == 0) {
      n = std::atoi(argv[i] + 4);
      nHtod = n;
    } else if (a.rfind("--k=", 0) == 0) {
      k = std::atoi(argv[i] + 4);
      kSet = true;
    } else if (a.rfind("--r=", 0) == 0) {
      rs = parseRList(argv[i] + 4);
      rsSet = true;
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
  int modes = (int)pairs + (int)mem + (int)ccPhase + (int)ccRewrite +
              (int)ssdMlp + (int)storageLoop + (int)storagePipe;
  if (modes != 1) {
    usage();
    return 1;
  }
  if ((pairs || ccPhase || ccRewrite || ssdMlp || storageLoop || storagePipe) &&
      k <= 0) {
    std::fprintf(stderr,
                 "s2c2-ascend-run: --pairs/--cc-phase/--cc-rewrite/"
                 "--ssd-mlp-wallclock/--storage-loop-wallclock/"
                 "--storage-pipeline needs k > 0\n");
    return 1;
  }
  if (ssdMlp && (nHtod <= 0 || nCc <= 0)) {
    std::fprintf(stderr,
                 "s2c2-ascend-run: --ssd-mlp-wallclock needs n>0 and n-cc>0\n");
    return 1;
  }
  if (storagePipe && (n <= 0 || nCc <= 0)) {
    std::fprintf(stderr,
                 "s2c2-ascend-run: --storage-pipeline needs n>0 and n-cc>0\n");
    return 1;
  }
  if (ccPhase && rs.empty()) {
    std::fprintf(stderr, "s2c2-ascend-run: --cc-phase needs r > 0\n");
    return 1;
  }
  if (ccRewrite) {
    if (!rsSet)
      rs = {1.0};
    if (rs.size() != 1) {
      std::fprintf(stderr,
                   "s2c2-ascend-run: --cc-rewrite needs a single r\n");
      return 1;
    }
  }
  if (n <= 0 || k < 0) {
    std::fprintf(stderr, "s2c2-ascend-run: n must be positive; k >= 0\n");
    return 1;
  }
  (void)rsSet;

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
  } else if (ccPhase) {
    rc = runCCPhase(n, k, rs, warmup, reps);
  } else if (ccRewrite) {
    rc = runCCRewrite(n, k, rs.front(), warmup, reps);
  } else if (ssdMlp) {
    if (!kSet)
      k = 32;
    rc = runSsdMlpWallclock(nHtod, nCc, k, warmup, reps);
  } else if (storageLoop) {
    if (!kSet)
      k = 32;
    if (n == (1 << 20))
      n = 4194304;
    rc = runStorageLoopWallclock(n, k, warmup, reps);
  } else if (storagePipe) {
    if (!kSet)
      k = 32;
    if (n == (1 << 20))
      n = 4194304;
    rc = runStoragePipelineWallclock(n, nCc, k, warmup, reps);
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
