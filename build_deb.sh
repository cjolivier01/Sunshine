#!/bin/bash
set -e
# Sunshine needs GCC 13 or newer for std::format. CUDA 12.0 still needs
# an older host compiler. Allow callers to override either toolchain.
export CC="${CC:-gcc-13}"
export CXX="${CXX:-g++-13}"
export CUDAHOSTCXX="${CUDAHOSTCXX:-g++-12}"
# Prefer the C++ compiler's runtime over the older CUDA host compiler's runtime.
cxx_library_dir=$(dirname "$("$CXX" -print-file-name=libstdc++.a)")
# A system DEB must not link against libraries from an active Conda environment.
ignore_prefixes=()
if [[ -n "${CONDA_PREFIX:-}" ]]; then
    ignore_prefixes+=("$CONDA_PREFIX")
fi
if [[ -n "${CONDA_EXE:-}" ]]; then
    ignore_prefixes+=("$(dirname "$(dirname "$CONDA_EXE")")")
fi
cmake --fresh -B build -G Ninja -S . -DBUILD_DOCS=OFF \
    "-DCMAKE_EXE_LINKER_FLAGS=-L\"$cxx_library_dir\" ${LDFLAGS:-}" \
    "-DCMAKE_IGNORE_PREFIX_PATH=$(IFS=';'; echo "${ignore_prefixes[*]}")"
ninja -C build
cpack -G DEB --config ./build/CPackConfig.cmake
echo "Going to install the new Sunshine DEB file..."
sudo apt install -y --reinstall ./build/cpack_artifacts/Sunshine.deb
echo "Done."
