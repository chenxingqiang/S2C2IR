add_mlir_conversion_library(S2C2ToAsync
  S2C2ToAsync.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2

  DEPENDS
  S2C2ConversionPassIncGen

  LINK_LIBS PUBLIC
  S2C2Comm
  S2C2Schedule
  MLIRAsyncDialect
  MLIRFuncDialect
  MLIRIR
  MLIRPass
  MLIRTransforms
)
