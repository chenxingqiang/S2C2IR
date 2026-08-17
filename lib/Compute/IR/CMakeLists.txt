add_mlir_dialect_library(S2C2Compute
  ComputeDialect.cpp
  ComputeOps.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2/Compute

  DEPENDS
  MLIRComputeOpsIncGen
  S2C2ComputeAttrsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSideEffectInterfaces
  MLIRTensorDialect
)
