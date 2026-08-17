configure_lit_site_cfg(
  ${CMAKE_CURRENT_SOURCE_DIR}/lit.site.cfg.py.in
  ${CMAKE_CURRENT_BINARY_DIR}/lit.site.cfg.py
  MAIN_CONFIG
  ${CMAKE_CURRENT_SOURCE_DIR}/lit.cfg.py
)

set(S2C2_TEST_DEPENDS
  s2c2-opt
  s2c2-translate
)
if(TARGET FileCheck)
  list(APPEND S2C2_TEST_DEPENDS FileCheck count not)
endif()

add_lit_testsuite(check-s2c2 "Running the S2C2 regression tests"
  ${CMAKE_CURRENT_BINARY_DIR}
  DEPENDS ${S2C2_TEST_DEPENDS}
)
set_target_properties(check-s2c2 PROPERTIES FOLDER "Tests")

add_lit_testsuites(S2C2 ${CMAKE_CURRENT_SOURCE_DIR} DEPENDS ${S2C2_TEST_DEPENDS})
