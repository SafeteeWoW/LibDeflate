#!/bin/bash
# Reformat Lua files in this repository
# Tool used is LuaFormatter: https://github.com/Koihik/LuaFormatter
# For tool installation and version used, see .github/workflows/format.yml
# This script is also used in CI. Edit with CAUTION!

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
git ls-files -c -o --exclude-standard -z '*.lua' | xargs -0 -P 0 -t -n 1 -I {} bash -c 'if [[ -e "{}" ]]; then lua-format -i -v; fi'
