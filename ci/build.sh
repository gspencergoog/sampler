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

function install_result() (
  local platform="$1"
  cd "$REPO_DIR/bin" || return 1
  git rm -rf "$platform" 2>/dev/null || true
  rm -rf "$platform" || true
  mkdir -p "$platform"
  case "$platform" in
    linux)
      mkdir -p "linux/sampler"
      cp -r "$REPO_DIR"/packages/sampler/build/linux/x64/release/bundle/* "linux/sampler"
      (cd linux; tar cvJf "../$platform.tar.xz" "sampler")
      git add "$platform.tar.xz"
      ;;
    macos)
      cp -r "$REPO_DIR/packages/sampler/build/macos/Build/Products/Release/sampler.app" "macos/sampler.app"
      rm -f "$platform.zip" || true
      (cd macos; zip -r "../$platform.zip" sampler.app)
      git add "$platform.zip"
      ;;
    windows)
      mkdir -p "windows/sampler"
      cp -r "$REPO_DIR"/packages/sampler/build/windows/runner/Release/* "windows/sampler"
      rm -f "$platform.zip" || true
      (cd windows; 7z a -r "../$platform.zip" "sampler") 1> /dev/null 2>&1 || echo "Failed to zip Windows binary."
      git add "$platform.zip"
      ;;
    *)
      echo "Unknown platform $platform"
      ;;
  esac
  cd "$REPO_DIR"
  git add "bin/$platform"
)

platform=$(get_platform)

cd "$REPO_DIR/packages/sampler"
flutter build $platform --release && install_result $platform
