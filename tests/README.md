# Licenses for files under this directory

This folder contains some third party code and data.
The license used by LibDeflate does not apply to the 3rdparty code or data.
Their original licenses shall be complied when used.

# Test Instructions for Windows

This library is developed on Windows, so this instruction assumes your OS is
Windows. However, the tests also supports Linux/MacOS and should be very similar
to Windows. If there is anything unclear, please refer to the test scripts
in : .appveyor.yml (For Windows tests), .travis.yml (For Linus/MacOS tests)

## Test Environment Setup

**The shell I use is x86 Native Tools Command Prompt for Visual  Studio**

1. Install luajit and make sure it is in your *PATH*. luajit can be downloaded from luajit.org
2. Install luarocks. Then setup PATH, LUA_PATH and LUA_CPATH according to luarocks' instruction. Then install the following three packages:
`luacheck, ldoc, luaunit, luacov, luacov-coveralls, cluacov`.
3. Make sure the following command works: `luajit -lluaunit -lluacov`. If not,
you should check if LUA_PATH an LUA_CPATH are correctly set for LuaRocks.
4. Download zlib source code from zlib.net, and decompress the source to some directory.
5. Set the environment variable *ZLIB_PATH* to the path of zlib source code directory and set the working directory to that directory.
6. Set the working directory to the *tests* directory in this repository. Run the command `nmake /f Makefile_Windows`. Two executables *puff.exe* and *zdeflate.exe*. Those two programs are called in the test suite as the reference program.
7. Add the *tests* directory in this repository to your *PATH*, otherwise the test suite cannot locate the above two programs.

## Run the tests

**For all following commands, I assume your working directory is the root directory of this repository (The directory where LibDeflate.lua locates)**

**It is not supported to run two test scripts at the same time.**

1. Run test suite:  
`luajit -lluacov tests\Test.lua --verbose --shuffle`  

2. Run complete code coverage test:  
First delete the file *luacov.stats.out*, if exists  
`luajit tests\Test.lua CommandLineCodeCoverage --verbose` (For commandline part coverage)  
`luajit -lluacov tests\Test.lua CodeCoverage --verbose` (For actual test coverage)  
Run two commands in order.  
For speed tests, this coverage tests only select part of tests in the test suite, but should be enough to achieve 100% code coverage.


3. View the code coverage test report:  
The above commands will generate store the test result in the file *luacov.stats.out*. To view it in readable format, run the command `luacov`,
a readable report *luacov.report.out* will be generated. (If the command `luacov` cannot be found, you should add the directory of *luacov.bat* to *PATH*, which locates in some directory under your Lua installation)

4. Above important tests will be run in online CI. There are some other extra tests not run in CI (For speed reasons), please see the batch scripts under *tests\dev_scripts*.  
These are some batch scripts to run the test commands, so no need to
run the command manually in the commandline. Just open them in the Windows
explorer. Those scripts set the working directory to the root of git repo
directory first, then run the test commands.


## Other environment setup I used

1. Install Git for Windows in the default setup path.




