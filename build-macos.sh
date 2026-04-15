#!/usr/bin/env bash
set -euo pipefail

# *** dependencies

if ! command -v brew &>/dev/null; then
  echo "ERROR: Homebrew not found"
  exit 1
fi

if ! command -v git &>/dev/null; then
  echo "ERROR: git not found"
  exit 1
fi

if ! command -v cmake &>/dev/null; then
  brew install cmake
fi

if ! command -v ninja &>/dev/null; then
  brew install ninja
fi

if ! command -v python3 &>/dev/null; then
  brew install python3
fi


# *** detect architecture

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
  SKIA_ARCH=arm64
  CMAKE_ARCH=arm64
else
  SKIA_ARCH=x64
  CMAKE_ARCH=x86_64
fi


# *** clone aseprite repo

if [ ! -d aseprite ]; then
  git clone --recursive --tags https://github.com/aseprite/aseprite.git aseprite
else
  git -C aseprite fetch --tags
fi


# *** get name of newest tag

if [ -z "${ASEPRITE_VERSION:-}" ]; then
  ASEPRITE_VERSION=$(git -C aseprite tag --sort=creatordate | tail -1)
fi

echo "building $ASEPRITE_VERSION"


# *** update local aseprite repo to selected tag

git -C aseprite clean --quiet -fdx
git -C aseprite submodule foreach --recursive git clean -xfd
git -C aseprite fetch --quiet --depth=1 --no-tags origin "$ASEPRITE_VERSION:refs/remotes/origin/$ASEPRITE_VERSION"
git -C aseprite reset --quiet --hard "origin/$ASEPRITE_VERSION"
git -C aseprite submodule update --init --recursive

python3 -c "v = open('aseprite/src/ver/CMakeLists.txt').read(); open('aseprite/src/ver/CMakeLists.txt', 'w').write(v.replace('1.x-dev', '${ASEPRITE_VERSION:1}'))"


# *** download skia

if [ -f aseprite/laf/misc/skia-tag.txt ]; then
  SKIA_VERSION=$(cat aseprite/laf/misc/skia-tag.txt)
elif [[ "$ASEPRITE_VERSION" == *"beta"* ]]; then
  SKIA_VERSION=m124-08a5439a6b
else
  SKIA_VERSION=m102-861e4743af
fi

if [ ! -d "skia-$SKIA_VERSION" ]; then
  mkdir "skia-$SKIA_VERSION"
  pushd "skia-$SKIA_VERSION"
  curl -sfLO "https://github.com/aseprite/skia/releases/download/$SKIA_VERSION/Skia-macOS-Release-$SKIA_ARCH.zip"
  unzip -q "Skia-macOS-Release-$SKIA_ARCH.zip"
  popd
fi


# *** build aseprite

rm -rf build

cmake                                                   \
  -G Ninja                                              \
  -S aseprite                                           \
  -B build                                              \
  -DCMAKE_BUILD_TYPE=Release                            \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5                    \
  -DCMAKE_OSX_ARCHITECTURES=$CMAKE_ARCH                 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-10.15}   \
  -DENABLE_CCACHE=OFF                                   \
  -DOPENSSL_USE_STATIC_LIBS=TRUE                        \
  -DLAF_BACKEND=skia                                    \
  -DSKIA_DIR="$PWD/skia-$SKIA_VERSION"                 \
  -DSKIA_LIBRARY_DIR="$PWD/skia-$SKIA_VERSION/out/Release-$SKIA_ARCH"

ninja -C build


# *** create output folder

mkdir -p "aseprite-$ASEPRITE_VERSION"
echo "# This file is here so Aseprite behaves as a portable program" > "aseprite-$ASEPRITE_VERSION/aseprite.ini"
cp -r aseprite/docs "aseprite-$ASEPRITE_VERSION/docs"
cp build/bin/aseprite "aseprite-$ASEPRITE_VERSION/"
cp -r build/bin/data "aseprite-$ASEPRITE_VERSION/data"

if [ -n "${GITHUB_WORKFLOW:-}" ]; then
  mkdir -p github
  mv "aseprite-$ASEPRITE_VERSION" github/
  echo "ASEPRITE_VERSION=$ASEPRITE_VERSION" >> "$GITHUB_OUTPUT"
fi
