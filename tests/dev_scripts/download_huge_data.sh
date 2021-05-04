#!/bin/bash
# Download big data for HugeTests.
# run "run_huge_test.sh" located the same folder to run these tests.
# Compression of these files take long time and are not included in CI.

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"

cd tests/huge_data

# Have not find a way to unzip from stdin
download_and_unzip() {
  local url="$1"
  filename=$(basename "${url}")
  curl -O "${url}"
  if [[ "${filename}" =~ .*\.zip ]]; then
    unzip "${filename}"
  elif [[ "${filename}" =~ .*\.bz2 ]]; then
    bunzip2 --keep "${filename}"
  else
    echo "Do not know how to handle filename ${filename}" >&2
    exit 1
  fi
  rm "${filename}"
}

download_and_unzip http://www.data-compression.info/files/corpora/largecanterburycorpus.zip
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/dickens.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/mozilla.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/mr.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/nci.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/ooffice.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/osdb.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/reymont.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/samba.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/sao.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/webster.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/xml.bz2
download_and_unzip http://sun.aei.polsl.pl/~sdeor/corpus/x-ray.bz2

echo "Download data for HugeTests complete"
