#!/bin/bash

# Install lua intepreter
# Environment variables:
# LUA: must be "lua5.**" or "luajit2.**".
# LUAROCKS: must be a version number similar to "3.7.0"

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

InstallLuajit() {
  local version=$1
  if [[ -z "${version}" ]]; then
    echo "No LuaJIT version specified" >&2
    exit 1
  fi
  cd
  echo ">> Downloading LuaJIT-${version}"
  curl --retry 10 --retry-delay 10 --location https://github.com/LuaJIT/LuaJIT/archive/refs/tags/v${version}.tar.gz | tar xz
  cd "LuaJIT-${version}"
  echo ">> Compiling LuaJIT-${version}"
  if [[ "${platform}" == "linux" ]]; then
    make HOST_SYS="$(uname -s)" PREFIX=${prefix} all -j "$(nproc)"
    make HOST_SYS="$(uname -s)" PREFIX=${prefix} install
  elif [[ "${platform}" == "mac" ]]; then
    make HOST_SYS="$(uname -s)" MACOSX_DEPLOYMENT_TARGET=10.14 PREFIX=${prefix} all -j "$(nproc)"
    make HOST_SYS="$(uname -s)" MACOSX_DEPLOYMENT_TARGET=10.14 PREFIX=${prefix} install
  elif [[ "${platform}" == "windows" ]]; then
    make PREFIX=${prefix} CC=gcc all -j "$(nproc)"
    make PREFIX=${prefix} CC=gcc install
    cp -f src/*.dll "${prefix}/bin/"
  else
    echo "Unsupported operating system: ${platform}" >&2
    exit 1
  fi

  if [[ "${platform}" == "windows" ]]; then
    if [[ -e "${prefix}/bin/luajit-${version}.exe" ]]; then
      cp -f "${prefix}/bin/luajit-${version}.exe" "${prefix}/bin/luajit"
      cp -f "${prefix}/bin/luajit-${version}.exe" "${prefix}/bin/luajit.exe"
    fi
    if [[ -e "${prefix}/bin/luajit" ]]; then
      cp -f "${prefix}/bin/luajit" "${prefix}/bin/lua"
      cp -f "${prefix}/bin/luajit" "${prefix}/bin/lua.exe"
    fi
    if [[ -e "${prefix}/bin/luajit.exe" ]]; then
      cp -f "${prefix}/bin/luajit.exe" "${prefix}/bin/lua.exe"
    fi
  else
    if [[ ! -e "${prefix}/bin/luajit" ]]; then
      ln -sf "${prefix}/bin/luajit-${version}" "${prefix}/bin/luajit"
    fi
    ln -sf "${prefix}/bin/luajit" "${prefix}/bin/lua"
  fi

  cd ..
  rm -rf "LuaJIT-${version}"
}

InstallLua() {
  local version="$1"
  if [[ -z "${version}" ]]; then
    echo "No Lua version specified" >&2
    exit 1
  fi

  cd
  echo ">> Downloading Lua-${version}"
  curl --retry 10 --retry-delay 10 http://www.lua.org/ftp/lua-${version}.tar.gz | tar xz
  cd lua-${version}

  # Build Lua without backwards compatibility for testing
  perl -i -pe 's/-DLUA_COMPAT_(ALL|5_2)//' src/Makefile

  echo ">> Compiling Lua-${version}"
  if [[ "${platform}" == "linux" ]]; then
    local plat=linux
  elif [[ "${platform}" == "mac" ]]; then
    local plat=macosx
  elif [[ "${platform}" == "windows" ]]; then
    local plat=mingw
  else
    echo "Unsupported operating system: ${platform}" >&2
    exit 1
  fi
  make "INSTALL_TOP=${prefix}" "PLAT=${plat}" "${plat}" -j "$(nproc)"
  make "INSTALL_TOP=${prefix}" "PLAT=${plat}" install

  if [[ "${platform}" == "windows" ]]; then
    cp -f src/*.dll "${prefix}/bin/"
  fi

  cd ..
  rm -rf "lua-${version}"
}

InstallLuarocksUnix() {
  local version="$1"
  if [[ -z "${version}" ]]; then
    echo "No luarocks version specified" >&2
    exit 1
  fi

  cd
  echo ">> Downloading luarocks-${version}"
  local luarocks_base=luarocks-${version}
  curl --retry 10 --retry-delay 10 --location http://luarocks.org/releases/${luarocks_base}.tar.gz | tar xz

  echo ">> Compiling luarocks-${version}"
  cd "${luarocks_base}"
  if [[ "${LUA}" =~ luajit-2\.0\..* ]]; then
    ./configure --with-lua="${prefix}" --with-lua-include="${prefix}/include/luajit-2.0" --prefix="${prefix}/luarocks"
  elif [[ "${LUA}" =~ luajit-2\.1\..* ]]; then
    ./configure --with-lua="${prefix}" --with-lua-include="${prefix}/include/luajit-2.1" --prefix="${prefix}/luarocks"
  else
    ./configure --with-lua="${prefix}" --prefix="${prefix}/luarocks"
  fi

  make build -j "$(nproc)"
  make install

  cd ..
  rm -rf "${luarocks_base}"
}

InstallLuarocksWindows() {
  local version="$1"
  if [[ -z "${version}" ]]; then
    echo "No luarocks version specified" >&2
    exit 1
  fi

  cd
  echo ">> Downloading luarocks-${version}"
  local luarocks_base=luarocks-${version}-win32
  curl --retry 10 --retry-delay 10 --location "http://luarocks.org/releases/${luarocks_base}.zip" -o "${luarocks_base}.zip"
  unzip -o "${luarocks_base}.zip"

  echo ">> Compiling luarocks-${version}"
  cd "${luarocks_base}"
  if [[ "${LUA}" =~ luajit-2\.0\..* ]]; then
    powershell -Command "& { .\install.bat /P ${prefix_win_style}\\luarocks /LUA ${prefix_win_style} /INC ${prefix_win_style}\\include\\luajit-2.0 /Q /SELFCONTAINED /MW }"
  elif [[ "${LUA}" =~ luajit-2\.1\..* ]]; then
    powershell -Command "& { .\install.bat /P ${prefix_win_style}\\luarocks /LUA ${prefix_win_style} /INC ${prefix_win_style}\\include\\luajit-2.1 /Q /SELFCONTAINED /MW }"
  else
    powershell -Command "& { .\install.bat /P ${prefix_win_style}\\luarocks /LUA ${prefix_win_style} /Q /SELFCONTAINED /MW }"
  fi

  cd ..
  rm -rf "${luarocks_base}"
}

main() {
  if [[ -z "${LUA}" ]]; then
    echo "ERROR: Environment variable LUA is not specified" >&2
    echo "Should be similar to lua5.1.5 or luajit2.0.4" >&2
    exit 1
  fi

  if [[ -z "${LUAROCKS}" ]]; then
    echo "ERROR: Environment variable LUAROCKS is not specified" >&2
    echo "Should be similar to a version number like 3.7.0" >&2
    exit 1
  fi

  trap 'ErrorHandler $? ${LINENO}' ERR

  SetPlatform

  if [[ "${platform}" == "windows" ]]; then
    prefix=/c/usr/local
    prefix_win_style="C:\\usr\\local"
  else
    prefix=/usr/local
  fi
  export PATH="${prefix}/bin:${PATH}"
  hash -r

  if [[ "$LUA" =~ luajit-.* ]]; then
    version=${LUA#luajit-}
    InstallLuajit "${version}"
  elif [[ "$LUA" =~ lua-.* ]]; then
    version=${LUA#lua-}
    InstallLua "${version}"
  else
    echo "Invalid environment variable LUA" >&2
    exit 1
  fi

  hash -r
  echo ">> Printing the verison of lua"
  lua -v

  if [[ "${platform}" == "windows" ]]; then
    InstallLuarocksWindows "${LUAROCKS}"
  else
    InstallLuarocksUnix "${LUAROCKS}"
  fi

}

main
