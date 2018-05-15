mkdir -p ${HOME}/install
cd ${HOME}/install && curl --retry 10 --retry-delay 10 --location http://www.zlib.net/zlib-1.2.11.tar.gz | tar xz
cd ${HOME}/install/zlib-1.2.11/ && ./configure && make -j4
export ZLIB_PATH=${HOME}/install/zlib-1.2.11
cd ${TRAVIS_BUILD_DIR}/tests
make -f Makefile_Unix
export PATH=:${TRAVIS_BUILD_DIR}/tests:${PATH}
cd ${TRAVIS_BUILD_DIR}
