#!/bin/bash
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Fast fail the script on failures.
set -e

# This script checks to make sure that everything is formatted correctly.

unset CDPATH

# So that developers can run this script from anywhere and it will work as
# expected.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

function format() {
  local dir="$1"
  shift
  dartfmt_dirs=(lib test example)
#  echo "(cd \"$dir\" && dartfmt --line-length=100 \"$@\" ${dartfmt_dirs[@]})"
  (cd "$dir" && dartfmt --line-length=100 "$@" ${dartfmt_dirs[@]})
}

# Make sure dartfmt is run on everything
function check_format() {
  local dir="$1"
  shift
  echo "Checking dartfmt in $dir..."
  local needs_dartfmt="$(format "$dir" -n "$@")"
  if [[ -n "$needs_dartfmt" ]]; then
    echo "FAILED"
    echo "$needs_dartfmt"
    echo ""
    echo "Fix formatting with: $REPO_DIR/ci/format.sh --fix"
    exit 1
  fi
  echo "PASSED"
}

function fix_formatting() {
  local dir="$1"
  shift
  echo "Fixing formatting in $dir..."
  format "$dir" "$@" -w
}

fix=0
if [[ "$1" == "--fix" ]]; then
  shift
  fix=1
fi

cd "$REPO_DIR/packages"
for dir in $(find * -maxdepth 0 -type d); do
  if [[ $fix == 1 ]]; then
    fix_formatting "$dir" "$@"
  else
    check_format "$dir" "$@"
  fi
done
