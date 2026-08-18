// RUN: s2c2-opt %s --check-s2c2-execution | FileCheck %s

// E5: Concurrent with no events. Both sibling orders are legal schedules.
module {
  // CHECK-LABEL: func.func @e5_ab
  func.func @e5_ab() {
    sched.concurrent {
      %ta = sched.task {
        sched.yield
      }
      %tb = sched.task {
        sched.yield
      }
      sched.yield
    }
    return
  }

  // CHECK-LABEL: func.func @e5_ba
  func.func @e5_ba() {
    sched.concurrent {
      %tb = sched.task {
        sched.yield
      }
      %ta = sched.task {
        sched.yield
      }
      sched.yield
    }
    return
  }
}
