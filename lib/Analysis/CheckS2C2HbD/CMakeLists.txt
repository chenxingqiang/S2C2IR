add_mlir_library(S2C2CheckHbD
  CheckS2C2HbD.cpp
  LowerS2C2HbD.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2

  DEPENDS
  S2C2ConversionPassIncGen

  LINK_LIBS PUBLIC
  S2C2Comm
  S2C2Schedule
  S2C2Storage
  MLIRFuncDialect
  MLIRIR
  MLIRPass
  MLIRSCFDialect
  MLIRShardDialect
)
