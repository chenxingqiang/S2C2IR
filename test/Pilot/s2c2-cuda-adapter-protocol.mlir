// RUN: s2c2-cuda-adapter --dry-run | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run --func=pilot_b_compute_par_comm | FileCheck %s --check-prefix=B

// Protocol witness for the CUDA adapter contract. No device, no
// kernel launch. Score_3 numbers are the frozen Pilot GPU totals.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute sched=gpu-async map=default device=gpu score3_total=130
// CHECK: s2c2-cuda-adapter func=pilot_b_compute_par_comm sched=gpu-async map=default device=gpu score3_total=128
// CHECK: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage sched=gpu-async map=default device=gpu score3_total=163
// CHECK: s2c2-cuda-adapter map stor.pack=host_pinned
// CHECK: s2c2-cuda-adapter map comm.stream=cudaMemcpyAsync
// CHECK: s2c2-cuda-adapter map sched.wait=cudaEventSynchronize
// CHECK: s2c2-cuda-adapter map sched.concurrent=two_streams
// CHECK: s2c2-cuda-adapter map sched.pipeline=stage_order_events
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: s2c2-search
// CHECK-NOT: kind=concurrent-reorder

// B: s2c2-cuda-adapter func=pilot_b_compute_par_comm sched=gpu-async map=default device=gpu score3_total=128
// B-NOT: func=pilot_a
// B-NOT: func=pilot_c
