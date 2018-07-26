FOR /F "tokens=*" %%i in ('git rev-parse --show-toplevel') do SET GIT_ROOT=%%i
cd /d "%GIT_ROOT%"
del /F luacov.stats.out
luajit tests\Test.lua CommandLineCodeCoverage --verbose
luajit -lluacov tests\Test.lua CodeCoverage --verbose
luacov & pause
pause