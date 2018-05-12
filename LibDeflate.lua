--[[--
	LibDeflate
	Pure Lua compressors and decompressors of the DEFLATE/zlib format.

	@author Haoqian He
		(Github: SafeteeWoW; World of Warcraft: Safetyy-Illidan(US))
	@copyright LibDeflate <2018> Haoqian He

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <https://www.gnu.org/licenses/>.

	Credits:
	1. zlib, by Jean-loup Gailly (compression) and Mark Adler (decompression).
		<http://www.zlib.net/>
		Licensed under Zlib License. <http://www.zlib.net/zlib_license.html>

		zlib is a wildly use library of the DEFLATE implementation.
		LibDeflate uses some algorithm of the zlib, and use zlib related
		program in the test script.

	2. puff, by Mark Adler.
	TODO
]]

------------------------------------------------------------------------------

--[[
	This library is implemented according to the following specifications.
	Both compressors and decompressors have been implemented in the library.
	1. RFC1950: DEFLATE Compressed Data Format Specification version 1.3
		<https://tools.ietf.org/html/rfc1951>
	2. RFC1951: ZLIB Compressed Data Format Specification version 3.3
		<https://tools.ietf.org/html/rfc1950>

	This library requires Lua 5.1+ interpreter or LuaJIT v2.0+.
	This library does not have any external library dependencies.
	(Exception: will register in the World of Warcraft library "LibStub",
	if detected). This is a pure Lua implementation. Therefore, no Lua
	C API is used. This file "LibDeflate.lua" is the only source file of
	the library.

	If your Lua distribution does not include all Lua Standary libraries,
	then the following Lua standard libraries are REQUIRED:
	1. string
	2. table

	The following Lua standard libraries are NOT used by this library,
	thus it is NOT REQUIRED to have them in your Lua to run this library:
	1. coroutine
	2. debug
	3. io
	4. math
	5. os
--]]

--[[
	key of the configuration table is the compression level,
	and its value stores the compression setting.
	These numbers come from zlib source code.

	Higher compression level usually means better compression.
	(Because LibDeflate uses a simplified version of zlib algorithm,
	there is no guarantee that higher compression level does not create
	bigger file than lower level, but I can say it's 99% likely)

	Be careful with the high compression level. This is a pure lua
	implementation compressor/decompressor, which is significant slower than
	a C/C++ equivalant compressor/decompressor. Very high compression level
	costs significant more CPU time, and usually compression size won't be
	significant smaller when you increase compression level by 1, when the
	level is already very high. Benchmark yourself if you can afford it.

	See also https://github.com/madler/zlib/blob/master/doc/algorithm.txt,
	https://github.com/madler/zlib/blob/master/deflate.c for more information.

	The meaning of each field:
	@field 1 use_lazy_evaluation:
		true/false. Whether the program uses lazy evaluation.
		See what is "lazy evaluation" in the link above.
		lazy_evaluation improves ratio, but relatively slow.
	@field 2 good_prev_length:
		Only effective if lazy is set, Only use 1/4 of max_chain,
		if prev length of lazy match is above this.
	@field 3 max_insert_length/max_lazy_match:
		If not using lazy evaluation,
		insert new strings in the hash table only if the match length is not
		greater than this length. Only continue lazy evaluation.
		If using lazy evaluation,
		only continue lazy evaluation,
		if prev length is strictly smaller than this.
	@field 4 nice_length:
		Number. Don't continue to go down the hash chain,
		if match length is above this.
	@field 5 max_chain:
		Number. The maximum number of hash chains we look.
--]]
local _compression_level_config = {
	[1] = {false, nil, 4, 8, 4}, -- level 1, similar to zlib level 1
	[2] = {false, nil, 5, 18, 8}, -- level 2, similar to zlib level 2
	[3] = {false, nil, 6, 32, 32},	-- level 3, similar to zlib level 3
	[4] = {true, 4,	4, 16, 16},	-- level 4, similar to zlib level 4
	[5] = {true, 8,	16,	32,	32}, -- level 5, similar to zlib level 5
	[6] = {true, 8,	16,	128, 128}, -- level 6, similar to zlib level 6
	[7] = {true, 8,	32,	128, 256}, -- (SLOW) level 7, similar to zlib level 7
	[8] = {true, 32, 128, 258,1024} ,-- (SLOW) level 8, similar to zlib level 8
	[9] = {true, 32, 258, 258, 4096},
		-- (VERY SLOW) level 9, similar to zlib level 9
}

local LibDeflate

do
	local _COPYRIGHT =
	"LibDeflate 0.1.0-alpha1 Copyright 2018 Haoqian He. Licensed under GPLv3"
	-- Semantic version. all lowercase.
	-- Suffix can be alpha1, alpha2, beta1, beta2, rc1, rc2, etc.
	local _VERSION = "0.1.0-alpha1"

	-- Register in the World of Warcraft library "LibStub" if detected.
	if LibStub then
		local MAJOR, MINOR = "LibDeflate", -1
		-- When MAJOR is changed, I should name it as LibDeflate2
		local lib, minor = LibStub:GetLibrary(MAJOR, true)
		if lib and minor and minor >= MINOR then -- No need to update.
			return lib
		else -- Update or first time register
			LibDeflate = LibStub:NewLibrary(MAJOR, _VERSION)
			-- NOTE: It is important that new version has implemented
			-- all exported APIs and tables in the old version,
			-- so the old library is fully garbage collected,
			-- and we 100% ensure the backward compatibility.
		end
	else -- "LibStub" is not detected.
		LibDeflate = {}
	end

	LibDeflate._VERSION = _VERSION
	LibDeflate._COPYRIGHT = _COPYRIGHT
end

-- localize Lua api for faster access.
local assert = assert
local error = error
local pairs = pairs
local string_byte = string.byte
local string_char = string.char
local string_gsub = string.gsub
local string_sub = string.sub
local table_concat = table.concat
local table_sort = table.sort
local type = type

-- Converts i to 2 to power of i, (0<=i<=31)
local _pow2 = {}

-- Converts any byte to a character, (0<=byte<=255)
local _byte_to_char = {}

-- _reverseBitsTbl[len][val] stores the bit reverse of
-- the number with bit length "len" and value "val"
-- For example, decimal number 6 with bits length 5 is binary 00110
-- It's reverse is binary 01100,
-- which is decimal 12 and 12 == _reverseBitsTbl[5][6]
local _reverse_bits_tbl = {}

-- Convert a LZ77 length (3<=len<=258) to
-- a deflate literal/LZ77_length code (257<=code<=285)
local _length_to_deflate_code = {}

-- convert a LZ77 length (3<=len<=258) to
-- a deflate literal/LZ77_length code extra bits.
local _length_to_deflate_extra_bits = {}

-- Convert a LZ77 length (3<=len<=258) to
-- a deflate literal/LZ77_length code extra bit length.
local _length_to_deflate_extra_bitlen = {}

-- Convert a small LZ77 distance (1<=dist<=256) to a deflate code.
local _dist256_to_deflate_code = {}

-- Convert a small LZ77 distance (1<=dist<=256) to
-- a deflate distance code extra bits.
local _dist256_to_deflate_extra_bits = {}

-- Convert a small LZ77 distance (1<=dist<=256) to
-- a deflate distance code extra bit length.
local _dist256_to_deflate_extra_bitlen = {}

-- Convert a literal/LZ77_length deflate code to LZ77 base length
-- The key of the table is (code - 256), 257<=code<=285
local _literal_deflate_code_to_base_len = {
	3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
	35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258}

-- Convert a literal/LZ77_length deflate code to base LZ77 length extra bits
-- The key of the table is (code - 256), 257<=code<=285
local _literal_deflate_code_to_extra_bitlen = {
	0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
	3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0}

-- Convert a distance deflate code to base LZ77 distance. (0<=code<=29)
local _dist_deflate_code_to_base_dist = {
	[0] = 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
	257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
	8193, 12289, 16385, 24577}

-- Convert a distance deflate code to LZ77 bits length. (0<=code<=29)
local _dist_deflate_code_to_extra_bitlen = {
	[0] = 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
	7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
	12, 12, 13, 13}

-- The code order of the first huffman header in the dynamic deflate block.
-- See the page 12 of RFC1951
local _hclen_code_order = {16, 17, 18,
	0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15}

-- The following tables are used by fixed deflate block.
-- The value of these tables are assigned at the bottom of the source.

-- The huffman code of the literal/LZ77_length deflate codes.
local _fix_block_literal_huffman_code

-- Convert huffman code of the literal/LZ77_length to deflate codes.
local _fix_block_literal_huffman_to_deflate_code

-- The bit length of the huffman code of literal/LZ77_length deflate codes.
local _fix_block_literal_huffman_bitlen

-- The count of each bit length of the literal/LZ77_length deflate codes.
local _fix_block_literal_huffman_bitlen_count

-- The huffman code of the distance deflate codes.
local _fix_block_dist_huffman_code

-- Convert huffman code of the distance to deflate codes.
local _fix_block_dist_huffman_to_deflate_code

-- The bit length of the huffman code of the distance deflate codes.
local _fix_block_dist_huffman_bitlen

-- The count of each bit length of the huffman code of 
-- the distance deflate codes.
local _fix_block_dist_huffman_bitlen_count

for i=0, 255 do
	_byte_to_char[i] = string_char(i)
end

do
	local pow = 1
	for i=0, 31 do
		_pow2[i] = pow
		pow = pow*2
	end
end

for i=1, 9 do
	_reverse_bits_tbl[i] = {}
	for j=0, _pow2[i+1]-1 do
		local res = 0
		local code = j
		for _=1, i do
			res = res - res%2 + (((res%2==1) or (code % 2) == 1) and 1 or 0) -- res | (code%2)
			code = (code-code%2)/2
			res = res*2
		end
		_reverse_bits_tbl[i][j] = (res-res%2)/2
	end
end

do
	local a = 18
	local b = 16
	local c = 265
	local bitsLen = 1
	for len=3, 258 do
		if len <= 10 then
			_length_to_deflate_code[len] = len + 254
			_length_to_deflate_extra_bitlen[len] = 0
		elseif len == 258 then
			_length_to_deflate_code[len] = 285
			_length_to_deflate_extra_bitlen[len] = 0
		else
			if len > a then
				a = a + b
				b = b * 2
				c = c + 4
				bitsLen = bitsLen + 1
			end
			local t = len-a-1+b/2
			_length_to_deflate_code[len] = (t-(t%(b/8)))/(b/8) + c
			_length_to_deflate_extra_bitlen[len] = bitsLen
			_length_to_deflate_extra_bits[len] = t % (b/8)
		end
	end
end


do
	_dist256_to_deflate_code[1] = 0
	_dist256_to_deflate_code[2] = 1
	_dist256_to_deflate_extra_bitlen[1] = 0
	_dist256_to_deflate_extra_bitlen[2] = 0

	local a = 3
	local b = 4
	local code = 2
	local bitsLen = 0
	for dist=3, 256 do
		if dist > b then
			a = a * 2
			b = b * 2
			code = code + 2
			bitsLen = bitsLen + 1
		end
		_dist256_to_deflate_code[dist] = (dist <= a) and code or (code+1)
		_dist256_to_deflate_extra_bitlen[dist] = (bitsLen < 0) and 0 or bitsLen
		if b >= 8 then
			_dist256_to_deflate_extra_bits[dist] = (dist-b/2-1) % (b/4)
		end
	end
end

local function CreateWriter()
	local bufferSize = 0
	local cache = 0
	local cacheBitRemaining = 0
	local buffer = {}

	local function WriteBits(code, bitLength)
		cache = cache + code * _pow2[cacheBitRemaining]
		cacheBitRemaining = bitLength + cacheBitRemaining
		if cacheBitRemaining >= 32 then
			-- we have at least 4 bytes to store; bulk it
			buffer[bufferSize+1] = _byte_to_char[cache % 256]
			buffer[bufferSize+2] = _byte_to_char[((cache-cache%256)/256 % 256)]
			buffer[bufferSize+3] = _byte_to_char[((cache-cache%65536)/65536 % 256)]
			buffer[bufferSize+4] = _byte_to_char[((cache-cache%16777216)/16777216 % 256)]
			bufferSize = bufferSize + 4
			local rShiftMask = _pow2[32 - cacheBitRemaining + bitLength]
			cache = (code - code%rShiftMask)/rShiftMask
			cacheBitRemaining = cacheBitRemaining - 32
		end
	end

	local function Flush(fullFlush)
		local ret
		if fullFlush then
			local paddingBit = (8-cacheBitRemaining%8)%8
			if cacheBitRemaining > 0 then
				for _=1, cacheBitRemaining, 8 do
					bufferSize = bufferSize + 1
					buffer[bufferSize] = string_char(cache % 256)
					cache = (cache-cache%256)/256
				end
				cache = 0
				cacheBitRemaining = 0
			end
			ret = table_concat(buffer)
			buffer = {ret}
			bufferSize = 1
			return ret, ret:len()*8-paddingBit
		else
			ret = table_concat(buffer)
			buffer = {ret}
			bufferSize = 1
			return ret, ret:len()*8+cacheBitRemaining
		end
	end

	local function WriteString(str)
		assert(cacheBitRemaining%8==0)
		for _=1, cacheBitRemaining, 8 do
			bufferSize = bufferSize + 1
			buffer[bufferSize] = string_char(cache % 256)
			cache = (cache-cache%256)/256
		end
		cacheBitRemaining = 0
		bufferSize = bufferSize + 1
		buffer[bufferSize] = str
	end

	return WriteBits, Flush, WriteString
end

--- Push an element into a max heap
-- Assume element is a table and we compare it using its first value table[1]
local function MinHeapPush(heap, e, heapSize)
	heapSize = heapSize + 1
	heap[heapSize] = e
	local value = e[1]
	local pos = heapSize
	local parentPos = (pos-pos%2)/2

	while (parentPos >= 1 and heap[parentPos][1] > value) do
		local t = heap[parentPos]
		heap[parentPos] = e
		heap[pos] = t
		pos = parentPos
		parentPos = (parentPos-parentPos%2)/2
	end
end

--- Pop an element from a max heap
-- Assume element is a table and we compare it using its first value table[1]
-- Note: This function does not change table size
local function MinHeapPop(heap, heapSize)
	local top = heap[1]
	local e = heap[heapSize]
	local value = e[1]
	heap[1] = e
	heap[heapSize] = top
	heapSize = heapSize - 1

	local pos = 1
	local leftChildPos = pos*2
	local rightChildPos = leftChildPos + 1

	while (leftChildPos <= heapSize) do
		local leftChild = heap[leftChildPos]
		if (rightChildPos <= heapSize and heap[rightChildPos][1] < leftChild[1]) then
			local rightChild = heap[rightChildPos]
			if rightChild[1] < value then
				heap[rightChildPos] = e
				heap[pos] = rightChild
				pos = rightChildPos
				leftChildPos = pos*2
				rightChildPos = leftChildPos + 1
			else
				break
			end
		else
			if leftChild[1] < value then
				heap[leftChildPos] = e
				heap[pos] = leftChild
				pos = leftChildPos
				leftChildPos = pos*2
				rightChildPos = leftChildPos + 1
			else
				break
			end
		end
	end

	return top
end

local function GetHuffmanCodeFromBitLength(bitLengthCount, symbolBitLength, maxSymbol, maxBitLength)
	local code = 0
	local nextCode = {}
	local symbolCode = {}
	for bitLength = 1, maxBitLength do
		code = (code+(bitLengthCount[bitLength-1] or 0))*2
		nextCode[bitLength] = code
	end
	for symbol = 0, maxSymbol do
		local len = symbolBitLength[symbol]
		if len then
			code = nextCode[len]
			nextCode[len] = code + 1

			-- Reverse the bits of "code"
			local res = 0
			for _=1, len do
				res = res - res%2 + (((res%2==1) or (code % 2) == 1) and 1 or 0) -- res | (code%2)
				code = (code-code%2)/2
				res = res*2
			end
			symbolCode[symbol] = (res-res%2)/2 -- Bit reverse of the variable "code"
		end
	end
	return symbolCode
end

local function SortByFirstThenSecond(a, b)
	return a[1] < b[1] or
		(a[1] == b[1] and a[2] < b[2])
	 -- This is important so our result is stable regardless of interpreter implementation.
end

--@treturn {table, table} symbol length table and symbol code table
local function GetHuffmanBitLengthAndCode(symCount, maxBitLength, maxSymbol)
	local heapSize
	local maxNonZeroLenSym = -1
	local leafs = {}
	local heap = {}
	local symbolBitLength = {}
	local symbolCode = {}
	local bitLengthCount = {}

	--[[
		tree[1]: weight, temporarily used as parent and bitLengths
		tree[2]: symbol
		tree[3]: left child
		tree[4]: right child
	--]]
	local uniqueSymbols = 0
	for symbol, count in pairs(symCount) do
		uniqueSymbols = uniqueSymbols + 1
		leafs[uniqueSymbols] = {count, symbol}
	end

	if (uniqueSymbols == 0) then
		return {}, {}, -1
	elseif (uniqueSymbols == 1) then -- Special case
		local sym = leafs[1][2]
		symbolBitLength[sym] = 1
		symbolCode[sym] = 0
		return symbolBitLength, symbolCode, sym
	else
		table_sort(leafs, SortByFirstThenSecond)
		heapSize = uniqueSymbols
		for i=1, heapSize do
			heap[i] = leafs[i]
		end

		while (heapSize > 1) do
			local leftChild = MinHeapPop(heap, heapSize) -- Note: pop does not change table size
			heapSize = heapSize - 1
			local rightChild = MinHeapPop(heap, heapSize)
			heapSize = heapSize - 1
			local newNode = {leftChild[1]+rightChild[1], -1, leftChild, rightChild}
			MinHeapPush(heap, newNode, heapSize)
			heapSize = heapSize + 1
		end

		local overflow = 0 -- Number of leafs whose bit length is greater than 15.
		-- Deflate does not allow any bit length greater than 15.

		-- Calculate bit length of all nodes
		local fifo = {heap[1], 0, 0, 0} -- preallocate some spaces.
		local fifoSize = 1
		local index = 1
		heap[1][1] = 0
		while (index <= fifoSize) do -- Breath first search
			local e = fifo[index]
			local bitLength = e[1]
			local sym = e[2]
			local leftChild = e[3]
			local rightChild = e[4]
			if leftChild then
				fifoSize = fifoSize + 1
				fifo[fifoSize] = leftChild
				leftChild[1] = bitLength + 1
			end
			if rightChild then
				fifoSize = fifoSize + 1
				fifo[fifoSize] = rightChild
				rightChild[1] = bitLength + 1
			end
			index = index + 1

			if (bitLength > maxBitLength) then
				overflow = overflow + 1
				bitLength = maxBitLength
			end
			if sym >= 0 then
				symbolBitLength[sym] = bitLength
				maxNonZeroLenSym = (sym > maxNonZeroLenSym) and sym or maxNonZeroLenSym
				bitLengthCount[bitLength] = (bitLengthCount[bitLength] or 0) + 1
			end
		end

		-- Resolve overflow (Huffman tree with any nodes bit length greater than 15)
		-- See ZLib/trees.c:gen_bitlen(s, desc)
		if (overflow > 0) then
			-- Update bitLengthCount
			repeat
				local bitLength = maxBitLength - 1
				while ((bitLengthCount[bitLength] or 0) == 0) do
					bitLength = bitLength - 1
				end
				bitLengthCount[bitLength] = bitLengthCount[bitLength] - 1 -- move one leaf down the tree
				-- move one overflow item as its brother
				bitLengthCount[bitLength+1] = (bitLengthCount[bitLength+1] or 0) + 2
				bitLengthCount[maxBitLength] = bitLengthCount[maxBitLength] - 1
				overflow = overflow - 2
			until (overflow <= 0)

			-- Update symbolBitLength
			index = 1
			for bitLength = maxBitLength, 1, -1 do
				local n = bitLengthCount[bitLength] or 0
				while (n > 0) do
					local sym = leafs[index][2]
					symbolBitLength[sym] = bitLength
					maxNonZeroLenSym = (sym > maxNonZeroLenSym) and sym or maxNonZeroLenSym
					n = n - 1
					index = index + 1
				end
			end
		end

		symbolCode = GetHuffmanCodeFromBitLength(bitLengthCount, symbolBitLength, maxSymbol, maxBitLength)
		return symbolBitLength, symbolCode, maxNonZeroLenSym
	end
end

local function RunLengthEncodeHuffmanLens(lcodeLens, maxNonZeroLenlCode, dcodeLens, maxNonZeroLendCode)
	local rleCodesTblLen = 0
	local rleCodes = {}
	local rleCodesCount = {}
	local rleExtraBitsTblLen = 0
	local rleExtraBits = {}
	local prev = nil
	local count = 0
	maxNonZeroLendCode = (maxNonZeroLendCode < 0) and 0 or maxNonZeroLendCode
	local maxCode = maxNonZeroLenlCode+maxNonZeroLendCode+1

	for code = 0, maxCode+1 do
		local len = (code <= maxNonZeroLenlCode) and (lcodeLens[code] or 0) or
			((code <= maxCode) and (dcodeLens[code-maxNonZeroLenlCode-1] or 0) or nil)
		if len == prev then
			count = count + 1
			if len ~= 0 and count == 6 then
				rleCodesTblLen = rleCodesTblLen + 1
				rleCodes[rleCodesTblLen] = 16
				rleExtraBitsTblLen = rleExtraBitsTblLen + 1
				rleExtraBits[rleExtraBitsTblLen] = 3
				rleCodesCount[16] = (rleCodesCount[16] or 0) + 1
				count = 0
			elseif len == 0 and count == 138 then
				rleCodesTblLen = rleCodesTblLen + 1
				rleCodes[rleCodesTblLen] = 18
				rleExtraBitsTblLen = rleExtraBitsTblLen + 1
				rleExtraBits[rleExtraBitsTblLen] = 127
				rleCodesCount[18] = (rleCodesCount[18] or 0) + 1
				count = 0
			end
		else
			if count == 1 then
				rleCodesTblLen = rleCodesTblLen + 1
				rleCodes[rleCodesTblLen] = prev
				rleCodesCount[prev] = (rleCodesCount[prev] or 0) + 1
			elseif count == 2 then
				rleCodesTblLen = rleCodesTblLen + 1
				rleCodes[rleCodesTblLen] = prev
				rleCodesTblLen = rleCodesTblLen + 1
				rleCodes[rleCodesTblLen] = prev
				rleCodesCount[prev] = (rleCodesCount[prev] or 0) + 2
			elseif count >= 3 then
				rleCodesTblLen = rleCodesTblLen + 1
				local rleCode = (prev ~= 0) and 16 or (count <= 10 and 17 or 18)
				rleCodes[rleCodesTblLen] = rleCode
				rleCodesCount[rleCode] = (rleCodesCount[rleCode] or 0) + 1
				rleExtraBitsTblLen = rleExtraBitsTblLen + 1
				rleExtraBits[rleExtraBitsTblLen] = (count <= 10) and (count - 3) or (count - 11)
			end

			prev = len
			if len and len ~= 0 then
				rleCodesTblLen = rleCodesTblLen + 1
				rleCodes[rleCodesTblLen] = len
				rleCodesCount[len] = (rleCodesCount[len] or 0) + 1
				count = 0
			else
				count = 1
			end
		end
	end

	return rleCodes, rleExtraBits, rleCodesTblLen, rleCodesCount
end

local function loadStrToTable(str, t, start, stop, offset)
	local i=start-offset
	while i <= stop - 15-offset do
		t[i], t[i+1], t[i+2], t[i+3], t[i+4], t[i+5], t[i+6], t[i+7],
			t[i+8], t[i+9], t[i+10], t[i+11], t[i+12], t[i+13], t[i+14], t[i+15] = string_byte(str, i+offset, i+15+offset)
		i = i + 16
	end
	while (i <= stop-offset) do
		t[i] = string_byte(str, i+offset, i+offset)
		i = i + 1
	end
	return t
end

local function CompressBlockLZ77(level, strTable, hashTables, blockStart, blockEnd, offset, dictionary)
	if not level then
		level = 5
	end

	local config = _compression_level_config[level]
	local config_use_lazy, config_good_prev_length, config_max_lazy_match, config_nice_length
		, config_max_hash_chain = config[1], config[2], config[3], config[4], config[5]

	local config_max_insert_length = (not config_use_lazy) and config_max_lazy_match or 2147483646
	local config_good_hash_chain = (config_max_hash_chain-config_max_hash_chain%4/4)

	local hash


	local dictHashTables
	local dictStrTable
	local dictStrLen = 0
	if dictionary then
		dictHashTables = dictionary.hashTables
		dictStrTable = dictionary.strTable
		dictStrLen = dictionary.strLen
		assert(blockStart == 1)
		if blockEnd >= blockStart and dictStrLen >= 2 then
			hash = dictStrTable[dictStrLen-1]*65536+dictStrTable[dictStrLen]*256+strTable[1]
			local t = hashTables[hash] or {-1}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = -1 end
		end
		if blockEnd >= blockStart+1 and dictStrLen >= 1 then
			hash = dictStrTable[dictStrLen]*65536+strTable[1]*256+strTable[2]
			local t = hashTables[hash] or {0}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = 0 end
		end
	end

	hash = (strTable[blockStart-offset] or 0)*256 + (strTable[blockStart+1-offset] or 0)

	-- Only hold max of 64KB string in the strTable at one time.
	-- When we have read half of it, wipe the first 32KB bytes of the strTable and load the next 32KB.
	-- Don't bother this if the input string is shorter than 64KB.
	-- This is to set a cap on memory, so we don't run out of memory when the file is large.
	local lCodes = {}
	local lCodeTblSize = 0
	local lCodesCount = {}
	local dCodes = {}
	local dCodeTblSize = 0
	local dCodesCount = {}

	local lExtraBits = {}
	local lExtraBitTblSize = 0
	local dExtraBits = {}
	local dExtraBitTblSize = 0

	local matchAvailable = false
	local prevLen
	local prevDist
	local curLen = 0
	local curDist = 0

	local index = blockStart
	local indexEnd = blockEnd + (config_use_lazy and 1 or 0)
	while (index <= indexEnd) do
		local strTableIndex = index - offset
		prevLen = curLen
		prevDist = curDist
		curLen = 0

		hash = (hash*256+(strTable[strTableIndex+2] or 0))%16777216

		local hashChain = hashTables[hash]
		if not hashChain then
			hashChain = {}
			hashTables[hash] = hashChain
		end
		local chainSize = #hashChain

		if (index+2 <= blockEnd and (not config_use_lazy or prevLen < config_max_lazy_match)) then
			local i = chainSize
			local curChain = hashChain
			if i == 0 and dictHashTables then
				curChain = dictHashTables[hash]
				i = curChain and #curChain or 0
			end
			local depth = (config_use_lazy and prevLen >= config_good_prev_length) and
				config_good_hash_chain or config_max_hash_chain

			while i >= 1 and depth > 0 do
				local prev = curChain[i]

				if index - prev > 32768 then
					break
				end
				if prev < index then
					local j = 3

					if prev >= -257 then -- TODO: Check boundary
						local prevStrTableIndex = prev-offset
						while (j < 258 and index + j < blockEnd) do
							if (strTable[prevStrTableIndex+j] == strTable[strTableIndex+j]) then
								j = j + 1
							else
								break
							end
						end
					else
						local prevStrTableIndex = dictStrLen+prev
						while (j < 258 and index + j < blockEnd) do
							if (dictStrTable[prevStrTableIndex+j] == strTable[strTableIndex+j]) then
								j = j + 1
							else
								break
							end
						end
					end
					if j > curLen then
						curLen = j
						curDist = index - prev
					end
					if curLen >= config_nice_length then
						break
					end
				end

				i = i - 1
				depth = depth - 1
				if i == 0 and prev > 0 and dictHashTables then
					curChain = dictHashTables[hash]
					i = curChain and #curChain or 0
				end
			end
		end

		if index <= blockEnd then
			hashChain[chainSize+1] = index
		end

		if not config_use_lazy then
			prevLen, prevDist = curLen, curDist
		end
		if ((not config_use_lazy or matchAvailable) and (prevLen > 3 or (prevLen == 3 and prevDist < 4096))
		and curLen <= prevLen )then
			local code = _length_to_deflate_code[prevLen]
			local lenExtraBitsLength = _length_to_deflate_extra_bitlen[prevLen]
			local distCode, distExtraBitsLength, distExtraBits
			if prevDist <= 256 then
				distCode = _dist256_to_deflate_code[prevDist]
				distExtraBits = _dist256_to_deflate_extra_bits[prevDist]
				distExtraBitsLength =  _dist256_to_deflate_extra_bitlen[prevDist]
			else
				distCode = 16
				distExtraBitsLength = 7
				local a = 384
				local b = 512

				while true do
					if prevDist <= a then
						distExtraBits = (prevDist-(b/2)-1) % (b/4)
						break
					elseif prevDist <= b then
						distExtraBits = (prevDist-(b/2)-1) % (b/4)
						distCode = distCode + 1
						break
					else
						distCode = distCode + 2
						distExtraBitsLength = distExtraBitsLength + 1
						a = a*2
						b = b*2
					end
				end
			end
			lCodeTblSize = lCodeTblSize + 1
			lCodes[lCodeTblSize] = code
			lCodesCount[code] = (lCodesCount[code] or 0) + 1

			dCodeTblSize = dCodeTblSize + 1
			dCodes[dCodeTblSize] = distCode
			dCodesCount[distCode] = (dCodesCount[distCode] or 0) + 1

			if lenExtraBitsLength > 0 then
				local lenExtraBits = _length_to_deflate_extra_bits[prevLen]
				lExtraBitTblSize = lExtraBitTblSize + 1
				lExtraBits[lExtraBitTblSize] = lenExtraBits
			end
			if distExtraBitsLength > 0 then
				dExtraBitTblSize = dExtraBitTblSize + 1
				dExtraBits[dExtraBitTblSize] = distExtraBits
			end

			for i=index+1, index+prevLen-(config_use_lazy and 2 or 1) do
				hash = (hash*256+(strTable[i-offset+2] or 0))%16777216
				if prevLen <= config_max_insert_length then
					hashChain = hashTables[hash]
					if not hashChain then
						hashChain = {}
						hashTables[hash] = hashChain
					end
					hashChain[#hashChain+1] = i
				end
			end
			index = index + prevLen - (config_use_lazy and 1 or 0)
			matchAvailable = false
		elseif (not config_use_lazy) or matchAvailable then
			local code = strTable[config_use_lazy and (strTableIndex-1) or strTableIndex]
			lCodeTblSize = lCodeTblSize + 1
			lCodes[lCodeTblSize] = code
			lCodesCount[code] = (lCodesCount[code] or 0) + 1
			index = index + 1
		else
			matchAvailable = true
			index = index + 1
		end
	end

	lCodeTblSize = lCodeTblSize + 1
	lCodes[lCodeTblSize] = 256
	lCodesCount[256] = (lCodesCount[256] or 0) + 1

	return lCodes, lExtraBits, lCodesCount, dCodes, dExtraBits, dCodesCount
end

local function GetBlockDynamicHuffmanHeader(lCodesCount, dCodesCount)
	local lCodeLens, lCodeCodes, maxNonZeroLenlCode = GetHuffmanBitLengthAndCode(lCodesCount, 15, 285)
	local dCodeLens, dCodeCodes, maxNonZeroLendCode = GetHuffmanBitLengthAndCode(dCodesCount, 15, 29)

	local rleCodes, rleExtraBits, _, rleCodesCount =
		RunLengthEncodeHuffmanLens(lCodeLens, maxNonZeroLenlCode, dCodeLens, maxNonZeroLendCode)

	local codeLensCodeLens, codeLensCodeCodes = GetHuffmanBitLengthAndCode(rleCodesCount, 7, 18)

	local HCLEN = 0
	for i=1, 19 do
		local symbol = _hclen_code_order[i]
		local length = codeLensCodeLens[symbol] or 0
		if length ~= 0 then
			HCLEN = i
		end
	end

	HCLEN = HCLEN - 4
	local HLIT = maxNonZeroLenlCode + 1 - 257 -- # of Literal/Length codes - 257 (257 - 286)
	local HDIST = maxNonZeroLendCode + 1 - 1 -- # of Distance codes - 1 (1 - 32)
	if HDIST < 0 then HDIST = 0 end

	return HLIT, HDIST, HCLEN, codeLensCodeLens, codeLensCodeCodes, rleCodes, rleExtraBits
		, lCodeLens, lCodeCodes, dCodeLens, dCodeCodes
end

local function GetBlockDynamicHuffmanSize(
		lCodes, dCodes, HCLEN, codeLensCodeLens, rleCodes, lCodeLens, dCodeLens)

	local blockBitSize = 17 -- 1+2+5+5+4
	blockBitSize = blockBitSize + (HCLEN+4)*3

	for i=1, #rleCodes do
		local code = rleCodes[i]
		blockBitSize = blockBitSize + codeLensCodeLens[code]
		if code >= 16 then
			blockBitSize = blockBitSize + ((code == 16) and 2 or (code == 17 and 3 or 7))
		end
	end

	local lengthCodeCount = 0

	for i=1, #lCodes do
		local code = lCodes[i]
		local huffmanLength = lCodeLens[code]
		blockBitSize = blockBitSize + huffmanLength
		if code > 256 then -- Length code
			lengthCodeCount = lengthCodeCount + 1
			if code > 264 and code < 285 then -- Length code with extra bits
				local extraBitsLength = _literal_deflate_code_to_extra_bitlen[code-256]
				blockBitSize = blockBitSize + extraBitsLength
			end
			local distCode = dCodes[lengthCodeCount]
			local distHuffmanLength = dCodeLens[distCode]
			blockBitSize = blockBitSize + distHuffmanLength

			if distCode > 3 then -- dist code with extra bits
				local distExtraBitsLength = (distCode-distCode%2)/2 - 1
				blockBitSize = blockBitSize + distExtraBitsLength
			end
		end
	end
	return blockBitSize
end

local function CompressBlockDynamicHuffman(WriteBits, isLastBlock,
		lCodes, lExtraBits, dCodes, dExtraBits, HLIT, HDIST, HCLEN,
		codeLensCodeLens, codeLensCodeCodes, rleCodes, rleExtraBits, lCodeLens, lCodeCodes, dCodeLens, dCodeCodes)

	WriteBits(isLastBlock and 1 or 0, 1) -- Last block marker
	WriteBits(2, 2) -- Dynamic Huffman Code

	WriteBits(HLIT, 5)
	WriteBits(HDIST, 5)
	WriteBits(HCLEN, 4)

	for i = 1, HCLEN+4 do
		local symbol = _hclen_code_order[i]
		local length = codeLensCodeLens[symbol] or 0
		WriteBits(length, 3)
	end

	local rleExtraBitsIndex = 1
	for i=1, #rleCodes do
		local code = rleCodes[i]
		WriteBits(codeLensCodeCodes[code], codeLensCodeLens[code])
		if code >= 16 then
			local extraBits = rleExtraBits[rleExtraBitsIndex]
			WriteBits(extraBits, (code == 16) and 2 or (code == 17 and 3 or 7))
			rleExtraBitsIndex = rleExtraBitsIndex + 1
		end
	end

	local lengthCodeCount = 0
	local lengthCodeWithExtraCount = 0
	local distCodeWithExtraCount = 0

	for i=1, #lCodes do
		local code = lCodes[i]
		local huffmanCode = lCodeCodes[code]
		local huffmanLength = lCodeLens[code]
		WriteBits(huffmanCode, huffmanLength)
		if code > 256 then -- Length code
			lengthCodeCount = lengthCodeCount + 1
			if code > 264 and code < 285 then -- Length code with extra bits
				lengthCodeWithExtraCount = lengthCodeWithExtraCount + 1
				local extraBits = lExtraBits[lengthCodeWithExtraCount]
				local extraBitsLength = _literal_deflate_code_to_extra_bitlen[code-256]
				WriteBits(extraBits, extraBitsLength)
			end
			-- Write distance code
			local distCode = dCodes[lengthCodeCount]
			local distHuffmanCode = dCodeCodes[distCode]
			local distHuffmanLength = dCodeLens[distCode]
			WriteBits(distHuffmanCode, distHuffmanLength)

			if distCode > 3 then -- dist code with extra bits
				distCodeWithExtraCount = distCodeWithExtraCount + 1
				local distExtraBits = dExtraBits[distCodeWithExtraCount]
				local distExtraBitsLength = (distCode-distCode%2)/2 - 1
				WriteBits(distExtraBits, distExtraBitsLength)
			end
		end
	end
end

local function GetBlockFixHuffmanSize(lCodes, dCodes)
	local blockBitSize = 3
	local lengthCodeCount = 0
	for i=1, #lCodes do
		local code = lCodes[i]
		local huffmanLength = _fix_block_literal_huffman_bitlen[code]
		blockBitSize = blockBitSize + huffmanLength
		if code > 256 then -- Length code
			lengthCodeCount = lengthCodeCount + 1
			if code > 264 and code < 285 then -- Length code with extra bits
				local extraBitsLength = _literal_deflate_code_to_extra_bitlen[code-256]
				blockBitSize = blockBitSize + extraBitsLength
			end
			local distCode = dCodes[lengthCodeCount]
			blockBitSize = blockBitSize + 5

			if distCode > 3 then -- dist code with extra bits
				local distExtraBitsLength = (distCode-distCode%2)/2 - 1
				blockBitSize = blockBitSize + distExtraBitsLength
			end
		end
	end
	return blockBitSize
end

local function CompressBlockFixHuffman(WriteBits, isLastBlock,
		lCodes, lExtraBits, dCodes, dExtraBits)
	WriteBits(isLastBlock and 1 or 0, 1) -- Is last block?
	WriteBits(1, 2) -- fix Huffman Code
	local lengthCodeCount = 0
	local lengthCodeWithExtraCount = 0
	local distCodeWithExtraCount = 0
	for i=1, #lCodes do
		local code = lCodes[i]
		local huffmanCode = _fix_block_literal_huffman_code[code]
		local huffmanLength = _fix_block_literal_huffman_bitlen[code]
		WriteBits(huffmanCode, huffmanLength)
		if code > 256 then -- Length code
			lengthCodeCount = lengthCodeCount + 1
			if code > 264 and code < 285 then -- Length code with extra bits
				lengthCodeWithExtraCount = lengthCodeWithExtraCount + 1
				local extraBits = lExtraBits[lengthCodeWithExtraCount]
				local extraBitsLength = _literal_deflate_code_to_extra_bitlen[code-256]
				WriteBits(extraBits, extraBitsLength)
			end
			-- Write distance code
			local distCode = dCodes[lengthCodeCount]
			local distHuffmanCode = _fix_block_dist_huffman_code[distCode]
			WriteBits(distHuffmanCode, 5)

			if distCode > 3 then -- dist code with extra bits
				distCodeWithExtraCount = distCodeWithExtraCount + 1
				local distExtraBits = dExtraBits[distCodeWithExtraCount]
				local distExtraBitsLength = (distCode-distCode%2)/2 - 1
				WriteBits(distExtraBits, distExtraBitsLength)
			end
		end
	end
end

local function GetBlockStoreSize(blockStart, blockEnd, totalBitSize)
	assert(blockEnd-blockStart+1 <= 65535)
	local blockBitSize = 3
	totalBitSize = totalBitSize + 3
	local paddingBitLen = (8-totalBitSize%8)%8
	blockBitSize = blockBitSize + paddingBitLen
	blockBitSize = blockBitSize + 32
	blockBitSize = blockBitSize + (blockEnd - blockStart + 1) * 8
	return blockBitSize
end

local function CompressBlockStore(WriteBits, WriteString, isLastBlock, str, blockStart, blockEnd, totalBitSize)
	assert(blockEnd-blockStart+1 <= 65535)
	WriteBits(isLastBlock and 1 or 0, 1) -- Is last block?
	WriteBits(0, 2) -- store block
	totalBitSize = totalBitSize + 3
	local paddingBitLen = (8-totalBitSize%8)%8
	if paddingBitLen > 0 then
		WriteBits(_pow2[paddingBitLen]-1, paddingBitLen)
	end
	local size = blockEnd - blockStart + 1
	WriteBits(size, 16)

	-- Write size's one's complement
	local comp = (255 - size % 256) + (255 - (size-size%256)/256)*256
	WriteBits(comp, 16)

	WriteString(str:sub(blockStart, blockEnd))
end

local function Deflate(WriteBits, Flush, WriteString, str, level, dictionary)
	local strTable = {}
	local hashTables = {}
	local isLastBlock = nil
	local blockStart
	local blockEnd
	local result, bitsWritten
	local totalBitSize = select(2, Flush())
	local strLen = str:len()
	local offset
	while not isLastBlock do
		if not blockStart then
			blockStart = 1
			blockEnd = 64*1024 - 1
			offset = 0
		else
			blockStart = blockEnd + 1
			blockEnd = blockEnd + 32*1024
			offset = blockStart - 32*1024 - 1
		end

		if blockEnd >= strLen then
			blockEnd = strLen
			isLastBlock = true
		else
			isLastBlock = false
		end

		assert(blockEnd-blockStart+1 <= 65535) -- TODO: comment


		loadStrToTable(str, strTable, blockStart, blockEnd + 3, offset)

		if blockStart == 1 and dictionary then
			local dictStrTable = dictionary.strTable
			local dictStrLen = dictionary.strLen
			for i=0, (-dictStrLen+1)<-257 and -257 or (-dictStrLen+1), -1 do
				local dictChar = dictStrTable[dictStrLen+i]
				strTable[i] = dictChar
				assert(dictChar)
			end
		end
		local lCodes, lExtraBits, lCodesCount, dCodes, dExtraBits, dCodesCount =
			CompressBlockLZ77(level, strTable, hashTables, blockStart, blockEnd, offset, dictionary)

		local HLIT, HDIST, HCLEN, codeLensCodeLens, codeLensCodeCodes, rleCodes, rleExtraBits
			, lCodeLens, lCodeCodes, dCodeLens, dCodeCodes =
			GetBlockDynamicHuffmanHeader(lCodesCount, dCodesCount)
		local dynamicBlockBitSize = GetBlockDynamicHuffmanSize(
				lCodes, dCodes, HCLEN, codeLensCodeLens, rleCodes, lCodeLens, dCodeLens)
		local fixBlockBitSize = GetBlockFixHuffmanSize(lCodes, dCodes)
		local storeBlockBitSize = GetBlockStoreSize(blockStart, blockEnd, totalBitSize)

		local minBitSize = dynamicBlockBitSize
		minBitSize = (fixBlockBitSize < minBitSize) and fixBlockBitSize or minBitSize
		minBitSize = (storeBlockBitSize < minBitSize) and storeBlockBitSize or minBitSize

		if storeBlockBitSize == minBitSize then
			CompressBlockStore(WriteBits, WriteString, isLastBlock, str, blockStart, blockEnd, totalBitSize)
			totalBitSize = totalBitSize + storeBlockBitSize
		elseif fixBlockBitSize ==  minBitSize then
			CompressBlockFixHuffman(WriteBits, isLastBlock,
					lCodes, lExtraBits, dCodes, dExtraBits)
			totalBitSize = totalBitSize + fixBlockBitSize
		elseif dynamicBlockBitSize == minBitSize then
			CompressBlockDynamicHuffman(WriteBits, isLastBlock,
					lCodes, lExtraBits, dCodes, dExtraBits, HLIT, HDIST, HCLEN,
					codeLensCodeLens, codeLensCodeCodes, rleCodes, rleExtraBits, lCodeLens, lCodeCodes, dCodeLens, dCodeCodes)
			totalBitSize = totalBitSize + dynamicBlockBitSize
		end

		result, bitsWritten = Flush()
		assert(bitsWritten == totalBitSize , ("sth wrong in the bitSize calculation, %d %d")
			:format(bitsWritten, totalBitSize))

		-- Memory clean up, so memory consumption does not always grow linearly, even if input string is > 64K.
		if not isLastBlock then
			local j
			if dictionary and blockStart == 1 then
				j = 0
				while (strTable[j]) do
					strTable[j] = nil
					j = j - 1
				end
			end
			dictionary = nil
			j = 1
			for i=blockEnd-32767, blockEnd do
				strTable[j] = strTable[i-offset]
				j = j + 1
			end

			for k, t in pairs(hashTables) do
				local tSize = #t
				if tSize > 0 and blockEnd+1 - t[1] > 32768 then
					if tSize == 1 then
						hashTables[k] = nil
					else
						local new = {}
						local newSize = 0
						for i=2, tSize do
							j = t[i]
							if blockEnd+1 - j <= 32768 then
								newSize = newSize + 1
								new[newSize] = j
							end
						end
						hashTables[k] = new
					end
				end
			end
		end
	end
end

function LibDeflate:CompressDeflate(str, level, dictionary)
	assert(type(str)=="string")
	assert(type(level)=="nil" or (type(level)=="number" and level >= 1 and level <= 9))

	local WriteBits, Flush, WriteString = CreateWriter()

	Deflate(WriteBits, Flush, WriteString, str, level, dictionary)
	local result, totalBitSize = Flush(true)
	return result, totalBitSize
end

function LibDeflate:CompressZlib(str, level, dictionary)
	assert(type(str)=="string")
	assert(type(level)=="nil" or (type(level)=="number" and level >= 1 and level <= 9))

	local WriteBits, Flush, WriteString = CreateWriter()

	local CM = 8 -- Compression method
	local CINFO = 7 --Window Size = 32K
	local CMF = CINFO*16+CM
	WriteBits(CMF, 8)

	local FDIST = 0 -- No dictionary
	local FLEVEL = 2 -- Default compression
	local FLG = FLEVEL*64+FDIST*32
	local FCHECK = (31-(CMF*256+FLG)%31)
	-- The FCHECK value must be such that CMF and FLG, when viewed as a 16-bit unsigned integer stored
	-- in MSB order (CMF*256 + FLG), is a multiple of 31.
	FLG = FLG + FCHECK
	assert((CMF*256+FLG)%31 == 0)
	WriteBits(FLG, 8)

	Deflate(WriteBits, Flush, WriteString, str, level, dictionary)
	Flush(true)

	local adler = self:Adler32(str)

	-- Most significant byte first
	local byte0 = ((adler-adler%16777216)/16777216)%256
	local byte1 = ((adler-adler%65536)/65536)%256
	local byte2 = ((adler-adler%256)/256)%256
	local byte3 = adler%256
	WriteBits(byte0, 8)
	WriteBits(byte1, 8)
	WriteBits(byte2, 8)
	WriteBits(byte3, 8)
	local result, totalBitSize = Flush(true)

	return result, totalBitSize
end

function LibDeflate:Compress(str, level, dictionary)
	return self:CompressDeflate(str, level, dictionary)
end

------------------------------------------------------------------------------
------------------------------------------------------------------------------
local function CreateReader(inputString)
	local input = inputString
	local inputLen = inputString:len()
	local inputNextBytePos = 1
	local cacheBitRemaining = 0
	local cache = 0

	local function SkipToByteBoundary()
		local skippedBits = cacheBitRemaining%8
		local rShiftMask = _pow2[skippedBits]
		cacheBitRemaining = cacheBitRemaining - skippedBits
		cache = (cache - cache % rShiftMask) / rShiftMask
	end

	local function ReadBytes(length, buffer, bufferSize) -- Assume on the byte boundary
		assert(cacheBitRemaining % 8 == 0)

		local byteFromCache = (cacheBitRemaining/8 < length) and (cacheBitRemaining/8) or length
		for _=1, byteFromCache do
			local byte = cache % 256
			bufferSize = bufferSize + 1
			buffer[bufferSize] = string_char(byte)
			cache = (cache - byte) / 256
		end
		cacheBitRemaining = cacheBitRemaining - byteFromCache*8
		length = length - byteFromCache
		if (inputLen - inputNextBytePos - length + 1) * 8 + cacheBitRemaining < 0 then
			return -1 -- out of input
		end
		for i=inputNextBytePos, inputNextBytePos+length-1 do
			bufferSize = bufferSize + 1
			buffer[bufferSize] = string_sub(input, i, i)
		end

		inputNextBytePos = inputNextBytePos + length
		return bufferSize
	end

	-- To improve speed, this function does not check if the input has been exhausted.
	-- Use ReaderBitsLeft() < 0 to check it.
	local function ReadBits(length)
		local rShiftMask = _pow2[length]
		local code
		if length <= cacheBitRemaining then
			code = cache % rShiftMask
			cache = (cache - code) / rShiftMask
			cacheBitRemaining = cacheBitRemaining - length
		else -- Whether input has been exhausted is not checked.
			local lShiftMask = _pow2[cacheBitRemaining]
			local byte1, byte2, byte3, byte4 = string_byte(input, inputNextBytePos, inputNextBytePos+3)
			-- This requires lua number to be at least double ()
			cache = cache + ((byte1 or 0)+(byte2 or 0)*256+(byte3 or 0)*65536+(byte4 or 0)*16777216)*lShiftMask
			inputNextBytePos = inputNextBytePos + 4
			cacheBitRemaining = cacheBitRemaining + 32 - length
			code = cache % rShiftMask
			cache = (cache - code) / rShiftMask
		end
		return code
	end

	-- To improve speed, this function does not check if the input has been exhausted.
	-- Use ReaderBitsLeft() < 0 to check it.
	local function Decode(huffmanLenCount, huffmanSymbol, minLen)
		local code = 0
		local first = 0
		local index = 0
		local count
		if minLen > 0 then
			if cacheBitRemaining < 15 and input then
				local lShiftMask = _pow2[cacheBitRemaining]
				local byte1, byte2, byte3, byte4 = string_byte(input, inputNextBytePos, inputNextBytePos+3)
				-- This requires lua number to be at least double ()
				cache = cache + ((byte1 or 0)+(byte2 or 0)*256+(byte3 or 0)*65536+(byte4 or 0)*16777216)*lShiftMask
				inputNextBytePos = inputNextBytePos + 4
				cacheBitRemaining = cacheBitRemaining + 32
			end
			-- Whether input has been exhausted is not checked.

			local rShiftMask = _pow2[minLen]
			cacheBitRemaining = cacheBitRemaining - minLen
			code = cache % rShiftMask
			cache = (cache - code) / rShiftMask
			-- Reverse the bits
			code = _reverse_bits_tbl[minLen][code]

			count = huffmanLenCount[minLen]-- Number of codes of length len
			if code < count then
				return huffmanSymbol[code]
			end
			index = count
			first = count + count -- First code of length lenfirst = first + count
			code = code + code
		end

		for len = minLen+1, 15 do
			local bit
			bit = cache % 2
			cache = (cache - bit) / 2
			cacheBitRemaining = cacheBitRemaining - 1

			code = (bit==1) and (code + 1 - code % 2) or code -- (code |= ReadBits(1)) Get next bit
			count = huffmanLenCount[len] or 0
			local diff = code - first
			if diff < count then
				return huffmanSymbol[index + diff]
			end
			index = index + count
			first = first + count
			first = first + first
			code = code + code
		end
		return -10 -- invalid literal/length or distance code in fixed or dynamic block (run out of code)
	end

	local function ReaderBitsLeft()
		return (inputLen - inputNextBytePos + 1) * 8 + cacheBitRemaining
	end

	return ReadBits, ReadBytes, Decode, ReaderBitsLeft, SkipToByteBoundary
end

local function ConstructInflateHuffman(huffmanLen, n, maxBitLength)
	local huffmanLenCount = {}
	local minLen = 15
	for symbol = 0, n-1 do
		local len = huffmanLen[symbol] or 0
		minLen = (len > 0 and len < minLen) and len or minLen
		huffmanLenCount[len] = (huffmanLenCount[len] or 0) + 1
	end

	if huffmanLenCount[0] == n then -- No Codes
		return 0, huffmanLenCount, {}, 0  -- Complete, but decode will fail
	end

	local left = 1
	for len = 1, maxBitLength do
		left = left * 2
		left = left - (huffmanLenCount[len] or 0)
		if left < 0 then
			return left -- Over-subscribed, return negative
		end
	end

	-- Generate offsets info symbol table for each length for sorting
	local offs = {}
	offs[1] = 0
	for len = 1, maxBitLength-1 do
		offs[len + 1] = offs[len] + (huffmanLenCount[len] or 0)
	end

	local huffmanSymbol = {}
	for symbol = 0, n-1 do
		local len = huffmanLen[symbol] or 0
		if len ~= 0 then
			local offset = offs[len]
			huffmanSymbol[offset] = symbol
			offs[len] = offs[len] + 1
		end
	end

	-- Return zero for complete set, positive for incomplete set.
	return left, huffmanLenCount, huffmanSymbol, minLen
end

local function DecodeUntilEndOfBlock(state, litHuffmanLen, litHuffmanSym, litMinLen
	, distHuffmanLen, distHuffmanSym, distMinLen)
	local buffer, bufferSize, ReadBits, Decode, ReaderBitsLeft, result =
		state.buffer, state.bufferSize, state.ReadBits, state.Decode, state.ReaderBitsLeft, state.result
	local dictionary = state.dictionary
	local dictStrTable
	local dictStrLen

	local bufferEnd = 1
	if dictionary and not buffer[0] then -- TODO: explain not buffer[0]
		dictStrTable = dictionary.strTable
		dictStrLen = dictionary.strLen
		bufferEnd = -dictStrLen + 1
		for i=0, (-dictStrLen+1)<-257 and -257 or (-dictStrLen+1), -1 do
			local dictChar = _byte_to_char[dictStrTable[dictStrLen+i]]
			buffer[i] = dictChar
		end
	end

	repeat
		local symbol = Decode(litHuffmanLen, litHuffmanSym, litMinLen)
		if symbol < 0 or symbol > 285 then
			return -10 -- invalid literal/length or distance code in fixed or dynamic block
		elseif symbol < 256 then -- Literal
			bufferSize = bufferSize + 1
			buffer[bufferSize] = _byte_to_char[symbol]
		elseif symbol > 256 then -- Length code
			symbol = symbol - 256
			local length = _literal_deflate_code_to_base_len[symbol]
			length = (symbol >= 8) and (length + ReadBits(_literal_deflate_code_to_extra_bitlen[symbol])) or length
			symbol = Decode(distHuffmanLen, distHuffmanSym, distMinLen)
			if symbol < 0 or symbol > 29 then
				return -10 -- invalid literal/length or distance code in fixed or dynamic block
			end
			local dist = _dist_deflate_code_to_base_dist[symbol]
			dist = (dist > 4) and (dist + ReadBits(_dist_deflate_code_to_extra_bitlen[symbol])) or dist

			local charBufferIndex = bufferSize-dist+1
			if charBufferIndex < bufferEnd then
				return -11 -- distance is too far back in fixed or dynamic block
			end
			if charBufferIndex >= -257 then
				for _=1, length do
					bufferSize = bufferSize + 1
					buffer[bufferSize] = buffer[charBufferIndex]
					charBufferIndex = charBufferIndex + 1
				end
			else
				charBufferIndex = dictStrLen + charBufferIndex
				for _=1, length do
					bufferSize = bufferSize + 1
					buffer[bufferSize] = _byte_to_char[dictStrTable[charBufferIndex]]
					charBufferIndex = charBufferIndex + 1
				end
			end
		end

		if ReaderBitsLeft() < 0 then
			return 2 -- available inflate data did not terminate
		end

		if bufferSize >= 65536 then
			result = result..table_concat(buffer, "", 1, 32768)
			for i=32769, bufferSize do
				buffer[i-32768] = buffer[i]
			end
			bufferSize = bufferSize - 32768
			buffer[bufferSize+1] = nil
			-- NOTE: buffer[32769..end] and buffer[-257..0] are not cleared. This is why "bufferSize" variable is needed.
		end
	until symbol == 256

	state.bufferSize = bufferSize
	state.result = result

	return 0
end

-- TODO: Actually test store block
local function DecompressStoreBlock(state)
	local buffer, bufferSize, ReadBits, ReadBytes, ReaderBitsLeft, SkipToByteBoundary, result =
		state.buffer, state.bufferSize, state.ReadBits, state.ReadBytes, state.ReaderBitsLeft,
		state.SkipToByteBoundary, state.result

	SkipToByteBoundary()
	local len = ReadBits(16)
	if ReaderBitsLeft() < 0 then
		return 2 -- available inflate data did not terminate
	end
	local lenComp = ReadBits(16)
	if ReaderBitsLeft() < 0 then
		return 2 -- available inflate data did not terminate
	end

	if len % 256 + lenComp % 256 ~= 255 then
		return -2 -- Not one's complement
	end
	if (len-len % 256)/256 + (lenComp-lenComp % 256)/256 ~= 255 then
		return -2 -- Not one's complement
	end

	-- Note that ReadBytes will skip to the next byte boundary first.
	bufferSize = ReadBytes(len, buffer, bufferSize)
	if bufferSize < 0 then
		return 2 -- available inflate data did not terminate
	end
	if bufferSize >= 65536 then
		result = result..table_concat(buffer, "", 1, 32768)
		for i=32769, bufferSize do
			buffer[i-32768] = buffer[i]
		end
		bufferSize = bufferSize - 32768
		buffer[bufferSize+1] = nil
	end
	state.result = result
	state.bufferSize = bufferSize
	return 0
end

local function DecompressFixBlock(state)
	return DecodeUntilEndOfBlock(state, _fix_block_literal_huffman_bitlen_count, _fix_block_literal_huffman_to_deflate_code, 7,
		_fix_block_dist_huffman_bitlen_count, _fix_block_dist_huffman_to_deflate_code, 5)
end

local function DecompressDynamicBlock(state)
	local ReadBits, Decode = state.ReadBits, state.Decode
	local nLen = ReadBits(5) + 257
	local nDist = ReadBits(5) + 1
	local nCode = ReadBits(4) + 4
	if nLen > 286 or nDist > 30 then
		return -3 -- dynamic block code description: too many length or distance codes
	end

	local lengthLengths = {}

	for index=1, nCode do
		lengthLengths[_hclen_code_order[index]] = ReadBits(3)
	end

	local err, lenLenHuffmanLenCount, lenLenHuffmanSym, lenLenMinLen = ConstructInflateHuffman(lengthLengths, 19, 7)
	if err ~= 0 then -- Require complete code set here
		return -4 -- dynamic block code description: code lengths codes incomplete
	end

	local litHuffmanLen = {}
	local distHuffmanLen = {}
	-- Read length/literal and distance code length tables
	local index = 0
	while index < nLen + nDist do
		local symbol -- Decoded value
		local len -- Last length to repeat

		symbol = Decode(lenLenHuffmanLenCount, lenLenHuffmanSym, lenLenMinLen)

		if symbol < 0 then
			return symbol -- Invalid symbol
		elseif symbol < 16 then
			if index < nLen then
				litHuffmanLen[index] = symbol
			else
				distHuffmanLen[index-nLen] = symbol
			end
			index = index + 1
		else
			len = 0
			if symbol == 16 then
				if index == 0 then
					return -5 -- dynamic block code description: repeat lengths with no first length
				end
				if index-1 < nLen then
					len = litHuffmanLen[index-1]
				else
					len = distHuffmanLen[index-nLen-1]
				end
				symbol = 3 + ReadBits(2)
			elseif symbol == 17 then -- Repeat zero 3..10 times
				symbol = 3 + ReadBits(3)
			else -- == 18, repeat zero 11.138 times
				symbol = 11 + ReadBits(7)
			end
			if index + symbol > nLen + nDist then
				return -6 -- dynamic block code description: repeat more than specified lengths
			end
			while symbol > 0 do -- Repeat last or zero symbol times
				symbol = symbol - 1
				if index < nLen then
					litHuffmanLen[index] = len
				else
					distHuffmanLen[index-nLen] = len
				end
				index = index + 1
			end
		end
	end

	if (litHuffmanLen[256] or 0) == 0 then
		return -9 -- dynamic block code description: missing end-of-block code
	end

	local litErr, litHuffmanLenCount, litHuffmanSym, litMinLen = ConstructInflateHuffman(litHuffmanLen, nLen, 15)
	--dynamic block code description: invalid literal/length code lengths,Incomplete code ok only for single length 1 code
	if (litErr ~=0 and (litErr < 0 or nLen ~= (litHuffmanLenCount[0] or 0)+(litHuffmanLenCount[1] or 0))) then
		return -7
	end

	local distErr, distHuffmanLenCount, distHuffmanSym, distMinLen = ConstructInflateHuffman(distHuffmanLen, nDist, 15)
	-- dynamic block code description: invalid distance code lengths, Incomplete code ok only for single length 1 code
	if (distErr ~=0 and (distErr < 0 or nDist ~= (distHuffmanLenCount[0] or 0)+(distHuffmanLenCount[1] or 0))) then
		return -8
	end

	-- Build buffman table for literal/length codes
	return DecodeUntilEndOfBlock(state, litHuffmanLenCount, litHuffmanSym, litMinLen
		, distHuffmanLenCount, distHuffmanSym, distMinLen)
end

local function Inflate(state)
	local ReadBits = state.ReadBits

	local isLastBlock
	while not isLastBlock do
		isLastBlock = (ReadBits(1) == 1)
		local blockType = ReadBits(2)
		local status
		if blockType == 0 then
			status = DecompressStoreBlock(state)
		elseif blockType == 1 then
			status = DecompressFixBlock(state)
		elseif blockType == 2 then
			status = DecompressDynamicBlock(state)
		else
			return nil, -1 -- invalid block type (type == 3)
		end
		if status ~= 0 then
			return nil, status
		end
	end

	state.result = state.result..table_concat(state.buffer, "", 1, state.bufferSize)
	return state.result
end

local function CreateInflateState(str, dictionary)
	local ReadBits, ReadBytes, Decode, ReaderBitsLeft, SkipToByteBoundary = CreateReader(str)
	local state =
	{
		ReadBits = ReadBits,
		ReadBytes = ReadBytes,
		Decode = Decode,
		ReaderBitsLeft = ReaderBitsLeft,
		SkipToByteBoundary = SkipToByteBoundary,
		bufferSize = 0,
		buffer = {},
		result = "",
		dictionary = dictionary,
	}
	return state
end
function LibDeflate:DecompressDeflate(str, dictionary)
	-- WIP
	assert(type(str) == "string")

	local state = CreateInflateState(str, dictionary)

	local result, status = Inflate(state)
	if not result then
		return nil, status
	end

	local bitsLeft = state.ReaderBitsLeft()
	local byteLeft = (bitsLeft - bitsLeft % 8) / 8
	return state.result, byteLeft
end

function LibDeflate:DecompressZlib(str, dictionary)
	-- WIP
	assert(type(str) == "string")

	local state = CreateInflateState(str, dictionary)
	local ReadBits = state.ReadBits

	local CMF = ReadBits(8)
	if state.ReaderBitsLeft() < 0 then
		return nil, 2 -- available inflate data did not terminate
	end
	local CM = CMF % 16
	local CINFO = (CMF - CM) / 16
	if CM ~= 8 then
		return nil, -12 -- TODO invalid compression method
	end
	if CINFO > 7 then
		return nil, -13 -- TODO invalid window size
	end

	local FLG = ReadBits(8)
	if state.ReaderBitsLeft() < 0 then
		return nil, 2 -- available inflate data did not terminate
	end
	if (CMF*256+FLG)%31 ~= 0 then
		return nil, -14 -- TODO invalid header checksum
	end

	local FDIST = (FLG-FLG%32)/32 -- TODO
	local FLEVEL = (FLG-FLG%64)/64 -- TODO

	local result, status = Inflate(state)
	if not result then
		return nil, status
	end
	state.SkipToByteBoundary()

	local adler_byte0 = ReadBits(8)
	local adler_byte1 = ReadBits(8)
	local adler_byte2 = ReadBits(8)
	local adler_byte3 = ReadBits(8)
	if state.ReaderBitsLeft() < 0 then
		return nil, 2 -- available inflate data did not terminate
	end

	local adler32_expected = adler_byte0*16777216+adler_byte1*65536+adler_byte2*256+adler_byte3
	local adler32_actual = self:Adler32(result)
	if adler32_expected ~= adler32_actual then
		return nil, -15 -- TODO Adler32 checksum does not match
	end

	local bitsLeft = state.ReaderBitsLeft()
	local byteLeft = (bitsLeft - bitsLeft % 8) / 8
	return state.result, byteLeft
end

function LibDeflate:Decompress(str, dictionary)
	return self:DecompressDeflate(str, dictionary)
end

function LibDeflate:Adler32(str)
	assert(type(str) == "string")
	local strLen = str:len()

	local i = 1
	local a = 1
	local b = 0
	while i <= strLen - 15 do
		local x1, x2, x3, x4, x5, x6, x7, x8,
			x9, x10, x11, x12, x13, x14, x15, x16 = string_byte(str, i, i+15)
		b = (b+16*a+16*x1+15*x2+14*x3+13*x4+12*x5+11*x6+10*x7+9*x8+8*x9+7*x10+6*x11+5*x12+4*x13+3*x14+2*x15+x16)%65521
		a = (a+x1+x2+x3+x4+x5+x6+x7+x8+x9+x10+x11+x12+x13+x14+x15+x16)%65521
		i =  i + 16
	end
	while (i <= strLen) do
		local x = string_byte(str, i, i)
		a = (a + x) % 65521
		b = (b + a) % 65521
		i = i + 1
	end
	return b*65536+a
end

function LibDeflate:CreateDictionary(str)
	assert(type(str) == "string")
	local strLen = str:len()
	assert(strLen > 0)
	assert(strLen <= 32768, tostring(strLen))
	local dictionary = {}
	dictionary.strTable = {}
	dictionary.strLen = strLen
	dictionary.hashTables = {}
	local strTable = dictionary.strTable
	local hashTables = dictionary.hashTables
	strTable[1] = string_byte(str, 1, 1)
	strTable[2] = string_byte(str, 2, 2)
	if strLen >= 3 then
		local i = 1
		local hash = strTable[1]*256+strTable[2]
		while i <= strLen - 2 - 3 do
			local x1, x2, x3, x4 = string_byte(str, i+2, i+5)
			strTable[i+2] = x1
			strTable[i+3] = x2
			strTable[i+4] = x3
			strTable[i+5] = x4
			hash = (hash*256+x1)%16777216
			local t = hashTables[hash] or {i-strLen}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = i-strLen end
			i =  i + 1
			hash = (hash*256+x2)%16777216
			t = hashTables[hash] or {i-strLen}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = i-strLen end
			i =  i + 1
			hash = (hash*256+x3)%16777216
			t = hashTables[hash] or {i-strLen}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = i-strLen end
			i =  i + 1
			hash = (hash*256+x4)%16777216
			t = hashTables[hash] or {i-strLen}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = i-strLen end
			i = i + 1
		end
		while i <= strLen - 2 do
			local x = string_byte(str, i+2)
			strTable[i+2] = x
			hash = (hash*256+x)%16777216
			local t = hashTables[hash] or {i-strLen}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = i-strLen end
			i = i + 1
		end
	end
	return dictionary
end

-- Fix huffman code
do
	_fix_block_literal_huffman_bitlen = {}
	for sym=0, 143 do
		_fix_block_literal_huffman_bitlen[sym] = 8
	end
	for sym=144, 255 do
		_fix_block_literal_huffman_bitlen[sym] = 9
	end
	for sym=256, 279 do
	    _fix_block_literal_huffman_bitlen[sym] = 7
	end
	for sym=280, 287 do
		_fix_block_literal_huffman_bitlen[sym] = 8
	end

	_fix_block_dist_huffman_bitlen = {}
	for dist=0, 31 do
		_fix_block_dist_huffman_bitlen[dist] = 5
	end
	local status
	status, _fix_block_literal_huffman_bitlen_count, _fix_block_literal_huffman_to_deflate_code = ConstructInflateHuffman(_fix_block_literal_huffman_bitlen, 288, 9)
	assert(status == 0)
	status, _fix_block_dist_huffman_bitlen_count, _fix_block_dist_huffman_to_deflate_code = ConstructInflateHuffman(_fix_block_dist_huffman_bitlen, 32, 5)
	assert(status == 0)

	_fix_block_literal_huffman_code = GetHuffmanCodeFromBitLength(_fix_block_literal_huffman_bitlen_count, _fix_block_literal_huffman_bitlen, 287, 9)
	_fix_block_dist_huffman_code = GetHuffmanCodeFromBitLength(_fix_block_dist_huffman_bitlen_count, _fix_block_dist_huffman_bitlen, 31, 5)
end



----------------------------------------------------------------------
----------------------------------------------------------------------
-- Encoding algorithms
--------------------------------------------------------------------------------
-- Prefix encoding algorithm
-- implemented by Galmok of European Stormrage (Horde), galmok@gmail.com
-- From LibCompress <https://www.wowace.com/projects/libcompress>, which is licensed under GPLv2
-- The code has been modified by the author of LibDeflate.
-----------------------------------------------------------------------

--[[
	Howto: Encode and Decode:

	3 functions are supplied, 2 of them are variants of the first.
	They return a table with functions to encode and decode text.

	table, msg = LibCompress:GetEncodeDecodeTable(reservedChars, escapeChars,  mapChars)

		reservedChars: The characters in this string will not appear in the encoded data.
		escapeChars: A string of characters used as escape-characters (don't supply more than needed). #escapeChars >= 1
		mapChars: First characters in reservedChars maps to first characters in mapChars.  (#mapChars <= #reservedChars)

	return value:
		table
			if nil then msg holds an error message, otherwise use like this:

			encoded_message = table:Encode(message)
			message = table:Decode(encoded_message)

	GetAddonEncodeTable: Sets up encoding for the addon channel (\000 is encoded)
	GetChatEncodeTable: Sets up encoding for the chat channel (many bytes encoded, see the function for details)

	Except for the mapped characters, all encoding will be with 1 escape character followed by 1 suffix, i.e. 2 bytes.
--]]
-- to be able to match any requested byte value, the search string must be preprocessed
-- characters to escape with %:
-- ( ) . % + - * ? [ ] ^ $
-- "illegal" byte values:
-- 0 is replaces %z
local _gsub_escape_table = {
	['\000'] = "%z",
	[('(')] = "%(",
	[(')')] = "%)",
	[('.')] = "%.",
	[('%')] = "%%",
	[('+')] = "%+",
	[('-')] = "%-",
	[('*')] = "%*",
	[('?')] = "%?",
	[('[')] = "%[",
	[(']')] = "%]",
	[('^')] = "%^",
	[('$')] = "%$"
}

local function escape_for_gsub(str)
	return str:gsub("([%z%(%)%.%%%+%-%*%?%[%]%^%$])",  _gsub_escape_table)
end

function LibDeflate:GetEncodeDecodeTable(reservedChars, escapeChars, mapChars)
	reservedChars = reservedChars or ""
	escapeChars = escapeChars or ""
	mapChars = mapChars or ""
	-- select a default escape character
	if escapeChars == "" then
		return nil, "No escape characters supplied"
	end
	if #reservedChars < #mapChars then
		return nil, "Number of reserved characters must be"
			.." at least as many as the number of mapped chars"
	end
	if reservedChars == "" then
		return nil, "No characters to encode"
	end

	local encodeBytes = reservedChars..escapeChars..mapChars
	-- build list of bytes not available as a suffix to a prefix byte
	local taken = {}
	for i = 1, #encodeBytes do
		local byte = string_byte(encodeBytes, i, i)
		if taken[byte] then -- Modified by LibDeflate:
			return nil, "There must be no duplicate characters in the"
				.." concatenation of reservedChars, escapeChars and mapChars "
		end
		taken[byte] = true
	end

	-- Modified by LibDeflate:
	-- Store the patterns and replacement in tables for later use.
	-- This function is modified that loadstring() lua api is no longer used.
	local decode_patterns = {}
	local decode_repls = {}

	-- the encoding can be a single gsub
	-- , but the decoding can require multiple gsubs
	local encode_search = {}
	local encode_translate = {}

	-- map single byte to single byte
	if #mapChars > 0 then
		local decode_search = {}
		local decode_translate = {}
		for i = 1, #mapChars do
			local from = string_sub(reservedChars, i, i)
			local to = string_sub(mapChars, i, i)
			encode_translate[from] = to
			encode_search[#encode_search+1] = from
			decode_translate[to] = from
			decode_search[#decode_search+1] = to
		end
		decode_patterns[#decode_patterns+1] =
			"([".. escape_for_gsub(table_concat(decode_search)).."])"
		decode_repls[#decode_repls+1] = decode_translate
	end

	local escapeCharIndex = 1
	local escapeChar = string_sub(escapeChars, escapeCharIndex, escapeCharIndex)
	-- map single byte to double-byte
	local r = 0 -- suffix char value to the escapeChar

	local decode_search = {}
	local decode_translate = {}
	for i = 1, #encodeBytes do
		local c = string_sub(encodeBytes, i, i)
		if not encode_translate[c] then
			-- this loop will update escapeChar and r
			while r >= 256 or taken[r] do
			-- Bug in LibCompress r81
			-- while r < 256 and taken[r] do
				r = r + 1
				if r > 255 then -- switch to next escapeChar
					if not escapeChar or escapeChar == "" then
						-- we are out of escape chars and we need more!
						return nil, "Out of escape characters"
					end
					decode_patterns[#decode_patterns+1] =
						escape_for_gsub(escapeChar)
						.."([".. escape_for_gsub(table_concat(decode_search)).."])"
					decode_repls[#decode_repls+1] = decode_translate

					escapeCharIndex = escapeCharIndex + 1
					escapeChar = string_sub(escapeChars, escapeCharIndex, escapeCharIndex)
					r = 0
					decode_search = {}
					decode_translate = {}
				end
			end

			local char_r = _byte_to_char[r]
			encode_translate[c] = escapeChar..char_r
			encode_search[#encode_search+1] = c
			decode_translate[char_r] = c
			decode_search[#decode_search+1] = char_r
			r = r + 1
		end
		if i == #encodeBytes then
			decode_patterns[#decode_patterns+1] =
				escape_for_gsub(escapeChar).."(["
				.. escape_for_gsub(table_concat(decode_search)).."])"
			decode_repls[#decode_repls+1] = decode_translate
		end
	end

	local codecTable = {}

	local encode_pattern = "([".. escape_for_gsub(table_concat(encode_search)).."])"
	local encode_repl = encode_translate

	function codecTable:Encode(str)
		return string_gsub(str, encode_pattern, encode_repl)
	end

	local decode_tblsize = #decode_patterns

	function codecTable:Decode(str)
		for i = 1, decode_tblsize do
			str = string_gsub(str, decode_patterns[i], decode_repls[i])
		end
		return str
	end
	codecTable.__newindex = function() error("This table is read-only") end

	return codecTable
end

local _addon_channel_encode_table

function LibDeflate:EncodeForWoWAddonChannel(str)
	if not _addon_channel_encode_table then
		_addon_channel_encode_table = self:GetEncodeDecodeTable("\000", "\001")
	end
	return _addon_channel_encode_table:Encode(str)
end

function LibDeflate:DecodeForWoWAddonChannel(str)
	if not _addon_channel_encode_table then
		_addon_channel_encode_table = self:GetEncodeDecodeTable("\000", "\001")
	end
	return _addon_channel_encode_table:Decode(str)
end

-- For World of Warcraft Chat Channel Encoding
-- implemented by Galmok of European Stormrage (Horde), galmok@gmail.com
-- From LibCompress <https://www.wowace.com/projects/libcompress>,
-- which is licensed under GPLv2
-- The code has been modified by the author of LibDeflate.
-- Following byte values are not allowed:
-- \000, s, S, \010, \013, \124, %
-- Because SendChatMessage will error
-- if an UTF8 multibyte character is incomplete,
-- all character values above 127 have to be encoded to avoid this.
-- This costs quite a bit of bandwidth (about 13-14%)
-- Also, because drunken status is unknown for the received
-- , strings used with SendChatMessage should be terminated with
-- an identifying byte value, after which the server MAY add "...hic!"
-- or as much as it can fit(!).
-- Pass the identifying byte as a reserved character to this function
-- to ensure the encoding doesn't contain that value.
-- or use this: local message, match = arg1:gsub("^(.*)\029.-$", "%1")
-- arg1 is message from channel, \029 is the string terminator
-- , but may be used in the encoded datastream as well. :-)
-- This encoding will expand data anywhere from:
-- 0% (average with pure ascii text)
-- 53.5% (average with random data valued zero to 255)
-- 100% (only encoding data that encodes to two bytes)
local function GenerateWoWChatChannelEncodeTable()
	local r = {}
	for i = 128, 255 do
		r[#r+1] = _byte_to_char[i]
	end

	local reservedChars = "sS\000\010\013\124%"..table_concat(r)
	return LibDeflate:GetEncodeDecodeTable(reservedChars, "\029\031", "\015\020")
end

local _chat_channel_encode_table

function LibDeflate:EncodeForWoWChatChannel(str)
	if not _chat_channel_encode_table then
		_chat_channel_encode_table = GenerateWoWChatChannelEncodeTable()
	end
	return _chat_channel_encode_table:Encode(str)
end

function LibDeflate:DecodeForWoWChatChannel(str)
	if not _chat_channel_encode_table then
		_chat_channel_encode_table = GenerateWoWChatChannelEncodeTable()
	end
	return _chat_channel_encode_table:Decode(str)
end

-- For test. Don't use the functions in this table for real application.
-- Stuffs in this table is subject to change.
LibDeflate.internals = {
	loadStrToTable = loadStrToTable,
}

return LibDeflate