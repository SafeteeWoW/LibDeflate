echo Setting up luaunit
if NOT EXIST "luaunit.lua" (
    @echo on
    echo Fetching luaunit From the Internet
    curl -fLsS -o luaunit.lua https://raw.githubusercontent.com/bluebird75/luaunit/master/luaunit.lua
) else (
    echo Using cached version of luaunit
)
@echo off
REM goto :EOF