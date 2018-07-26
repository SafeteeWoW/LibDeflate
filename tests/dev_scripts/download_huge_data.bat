FOR /F "tokens=*" %%i in ('git rev-parse --show-toplevel') do SET GIT_ROOT=%%i
cd /d "%GIT_ROOT%"
cd tests\huge_data
curl -O http://www.data-compression.info/files/corpora/largecanterburycorpus.zip
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/dickens.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/mozilla.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/mr.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/nci.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/ooffice.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/osdb.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/reymont.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/samba.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/sao.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/webster.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/xml.bz2
curl -O http://sun.aei.polsl.pl/~sdeor/corpus/x-ray.bz2
echo "You have not done yet. Please decompress the data directly in the tests\huge_data directory."
pause