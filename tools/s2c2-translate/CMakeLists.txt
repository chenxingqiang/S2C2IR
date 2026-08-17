set(LLVM_LINK_COMPONENTS
  Support
  )

get_property(dialect_libs GLOBAL PROPERTY MLIR_DIALECT_LIBS)
get_property(translation_libs GLOBAL PROPERTY MLIR_TRANSLATION_LIBS)

add_llvm_executable(s2c2-translate
  s2c2-translate.cpp
  )
llvm_update_compile_flags(s2c2-translate)
target_link_libraries(s2c2-translate
  PRIVATE
  ${dialect_libs}
  ${translation_libs}
  MLIRIR
  MLIRParser
  MLIRPass
  MLIRTranslateLib
  MLIRSupport
  S2C2Storage
  S2C2Compute
  S2C2Comm
  S2C2Schedule
  )

mlir_check_link_libraries(s2c2-translate)
