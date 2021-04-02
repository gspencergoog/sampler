#!/bin/bash
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Fast fail the script on failures.
set -e

# This script builds the executabe for this platform and copies it into 
# the bin directory.
unset CDPATH

# So that developers can run this script from anywhere and it will work as
# expected.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

function get_platform() {
  # Only works on macos, linux, and Windows (under GitBash) so that's all we check for.
  local uname=$(uname --operating-system 2> /dev/null || uname -a)
  case "$uname" in
    Darwin*)
      echo "macos"
      ;;
    *[Ll]inux*)
      echo "linux"
      ;;
    *[Mm][Ss]ys*)
      echo "windows"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

function install_result() {
  local platform="$1"
  git rm -rf "$REPO_DIR/bin/$platform"
  rm -rf "$REPO_DIR/bin/$platform"
  mkdir -p "$REPO_DIR/bin/$platform"
  case "$platform" in
    linux)
      cp -r "build/linux/x64/release/bundle/*" "$REPO_DIR/bin/linux"
      ;;
    macos)
      cp -r "build/macos/Build/Products/Release/sampler.app" "$REPO_DIR/bin/macos/sampler.app"
      ;;
    windows)
      cp -r "build/windows/runner/Release/*" "$REPO_DIR/bin/windows"
      ;;
    *)
      echo "Unknown platform $platform"
      ;;
   esac
  git add "$REPO_DIR/bin/$platform"
}

platform=$(get_platform)

cd "$REPO_DIR/packages/sampler"
flutter build $platform --release && install_result $platform
