#!/bin/bash
# Run quick tests. This should be less than 1min
# Run if you just want a sanity check

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
luajit tests/Test.lua TestBasicStrings --verbose
