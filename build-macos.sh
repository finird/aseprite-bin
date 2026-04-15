#!/usr/bin/env bash

set -euo pipefail

for cmd in git curl cmake ninja python3 unzip; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $cmd"
    exit 1
  }
done

if [ ! -d aseprite ]; then
  git clone --recursive --tags https://github.com/aseprite/aseprite.git aseprite
else
  git -C aseprite fetch --tags
fi

if [ -z "${ASEPRITE_VERSION:-}" ]; then
  ASEPRITE_VERSION="$(git -C aseprite tag --sort=creatordate | tail -n 1)"
fi

if [ -z "$ASEPRITE_VERSION" ]; then
  echo "ERROR: failed to determine ASEPRITE_VERSION"
  exit 1
fi

echo "building $ASEPRITE_VERSION"

git -C aseprite clean -fdx
git -C aseprite submodule foreach --recursive git clean -xfd
git -C aseprite fetch --depth=1 --no-tags origin "$ASEPRITE_VERSION":"refs/remotes/origin/$ASEPRITE_VERSION"
git -C aseprite reset --hard "origin/$ASEPRITE_VERSION"
git -C aseprite submodule update --init --recursive

python3 <<PY
import os
from pathlib import Path

path = Path("aseprite/src/ver/CMakeLists.txt")
content = path.read_text()
path.write_text(content.replace("1.x-dev", os.environ["ASEPRITE_VERSION"][1:]))
PY

if [ -f aseprite/laf/misc/skia-tag.txt ]; then
  SKIA_VERSION="$(cat aseprite/laf/misc/skia-tag.txt)"
else
  if [[ "$ASEPRITE_VERSION" == *beta* ]]; then
    SKIA_VERSION="m124-08a5439a6b"
  else
    SKIA_VERSION="m102-861e4743af"
  fi
fi

if [ ! -d "skia-$SKIA_VERSION" ]; then
  mkdir -p "skia-$SKIA_VERSION"
  pushd "skia-$SKIA_VERSION" >/dev/null
  curl -fL -o "Skia-macOS-Release-x64.zip" "https://github.com/aseprite/skia/releases/download/$SKIA_VERSION/Skia-macOS-Release-x64.zip" || {
    echo "ERROR: failed to download Skia archive for $SKIA_VERSION"
    exit 1
  }
  unzip -q "Skia-macOS-Release-x64.zip"
  popd >/dev/null
fi

rm -rf build

cmake \
  -G Ninja \
  -S aseprite \
  -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DENABLE_CCACHE=OFF \
  -DOPENSSL_USE_STATIC_LIBS=TRUE \
  -DLAF_BACKEND=skia \
  -DSKIA_DIR="$PWD/skia-$SKIA_VERSION" \
  -DSKIA_LIBRARY_DIR="$PWD/skia-$SKIA_VERSION/out/Release-x64" \
  -DSKIA_LIBRARY="$PWD/skia-$SKIA_VERSION/out/Release-x64/libskia.a"

ninja -C build aseprite

rm -rf "aseprite-$ASEPRITE_VERSION"
mkdir -p "aseprite-$ASEPRITE_VERSION"
echo "# This file is here so Aseprite behaves as a portable program" >"aseprite-$ASEPRITE_VERSION/aseprite.ini"
cp -R aseprite/docs "aseprite-$ASEPRITE_VERSION/docs"
cp build/bin/aseprite "aseprite-$ASEPRITE_VERSION/"
cp -R build/bin/data "aseprite-$ASEPRITE_VERSION/data"

if [ -n "${GITHUB_WORKFLOW:-}" ]; then
  rm -rf github
  mkdir -p github
  mv "aseprite-$ASEPRITE_VERSION" github/
  echo "ASEPRITE_VERSION=$ASEPRITE_VERSION" >>"$GITHUB_OUTPUT"
fi
