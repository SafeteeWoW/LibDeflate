#!/bin/bash
# Upload generated docs to gh-pages branch
# Should only be run in CI, after doc has been generated

set -euxo pipefail

ErrorHandler() {
  local exit_code="$1"
  local parent_lineno="$2"
  echo "error on or near line ${parent_lineno}; exiting with status ${exit_code}"
  exit "${exit_code}"
}

SetCommitUsernameAndEmail() {
  local username="$(git log -n 1 HEAD --pretty=format:'%an')"
  local email="$(git log -n 1 HEAD --pretty=format:'%ae')"
  git config user.name "${username}"
  git config user.email "${email}"
}

CopyDocsToGhPagesBranch() {
  local tmpdir="$(mktemp --tmpdir -d tmp.XXXXXXXXXX)"
  origin_commit="$(git rev-parse HEAD)"
  rsync -va docs/ "${tmpdir}/"

  git fetch origin gh-pages
  git checkout gh-pages
  git clean . -dxf
  git rm -r -f .
  rsync -va "${tmpdir}/" ./
  git add --all --verbose .
  rm -rf "${tmpdir}"
}

Upload() {
  set +e
  git diff --cached --quiet
  if [[ $? -eq 0 ]]; then
    echo "No change. No upload is needed"
    return 0
  fi
  set -e

  git commit -m "Doc auto generated from commit ${origin_commit}"
  git push -u origin gh-pages
}

main() {
  trap 'ErrorHandler $? ${LINENO}' ERR
  cd "$(git rev-parse --show-toplevel)"

  SetCommitUsernameAndEmail
  CopyDocsToGhPagesBranch
  Upload
}

main
