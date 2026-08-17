#!/usr/bin/env bash
# Build and install LLVM/MLIR 20.1.8 into third_party/llvm-install.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLVM_TAG="${LLVM_TAG:-llvmorg-20.1.8}"
SRC="${ROOT}/third_party/llvm-project"
BUILD="${ROOT}/third_party/llvm-build"
PREFIX="${ROOT}/third_party/llvm-install"
JOBS="${JOBS:-$(nproc)}"

mkdir -p "${ROOT}/third_party"
if [[ ! -d "${SRC}/.git" ]]; then
  git clone --depth 1 --branch "${LLVM_TAG}" https://github.com/llvm/llvm-project.git "${SRC}"
fi

cmake -G Ninja -S "${SRC}/llvm" -B "${BUILD}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DLLVM_ENABLE_PROJECTS=mlir \
  -DLLVM_TARGETS_TO_BUILD=Native \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_INSTALL_UTILS=ON \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DMLIR_ENABLE_BINDINGS_PYTHON=OFF \
  -DLLVM_PARALLEL_LINK_JOBS=1

cmake --build "${BUILD}" --target install -j "${JOBS}"
echo "Installed MLIR to ${PREFIX}"
echo "Configure S2C2IR with:"
echo "  cmake -G Ninja -S . -B build \\
    -DMLIR_DIR=${PREFIX}/lib/cmake/mlir \\
    -DLLVM_EXTERNAL_LIT=${PREFIX}/bin/llvm-lit"
