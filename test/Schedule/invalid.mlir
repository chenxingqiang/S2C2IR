// RUN: s2c2-opt %s -split-input-file -verify-diagnostics

func.func @task_yield_mismatch(%v: tensor<4xf32>) {
  // expected-error@+1 {{yield operands must match result types}}
  %t = sched.task {
    sched.yield %v : tensor<4xf32>
  }
  return
}

// -----

func.func @concurrent_rejects_nested_pipeline() {
  // expected-error@+1 {{body may only contain sched.task ops before the terminator}}
  sched.concurrent {
    sched.pipeline {
      sched.yield
    }
    sched.yield
  }
  return
}

// -----

func.func @concurrent_rejects_nested_concurrent() {
  // expected-error@+1 {{body may only contain sched.task ops before the terminator}}
  sched.concurrent {
    sched.concurrent {
      sched.yield
    }
    sched.yield
  }
  return
}

// -----

func.func @concurrent_rejects_bare_ops(%v: tensor<4xf32>) -> tensor<4xf32> {
  // expected-error@+1 {{body may only contain sched.task ops before the terminator}}
  %y = sched.concurrent -> tensor<4xf32> {
    %t = sched.task {
      sched.yield
    }
    sched.wait %t : !sched.token
    sched.yield %v : tensor<4xf32>
  }
  return %y : tensor<4xf32>
}
