add_mlir_dialect_library(S2C2Dist
  DistDialect.cpp
  DistOps.cpp
  DistTypes.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2/Dist

  DEPENDS
  MLIRDistOpsIncGen
  S2C2DistEnumsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSupport
  MLIRSideEffectInterfaces
)
