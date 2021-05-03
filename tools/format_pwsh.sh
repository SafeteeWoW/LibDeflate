#!/bin/bash
# Reformat pwsh files (powershell script) in this repository
# Tool used is PowerShell-Beautifier: https://github.com/DTW-DanWard/PowerShell-Beautifier
# For tool installation and version used, see .github/workflows/format.yml
# This script is also used in CI. Edit with CAUTION!

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"

pwsh -Command "@(git ls-files -c -o --exclude-standard '*.ps1' | xargs -t -n 1 -I __ bash -c 'if [[ -e \"__\" ]]; then echo \"__\"; fi') | Edit-DTWBeautifyScript -NewLine LF"
