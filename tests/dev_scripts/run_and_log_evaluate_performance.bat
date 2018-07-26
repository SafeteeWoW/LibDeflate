REM Assuming Git for Windows has been installed in the default setup path
REM assuming Lua and Luajit have been installed
set tee="C:\Program Files\Git\usr\bin\tee.exe"
set log="performance.log"
FOR /F "tokens=*" %%i in ('git rev-parse --show-toplevel') do SET GIT_ROOT=%%i
cd /d "%GIT_ROOT%"
echo. | %tee% -a %log%
echo -------------------------------------------------------------------------------------------------------------------------------------------- | %tee% -a %log%
echo -------------------------------------------------------------------------------------------------------------------------------------------- | %tee% -a %log%
echo. | %tee% -a %log%
echo. | %tee% -a %log%
echo "%DATE%" | %tee% -a %log%
git log -n 1 --format=medium | %tee% -a %log%
lua tests\Test.lua PerformanceEvaluation | %tee% -a %log%
luajit tests\Test.lua PerformanceEvaluation | %tee% -a %log%
pause