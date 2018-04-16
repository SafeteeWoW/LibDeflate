mkdir -p $HOME/install
export PATH=${PATH}:$HOME/.lua:$HOME/.local/bin:${HOME}/install/luarocks/bin
bash .travis/setup_lua.sh
bash .travis/setup_compressor_decompressor.sh
eval `$HOME/.lua/luarocks path`
