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
	[8] = {true, 32, 128, 258, 1024} , --(SLOW) level 8,similar to zlib level 8
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
local select = select
local string_byte = string.byte
local string_char = string.char
local string_gsub = string.gsub
local string_sub = string.sub
local table_concat = table.concat
local table_sort = table.sort
local type = type

-- Converts i to 2^i, (0<=i<=31)
-- This is used to implement bit left shift and bit right shift.
-- "x >> y" in C:   "(x-x%_pow2[y])/_pow2[y]" in Lua
-- "x << y" in C:   "x*_pow2[y]" in Lua
local _pow2 = {}

-- Converts any byte to a character, (0<=byte<=255)
local _byte_to_char = {}

-- _reverseBitsTbl[len][val] stores the bit reverse of
-- the number with bit length "len" and value "val"
-- For example, decimal number 6 with bits length 5 is binary 00110
-- It's reverse is binary 01100,
-- which is decimal 12 and 12 == _reverseBitsTbl[5][6]
-- 1<=len<=9, 0<=val<=2^len-1
-- The reason for 1<=len<=9 is that the max of min bitlen of huffman code
-- of a huffman alphabet is 9?
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
local _header_code_order = {16, 17, 18,
	0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15}

-- The following tables are used by fixed deflate block.
-- The value of these tables are assigned at the bottom of the source.

-- The huffman code of the literal/LZ77_length deflate codes,
-- in fixed deflate block.
local _fix_block_literal_huffman_code

-- Convert huffman code of the literal/LZ77_length to deflate codes,
-- in fixed deflate block.
local _fix_block_literal_huffman_to_deflate_code

-- The bit length of the huffman code of literal/LZ77_length deflate codes,
-- in fixed deflate block.
local _fix_block_literal_huffman_bitlen

-- The count of each bit length of the literal/LZ77_length deflate codes,
-- in fixed deflate block.
local _fix_block_literal_huffman_bitlen_count

-- The huffman code of the distance deflate codes,
-- in fixed deflate block.
local _fix_block_dist_huffman_code

-- Convert huffman code of the distance to deflate codes,
-- in fixed deflate block.
local _fix_block_dist_huffman_to_deflate_code

-- The bit length of the huffman code of the distance deflate codes,
-- in fixed deflate block.
local _fix_block_dist_huffman_bitlen

-- The count of each bit length of the huffman code of 
-- the distance deflate codes,
-- in fixed deflate block.
local _fix_block_dist_huffman_bitlen_count

for i = 0, 255 do
	_byte_to_char[i] = string_char(i)
end

do
	local pow = 1
	for i = 0, 31 do
		_pow2[i] = pow
		pow = pow * 2
	end
end

for i = 1, 9 do
	_reverse_bits_tbl[i] = {}
	for j=0, _pow2[i+1]-1 do
		local reverse = 0
		local value = j
		for _ = 1, i do
			-- The following line is equivalent to "res | (code %2)" in C.
			reverse = reverse - reverse%2 
				+ (((reverse%2==1) or (value % 2) == 1) and 1 or 0)
			value = (value-value%2)/2
			reverse = reverse * 2
		end
		_reverse_bits_tbl[i][j] = (reverse-reverse%2)/2
	end
end

-- The source code is written according to the pattern in the numbers
-- in RFC1951 Page10.
do
	local a = 18
	local b = 16
	local c = 265
	local bitlen = 1
	for len = 3, 258 do
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
				bitlen = bitlen + 1
			end
			local t = len-a-1+b/2
			_length_to_deflate_code[len] = (t-(t%(b/8)))/(b/8) + c
			_length_to_deflate_extra_bitlen[len] = bitlen
			_length_to_deflate_extra_bits[len] = t % (b/8)
		end
	end
end

-- The source code is written according to the pattern in the numbers
-- in RFC1951 Page11.
do
	_dist256_to_deflate_code[1] = 0
	_dist256_to_deflate_code[2] = 1
	_dist256_to_deflate_extra_bitlen[1] = 0
	_dist256_to_deflate_extra_bitlen[2] = 0

	local a = 3
	local b = 4
	local code = 2
	local bitlen = 0
	for dist = 3, 256 do
		if dist > b then
			a = a * 2
			b = b * 2
			code = code + 2
			bitlen = bitlen + 1
		end
		_dist256_to_deflate_code[dist] = (dist <= a) and code or (code+1)
		_dist256_to_deflate_extra_bitlen[dist] = (bitlen < 0) and 0 or bitlen
		if b >= 8 then
			_dist256_to_deflate_extra_bits[dist] = (dist-b/2-1) % (b/4)
		end
	end
end

--[[
	Create an empty writer to easily write stuffs as the unit of bits.
	Return values:
	1. WriteBits(code, bitlen):
	2. WriteString(str):
	3. Flush(full_flush):
--]]
local function CreateWriter()
	local buffer_size = 0
	local cache = 0
	local cache_bitlen = 0
	local buffer = {}

	-- Write bits with value "value" and bit length of "bitlen" into writer.
	-- @param value: The value being written
	-- @param bitlen: The bit length of "value"
	-- @return nil
	local function WriteBits(value, bitlen)
		cache = cache + value * _pow2[cache_bitlen]
		cache_bitlen = cache_bitlen + bitlen

		-- Only bulk to buffer every 4 bytes. This is quicker.
		if cache_bitlen >= 32 then
			buffer[buffer_size+1] = _byte_to_char[cache % 256]
			buffer[buffer_size+2] =
				_byte_to_char[((cache-cache%256)/256 % 256)]
			buffer[buffer_size+3] =
				_byte_to_char[((cache-cache%65536)/65536 % 256)]
			buffer[buffer_size+4] =
				_byte_to_char[((cache-cache%16777216)/16777216 % 256)]
			buffer_size = buffer_size + 4
			local rshift_mask = _pow2[32 - cache_bitlen + bitlen]
			cache = (value - value%rshift_mask)/rshift_mask
			cache_bitlen = cache_bitlen - 32
		end
	end

	-- Write the entire string into the writer.
	-- @param str The string being written
	-- @return nil
	local function WriteString(str)
		for _ = 1, cache_bitlen, 8 do
			buffer_size = buffer_size + 1
			buffer[buffer_size] = string_char(cache % 256)
			cache = (cache-cache%256)/256
		end
		cache_bitlen = 0
		buffer_size = buffer_size + 1
		buffer[buffer_size] = str
	end

	-- Flush current stuffs in the writer and return it.
	-- This operation will free most of the memory.
	-- @param full_flush If true, also flush "cache" into the output,
	-- with last byte padded with some bits if cache_bitlen is
	-- not a multiple of 8.
	-- @return All stuffs in the writer, excluding bits in "cache"
	-- variable, as a string.
	-- @return The number of bits stored in the writer.
	local function FlushWriter(full_flush)
		local ret
		if full_flush then
			-- Full flush, also output cache.
			-- Need to pad some bits if cache_bitlen is not multiple of 8.
			local padding_bitlen = (8-cache_bitlen%8)%8
			if cache_bitlen > 0 then
				for _ = 1, cache_bitlen, 8 do
					buffer_size = buffer_size + 1
					buffer[buffer_size] = string_char(cache % 256)
					cache = (cache-cache%256)/256
				end
				cache = 0
				cache_bitlen = 0
			end
			ret = table_concat(buffer)
			buffer = {ret}
			buffer_size = 1
			return ret, (#ret*8)-padding_bitlen
		else
			-- Not full flush
			-- This operation is mainly used to free memory,
			-- not for return value.
			ret = table_concat(buffer)
			buffer = {ret}
			buffer_size = 1
			return ret, (#ret*8)+cache_bitlen
		end
	end

	return WriteBits, WriteString, FlushWriter
end

-- Push an element into a max heap
-- @param heap A max heap whose max element is at index 1.
-- @param e The element to be pushed. Assume element "e" is a table
--  and comparison is done via its first entry e[1]
-- @param heap_size current number of elements in the heap.
--  NOTE: There may be some garbage stored in
--  heap[heap_size+1], heap[heap_size+2], etc..
-- @return nil
local function MinHeapPush(heap, e, heap_size)
	heap_size = heap_size + 1
	heap[heap_size] = e
	local value = e[1]
	local pos = heap_size
	local parent_pos = (pos-pos%2)/2

	while (parent_pos >= 1 and heap[parent_pos][1] > value) do
		local t = heap[parent_pos]
		heap[parent_pos] = e
		heap[pos] = t
		pos = parent_pos
		parent_pos = (parent_pos-parent_pos%2)/2
	end
end

-- Pop an element from a max heap
-- @param heap A max heap whose max element is at index 1.
-- @param heap_size current number of elements in the heap.
-- @return the poped element
-- Note: This function does not change table size of "heap" to save CPU time.
local function MinHeapPop(heap, heap_size)
	local top = heap[1]
	local e = heap[heap_size]
	local value = e[1]
	heap[1] = e
	heap[heap_size] = top
	heap_size = heap_size - 1

	local pos = 1
	local left_child_pos = pos * 2
	local right_child_pos = left_child_pos + 1

	while (left_child_pos <= heap_size) do
		local left_child = heap[left_child_pos]
		if (right_child_pos <= heap_size
			and heap[right_child_pos][1] < left_child[1]) then
			local right_child = heap[right_child_pos]
			if right_child[1] < value then
				heap[right_child_pos] = e
				heap[pos] = right_child
				pos = right_child_pos
				left_child_pos = pos * 2
				right_child_pos = left_child_pos + 1
			else
				break
			end
		else
			if left_child[1] < value then
				heap[left_child_pos] = e
				heap[pos] = left_child
				pos = left_child_pos
				left_child_pos = pos * 2
				right_child_pos = left_child_pos + 1
			else
				break
			end
		end
	end

	return top
end

-- Deflate defines a special huffman tree, which is unique once the bit length
-- of huffman code of all symbols are known.
-- @param bitlen_count Number of symbols with a specific bitlen
-- @param symbol_bitlen The bit length of a symbol
-- @param max_symbol The max symbol among all symbols,
--		which is (number of symbols - 1)
-- @param max_bitlen The max huffman bit length among all symbols.
-- @return The huffman code of all symbols.
local function GetHuffmanCodeFromBitlen(bitlen_counts, symbol_bitlens
		, max_symbol, max_bitlen)
	local huffman_code = 0
	local next_codes = {}
	local symbol_huffman_codes = {}
	for bitlen = 1, max_bitlen do
		huffman_code = (huffman_code+(bitlen_counts[bitlen-1] or 0))*2
		next_codes[bitlen] = huffman_code
	end
	for symbol = 0, max_symbol do
		local bitlen = symbol_bitlens[symbol]
		if bitlen then
			huffman_code = next_codes[bitlen]
			next_codes[bitlen] = huffman_code + 1

			-- Reverse the bits of huffman code,
			-- because most signifant bits of huffman code
			-- is stored first into the compressed data.
			-- @see RFC1951 Page5 Section 3.1.1
			if bitlen <= 9 then -- Have cached reverse for small bitlen.
				symbol_huffman_codes[symbol] = 
					_reverse_bits_tbl[bitlen][huffman_code]
			else
				local reverse = 0
				for _ = 1, bitlen do
					reverse = reverse - reverse%2 
						+ (((reverse%2==1) 
							or (huffman_code % 2) == 1) and 1 or 0)
					huffman_code = (huffman_code-huffman_code%2)/2
					reverse = reverse*2
				end
				symbol_huffman_codes[symbol] = (reverse-reverse%2)/2
			end
		end
	end
	return symbol_huffman_codes
end

-- A helper function to sort heap elements
-- a[1], b[1] is the huffman frequency
-- a[2], b[2] is the symbol value.
local function SortByFirstThenSecond(a, b)
	return a[1] < b[1] or
		(a[1] == b[1] and a[2] < b[2])
end

-- Calculate the huffman bit length and huffman code.
-- @param symbol_count: A table whose table key is the symbol, and table value
--		is the symbol frenquency (nil means 0 frequency).
-- @param max_bitlen: See description of return value.
-- @param max_symbol: The maximum symbol
-- @return a table whose key is the symbol, and the value is the huffman bit
--		bit length. We guarantee that all bit length <= max_bitlen.
--		For 0<=symbol<=max_symbol, table value could be nil if the frequency
--		of the symbol is 0 or nil.
-- @return a table whose key is the symbol, and the value is the huffman code.
-- @return a number indicating the maximum symbol whose bitlen is not 0.
local function GetHuffmanBitlenAndCode(symbol_counts, max_bitlen, max_symbol)
	local heap_size
	local max_non_zero_bitlen_symbol = -1
	local leafs = {}
	local heap = {}
	local symbol_bitlens = {}
	local symbol_codes = {}
	local bitlen_counts = {}

	--[[
		tree[1]: weight, temporarily used as parent and bitLengths
		tree[2]: symbol
		tree[3]: left child
		tree[4]: right child
	--]]
	local number_unique_symbols = 0
	for symbol, count in pairs(symbol_counts) do
		number_unique_symbols = number_unique_symbols + 1
		leafs[number_unique_symbols] = {count, symbol}
	end

	if (number_unique_symbols == 0) then
		-- no code.
		return {}, {}, -1
	elseif (number_unique_symbols == 1) then
		-- Only one code. In this case, its huffman code
		-- needs to be assigned as 0, and bit length is 1.
		-- This is the only case that the return result
		-- represents an imcomplete huffman tree.
		local symbol = leafs[1][2]
		symbol_bitlens[symbol] = 1
		symbol_codes[symbol] = 0
		return symbol_bitlens, symbol_codes, symbol
	else
		table_sort(leafs, SortByFirstThenSecond)
		heap_size = number_unique_symbols
		for i = 1, heap_size do
			heap[i] = leafs[i]
		end

		while (heap_size > 1) do
			-- Note: pop does not change table size of heap
			local leftChild = MinHeapPop(heap, heap_size) 
			heap_size = heap_size - 1
			local rightChild = MinHeapPop(heap, heap_size)
			heap_size = heap_size - 1
			local newNode =
				{leftChild[1]+rightChild[1], -1, leftChild, rightChild}
			MinHeapPush(heap, newNode, heap_size)
			heap_size = heap_size + 1
		end

		-- Number of leafs whose bit length is greater than max_len.
		local number_bitlen_overflow = 0

		-- Calculate bit length of all nodes
		local fifo = {heap[1], 0, 0, 0} -- preallocate some spaces.
		local fifo_size = 1
		local index = 1
		heap[1][1] = 0
		while (index <= fifo_size) do -- Breath first search
			local e = fifo[index]
			local bitlen = e[1]
			local symbol = e[2]
			local left_child = e[3]
			local right_child = e[4]
			if left_child then
				fifo_size = fifo_size + 1
				fifo[fifo_size] = left_child
				left_child[1] = bitlen + 1
			end
			if right_child then
				fifo_size = fifo_size + 1
				fifo[fifo_size] = right_child
				right_child[1] = bitlen + 1
			end
			index = index + 1

			if (bitlen > max_bitlen) then
				number_bitlen_overflow = number_bitlen_overflow + 1
				bitlen = max_bitlen
			end
			if symbol >= 0 then
				symbol_bitlens[symbol] = bitlen
				max_non_zero_bitlen_symbol =
					(symbol > max_non_zero_bitlen_symbol)
					and symbol or max_non_zero_bitlen_symbol
				bitlen_counts[bitlen] = (bitlen_counts[bitlen] or 0) + 1
			end
		end

		-- Resolve bit length overflow
		-- @see ZLib/trees.c:gen_bitlen(s, desc), for reference
		if (number_bitlen_overflow > 0) then
			repeat
				local bitlen = max_bitlen - 1
				while ((bitlen_counts[bitlen] or 0) == 0) do
					bitlen = bitlen - 1
				end
				-- move one leaf down the tree
				bitlen_counts[bitlen] = bitlen_counts[bitlen] - 1
				-- move one overflow item as its brother
				bitlen_counts[bitlen+1] = (bitlen_counts[bitlen+1] or 0) + 2
				bitlen_counts[max_bitlen] = bitlen_counts[max_bitlen] - 1
				number_bitlen_overflow = number_bitlen_overflow - 2
			until (number_bitlen_overflow <= 0)

			index = 1
			for bitlen = max_bitlen, 1, -1 do
				local n = bitlen_counts[bitlen] or 0
				while (n > 0) do
					local symbol = leafs[index][2]
					symbol_bitlens[symbol] = bitlen
					max_non_zero_bitlen_symbol = 
						(symbol > max_non_zero_bitlen_symbol) 
						and symbol or max_non_zero_bitlen_symbol
					n = n - 1
					index = index + 1
				end
			end
		end

		symbol_codes = GetHuffmanCodeFromBitlen(bitlen_counts, symbol_bitlens,
				max_symbol, max_bitlen)
		return symbol_bitlens, symbol_codes, max_non_zero_bitlen_symbol
	end
end

-- Calculate the first huffman header in the dynamic huffman block
-- @see RFC1951 Page 12
-- @param lcode_bitlen: The huffman bit length of literal/LZ77_length.
-- @param max_non_zero_bitlen_lcode: The maximum literal/LZ77_length symbol
--		whose huffman bit length is not zero.
-- @param dcode_bitlen: The huffman bit length of LZ77 distance.
-- @param max_non_zero_bitlen_dcode: The maximum LZ77 distance symbol
--		whose huffman bit length is not zero.
-- @return The run length encoded codes.
-- @return The extra bits. One entry for each rle code that needs extra bits.
--		(code == 16 or 17 or 18).
-- @return The count of appearance of each rle codes.
local function RunLengthEncodeHuffmanBitlen(
		lcode_bitlens,
		max_non_zero_bitlen_lcode,
		dcode_bitlens,
		max_non_zero_bitlen_dcode)
	local rle_code_tblsize = 0
	local rle_codes = {}
	local rle_code_counts = {}
	local rle_extra_bits_tblsize = 0
	local rle_extra_bits = {}
	local prev = nil
	local count = 0

	-- If there is no distance code, assume one distance code of bit length 0.
	-- RFC1951: One distance code of zero bits means that
	-- there are no distance codes used at all (the data is all literals).
	max_non_zero_bitlen_dcode = (max_non_zero_bitlen_dcode < 0)
			and 0 or max_non_zero_bitlen_dcode
	local max_code = max_non_zero_bitlen_lcode+max_non_zero_bitlen_dcode+1

	for code = 0, max_code+1 do
		local len = (code <= max_non_zero_bitlen_lcode)
			and (lcode_bitlens[code] or 0)
			or ((code <= max_code)
			and (dcode_bitlens[code-max_non_zero_bitlen_lcode-1] or 0) or nil)
		if len == prev then
			count = count + 1
			if len ~= 0 and count == 6 then
				rle_code_tblsize = rle_code_tblsize + 1
				rle_codes[rle_code_tblsize] = 16
				rle_extra_bits_tblsize = rle_extra_bits_tblsize + 1
				rle_extra_bits[rle_extra_bits_tblsize] = 3
				rle_code_counts[16] = (rle_code_counts[16] or 0) + 1
				count = 0
			elseif len == 0 and count == 138 then
				rle_code_tblsize = rle_code_tblsize + 1
				rle_codes[rle_code_tblsize] = 18
				rle_extra_bits_tblsize = rle_extra_bits_tblsize + 1
				rle_extra_bits[rle_extra_bits_tblsize] = 127
				rle_code_counts[18] = (rle_code_counts[18] or 0) + 1
				count = 0
			end
		else
			if count == 1 then
				rle_code_tblsize = rle_code_tblsize + 1
				rle_codes[rle_code_tblsize] = prev
				rle_code_counts[prev] = (rle_code_counts[prev] or 0) + 1
			elseif count == 2 then
				rle_code_tblsize = rle_code_tblsize + 1
				rle_codes[rle_code_tblsize] = prev
				rle_code_tblsize = rle_code_tblsize + 1
				rle_codes[rle_code_tblsize] = prev
				rle_code_counts[prev] = (rle_code_counts[prev] or 0) + 2
			elseif count >= 3 then
				rle_code_tblsize = rle_code_tblsize + 1
				local rleCode = (prev ~= 0) and 16 or (count <= 10 and 17 or 18)
				rle_codes[rle_code_tblsize] = rleCode
				rle_code_counts[rleCode] = (rle_code_counts[rleCode] or 0) + 1
				rle_extra_bits_tblsize = rle_extra_bits_tblsize + 1
				rle_extra_bits[rle_extra_bits_tblsize] =
					(count <= 10) and (count - 3) or (count - 11)
			end

			prev = len
			if len and len ~= 0 then
				rle_code_tblsize = rle_code_tblsize + 1
				rle_codes[rle_code_tblsize] = len
				rle_code_counts[len] = (rle_code_counts[len] or 0) + 1
				count = 0
			else
				count = 1
			end
		end
	end

	return rle_codes, rle_extra_bits, rle_code_counts
end

-- Load the string into a table, in order to speed up LZ77.
-- Loop unrolled 16 times to speed this function up.
-- @param str The string to be loaded.
-- @param t The load destination
-- @param start str[index] will be the first character to be loaded.
-- @param end str[index] will be the last character to be loaded
-- @param offset str[index] will be loaded into t[index+offset]
-- @return t
local function loadStrToTable(str, t, start, stop, offset)
	local i = start - offset
	while i <= stop - 15 - offset do
		t[i], t[i+1], t[i+2], t[i+3], t[i+4], t[i+5], t[i+6], t[i+7], t[i+8],
		t[i+9], t[i+10], t[i+11], t[i+12], t[i+13], t[i+14], t[i+15] = 
			string_byte(str, i + offset, i + 15 + offset)
		i = i + 16
	end
	while (i <= stop - offset) do
		t[i] = string_byte(str, i + offset, i + offset)
		i = i + 1
	end
	return t
end

-- Do LZ77 process. This function uses the majority of the CPU time.
-- @see zlib/deflate.c:deflate_fast(), zlib/deflate.c:deflate_slow()
-- @see https://github.com/madler/zlib/blob/master/doc/algorithm.txt
-- This function uses the algorithms used above. You should read the
-- algorithm.txt above to understand what is the hash function and the
-- lazy evaluation.
--
-- The special optimization used here is hash functions used here.
-- The hash function is just the multiplication of the three consective
-- characters. So if the hash matches, it guarantees 3 characters are matched.
-- This optimization can be implemented because Lua table is a hash table.
--
-- @param level integer that describes compression level.
-- @param string_table table that stores the value of string to be compressed.
--			The index of this table starts from 1. 
--			The caller needs to make sure all values needed by this function
--			are loaded.
--			Assume "str" is the origin input string into the compressor
--			str[block_start]..str[block_end+3] needs to be loaded into
--			string_table[block_start-offset]..string_table[block_end-offset]
--			If dictionary is presented, the last 258 bytes of the dictionary
--			needs to be loaded into sing_table[-257..0]
--			(See more in the description of offset.)
-- @param hash_tables. The table key is the hash value (0<=hash<=16777216=256^3)
--			The table value is an array0 that stores the indexes of the
--			input data string to be compressed, such that
--			hash == str[index]*str[index+1]*str[index+2]
--			Indexes are ordered in this array.
-- @param block_start The indexes of the input data string to be compressed.
--				that starts the LZ77 block.
-- @param block_end The indexes of the input data string to be compressed.
--				that stores the LZ77 block.
-- @param offset str[index] is stored in string_table[index-offset],
--			This offset is mainly an optimization to limit the index
--			of string_table, so lua can access this table quicker.
-- @param dictionary TODO
-- @return literal/LZ77_length deflate codes.
-- @return the extra bits of literal/LZ77_length deflate codes.
-- @return the count of each literal/LZ77 deflate code.
-- @return LZ77 distance deflate codes.
-- @return the extra bits of LZ77 distance deflate codes.
-- @return the count of each LZ77 distance deflate code.
local function GetBlockLZ77Result(level, string_table, hash_tables, block_start,
		block_end, offset, dictionary)
	if not level then
		level = 5
	end

	local config = _compression_level_config[level]
	local config_use_lazy
		, config_good_prev_length
		, config_max_lazy_match
		, config_nice_length
		, config_max_hash_chain = 
			config[1], config[2], config[3], config[4], config[5]

	local config_max_insert_length = (not config_use_lazy)
		and config_max_lazy_match or 2147483646
	local config_good_hash_chain =
		(config_max_hash_chain-config_max_hash_chain%4/4)

	local hash

	local dict_hash_tables
	local dict_string_table
	local dict_string_len = 0

	if dictionary then
		dict_hash_tables = dictionary.hash_tables
		dict_string_table = dictionary.string_table
		dict_string_len = dictionary.strlen
		assert(block_start == 1)
		if block_end >= block_start and dict_string_len >= 2 then
			hash = dict_string_table[dict_string_len-1]*65536
				+ dict_string_table[dict_string_len]*256 + string_table[1]
			local t = hash_tables[hash] or {-1}
			if #t == 1 then hash_tables[hash] = t else t[#t+1] = -1 end
		end
		if block_end >= block_start+1 and dict_string_len >= 1 then
			hash = dict_string_table[dict_string_len]*65536
				+ string_table[1]*256 + string_table[2]
			local t = hash_tables[hash] or {0}
			if #t == 1 then hash_tables[hash] = t else t[#t+1] = 0 end
		end
	end

	hash = (string_table[block_start-offset] or 0)*256
		+ (string_table[block_start+1-offset] or 0)

	local lcodes = {}
	local lcode_tblsize = 0
	local lcodes_counts = {}
	local dcodes = {}
	local dcodes_tblsize = 0
	local dcodes_counts = {}

	local lextra_bits = {}
	local lextra_bits_tblsize = 0
	local dextra_bits = {}
	local dextra_bits_tblsize = 0

	local match_available = false
	local prev_len
	local prev_dist
	local cur_len = 0
	local cur_dist = 0

	local index = block_start
	local index_end = block_end + (config_use_lazy and 1 or 0)

	-- the zlib source code writes separate code for lazy evaluation and
	-- not lazy evaluation, which is easier to understand.
	-- I put them together, so it is a bit harder to understand.
	-- because I think this is easier for me to maintain it.
	while (index <= index_end) do
		local string_table_index = index - offset
		prev_len = cur_len
		prev_dist = cur_dist
		cur_len = 0

		hash = (hash*256+(string_table[string_table_index+2] or 0))%16777216

		local chain_index
		local cur_chain
		local hash_chain = hash_tables[hash]
		local chain_old_size
		if not hash_chain then
			chain_old_size = 0
			hash_chain = {}
			hash_tables[hash] = hash_chain
			if dict_hash_tables then
				cur_chain = dict_hash_tables[hash]
				chain_index = cur_chain and #cur_chain or 0
			else
				chain_index = 0
			end
		else
			chain_old_size = #hash_chain
			cur_chain = hash_chain
			chain_index = chain_old_size
		end

		if index <= block_end then
			hash_chain[chain_old_size+1] = index
		end

		if (chain_index > 0 and index + 2 <= block_end
			and (not config_use_lazy or prev_len < config_max_lazy_match)) then

			local depth =
				(config_use_lazy and prev_len >= config_good_prev_length)
				and config_good_hash_chain or config_max_hash_chain

			while chain_index >= 1 and depth > 0 do
				local prev = cur_chain[chain_index]

				if index - prev > 32768 then
					break
				end
				if prev < index then
					local j = 3

					if prev >= -257 then
						local prev_table_index = prev-offset
						while (j < 258 and index + j < block_end) do
							if (string_table[prev_table_index+j] 
								== string_table[string_table_index+j]) then
								j = j + 1
							else
								break
							end
						end
					else
						local prev_table_index = dict_string_len+prev
						while (j < 258 and index + j < block_end) do
							if (dict_string_table[prev_table_index+j] 
								== string_table[string_table_index+j]) then
								j = j + 1
							else
								break
							end
						end
					end
					if j > cur_len then
						cur_len = j
						cur_dist = index - prev
					end
					if cur_len >= config_nice_length then
						break
					end
				end

				chain_index = chain_index - 1
				depth = depth - 1
				if chain_index == 0 and prev > 0 and dict_hash_tables then
					cur_chain = dict_hash_tables[hash]
					chain_index = cur_chain and #cur_chain or 0
				end
			end
		end

		if not config_use_lazy then
			prev_len, prev_dist = cur_len, cur_dist
		end
		if ((not config_use_lazy or match_available) 
			and (prev_len > 3 or (prev_len == 3 and prev_dist < 4096))
			and cur_len <= prev_len )then
			local code = _length_to_deflate_code[prev_len]
			local length_extra_bits_bitlen = 
				_length_to_deflate_extra_bitlen[prev_len]
			local dist_code, dist_extra_bits_bitlen, dist_extra_bits
			if prev_dist <= 256 then -- have cached code for small distance.
				dist_code = _dist256_to_deflate_code[prev_dist]
				dist_extra_bits = _dist256_to_deflate_extra_bits[prev_dist]
				dist_extra_bits_bitlen =
					_dist256_to_deflate_extra_bitlen[prev_dist]
			else
				dist_code = 16
				dist_extra_bits_bitlen = 7
				local a = 384
				local b = 512

				while true do
					if prev_dist <= a then
						dist_extra_bits = (prev_dist-(b/2)-1) % (b/4)
						break
					elseif prev_dist <= b then
						dist_extra_bits = (prev_dist-(b/2)-1) % (b/4)
						dist_code = dist_code + 1
						break
					else
						dist_code = dist_code + 2
						dist_extra_bits_bitlen = dist_extra_bits_bitlen + 1
						a = a*2
						b = b*2
					end
				end
			end
			lcode_tblsize = lcode_tblsize + 1
			lcodes[lcode_tblsize] = code
			lcodes_counts[code] = (lcodes_counts[code] or 0) + 1

			dcodes_tblsize = dcodes_tblsize + 1
			dcodes[dcodes_tblsize] = dist_code
			dcodes_counts[dist_code] = (dcodes_counts[dist_code] or 0) + 1

			if length_extra_bits_bitlen > 0 then
				local lenExtraBits = _length_to_deflate_extra_bits[prev_len]
				lextra_bits_tblsize = lextra_bits_tblsize + 1
				lextra_bits[lextra_bits_tblsize] = lenExtraBits
			end
			if dist_extra_bits_bitlen > 0 then
				dextra_bits_tblsize = dextra_bits_tblsize + 1
				dextra_bits[dextra_bits_tblsize] = dist_extra_bits
			end

			for i=index+1, index+prev_len-(config_use_lazy and 2 or 1) do
				hash = (hash*256+(string_table[i-offset+2] or 0))%16777216
				if prev_len <= config_max_insert_length then
					hash_chain = hash_tables[hash]
					if not hash_chain then
						hash_chain = {}
						hash_tables[hash] = hash_chain
					end
					hash_chain[#hash_chain+1] = i
				end
			end
			index = index + prev_len - (config_use_lazy and 1 or 0)
			match_available = false
		elseif (not config_use_lazy) or match_available then
			local code = string_table[config_use_lazy 
				and (string_table_index-1) or string_table_index]
			lcode_tblsize = lcode_tblsize + 1
			lcodes[lcode_tblsize] = code
			lcodes_counts[code] = (lcodes_counts[code] or 0) + 1
			index = index + 1
		else
			match_available = true
			index = index + 1
		end
	end

	-- Write "end of block" symbol
	lcode_tblsize = lcode_tblsize + 1
	lcodes[lcode_tblsize] = 256
	lcodes_counts[256] = (lcodes_counts[256] or 0) + 1

	return lcodes, lextra_bits, lcodes_counts, dcodes, dextra_bits
		, dcodes_counts
end

-- Get the header data of dynamic block.
-- @param lcodes_count The count of each literal/LZ77_length codes.
-- @param dcodes_count The count of each Lz77 distance codes.
-- @return a lots of stuffs.
-- @see RFC1951 Page 12
local function GetBlockDynamicHuffmanHeader(lcodes_counts, dcodes_counts)
	local lcodes_huffman_bitlens, lcodes_huffman_codes
		, max_non_zero_bitlen_lcode =
		GetHuffmanBitlenAndCode(lcodes_counts, 15, 285)
	local dcodes_huffman_bitlens, dcodes_huffman_codes
		, max_non_zero_bitlen_dcode =
		GetHuffmanBitlenAndCode(dcodes_counts, 15, 29)

	local rle_deflate_codes, rle_extra_bits, rle_codes_counts =
		RunLengthEncodeHuffmanBitlen(lcodes_huffman_bitlens
		,max_non_zero_bitlen_lcode, dcodes_huffman_bitlens
		, max_non_zero_bitlen_dcode)

	local rle_codes_huffman_bitlens, rle_codes_huffman_codes =
		GetHuffmanBitlenAndCode(rle_codes_counts, 7, 18)

	local HCLEN = 0
	for i = 1, 19 do
		local symbol = _header_code_order[i]
		local length = rle_codes_huffman_bitlens[symbol] or 0
		if length ~= 0 then
			HCLEN = i
		end
	end

	HCLEN = HCLEN - 4
	local HLIT = max_non_zero_bitlen_lcode + 1 - 257
	local HDIST = max_non_zero_bitlen_dcode + 1 - 1
	if HDIST < 0 then HDIST = 0 end

	return HLIT, HDIST, HCLEN, rle_codes_huffman_bitlens
		, rle_codes_huffman_codes, rle_deflate_codes, rle_extra_bits
		, lcodes_huffman_bitlens, lcodes_huffman_codes
		, dcodes_huffman_bitlens, dcodes_huffman_codes
end

-- Get the size of dynamic block without writing any bits into the writer.
-- @param ... Read the source code of GetBlockDynamicHuffmanHeader()
-- @return the bit length of the dynamic block
local function GetDynamicHuffmanBlockSize(lcodes, dcodes, HCLEN
	, rle_codes_huffman_bitlens, rle_deflate_codes
	, lcodes_huffman_bitlens, dcodes_huffman_bitlens)

	local block_bitlen = 17 -- 1+2+5+5+4
	block_bitlen = block_bitlen + (HCLEN+4)*3

	for i = 1, #rle_deflate_codes do
		local code = rle_deflate_codes[i]
		block_bitlen = block_bitlen + rle_codes_huffman_bitlens[code]
		if code >= 16 then
			block_bitlen = block_bitlen +
			((code == 16) and 2 or (code == 17 and 3 or 7))
		end
	end

	local length_code_count = 0
	for i = 1, #lcodes do
		local code = lcodes[i]
		local huffman_bitlen = lcodes_huffman_bitlens[code]
		block_bitlen = block_bitlen + huffman_bitlen
		if code > 256 then -- Length code
			length_code_count = length_code_count + 1
			if code > 264 and code < 285 then -- Length code with extra bits
				local extra_bits_bitlen =
					_literal_deflate_code_to_extra_bitlen[code-256]
				block_bitlen = block_bitlen + extra_bits_bitlen
			end
			local dist_code = dcodes[length_code_count]
			local dist_huffman_bitlen = dcodes_huffman_bitlens[dist_code]
			block_bitlen = block_bitlen + dist_huffman_bitlen

			if dist_code > 3 then -- dist code with extra bits
				local dist_extra_bits_bitlen = (dist_code-dist_code%2)/2 - 1
				block_bitlen = block_bitlen + dist_extra_bits_bitlen
			end
		end
	end
	return block_bitlen
end

-- Write dynamic block.
-- @param ... Read the source code of GetBlockDynamicHuffmanHeader()
-- @return nil
local function CompressDynamicHuffmanBlock(WriteBits, is_last_block
		, lcodes, lextra_bits, dcodes, dextra_bits, HLIT, HDIST, HCLEN
		, rle_codes_huffman_bitlens, rle_codes_huffman_codes
		, rle_deflate_codes, rle_extra_bits
		, lcodes_huffman_bitlens, lcodes_huffman_codes
		, dcodes_huffman_bitlens, dcodes_huffman_codes)

	WriteBits(is_last_block and 1 or 0, 1) -- Last block identifier
	WriteBits(2, 2) -- Dynamic Huffman block identifier

	WriteBits(HLIT, 5)
	WriteBits(HDIST, 5)
	WriteBits(HCLEN, 4)

	for i = 1, HCLEN+4 do
		local symbol = _header_code_order[i]
		local length = rle_codes_huffman_bitlens[symbol] or 0
		WriteBits(length, 3)
	end

	local rleExtraBitsIndex = 1
	for i=1, #rle_deflate_codes do
		local code = rle_deflate_codes[i]
		WriteBits(rle_codes_huffman_codes[code]
			, rle_codes_huffman_bitlens[code])
		if code >= 16 then
			local extraBits = rle_extra_bits[rleExtraBitsIndex]
			WriteBits(extraBits, (code == 16) and 2 or (code == 17 and 3 or 7))
			rleExtraBitsIndex = rleExtraBitsIndex + 1
		end
	end

	local length_code_count = 0
	local length_code_with_extra_count = 0
	local dist_code_with_extra_count = 0

	for i=1, #lcodes do
		local deflate_codee = lcodes[i]
		local huffman_code = lcodes_huffman_codes[deflate_codee]
		local huffman_bitlen = lcodes_huffman_bitlens[deflate_codee]
		WriteBits(huffman_code, huffman_bitlen)
		if deflate_codee > 256 then -- Length code
			length_code_count = length_code_count + 1
			if deflate_codee > 264 and deflate_codee < 285 then
				-- Length code with extra bits
				length_code_with_extra_count = length_code_with_extra_count + 1
				local extra_bits = lextra_bits[length_code_with_extra_count]
				local extra_bits_bitlen =
					_literal_deflate_code_to_extra_bitlen[deflate_codee-256]
				WriteBits(extra_bits, extra_bits_bitlen)
			end
			-- Write distance code
			local dist_deflate_code = dcodes[length_code_count]
			local dist_huffman_code = dcodes_huffman_codes[dist_deflate_code]
			local dist_huffman_bitlen =
				dcodes_huffman_bitlens[dist_deflate_code]
			WriteBits(dist_huffman_code, dist_huffman_bitlen)

			if dist_deflate_code > 3 then -- dist code with extra bits
				dist_code_with_extra_count = dist_code_with_extra_count + 1
				local dist_extra_bits = dextra_bits[dist_code_with_extra_count]
				local dist_extra_bits_bitlen =
					(dist_deflate_code-dist_deflate_code%2)/2 - 1
				WriteBits(dist_extra_bits, dist_extra_bits_bitlen)
			end
		end
	end
end

-- Get the size of fixed block without writing any bits into the writer.
-- @param lcodes literal/LZ77_length deflate codes
-- @param decodes LZ77 distance deflate codes
-- @return the bit length of the fixed block
local function GetFixedHuffmanBlockSize(lcodes, dcodes)
	local block_bitlen = 3
	local length_code_count = 0
	for i=1, #lcodes do
		local code = lcodes[i]
		local huffman_bitlen = _fix_block_literal_huffman_bitlen[code]
		block_bitlen = block_bitlen + huffman_bitlen
		if code > 256 then -- Length code
			length_code_count = length_code_count + 1
			if code > 264 and code < 285 then -- Length code with extra bits
				local extra_bits_bitlen =
					_literal_deflate_code_to_extra_bitlen[code-256]
				block_bitlen = block_bitlen + extra_bits_bitlen
			end
			local dist_code = dcodes[length_code_count]
			block_bitlen = block_bitlen + 5

			if dist_code > 3 then -- dist code with extra bits
				local dist_extra_bits_bitlen =
					(dist_code-dist_code%2)/2 - 1
				block_bitlen = block_bitlen + dist_extra_bits_bitlen
			end
		end
	end
	return block_bitlen
end

-- Write fixed block.
-- @param lcodes literal/LZ77_length deflate codes
-- @param decodes LZ77 distance deflate codes
-- @return nil
local function CompressFixedHuffmanBlock(WriteBits, is_last_block,
		lcodes, lextra_bits, dcodes, dextra_bits)
	WriteBits(is_last_block and 1 or 0, 1) -- Last block identifier
	WriteBits(1, 2) -- Fixed Huffman block identifier
	local length_code_count = 0
	local length_code_with_extra_count = 0
	local dist_code_with_extra_count = 0
	for i=1, #lcodes do
		local deflate_code = lcodes[i]
		local huffman_code = _fix_block_literal_huffman_code[deflate_code]
		local huffman_bitlen = _fix_block_literal_huffman_bitlen[deflate_code]
		WriteBits(huffman_code, huffman_bitlen)
		if deflate_code > 256 then -- Length code
			length_code_count = length_code_count + 1
			if deflate_code > 264 and deflate_code < 285 then
				-- Length code with extra bits
				length_code_with_extra_count = length_code_with_extra_count + 1
				local extra_bits = lextra_bits[length_code_with_extra_count]
				local extra_bits_bitlen =
					_literal_deflate_code_to_extra_bitlen[deflate_code-256]
				WriteBits(extra_bits, extra_bits_bitlen)
			end
			-- Write distance code
			local dist_code = dcodes[length_code_count]
			local dist_huffman_code = _fix_block_dist_huffman_code[dist_code]
			WriteBits(dist_huffman_code, 5)

			if dist_code > 3 then -- dist code with extra bits
				dist_code_with_extra_count = dist_code_with_extra_count + 1
				local dist_extra_bits = dextra_bits[dist_code_with_extra_count]
				local dist_extra_bits_bitlen = (dist_code-dist_code%2)/2 - 1
				WriteBits(dist_extra_bits, dist_extra_bits_bitlen)
			end
		end
	end
end

-- Get the size of store block without writing any bits into the writer.
-- @param block_start The start index of the origin input string
-- @param block_end The end index of the origin input string
-- @param Total bit lens had been written into the compressed result before,
-- because store block needs to shift to byte boundary.
-- @return the bit length of the fixed block
local function GetStoreBlockSize(block_start, block_end, total_bitlen)
	assert(block_end-block_start+1 <= 65535)
	local block_bitlen = 3
	total_bitlen = total_bitlen + 3
	local padding_bitlen = (8-total_bitlen%8)%8
	block_bitlen = block_bitlen + padding_bitlen
	block_bitlen = block_bitlen + 32
	block_bitlen = block_bitlen + (block_end - block_start + 1) * 8
	return block_bitlen
end

-- Write the store block.
-- @param ... lots of stuffs
-- @return nil
local function CompressStoreBlock(WriteBits, WriteString, is_last_block, str
	, block_start, block_end, total_bitlen)
	assert(block_end-block_start+1 <= 65535)
	WriteBits(is_last_block and 1 or 0, 1) -- Last block identifer.
	WriteBits(0, 2) -- Store block identifier.
	total_bitlen = total_bitlen + 3
	local padding_bitlen = (8-total_bitlen%8)%8
	if padding_bitlen > 0 then
		WriteBits(_pow2[padding_bitlen]-1, padding_bitlen)
	end
	local size = block_end - block_start + 1
	WriteBits(size, 16)

	-- Write size's one's complement
	local comp = (255 - size % 256) + (255 - (size-size%256)/256)*256
	WriteBits(comp, 16)

	WriteString(str:sub(block_start, block_end))
end

-- Do the deflate
-- Currently using a simple way to determine the block size
-- (This is why the compression ratio is little bit worse than zlib when
-- the input size is very large
-- The first block is 64KB, the following block is 32KB.
-- After each block, there is a memory cleanup operation.
-- This is not a fast operation, but it is needed to save memory usage, so
-- the memory usage does not grow unboundly. If the data size is less than
-- 64KB, then memory cleanup won't happen.
-- This function determines whether to use store/fixed/dynamic blocks by
-- calculating the block size of each block type and chooses the smallest one.
local function Deflate(WriteBits, WriteString, Flush, str, level, dictionary)
	local string_table = {}
	local hash_tables = {}
	local is_last_block = nil
	local block_start
	local block_end
	local result, bitlen_written
	local total_bitlen = select(2, Flush())
	local strlen = #str
	local offset
	while not is_last_block do
		if not block_start then
			block_start = 1
			block_end = 64*1024 - 1
			offset = 0
		else
			block_start = block_end + 1
			block_end = block_end + 32*1024
			offset = block_start - 32*1024 - 1
		end

		if block_end >= strlen then
			block_end = strlen
			is_last_block = true
		else
			is_last_block = false
		end

		-- GetBlockLZ77 needs block_start to block_end+3 to be loaded.
		loadStrToTable(str, string_table, block_start, block_end + 3, offset)

		if block_start == 1 and dictionary then
			local dict_string_table = dictionary.string_table
			local dict_strlen = dictionary.strlen
			for i=0, (-dict_strlen+1)<-257 and -257 or (-dict_strlen+1), -1 do
				local dictChar = dict_string_table[dict_strlen+i]
				string_table[i] = dictChar
			end
		end
		local lcodes, lextra_bits, lcodes_counts, dcodes, dextra_bits
			, dcodes_counts = GetBlockLZ77Result(level, string_table
			, hash_tables, block_start, block_end, offset, dictionary)

		local HLIT, HDIST, HCLEN, rle_codes_huffman_bitlens
			, rle_codes_huffman_codes, rle_deflate_codes
			, rle_extra_bits, lcodes_huffman_bitlens, lcodes_huffman_codes
			, dcodes_huffman_bitlens, dcodes_huffman_codes =
			GetBlockDynamicHuffmanHeader(lcodes_counts, dcodes_counts)
		local dynamic_block_bitlen = GetDynamicHuffmanBlockSize(
				lcodes, dcodes, HCLEN, rle_codes_huffman_bitlens
				, rle_deflate_codes, lcodes_huffman_bitlens
				, dcodes_huffman_bitlens)
		local fixed_block_bitlen = GetFixedHuffmanBlockSize(lcodes, dcodes)
		local store_block_bitlen = GetStoreBlockSize(block_start, block_end
			, total_bitlen)

		local min_bitlen = dynamic_block_bitlen
		min_bitlen = (fixed_block_bitlen < min_bitlen)
			and fixed_block_bitlen or min_bitlen
		min_bitlen = (store_block_bitlen < min_bitlen)
			and store_block_bitlen or min_bitlen

		if store_block_bitlen == min_bitlen then
			CompressStoreBlock(WriteBits, WriteString, is_last_block
				, str, block_start, block_end, total_bitlen)
			total_bitlen = total_bitlen + store_block_bitlen
		elseif fixed_block_bitlen ==  min_bitlen then
			CompressFixedHuffmanBlock(WriteBits, is_last_block,
					lcodes, lextra_bits, dcodes, dextra_bits)
			total_bitlen = total_bitlen + fixed_block_bitlen
		elseif dynamic_block_bitlen == min_bitlen then
			CompressDynamicHuffmanBlock(WriteBits, is_last_block, lcodes
				, lextra_bits, dcodes, dextra_bits, HLIT, HDIST, HCLEN
				, rle_codes_huffman_bitlens, rle_codes_huffman_codes
				, rle_deflate_codes, rle_extra_bits
				, lcodes_huffman_bitlens, lcodes_huffman_codes
				, dcodes_huffman_bitlens, dcodes_huffman_codes)
			total_bitlen = total_bitlen + dynamic_block_bitlen
		end

		result, bitlen_written = Flush()
		if bitlen_written ~= total_bitlen then
			error(("sth wrong in the bitSize calculation, %d %d")
				:format(bitlen_written, total_bitlen))
		end

		-- Memory clean up, so memory consumption does not always grow linearly
		-- , even if input string is > 64K.
		-- Not a very efficient operation, but this operation won't happen
		-- when the input data size is less than 64K.
		if not is_last_block then
			local j
			if dictionary and block_start == 1 then
				j = 0
				while (string_table[j]) do
					string_table[j] = nil
					j = j - 1
				end
			end
			dictionary = nil
			j = 1
			for i = block_end-32767, block_end do
				string_table[j] = string_table[i-offset]
				j = j + 1
			end

			for k, t in pairs(hash_tables) do
				local tSize = #t
				if tSize > 0 and block_end+1 - t[1] > 32768 then
					if tSize == 1 then
						hash_tables[k] = nil
					else
						local new = {}
						local newSize = 0
						for i = 2, tSize do
							j = t[i]
							if block_end+1 - j <= 32768 then
								newSize = newSize + 1
								new[newSize] = j
							end
						end
						hash_tables[k] = new
					end
				end
			end
		end
	end
end

function LibDeflate:CompressDeflate(str, level, dictionary)
	assert(type(str)=="string")
	assert(type(level)=="nil" or (type(level)=="number" and level >= 1 and level <= 9))

	local WriteBits, WriteString, Flush = CreateWriter()

	Deflate(WriteBits, WriteString, Flush, str, level, dictionary)
	local result, totalBitSize = Flush(true)
	return result, totalBitSize
end

function LibDeflate:CompressZlib(str, level, dictionary)
	assert(type(str)=="string")
	assert(type(level)=="nil" or (type(level)=="number" and level >= 1 and level <= 9))

	local WriteBits, WriteString, Flush = CreateWriter()

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

	Deflate(WriteBits, WriteString, Flush, str, level, dictionary)
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


-- TODO: Deprecated.
function LibDeflate:Compress(str, level, dictionary)
	return self:CompressDeflate(str, level, dictionary)
end

------------------------------------------------------------------------------
------------------------------------------------------------------------------
local function CreateReader(inputString)
	local input = inputString
	local inputLen = #inputString
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
		dictStrTable = dictionary.string_table
		dictStrLen = dictionary.strlen
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
		lengthLengths[_header_code_order[index]] = ReadBits(3)
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
	local strLen = #str

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
	local strlen = #str
	assert(strlen > 0)
	assert(strlen <= 32768, tostring(strlen))
	local dictionary = {}
	dictionary.string_table = {}
	dictionary.strlen = strlen
	dictionary.hash_tables = {}
	local string_table = dictionary.string_table
	local hashTables = dictionary.hash_tables
	string_table[1] = string_byte(str, 1, 1)
	string_table[2] = string_byte(str, 2, 2)
	if strlen >= 3 then
		local i = 1
		local hash = string_table[1]*256+string_table[2]
		while i <= strlen - 2 - 3 do
			local x1, x2, x3, x4 = string_byte(str, i+2, i+5)
			string_table[i+2] = x1
			string_table[i+3] = x2
			string_table[i+4] = x3
			string_table[i+5] = x4
			hash = (hash*256+x1)%16777216
			local t = hashTables[hash] or {i-strlen}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = i-strlen end
			i =  i + 1
			hash = (hash*256+x2)%16777216
			t = hashTables[hash] or {i-strlen}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = i-strlen end
			i =  i + 1
			hash = (hash*256+x3)%16777216
			t = hashTables[hash] or {i-strlen}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = i-strlen end
			i =  i + 1
			hash = (hash*256+x4)%16777216
			t = hashTables[hash] or {i-strlen}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = i-strlen end
			i = i + 1
		end
		while i <= strlen - 2 do
			local x = string_byte(str, i+2)
			string_table[i+2] = x
			hash = (hash*256+x)%16777216
			local t = hashTables[hash] or {i-strlen}
			if #t == 1 then hashTables[hash] = t else t[#t+1] = i-strlen end
			i = i + 1
		end
	end
	return dictionary
end

-- Calculate the huffman code of fixed block
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
	status, _fix_block_literal_huffman_bitlen_count
		, _fix_block_literal_huffman_to_deflate_code =
		ConstructInflateHuffman(_fix_block_literal_huffman_bitlen, 288, 9)
	assert(status == 0)
	status, _fix_block_dist_huffman_bitlen_count,
		_fix_block_dist_huffman_to_deflate_code =
		ConstructInflateHuffman(_fix_block_dist_huffman_bitlen, 32, 5)
	assert(status == 0)

	_fix_block_literal_huffman_code =
		GetHuffmanCodeFromBitlen(_fix_block_literal_huffman_bitlen_count
		, _fix_block_literal_huffman_bitlen, 287, 9)
	_fix_block_dist_huffman_code =
		GetHuffmanCodeFromBitlen(_fix_block_dist_huffman_bitlen_count
		, _fix_block_dist_huffman_bitlen, 31, 5)
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