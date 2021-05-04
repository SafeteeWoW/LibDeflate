#!/bin/bash
# Run test suite
# This is the same as CI,
# Except luajit is used here for development efficiency.

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
luajit tests/Test.lua --verbose --shuffle
