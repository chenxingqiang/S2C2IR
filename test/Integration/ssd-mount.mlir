// Host mount lookup for --ssd-dir. No CUDA. No analyzer change.
// A relative directory is resolved before the lookup. The root stays `/`.
// Overlay reports nvme only when the upperdir sits on a mount whose
// source names nvme. Do not FileCheck microseconds.
// RUN: clang++ -std=c++17 -I%S/../../runtime/cuda %S/ssd_mount_test.cpp -o %t
// RUN: %t | FileCheck %s

module {
}

// CHECK: ssd-mount PASS
