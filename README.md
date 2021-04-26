[![Build Status](https://www.travis-ci.org/SafeteeWoW/LibDeflate.svg?branch=master)](https://www.travis-ci.org/SafeteeWoW/LibDeflate)
[![Build status](https://ci.appveyor.com/api/projects/status/owdccv4jrc0g1s2x/branch/master?svg=true&passingText=Windows%20Build%20passing&failingText=Windows%20Build%20failing)](https://ci.appveyor.com/project/SafeteeWoW/libdeflate/branch/master)
[![AppVeyor tests branch](https://img.shields.io/appveyor/tests/SafeteeWoW/LibDeflate/master.svg)](https://ci.appveyor.com/project/SafeteeWoW/libdeflate/branch/master)
[![codecov.io](http://codecov.io/github/safeteeWoW/LibDeflate/branch/master/graphs/badge.svg)](http://codecov.io/github/safeteeWoW/LibDeflate)
[![license](https://img.shields.io/github/license/SafeteeWoW/LibDeflate)](LICENSE.txt)
[![LuaRocks](https://img.shields.io/luarocks/v/SafeteeWoW/libdeflate)](http://luarocks.org/modules/SafeteeWoW/libdeflate)
[![GitHub issues](https://img.shields.io/github/issues/SafeteeWoW/LibDeflate)](https://github.com/SafeteeWoW/LibDeflate/issues)

# LibDeflate
## Pure Lua compressor and decompressor with high compression ratio using DEFLATE/zlib format.

Copyright (C) 2018-2020 Haoqian He

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
[tests/zdeflate.c](https://github.com/SafeteeWoW/LibDeflate/blob/master/tests/zdeflate.c) in this repository.

## Supported Lua Versions
LibDeflate supports and is fully tested under Lua 5.1/5.2/5.3/5.4, LuaJIT 2.0/2.1,
for Linux, MaxOS and Windows. Click the Travis CI(Linux/MaxOS) and
Appveyor(Windows) badge on the top of this README for the test results. Click
the CodeCov badge to see the test coverage (should be 100%).

## Documentation
[Documentation](https://safeteewow.github.io/LibDeflate/source/LibDeflate.lua.html) is hosted on Github.
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
More benchmarks can be viewed in the [documentation](https://safeteewow.github.io/LibDeflate/topics/benchmark.md.html).

+ Interpreter: Lua 5.1.5
+ Input data: [WeakAuras2 String](https://raw.githubusercontent.com/SafeteeWoW/LibDeflate/master/tests/data/warlockWeakAuras.txt), Size: 132462 bytes

<table>
<thead>
<tr>
<th></th>
<th>LibDeflate</th>
<th>LibDeflate</th>
<th>LibDeflate</th>
<th>LibCompress</th>
<th>LibCompress</th>
<th>LibCompress</th>
</tr>
</thead>
<tbody>
<tr>
<td></td>
<td>CompressDeflate Level 1</td>
<td>CompressDeflate Level 5</td>
<td>CompressDeflate Level 8</td>
<td>Compress</td>
<td>CompressLZW</td>
<td>CompressHuffman</td>
</tr>
<tr>
<td>compress ratio</td>
<td>3.15</td>
<td>3.68</td>
<td>3.71</td>
<td>1.36</td>
<td>1.20</td>
<td>1.36</td>
</tr>
<tr>
<td>compress time(ms)</td>
<td>68</td>
<td>116</td>
<td>189</td>
<td>111</td>
<td>52</td>
<td>50</td>
</tr>
<tr>
<td>decompress time(ms)</td>
<td>48</td>
<td>30</td>
<td>27</td>
<td>55</td>
<td>26</td>
<td>59</td>
</tr>
<tr>
<td>compress+decompress time(ms)</td>
<td>116</td>
<td>145</td>
<td>216</td>
<td>166</td>
<td>78</td>
<td>109</td>
</tr>
</tbody>
</table>


LibDeflate with compression level 1 compresses as fast as LibCompress, but already produces significantly smaller data than LibCompress. High compression level takes a bit more time to get better compression.

## Download And Install

+ The [official repository](https://github.com/SafeteeWoW/LibDeflate) locates on Github.
[LibDeflate.lua](https://github.com/SafeteeWoW/LibDeflate/blob/master/LibDeflate.lua) is the only file of LibDeflate. Copy the file
to your LUA_PATH to install it.

+ To download as a World of Warcraft library, goto [LibDeflate Curseforge Page](https://wow.curseforge.com/projects/libdeflate) or [LibDeflate WoWInterface Page](https://www.wowinterface.com/downloads/info25453-LibDeflate.html)

+ You can also install via Luarocks using the command "luarocks install libdeflate"

+ All packages files can also in downloaded in the [Github Release Page](https://github.com/SafeteeWoW/LibDeflate/releases)

+ To use after installation, ```require("LibDeflate")``` (case sensitive) in your Lua interpreter,
or ```LibStub:GetLibrary("LibDeflate")``` (case sensitive) for World of Warcraft.


## Usage
```lua
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
local decompress_deflate = LibDeflate:DecompressDeflate(compress_deflate)

-- Check if the first return value of DecompressXXXX is non-nil to know if the
-- decompression succeeds.
if decompress_deflate == nil then
	error("Decompression fails.")
else
	-- Decompression succeeds.
	assert(example_input == decompress_deflate)
end

-- Can also compress and decompress in chunks mode
local compress_co = LibDeflate:CompressDeflate(example_input, {level=9, chunksMode=true})
local ongoing, compressed_chunks = true
repeat 
  ongoing, compressed_chunks = compress_co()
until not ongoing

local decompress_co = LibDeflate:DecompressDeflate(compressed_chunks, {chunksMode=true})
local ongoing, decompressed_chunks = true
repeat 
  ongoing, decompressed_chunks = decompress_co()
until not ongoing
if decompressed_chunks == nil then
	error("Decompression fails.")
else
	-- Decompression succeeds.
	assert(example_input == decompressed_chunks)
end

-- In WoW, coroutine processing can be handled on frame updates to reduce loss of framerate.
local processing = CreateFrame('Frame')
local WoW_compress_co = LibDeflate:CompressDeflate(example_input, {level=9, chunksMode=true})
processing:SetScript('OnUpdate', function()
  local ongoing, WoW_compressed = WoW_compress_co()
  if not ongoing then
    -- do something with `WoW_compressed`
    processing:SetScript('OnUpdate', nil)
  end
end)

local WoW_decompress_co = LibDeflate:DecompressDeflate(compress_deflate, {chunksMode=true})
processing:SetScript('OnUpdate', function()
  local ongoing, WoW_decompressed = WoW_decompress_co()
  if not ongoing then
    -- do something with `WoW_decompressed`
	  assert(example_input == WoW_decompressed)
    processing:SetScript('OnUpdate', nil)
  end
end)


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
See Full examples in [examples/example.lua](https://github.com/SafeteeWoW/LibDeflate/blob/master/examples/example.lua)

## License

LibDeflate is licensed under the zlib license. See LICENSE.txt.
The "tests" folder in the repository contains some third party code and data.
Their original licenses shall be complied when used.

## Credits and Disclaimer

This library rewrites the code from the algorithm and the ideas of the following projects,
and uses their code to help to test the correctness of this library,
but their code is not included directly in the library itself.
Their original licenses shall be complied when used.

1. [zlib](http://www.zlib.net), by Jean-loup Gailly (compression) and Mark Adler (decompression). Licensed under [zlib License](http://www.zlib.net/zlib_license.html).
2. [puff](https://github.com/madler/zlib/tree/master/contrib/puff), by Mark Adler. Licensed under zlib License.
3. [LibCompress](https://www.wowace.com/projects/libcompress), by jjsheets and Galmok of European Stormrage (Horde). Licensed under GPLv2.
4. [WeakAuras2](https://github.com/WeakAuras/WeakAuras2). Licensed under GPLv2.