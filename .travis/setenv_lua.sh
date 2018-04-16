mkdir -p $HOME/install
export PATH=${PATH}:$HOME/.lua:$HOME/.local/bin:${HOME}/install/luarocks/bin
bash .travis/setup_lua.sh
eval `$HOME/.lua/luarocks path`
cd ${TRAVIS_BUILD_DIR}
