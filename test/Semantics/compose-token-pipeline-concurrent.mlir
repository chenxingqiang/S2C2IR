// RUN: s2c2-opt %s --check-s2c2-execution | FileCheck %s

// X1 (source): Token + Concurrent + Pipeline compose without interference.
//
//   SSD prefetch --SW/wait--> Pipeline
//        S1.pack --StageOrder--> S2
//        S2.compute ∥ S2.comm   (NoOrderingRequirement; distinct residencies)
//
// Reads that must be defined:
//   compute unpack(weights)     <- prefetch stream + wait (Token / SW)
//   compute unpack(activations) <- S1 pack (StageOrder)
//   comm stream src(activations)<- S1 pack (StageOrder)
//   parent unpack(activations)  <- pipeline completion (PO after Sk)
module {
  // CHECK-LABEL: func.func @compose_token_pipeline_concurrent
  func.func @compose_token_pipeline_concurrent(%t: tensor<4xf32>) -> tensor<4xf32> {
    %w_obj = stor.object : !stor.object<tensor<4xf32>>
    %a_obj = stor.object : !stor.object<tensor<4xf32>>
    %w_ssd = stor.materialize %w_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %w_hbm = stor.materialize %w_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %a_hbm = stor.materialize %a_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %a_ssd = stor.materialize %a_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>

    stor.pack %t into %w_ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
    %e = comm.stream %w_ssd, %w_hbm : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
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
            %spill = comm.stream %a_hbm, %a_ssd : !stor.buffer<tensor<4xf32>, hbm>, !stor.buffer<tensor<4xf32>, ssd> -> !sched.token
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
}
