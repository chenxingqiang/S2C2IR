// RUN: s2c2-opt %s --check-s2c2-execution
// RUN: s2c2-opt %s --s2c2-lower | FileCheck %s --check-prefix=CPU
// RUN: s2c2-opt %s --s2c2-lower="space-map=ssd=100,dram=2,hbm=9" | FileCheck %s --check-prefix=MAP
// RUN: s2c2-opt %s --convert-s2c2-token-to-async --convert-s2c2-concurrent-to-async --convert-s2c2-pipeline-to-async | FileCheck %s --check-prefix=GPU

// Capability matrix v0.1: same frozen S²C² program, different legal
// realizations. Does not add execution semantics.
//
//   CPU  = SequentialSchedule (blocking memref.copy)
//   GPU  = Token SW + StageOrder + Concurrent (no sibling await)
//   MAP  = logical spaces → target memref integers (not enum ABI)
module {
  // CPU-LABEL: func.func @compose_token_pipeline_concurrent
  // MAP-LABEL: func.func @compose_token_pipeline_concurrent
  // GPU-LABEL: func.func @compose_token_pipeline_concurrent
  func.func @compose_token_pipeline_concurrent(%t: tensor<4xf32>) -> tensor<4xf32> {
    %w_obj = stor.object : !stor.object<tensor<4xf32>>
    %a_obj = stor.object : !stor.object<tensor<4xf32>>
    %w_ssd = stor.materialize %w_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %w_hbm = stor.materialize %w_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %a_hbm = stor.materialize %a_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %a_ssd = stor.materialize %a_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>

    stor.pack %t into %w_ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
    // CPU: memref.alloc() : memref<4xf32, 4>
    // CPU: memref.alloc() : memref<4xf32, 3>
    // CPU: memref.copy
    // CPU: memref.copy
    // CPU-NOT: async.execute
    // CPU-NOT: async.await
    // CPU-NOT: sched.pipeline
    // CPU-NOT: sched.concurrent
    // CPU-NOT: sched.wait
    // CPU-NOT: comm.stream
    //
    // MAP: memref.alloc() : memref<4xf32, 100>
    // MAP: memref.alloc() : memref<4xf32, 9>
    // MAP: memref.copy
    // MAP-NOT: memref<4xf32, 4>
    // MAP-NOT: memref<4xf32, 3>
    // MAP-NOT: async.execute
    //
    // GPU: %[[PRE:.*]] = async.execute {
    // GPU:   comm.copy
    // GPU:   async.yield
    // GPU: }
    // GPU: async.await %[[PRE]] : !async.token
    // GPU: %[[S1:.*]] = async.execute {
    // GPU:   stor.pack
    // GPU:   async.yield
    // GPU: }
    // GPU: async.await %[[S1]] : !async.token
    // GPU: %[[S2:.*]] = async.execute {
    // GPU:   %[[COMP:.*]] = async.execute {
    // GPU:     stor.unpack
    // GPU:     stor.unpack
    // GPU:     comp.elemwise
    // GPU:     async.yield
    // GPU:   }
    // GPU-NOT: async.await
    // GPU:   %[[COMM:.*]] = async.execute {
    // GPU:     comm.copy
    // GPU:     async.yield
    // GPU:   }
    // GPU:   async.await %[[COMP]] : !async.token
    // GPU:   async.await %[[COMM]] : !async.token
    // GPU:   async.yield
    // GPU: }
    // GPU: async.await %[[S2]] : !async.token
    // GPU-NOT: sched.pipeline
    // GPU-NOT: sched.concurrent
    // GPU-NOT: comm.stream
    %e = comm.stream %w_ssd, %w_hbm {engine = #comm.engine<dma>} : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
    sched.wait %e : !sched.token

    sched.pipeline {
      sched.stage "prepare" {
        stor.pack %t into %a_hbm : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        sched.yield
      }
      sched.stage "execute" {
        sched.concurrent {
          %tc = sched.task {
            %w = stor.unpack %w_hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
            %a = stor.unpack %a_hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
            %y = comp.elemwise %a {kind = #comp.elemwise<silu>} : tensor<4xf32> -> tensor<4xf32>
            sched.yield
          }
          %ts = sched.task {
            %spill = comm.stream %a_hbm, %a_ssd {engine = #comm.engine<dma>} : !stor.buffer<tensor<4xf32>, hbm>, !stor.buffer<tensor<4xf32>, ssd> -> !sched.token
            sched.yield
          }
          sched.yield
        }
        sched.yield
      }
      sched.yield
    }

    %out = stor.unpack %a_hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return %out : tensor<4xf32>
  }

  // SSD → DRAM → HBM (device-like). Two Token SW edges; no new construct.
  // CPU-LABEL: func.func @ssd_dram_hbm_hops
  // MAP-LABEL: func.func @ssd_dram_hbm_hops
  // GPU-LABEL: func.func @ssd_dram_hbm_hops
  func.func @ssd_dram_hbm_hops(%t: tensor<4xf32>) -> tensor<4xf32> {
    %obj = stor.object : !stor.object<tensor<4xf32>>
    %ssd = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %dram = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, dram>
    %hbm = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %t into %ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
    // CPU: memref.alloc() : memref<4xf32, 4>
    // CPU: memref.alloc() : memref<4xf32, 2>
    // CPU: memref.alloc() : memref<4xf32, 3>
    // CPU: memref.copy
    // CPU: memref.copy
    // CPU-NOT: sched.wait
    //
    // MAP: memref.alloc() : memref<4xf32, 100>
    // MAP: memref.alloc() : memref<4xf32, 2>
    // MAP: memref.alloc() : memref<4xf32, 9>
    // MAP: memref.copy
    // MAP-NOT: memref<4xf32, 4>
    // MAP-NOT: memref<4xf32, 3>
    //
    // GPU: %[[E0:.*]] = async.execute {
    // GPU:   comm.copy
    // GPU:   async.yield
    // GPU: }
    // GPU: async.await %[[E0]] : !async.token
    // GPU: %[[E1:.*]] = async.execute {
    // GPU:   comm.copy
    // GPU:   async.yield
    // GPU: }
    // GPU: async.await %[[E1]] : !async.token
    // GPU: stor.unpack
    // GPU-NOT: comm.stream
    // GPU-NOT: sched.wait
    %e0 = comm.stream %ssd, %dram {engine = #comm.engine<dma>} : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, dram> -> !sched.token
    sched.wait %e0 : !sched.token
    %e1 = comm.stream %dram, %hbm {engine = #comm.engine<dma>} : !stor.buffer<tensor<4xf32>, dram>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
    sched.wait %e1 : !sched.token
    %out = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return %out : tensor<4xf32>
  }
}
