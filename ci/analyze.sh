#!/bin/bash
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Fast fail the script on failures.
set -e

# So cd doesn't print the path it changes to.
unset CDPATH

# So that developers can run this script from anywhere and it will work as
# expected.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

function analyze() (
  cd "$1"
  # Make sure we pass the analyzer
  echo "Checking dart analyzer in $PWD..."
  if ! fails_analyzer="$(find lib test -name "*.dart" -print0 | xargs -0 dartanalyzer --options "$REPO_DIR/analysis_options.yaml")"; then
    echo "FAILED"
    echo "$fails_analyzer"
    exit 1
  fi
  echo "PASSED"
)

cd "$REPO_DIR/packages"

for dir in $(find * -maxdepth 0 -type d); do
  analyze "$dir"
done
