#!/bin/bash
# Run huge tests. Not in CI
# Before run this script
# download required data by download_huge_data.sh

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
luajit tests/Test.lua HugeTests --verbose
