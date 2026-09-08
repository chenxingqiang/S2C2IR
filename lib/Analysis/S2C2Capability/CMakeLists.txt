add_mlir_library(S2C2Capability
  S2C2CapabilitySchedule.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2

  DEPENDS
  S2C2ConversionPassIncGen

  LINK_LIBS PUBLIC
  S2C2Comm
  S2C2Compute
  S2C2Schedule
  S2C2Storage
  MLIRArithDialect
  MLIRFuncDialect
  MLIRIR
  MLIRPass
  MLIRSCFDialect
)

target_compile_definitions(S2C2Capability PRIVATE
  "S2C2_SOURCE_DIR=\"${PROJECT_SOURCE_DIR}\"")
