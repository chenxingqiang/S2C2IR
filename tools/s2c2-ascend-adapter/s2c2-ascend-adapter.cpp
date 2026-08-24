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
               "[--cap-schema] [--classify=ta:tb:tpar] [--emit-record=<pair>] "
               "[--accept-hardware=<id>]\n"
               "Host protocol only. Timed AscendCL: runtime/ascend/\n");
}

int main(int argc, char **argv) {
  bool dryRun = false;
  bool pairs = false;
  bool workload = false;
  bool capSchema = false;
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
  int modes = (int)pairs + (int)workload + (int)capSchema +
              (int)(classify != nullptr) + (int)(emit != nullptr) +
              (int)(acceptHw != nullptr);
  if (modes > 1) {
    std::fprintf(stderr,
                 "s2c2-ascend-adapter: --cap-schema/--pairs/--workload/"
                 "--classify/--emit-record/--accept-hardware cannot combine\n");
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
