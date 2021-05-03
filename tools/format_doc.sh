#!/bin/bash
# Reformat Markdown and YAML files in this repository
# Tool used is prettier: https://prettier.io/
# For tool installation and version used, see .github/workflows/format.yml
# This script is also used in CI. Edit with CAUTION!

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
git ls-files -c -o --exclude-standard -z '*.md' '*.yml' | xargs -0 -P 0 -t -n 1 -I {} bash -c 'if [[ -e "{}" ]]; then npx prettier -w "{}"; fi'
