add_mlir_dialect(ScheduleOps sched)
add_mlir_doc(ScheduleDialect ScheduleDialect Schedule/ -gen-dialect-doc)
add_mlir_doc(ScheduleOps ScheduleOps Schedule/ -gen-op-doc)

set(LLVM_TARGET_DEFINITIONS ScheduleInterfaces.td)
mlir_tablegen(ScheduleInterfaces.h.inc -gen-op-interface-decls)
mlir_tablegen(ScheduleInterfaces.cpp.inc -gen-op-interface-defs)
add_public_tablegen_target(S2C2ScheduleInterfacesIncGen)
