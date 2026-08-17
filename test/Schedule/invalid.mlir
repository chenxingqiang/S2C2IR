// RUN: s2c2-opt %s -split-input-file -verify-diagnostics

func.func @task_yield_mismatch(%v: tensor<4xf32>) {
  // expected-error@+1 {{yield operands must match result types}}
  %t = sched.task {
    sched.yield %v : tensor<4xf32>
  }
  return
}
