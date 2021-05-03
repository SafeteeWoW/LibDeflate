#!/bin/bash
# Reformat all kinds of text files in this repository
# For tools and version used, see .github/workflows/format.yml

set -euxo pipefail

function ErrorHandler() {
  local code="$1"
  local parent_lineno="$2"
  echo "error on or near line ${parent_lineno} with exit code ${code}" >&2
  exit "${code}"
}

function main() {
  trap 'ErrorHandler $? ${LINENO}' ERR
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  "${SHELL}" "${script_dir}/format_lua.sh"
  "${SHELL}" "${script_dir}/format_doc.sh"
  "${SHELL}" "${script_dir}/format_sh.sh"
  "${SHELL}" "${script_dir}/format_c.sh"
  "${SHELL}" "${script_dir}/format_pwsh.sh"
  "${SHELL}" "${script_dir}/format_py.sh"
}

main
