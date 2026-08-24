# Host protocol only. Do not link LLVM / MLIR / CANN.
add_executable(s2c2-ascend-adapter s2c2-ascend-adapter.cpp)
target_include_directories(s2c2-ascend-adapter PRIVATE
  ${S2C2_SOURCE_DIR}/runtime/ascend)
set_target_properties(s2c2-ascend-adapter PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${LLVM_RUNTIME_OUTPUT_INTDIR}")
