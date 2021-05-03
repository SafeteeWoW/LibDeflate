#!/bin/bash
# Reformat python files in this repository
# Tool used is yapf
# For tool installation and version used, see .github/workflows/format.yml
# This script is also used in CI. Edit with CAUTION!

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
yapf -i -r .
