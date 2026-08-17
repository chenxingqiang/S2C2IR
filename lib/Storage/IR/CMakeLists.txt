add_mlir_dialect_library(S2C2Storage
  StorageDialect.cpp
  StorageOps.cpp
  StorageTypes.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2/Storage

  DEPENDS
  MLIRStorageOpsIncGen
  S2C2StorageAttrsIncGen
  S2C2StorageInterfacesIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSideEffectInterfaces
  MLIRTensorDialect
)
