#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${BUILD_DIR:-build}"
NODE_MAJOR="${NODE_MAJOR:-22}"

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo "nvm not found, installing to $NVM_DIR..."
  wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
fi

# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"

nvm install "$NODE_MAJOR" >/dev/null
nvm use --delete-prefix "$NODE_MAJOR" >/dev/null
hash -r

echo "Using node: $(node -v) ($(which node))"
echo "Using npm:  $(npm -v) ($(which npm))"

if command -v gcc-14 >/dev/null 2>&1 && command -v g++-14 >/dev/null 2>&1; then
  export CC=gcc-14
  export CXX=g++-14
  echo "Using compiler: $CC / $CXX"
fi

cmake -B "$BUILD_DIR" -G Ninja -S . -DBUILD_DOCS=OFF -DNPM:FILEPATH="$(which npm)"
PATH="$(dirname "$(which node)"):$PATH" ninja -C "$BUILD_DIR"

echo "Build complete."
