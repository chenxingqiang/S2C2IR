find_package(MPI REQUIRED COMPONENTS CXX)

set(LLVM_LINK_COMPONENTS
  Support
  )

get_property(dialect_libs GLOBAL PROPERTY MLIR_DIALECT_LIBS)

add_llvm_executable(s2c2-dist-runtime
  s2c2-dist-runtime.cpp
  )
llvm_update_compile_flags(s2c2-dist-runtime)
target_compile_definitions(s2c2-dist-runtime PRIVATE OMPI_SKIP_MPICXX=1)
target_link_libraries(s2c2-dist-runtime
  PRIVATE
  ${dialect_libs}
  MLIRFuncDialect
  MLIRIR
  MLIRParser
  MLIRShardDialect
  MLIRSupport
  MPI::MPI_CXX
  S2C2Comm
  S2C2ExecutionModel
  S2C2Schedule
  S2C2Storage
  )

mlir_check_link_libraries(s2c2-dist-runtime)
