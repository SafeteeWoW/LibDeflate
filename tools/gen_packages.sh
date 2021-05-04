#!/bin/bash
# Generate source packages. Luarocks is not used, using BigWigs packager.
# Create a files in .release folder called libdeflate-VERSION.zip
# VERSION is the commit id if not on tag, tag name otherwise
# Release zip file will contains "COMMIT" file,
# which contains the current full commit id

set -euxo pipefail

ErrorHandler() {
  local exit_code="$1"
  local parent_lineno="$2"
  echo "error on or near line ${parent_lineno}; exiting with status ${exit_code}"
  exit "${exit_code}"
}

GetFilename() {
  local commit="$(git rev-parse HEAD)"
  local prefix="libdeflate-"
  local tag="$(git describe --tags --exact-match ${commit} 2>/dev/null)"
  if [[ -n "${tag}" ]]; then
    echo "${prefix}${tag}"
  else
    echo "${prefix}${commit}"
  fi
}

MakePackage() {
  echo ">>>>> Creating Package."
  mkdir -p .release
  local filename="$1"
  if [[ -z "${filename}" ]]; then
    echo "No filename specified" >&2
  fi
  echo ">>>>> Creating WoW Package. Filename: ${filename}"
  local base_dir="$(pwd)/.release"
  local rel_dir="LibDeflate"
  local dir="${base_dir}/${rel_dir}"
  rm -rf "${base_dir}"
  mkdir -p "${base_dir}"
  git clone --depth=1 https://github.com/BigWigsMods/packager.git "${base_dir}/packager"
  local script="${base_dir}/packager/release.sh"
  bash "${script}" -d -u -n "${filename}" -r "${base_dir}"
  rm -rf "${dir}"
  rm -rf "${base_dir}/packager"
  echo ">>>>> Done Package generation."
}

main() {
  trap 'ErrorHandler $? ${LINENO}' ERR
  cd "$(git rev-parse --show-toplevel)"
  rm -rf .release
  local filename="$(GetFilename)"
  MakePackage "${filename}"
}

main
