#!/bin/bash
# Lint Lua code
# Tool used is Luacheck
# For tool installation and version used, see .github/workflows/lua_lint.yml
# This script is also used in CI. Edit with CAUTION!

set -euxo pipefail

luacheck -g -u .
