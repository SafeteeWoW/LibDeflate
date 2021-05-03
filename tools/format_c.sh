#!/bin/bash
# Reformat C/C++ files in this repository
# Tool used is clang-format
# For tool installation and version used, see .github/workflows/format.yml
# This script is also used in CI. Edit with CAUTION!

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
git ls-files -c -o --exclude-standard -z '*.c' '*.cc' '*.cpp' | xargs -0 -P 0 -t -n 1 clang-format -i
