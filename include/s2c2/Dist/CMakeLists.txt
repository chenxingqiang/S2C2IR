add_mlir_dialect(DistOps dist)
add_mlir_doc(DistDialect DistDialect Dist/ -gen-dialect-doc)
add_mlir_doc(DistOps DistOps Dist/ -gen-op-doc)

set(LLVM_TARGET_DEFINITIONS DistEnums.td)
mlir_tablegen(DistEnums.h.inc -gen-enum-decls)
mlir_tablegen(DistEnums.cpp.inc -gen-enum-defs)
add_public_tablegen_target(S2C2DistEnumsIncGen)
