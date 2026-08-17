add_mlir_conversion_library(S2C2ToLinalg
  S2C2ToLinalg.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2

  DEPENDS
  S2C2ConversionPassIncGen

  LINK_LIBS PUBLIC
  S2C2Compute
  MLIRArithDialect
  MLIRFuncDialect
  MLIRIR
  MLIRLinalgDialect
  MLIRMathDialect
  MLIRPass
  MLIRTensorDialect
  MLIRTransforms
)
