mkdir -p $HOME/install
cd ${HOME}/install && curl --location http://www.zlib.net/zlib-1.2.11.tar.gz | tar xz
cd ${HOME}/install/zlib-1.2.11/contrib/puff/ && make
export PATH=${PATH}:${HOME}/install/zlib-1.2.11/contrib/puff
cd ${TRAVIS_BUILD_DIR}