#!/bin/bash
# Build zlib,
# and build reference programs (zdeflate, puff) in LibDeflate which depend on zlib
# LibDeflate requires these reference program for testing

set -euxo pipefail

ErrorHandler() {
  local exit_code="$1"
  local parent_lineno="$2"
  echo "error on or near line ${parent_lineno}; exiting with status ${exit_code}"
  exit "${exit_code}"
}

SetPlatform() {
  local uname_s="$(uname -s)"
  if [[ "${uname_s}" == "Linux" ]]; then
    platform="linux"
  elif [[ "${uname_s}" == "Darwin" ]]; then
    platform="mac"
  elif [[ "${uname_s}" =~ .*_NT-.* ]]; then
    platform="windows"
  else
    echo "Unsupported operating system: ${uname}" >&2
    exit 1
  fi
}

nproc() {
  # Get numer of cpu logical cores
  if [[ "${platform}" == "windows" ]]; then
    powershell -Command "Write-Output (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfLogicalProcessors"
  else
    getconf _NPROCESSORS_ONLN
  fi
}

BuildZlib() {
  cd
  curl --retry 10 --retry-delay 10 --location http://www.zlib.net/zlib-1.2.11.tar.gz | tar xz
  cd zlib-1.2.11
  if [[ "${platform}" == "windows" ]]; then
    make -f win32/Makefile.gcc
  else
    ./configure
    make -j "$(nproc)"
  fi
}

BuildReferenceProgram() {
  cd
  export ZLIB_PATH="$(pwd)/zlib-1.2.11"
  cd "${GITHUB_WORKSPACE}/tests"
  make
}

main() {
  trap 'ErrorHandler $? ${LINENO}' ERR
  SetPlatform
  BuildZlib
  BuildReferenceProgram
}

main
