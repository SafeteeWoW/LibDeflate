#!/bin/bash
# Run decompress lua error test
# This is to ensure malformed compressed data
# will not generate Lua Error

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
luajit tests/Test.lua DecompressLuaErrorTest --verbose
