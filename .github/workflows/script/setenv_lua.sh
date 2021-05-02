#/usr/bin/env false
# Should be called by source this script

# PATH that contains lua and luarocks
export PATH="/usr/local/bin:/usr/local/luarocks/bin:${PATH}"

# PATH that contains reference compressor
export PATH="${GITHUB_WORKSPACE}/tests:${PATH}"

hash -r
# Setup PATH for Lua package
eval $(luarocks path)
hash -r
