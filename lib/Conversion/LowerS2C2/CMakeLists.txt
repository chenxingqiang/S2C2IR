add_mlir_conversion_library(S2C2Lower
  LowerS2C2.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/s2c2

  DEPENDS
  S2C2ConversionPassIncGen

  LINK_LIBS PUBLIC
  S2C2SequentializeSchedule
  S2C2StorToMemref
  S2C2ToLinalg
  MLIRIR
  MLIRPass
)
