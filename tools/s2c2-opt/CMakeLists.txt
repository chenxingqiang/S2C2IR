get_property(dialect_libs GLOBAL PROPERTY MLIR_DIALECT_LIBS)
get_property(conversion_libs GLOBAL PROPERTY MLIR_CONVERSION_LIBS)
set(LIBS
        ${dialect_libs}
        ${conversion_libs}
        MLIROptLib
        S2C2Storage
        S2C2Compute
        S2C2Comm
        S2C2Schedule
        S2C2StorToMemref
        S2C2ExpandComposites
        S2C2ToLinalg
        S2C2SequentializeSchedule
        S2C2Lower
        S2C2CheckExecution
        )
add_llvm_executable(s2c2-opt s2c2-opt.cpp)

llvm_update_compile_flags(s2c2-opt)
target_link_libraries(s2c2-opt PRIVATE ${LIBS})

mlir_check_all_link_libraries(s2c2-opt)
