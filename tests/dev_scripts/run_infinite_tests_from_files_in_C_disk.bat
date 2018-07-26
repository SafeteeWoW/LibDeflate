FOR /F "tokens=*" %%i in ('git rev-parse --show-toplevel') do SET GIT_ROOT=%%i
cd /d "%GIT_ROOT%"
python tests\dev_scripts\test_from_random_files_in_disk.py C:\ & pause
pause