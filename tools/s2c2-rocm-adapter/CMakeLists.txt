# Host protocol only. Do not link LLVM / MLIR / HIP.
add_executable(s2c2-rocm-adapter s2c2-rocm-adapter.cpp)
target_include_directories(s2c2-rocm-adapter PRIVATE
  ${S2C2_SOURCE_DIR}/runtime/rocm)
set_target_properties(s2c2-rocm-adapter PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${LLVM_RUNTIME_OUTPUT_INTDIR}")
