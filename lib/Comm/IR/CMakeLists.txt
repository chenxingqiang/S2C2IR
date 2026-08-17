add_mlir_dialect_library(S2C2Comm
  CommDialect.cpp
  CommOps.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2/Comm

  DEPENDS
  MLIRCommOpsIncGen
  S2C2CommAttrsIncGen
  MLIRStorageOpsIncGen
  MLIRScheduleOpsIncGen
  S2C2ScheduleInterfacesIncGen

  LINK_LIBS PUBLIC
  S2C2Storage
  S2C2Schedule
  MLIRIR
  MLIRSideEffectInterfaces
)
