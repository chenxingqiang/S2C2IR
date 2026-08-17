add_mlir_dialect_library(S2C2Schedule
  ScheduleDialect.cpp
  ScheduleOps.cpp
  ScheduleTypes.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2/Schedule

  DEPENDS
  MLIRScheduleOpsIncGen
  S2C2ScheduleInterfacesIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRControlFlowInterfaces
  MLIRSideEffectInterfaces
)
