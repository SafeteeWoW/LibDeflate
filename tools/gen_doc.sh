#!/bin/bash
# Generate doc
# "LDoc" is the required tool
# See .github/workflows/gen_doc.yml for the exact tool version used

set -euxo pipefail

ErrorHandler() {
  local exit_code="$1"
  local parent_lineno="$2"
  echo "error on or near line ${parent_lineno}; exiting with status ${exit_code}"
  exit "${exit_code}"
}

main() {
  trap 'ErrorHandler $? ${LINENO}' ERR
  cd "$(git rev-parse --show-toplevel)"
  cd docs

  ldoc --date "" .
}

main
