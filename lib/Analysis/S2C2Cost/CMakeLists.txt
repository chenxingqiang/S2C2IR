add_mlir_library(S2C2Cost
  S2C2Cost.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2

  DEPENDS
  S2C2ConversionPassIncGen

  LINK_LIBS PUBLIC
  S2C2Comm
  S2C2Compute
  S2C2Schedule
  S2C2Storage
  MLIRFuncDialect
  MLIRIR
  MLIRPass
)
