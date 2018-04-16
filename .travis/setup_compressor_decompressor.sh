mkdir -p $TRAVIS_BUILD_DIR/install
cd ${TRAVIS_BUILD_DIR}/install && curl --location http://www.zlib.net/zlib-1.2.11.tar.gz | tar xz
cd ${TRAVIS_BUILD_DIR}/install/zlib-1.2.11/contrib/puff/ && make
export PATH=${PATH}:${TRAVIS_BUILD_DIR}/install/zlib-1.2.11/contrib/puff
cd ${TRAVIS_BUILD_DIR}