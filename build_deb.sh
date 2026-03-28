#!/bin/bah
set -e
cmake -B build -G Ninja -S . -DBUILD_DOCS=OFF
ninja -C build
cpack -G DEB --config ./build/CPackConfig.cmake
echo "Going to install the new Sunshine DEB file..."
sudo apt install --reinstall ./build/cpack_artifacts/Sunshine.deb
echo "Done."
