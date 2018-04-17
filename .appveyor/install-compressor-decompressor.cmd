set PATH=C:\MinGW\bin;%PATH%
set ZIP_ZLIB=zlib1211.zip

echo Setting up Puff
if NOT EXIST "zlib-1.2.11\contrib\puff\puff.exe" (
    @echo on
    echo Fetching zlib-1.2.11 From the Internet
    curl -fLsS -o %ZIP_ZLIB% http://www.zlib.net/%ZIP_ZLIB%
    unzip -o -d . %ZIP_ZLIB%
    mingw32-gcc zlib-1.2.11\contrib\puff\puff.c zlib-1.2.11\contrib\puff\pufftest.c -o zlib-1.2.11\contrib\puff\puff.exe
) else (
    echo Using cached version of puff
)
set PATH=%APPVEYOR_BUILD_FOLDER%\zlib-1.2.11\contrib\puff;%PATH%
@echo off
REM goto :EOF