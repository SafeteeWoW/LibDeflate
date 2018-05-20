[![Build Status](https://www.travis-ci.org/SafeteeWoW/LibDeflate.svg?branch=master)](https://www.travis-ci.org/SafeteeWoW/LibDeflate)
[![Build status](https://ci.appveyor.com/api/projects/status/owdccv4jrc0g1s2x/branch/master?svg=true&passingText=Windows%20Build%20passing&failingText=Windows%20Build%20failing)](https://ci.appveyor.com/project/SafeteeWoW/libdeflate/branch/master)
[![AppVeyor tests branch](https://img.shields.io/appveyor/tests/SafeteeWoW/LibDeflate/master.svg)](https://ci.appveyor.com/project/SafeteeWoW/libdeflate/branch/master)
[![codecov.io](http://codecov.io/github/safeteeWoW/LibDeflate/branch/master/graphs/badge.svg)](http://codecov.io/github/safeteeWoW/LibDeflate)
[![license](https://img.shields.io/github/license/SafeteeWoW/LibDeflate.svg)](LICENSE.txt)

# LibDeflate v0.9.0-alpha1
## Pure Lua DEFLATE/zlib compressors and decompressors.

Copyright (C) 2018 Haoqian He

## Introduction
LibDeflate is a pure Lua DEFLATE/zlib compressors and decompressors, which compress
almost as good as [zlib](https://github.com/madler/zlib). LibDeflate does not have any dependencies except you need to have a working Lua interpreter.

## Supported Lua Versions
LibDeflate supports and is fully tested under Lua 5.1/5.2/5.3, LuaJIT 2.0/2.1,
for Linux, MaxOS and Windows. See the badge on the top of this README for the test result.

## Documentation
[Documentation](doc/index.html) is in the Github repository.

## Limitation
Though many performance optimization has been done in the source code, as a pure lua implementation, its speed is significantly slower than a C compressor. LibDeflate aims to compress small files, and it is suggestted
to not compress files bigger than 1MB. If you need to compress files hundreds
of MetaBytes, please use a C compressor, or a Lua compressor with C binding.

## Performance
Below is a simple benchmark compared with another pure Lua compressor [LibCompress](https://www.wowace.com/projects/libcompress).
LibDeflate with compressino level 1 compresses as fast as LibCompress, but already produces significantly smaller file than LibCompress. High compression level takes a bit more time to get better compression.

The size of [The input data](https://gist.github.com/SafeteeWoW/d9770e08a6989032de01b7d61b53d981) is 158492 bytes. The benchmark runs on Lua 5.1.4 interprefer.

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

## Download And Install
The [official repository](https://github.com/SafeteeWoW/LibDeflate) locates on Github.
[LibDeflate.lua](https://github.com/SafeteeWoW/LibDeflate/blob/master/LibDeflate.lua) is the only file of LibDeflate. Copy the file
to your LUA_PATH to install it.

To download as a World of Warcraft library, goto [LibDeflate Curseforge Page](https://wow.curseforge.com/projects/libdeflate)


## Usage
See examples/example.lua

## Credits
1. [zlib](http://www.zlib.net), by Jean-loup Gailly (compression) and Mark Adler (decompression). Licensed under [zlib License](http://www.zlib.net/zlib_license.html).
2. [puff](https://github.com/madler/zlib/tree/master/contrib/puff), by Mark Adler. Licensed under zlib License.
3. [LibCompress](https://www.wowace.com/projects/libcompress), by jjsheets and Galmok of European Stormrage (Horde). Licensed under GPLv2.
4. [WeakAuras2](https://github.com/WeakAuras/WeakAuras2). Licensed under GPLv2.

## License
LibDeflate is licensed under GNU General Public License Version 3 or later.
