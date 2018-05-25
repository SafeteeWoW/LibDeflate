[![Build Status](https://www.travis-ci.org/SafeteeWoW/LibDeflate.svg?branch=master)](https://www.travis-ci.org/SafeteeWoW/LibDeflate)
[![Build status](https://ci.appveyor.com/api/projects/status/owdccv4jrc0g1s2x/branch/master?svg=true&passingText=Windows%20Build%20passing&failingText=Windows%20Build%20failing)](https://ci.appveyor.com/project/SafeteeWoW/libdeflate/branch/master)
[![AppVeyor tests branch](https://img.shields.io/appveyor/tests/SafeteeWoW/LibDeflate/master.svg)](https://ci.appveyor.com/project/SafeteeWoW/libdeflate/branch/master)
[![codecov.io](http://codecov.io/github/safeteeWoW/LibDeflate/branch/master/graphs/badge.svg)](http://codecov.io/github/safeteeWoW/LibDeflate)
[![license](https://img.shields.io/github/license/SafeteeWoW/LibDeflate.svg)](LICENSE.txt)
[![LuaRocks](https://img.shields.io/luarocks/v/SafeteeWoW/libdeflate.svg)](http://luarocks.org/modules/SafeteeWoW/libdeflate)
[![GitHub issues](https://img.shields.io/github/issues/SafeteeWoW/LibDeflate.svg)](https://github.com/SafeteeWoW/LibDeflate/issues)

# LibDeflate
## Pure Lua compressor and decompressor with high compression ratio using DEFLATE/zlib format.

Copyright (C) 2018 Haoqian He

## Introduction
LibDeflate is pure Lua compressor and decompressor with high compression ratio,
which compresses almost as good as [zlib](https://github.com/madler/zlib). The
purpose of this project is to give a reasonable good compression when you only
have access to a pure Lua environment, without accessing to Lua C bindings or
any external Lua libraries. LibDeflate does not have any dependencies except you
need to have a working Lua interpreter.

LibDeflate uses the following compression formats:
1. *DEFLATE*, as defined by the specification
[RFC1951](https://tools.ietf.org/html/rfc1951). DEFLATE is the default compression method of ZIP.
2.  *zlib*, as defined by the specification
[RFC1950](https://tools.ietf.org/html/rfc1950).
zlib format uses DEFLATE formats to compress data and adds several bytes as
headers and checksum.

A simple C program utilizing [zlib](https://github.com/madler/zlib) should be
compatible with LibDeflate. If you are not sure how to write this program,
goto the [zlib](https://github.com/madler/zlib) repository, or read
[tests/zdeflate.c](tests/zdeflate.c) in this repository.

## Supported Lua Versions
LibDeflate supports and is fully tested under Lua 5.1/5.2/5.3, LuaJIT 2.0/2.1,
for Linux, MaxOS and Windows. Click the Travis CI(Linux/MaxOS) and
Appveyor(Windows) badge on the top of this README for the test results. Click
the CodeCov badge to see the test coverage (should be 100%).

## Documentation
[Documentation](https://safeteewow.github.io/LibDeflate/) is hosted on Github.
Beside run as a library, LibDeflate can also be run directly in commmandline.
See the documentation for detail.

## Limitation
Though many performance optimization has been done in the source code, as a
pure Lua implementation, the compression speed of LibDeflate is significantly
slower than a C compressor. LibDeflate aims to compress small files, and it is
suggested to not compress files with the order of several Megabytes. If you
need to compress files hundreds of MetaBytes, please use a C compressor, or a
Lua compressor with C binding.

## Performance
Below is a simple benchmark compared with another pure Lua compressor [LibCompress](https://www.wowace.com/projects/libcompress).


The size of [The input data](https://gist.github.com/SafeteeWoW/d9770e08a6989032de01b7d61b53d981) is 158492 bytes. The benchmark runs on Lua 5.1.4 interpreter.

NOTE: The compression method used by LibDeflate here is LibDeflate:CompressDeflate (Compress using raw DEFLATE format)

<table>
<thead>
<tr>
<th></th>
<th>LibDeflate</th>
<th>LibDeflate</th>
<th>LibDeflate</th>
<th>LibCompress</th>
<th>LibCompress</th>
</tr>
</thead>
<tbody>
<tr>
<td></td>
<td>level 1</td>
<td>level 5</td>
<td>level 8</td>
<td>CompressLZW</td>
<td>CompressHuffman</td>
</tr>
<tr>
<td>Compress(ms)</td>
<td>65</td>
<td>150</td>
<td>465</td>
<td>66</td>
<td>75</td>
</tr>
<tr>
<td>Decompress(ms)</td>
<td>32</td>
<td>28</td>
<td>28</td>
<td>21</td>
<td>99</td>
</tr>
<tr>
<td>compress size(Bytes)</td>
<td>23659</td>
<td>17323</td>
<td>16106</td>
<td>72639</td>
<td>99346</td>
</tr>
</tbody>
</table>

LibDeflate with compression level 1 compresses as fast as LibCompress, but already produces significantly smaller file than LibCompress. High compression level takes a bit more time to get better compression.

## Download And Install
+ The [official repository](https://github.com/SafeteeWoW/LibDeflate) locates on Github.
[LibDeflate.lua](https://github.com/SafeteeWoW/LibDeflate/blob/master/LibDeflate.lua) is the only file of LibDeflate. Copy the file
to your LUA_PATH to install it.

+ To download as a World of Warcraft library, goto [LibDeflate Curseforge Page](https://wow.curseforge.com/projects/libdeflate)

+ You can also install via Luarocks using the command "luarocks install libdeflate"

+ To use after installation, ```require("LibDeflate")``` (case sensitive) in your Lua interpreter,
or ```LibStub:GetLibrary("LibDeflate")``` (case sensitive) for World of Warcraft.


## Usage
```
local LibDeflate
if LibStub then -- You are using LibDeflate as WoW addon
	LibDeflate = LibStub:GetLibrary("LibDeflate")
else
	LibDeflate = require("LibDeflate")
end

local example_input = "12123123412345123456123456712345678123456789"

--- Compress using raw deflate format
local compress_deflate = LibDeflate:CompressDeflate(example_input)
-- decompress
assert(example_input == LibDeflate:DecompressDeflate(compress_deflate))


-- To transmit through WoW addon channel, data must be encoded so NULL ("\000")
-- is not in the data.
local data_to_trasmit_WoW_addon = LibDeflate:EncodeForWoWAddonChannel(
	compress_deflate)
-- When the receiver gets the data, decoded it first.
local data_decoded_WoW_addon = LibDeflate:DecodeForWoWAddonChannel(
	data_to_trasmit_WoW_addon)
-- Then decomrpess it
local decompress_deflate = LibDeflate:DecompressDeflate(data_decoded_WoW_addon)

assert(decompress_deflate == example_input)

-- The compressed output is not printable. EncodeForPrint will convert to
-- a printable format, in case you want to export to the user to
-- copy and paste. This encoding will make the data 25% bigger.
local printable_compressed = LibDeflate:EncodeForPrint(compress_deflate)

-- DecodeForPrint to convert back.
-- DecodeForPrint will remove prefixed and trailing control or space characters
-- in the string before decode it.
assert(LibDeflate:DecodeForPrint(printable_compressed) == compress_deflate)
```
See Full examples in [examples/example.lua](examples/example.lua)

## Credits
1. [zlib](http://www.zlib.net), by Jean-loup Gailly (compression) and Mark Adler (decompression). Licensed under [zlib License](http://www.zlib.net/zlib_license.html).
2. [puff](https://github.com/madler/zlib/tree/master/contrib/puff), by Mark Adler. Licensed under zlib License.
3. [LibCompress](https://www.wowace.com/projects/libcompress), by jjsheets and Galmok of European Stormrage (Horde). Licensed under GPLv2.
4. [WeakAuras2](https://github.com/WeakAuras/WeakAuras2). Licensed under GPLv2.

## License
LibDeflate is licensed under GNU General Public License Version 3 or later.