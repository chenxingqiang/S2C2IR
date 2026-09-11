add_mlir_conversion_library(S2C2StorToMemref
  StorToMemref.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2

  DEPENDS
  S2C2ConversionPassIncGen

  LINK_LIBS PUBLIC
  S2C2Comm
  S2C2Schedule
  S2C2Storage
  MLIRBufferizationDialect
  MLIRFuncDialect
  MLIRIR
  MLIRMemRefDialect
  MLIRPass
  MLIRSCFDialect
  MLIRSCFTransforms
  MLIRTransforms
)
