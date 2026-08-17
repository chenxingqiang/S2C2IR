# -*- Python -*-

import os

import lit.formats
from lit.llvm import llvm_config

config.name = "S2C2"
config.test_format = lit.formats.ShTest(not llvm_config.use_lit_shell)
config.suffixes = [".mlir"]
config.test_source_root = os.path.dirname(__file__)
config.test_exec_root = os.path.join(config.s2c2_obj_root, "test")
config.s2c2_tools_dir = os.path.join(config.s2c2_obj_root, "bin")

config.substitutions.append(("%PATH%", config.environment["PATH"]))
config.substitutions.append(("%shlibext", config.llvm_shlib_ext))

llvm_config.with_system_environment(["HOME", "INCLUDE", "LIB", "TMP", "TEMP"])
llvm_config.use_default_substitutions()

config.excludes = ["Inputs", "CMakeLists.txt", "README.txt", "LICENSE.txt"]

llvm_config.with_environment("PATH", config.llvm_tools_dir, append_path=True)

tool_dirs = [config.s2c2_tools_dir, config.llvm_tools_dir]
tools = ["s2c2-opt", "s2c2-translate"]
llvm_config.add_tool_substitutions(tools, tool_dirs)
