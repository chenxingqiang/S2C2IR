# Host protocol only. Do not link LLVM / MLIR / CUDA.
add_executable(s2c2-cuda-adapter s2c2-cuda-adapter.cpp)
target_include_directories(s2c2-cuda-adapter PRIVATE
  ${S2C2_SOURCE_DIR}/runtime/cuda)
set_target_properties(s2c2-cuda-adapter PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${LLVM_RUNTIME_OUTPUT_INTDIR}")
