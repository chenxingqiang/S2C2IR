// RUN: clang++ -std=c++17 -I%S/../../runtime/cuda %S/ssd_unescape_test.cpp -o %t
// RUN: %t | FileCheck %s
// CHECK: ssd-unescape PASS
