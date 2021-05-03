#!/bin/bash
# Reformat sh files (bash script) in this repository
# Tool used is shfmt: https://github.com/mvdan/sh
# For tool installation and version used, see .github/workflows/format.yml
# This script is also used in CI. Edit with CAUTION!

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
git ls-files -c -o --exclude-standard -z '*.sh' | xargs -0 -P 0 -t -n 1 -I {} bash -c 'if [[ -e "{}" ]]; then shfmt -i 2 -w "{}"; fi'
