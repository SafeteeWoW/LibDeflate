# Test Instructions

## Use Github workflow yaml as a reference

If you get any issues after reading this document,
use Github Workflow config file [lua_test.yml](../.github/workflows/lua_test.yml)
as a golden reference, including the version of Luarocks packages

## Test requirement

1. Do not add external dependencies not in this repository, for the default testsuite.

2. 100% code coverage required.

## Luarocks packages for testing

1. luaunit: Required for all kinds of tests.

2. luacov: Required only for code coverage tests.

3. cluacov: Recommend for code coverage tests. This speed up code coverage tests.

4. luacov-coveralls: Only used in CI, for [coveralls.io](coveralls.io) service.

5. luabitop: Only needed when using Lua5.1 or LuaJIT, and compare performance against LibCompress.

## Install reference compressor/decompressor and add to PATH

Two reference programs are included to test LibDeflate for DEFLATE format compliance. Building them and add them to the PATH are required,
otherwise most tests will fail.

[puff](pufftest.c): Decompressor only.

[zdeflate](zdeflate.c): Compressor and compressor.

1. Build zlib. Read [install_compressor.sh](../.github/workflows/script/install_compressor.sh) for reference. Download [zlib](https://www.zlib.net/), unzip it, and change working directory to zlib directory. For Linux or MacOS, run `./configure && make`. For Windows, assuming you have installed MinGW, run `make -f win32/Makefile.gcc`

2. Set the environment variable "ZLIB_PATH" to the absolute path of the zlib directory.

3. In _this_ directory, where this README locates, run "make" to build puff and zdeflate.

4. Add _this_ directory, where this README locates, to the environment variable PATH.

## Run the tests

When running test, the working directory must be the root directory of this repository (The directory where LibDeflate.lua locates),
otherwise most tests will fail.

Run two test scripts at the same time is **NOT SUPPORTED**.

You can use LuaJIT or the original Lua interpreter. I prefer LuaJIT during development because it is faster.

1. Run test suite:

   `luajit tests/Test.lua --verbose --shuffle`

2. Run complete code coverage test:

   First delete the file _luacov.stats.out_, if exists.

   Run the following two commands in order.

   `luajit tests/Test.lua CommandLineCodeCoverage --verbose` (For commandline part coverage)
   `luajit -lluacov tests\Test.lua CodeCoverage --verbose` (For other test coverage)

   Finally, `luacov` to generate test report in _luacov.report.out_

3. Run HugeTests

   It is slow to test big files. These files are not included in the repository.
   Testing these files are not included in CI.

   First, download data by the script [dev_scripts/download_huge_data.sh](dev_scripts/download_huge_data.sh)

   `luajit tests/Test.lua HugeTests --verbose`

## Helper scripts

There are some helper scripts in [dev_scripts](dev_scripts) directory inside this directory.

Read comment in these scripts for usage.

Any working directory is ok when running these scripts.

## Test Instructions for Windows

This library is developed in Linux environment.

If you are using Windows, I suggest to use a Bash terminal, such as Git Bash

## Add tests

1. If new API is added in [LibDeflate.lua](../LibDeflate.lua), please add the function name into `TestExported:TestExported`

2. All test code should be added to [Test.lua](Test.lua)

3. If extra reference data needed: For small data, put them to the [data](data) folder and add to repository. Big data should added as an url in [dev_scripts/download_huge_data.sh](dev_scripts/download_huge_data.sh)

4. To add a test cases included in the default test suite, add a class whose name begins with **Test** in [Test.lua](Test.lua)

5. By default, test cases are not included in code coverage tests. This is for speed reasons. Code coverage tests should only include minimal amount of tests required to reach 100% code coverage.
   Use function `AddAllToCoverageTest` or `AddToCoverageTest` to add test to code coverage test.

## Licenses for files under this directory

This folder contains some third party code and data.
The license used by LibDeflate does not apply to the 3rdparty code or data.
Their original licenses shall be complied when used.
