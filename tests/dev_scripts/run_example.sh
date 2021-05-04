#!/bin/bash
# Run example

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
luajit examples/example.lua
