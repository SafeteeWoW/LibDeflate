REM set PATH=C:\MinGW\bin;%PATH%

set ZIP_ZLIB=zlib1211.zip
@echo on
echo Fetching zlib-1.2.11 From the Internet
cd %HOMEPATH%
curl --retry 10 --retry-delay 10 -fLsS -o %ZIP_ZLIB% http://www.zlib.net/%ZIP_ZLIB%
unzip -o -d . %ZIP_ZLIB%
set ZLIB_PATH=%HOMEPATH%\zlib-1.2.11
cd zlib-1.2.11
nmake /f win32\Makefile.msc
cd %APPVEYOR_BUILD_FOLDER%\tests
set PATH=%APPVEYOR_BUILD_FOLDER%\tests;%PATH%
nmake /f Makefile_Windows
cd %APPVEYOR_BUILD_FOLDER%
@echo off
