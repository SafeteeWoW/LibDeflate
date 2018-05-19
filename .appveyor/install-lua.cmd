REM This is a batch file to help with setting up the desired Lua environment.
REM It is intended to be run as "install" step from within AppVeyor.

REM version numbers and file names for binaries from http://sf.net/p/luabinaries/
set VER_514=5.1.4
set VER_515=5.1.5
set VER_524=5.2.4
set VER_533=5.3.3
set ZIP_514=lua5_1_4_Win32_bin.zip
set ZIP_515=lua-%VER_515%_Win32_bin.zip
set ZIP_524=lua-%VER_524%_Win32_bin.zip
set ZIP_533=lua-%VER_533%_Win32_bin.zip

:cinst
@echo off
if NOT "%LUAENV%"=="cinst" goto lua514
echo Chocolatey install of Lua ...
if NOT EXIST "C:\Program Files (x86)\Lua\5.1\lua.exe" (
    @echo on
    cinst lua
) else (
    @echo on
    echo Using cached version of Lua
)
set LUA="C:\Program Files (x86)\Lua\5.1\lua.exe
set PATH=C:\Program Files (x86)\Lua\5.1;%PATH%
@echo off
goto :AFTERLUA

:lua514
@echo off
if NOT "%LUAENV%"=="lua514" goto lua515
echo Setting up Lua 5.1.4 ...
if NOT EXIST "lua514\lua5.1.exe" (
    @echo on
    echo Fetching Lua v5.1.4 from internet
    curl --retry 10 --retry-delay 10 -fLsS -o %ZIP_514% http://sourceforge.net/projects/luabinaries/files/%VER_514%/Tools%%20Executables/%ZIP_514%/download
    unzip -d lua514 %ZIP_514%
) else (
    echo Using cached version of Lua v5.1.4
)
set LUA=lua514\lua5.1.exe
move %LUA% lua514\lua.exe
set PATH=%cd%\lua514;%PATH%
@echo off
goto :AFTERLUA

:lua515
@echo off
if NOT "%LUAENV%"=="lua515" goto lua524
echo Setting up Lua 5.1.5 ...
if NOT EXIST "lua515\lua5.1.exe" (
    @echo on
    echo Fetching Lua v5.1.5 from internet
    curl --retry 10 --retry-delay 10 -fLsS -o %ZIP_515% http://sourceforge.net/projects/luabinaries/files/%VER_515%/Tools%%20Executables/%ZIP_515%/download
    unzip -d lua515 %ZIP_515%
) else (
    echo Using cached version of Lua v5.1.5
)
set LUA=lua515\lua5.1.exe
move %LUA% lua515\lua.exe
set PATH=%cd%\lua515;%PATH%
@echo off
goto :AFTERLUA

:lua524
@echo off
if NOT "%LUAENV%"=="lua524" goto lua533
echo Setting up Lua 5.2.4 ...
if NOT EXIST "lua524\lua524.exe" (
    @echo on
    echo Fetching Lua v5.2.4 from internet
    curl --retry 10 --retry-delay 10 -fLsS -o %ZIP_524% http://sourceforge.net/projects/luabinaries/files/%VER_524%/Tools%%20Executables/%ZIP_524%/download
    unzip -d lua524 %ZIP_524%
) else (
    echo Using cached version of Lua v5.2.4
)
@echo on
set LUA=lua524\lua52.exe
move %LUA% lua524\lua.exe
set PATH=%cd%\lua524;%PATH%
@echo off
goto :AFTERLUA

:lua533
@echo off
if NOT "%LUAENV%"=="lua533" goto luajit
echo Setting up Lua 5.3.3 ...
if NOT EXIST "lua533\lua533.exe" (
    @echo on
    echo Fetching Lua v5.3.3 from internet
    curl --retry 10 --retry-delay 10 -fLsS -o %ZIP_533% http://sourceforge.net/projects/luabinaries/files/%VER_533%/Tools%%20Executables/%ZIP_533%/download
    unzip -d lua533 %ZIP_533%
) else (
    echo Using cached version of Lua v5.3.3
)
@echo on
set LUA=lua533\lua53.exe
move %LUA% lua533\lua.exe
set PATH=%cd%\lua533;%PATH%
@echo off
goto :AFTERLUA

:luajit
if NOT "%LUAENV%"=="luajit20" goto luajit21
echo Setting up LuaJIT 2.0 ...
if NOT EXIST "luajit20\luajit.exe" (
    call %~dp0install-luajit.cmd LuaJIT-2.0.4 luajit20
) else (
    echo Using cached version of LuaJIT 2.0
)
set LUA=luajit20\luajit.exe
move %LUA% luajit20\lua.exe
set PATH=%cd%\luajit20;%PATH%
goto :AFTERLUA

:luajit21
echo Setting up LuaJIT 2.1 ...
if NOT EXIST "luajit21\luajit.exe" (
    call %~dp0install-luajit.cmd LuaJIT-2.1.0-beta2 luajit21
) else (
    echo Using cached version of LuaJIT 2.1
)
set LUA=luajit21\luajit.exe
move %LUA% luajit21\lua.exe
set PATH=%cd%\luajit21;%PATH%

:AFTERLUA
@echo on
echo %PATH%
where lua
lua -v
choco install luarocks
set LUA_PATH=C:\ProgramData\chocolatey\lib\luarocks\luarocks-2.4.4-win32\systree\share\lua\5.1\?.lua;C:\ProgramData\chocolatey\lib\luarocks\luarocks-2.4.4-win32\systree\share\lua\5.1\?\init.lua;%APPVEYOR_BUILD_FOLDER%\?.lua;%LUA_PATH%
set LUA_CPATH=C:\ProgramData\chocolatey\lib\luarocks\luarocks-2.4.4-win32\systree\lib\lua\5.1\?.dll;%APPVEYOR_BUILD_FOLDER%\?.dll;%LUA_CPATH%;
luarocks install luaunit
cd %APPVEYOR_BUILD_FOLDER%
@echo off