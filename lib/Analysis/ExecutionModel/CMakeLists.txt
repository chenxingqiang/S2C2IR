add_mlir_library(S2C2ExecutionModel
  HBGraph.cpp
  RankContext.cpp
  CollectiveDependency.cpp
  EventDependency.cpp
  ValidityAnalysis.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2

  LINK_LIBS PUBLIC
  S2C2Comm
  S2C2Schedule
  S2C2Storage
  MLIRFuncDialect
  MLIRIR
  MLIRSCFDialect
  MLIRShardDialect
)
