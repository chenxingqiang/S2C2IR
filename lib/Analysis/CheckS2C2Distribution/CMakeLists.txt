add_mlir_library(S2C2CheckDistribution
  CheckS2C2Distribution.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2

  DEPENDS
  S2C2ConversionPassIncGen

  LINK_LIBS PUBLIC
  S2C2Dist
  S2C2Storage
  MLIRFuncDialect
  MLIRIR
  MLIRPass
  MLIRShardDialect
)
