add_subdirectory(Storage)
add_subdirectory(Compute)
add_subdirectory(Comm)
add_subdirectory(Schedule)

set(LLVM_TARGET_DEFINITIONS S2C2Passes.td)
mlir_tablegen(S2C2Passes.h.inc --gen-pass-decls)
add_public_tablegen_target(S2C2ConversionPassIncGen)
add_mlir_doc(S2C2Passes S2C2Passes S2C2/ -gen-pass-doc)
