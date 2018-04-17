mkdir -p ${HOME}/install
if [ ! -e ${HOME}/install/zlib-1.2.11/contrib/puff/puff ]
then
	cd ${HOME}/install && curl --location http://www.zlib.net/zlib-1.2.11.tar.gz | tar xz
	cd ${HOME}/install/zlib-1.2.11/contrib/puff/ && make
fi
export PATH=${PATH}:${HOME}/install/zlib-1.2.11/contrib/puff
cd ${TRAVIS_BUILD_DIR}