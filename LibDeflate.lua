--[[
	LibDeflate: Pure Lua implemenation of the DEFLATE lossless data compression algorithm.
	Copyright (C) <2018>  Haoqian He (Github: SafeteeWoW; World of Warcraft: Safetyy-Illidan(US))

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
--]]

local LibDeflate
if LibStub then
	local MAJOR,MINOR = "LibDeflate-1.0", -1
	LibDeflate = LibStub:NewLibrary(MAJOR, MINOR)
	if not LibDeflate then
		return LibStub:GetLibrary(MAJOR)
	end
else
	-- TODO: Cleanup tables in the old version
	LibDeflate = {}
end

-- local is faster than global
local assert = assert
local table_concat = table.concat
local table_sort = table.sort
local string_char = string.char
local string_byte = string.byte
local string_sub = string.sub
local pairs = pairs
local type = type

---------------------------------------
--	Precalculated tables start.
---------------------------------------

--[[
	key of the configuration table is the compression level, and its value stores the compression setting
	See also https://github.com/madler/zlib/blob/master/doc/algorithm.txt,
	And https://github.com/madler/zlib/blob/master/deflate.c for more infomration

	The meaning of each field:
	1. use_lazy_evaluation: true/false. Whether the program uses lazy evaluation.
							See what is "lazy evaluation" in the link above.
							lazy_evaluation improves ratio, but relatively slow.
	2. good_prev_length: Only effective if lazy is set, Only use 1/4 of max_chain
						 if prev length of lazy match is above this.
	3. max_insert_length/max_lazy_match:
			If not using lazy evaluation, Insert new strings in the hash table only if the match length is not
			greater than this length.Only continue lazy evaluation.
			If using lazy evaluation, only continue lazy evaluation if prev length is strictly smaller than this.
	4. nice_length: Number. Don't continue to go down the hash chain if match length is above this.
	5. max_chain: Number. The maximum number of hash chains we look.

--]]
local _configuration_table = {
	[1] = {false,	nil,	4,	8,	 4},		-- gzip -1
	[2] = {false,	nil,	5,	18, 8},		-- gzip -2
	[3] = {false,	nil,	6,	 32,	32,},	-- gzip -3

	[4] = {true,	4,		4,		16,	16},	-- gzip -4
	[5] = {true,	8,		16,		32,	32},	-- gzip -5
	[6] = {true,	8,		16,		128,128},	  -- gzip -6
	[7] = {true,	8,		32,		128,256},	  -- gzip -7
	[8] = {true,	32,	 128,	258,1024},	 -- gzip -8
	[9] = {true,	32,	 258,	258,4096},	 -- gzip -9 (maximum compression)
}

local _pow2 = {}
local _byteToChar = {}
local _reverseBitsTbl = {}
-- _reverseBitsTbl[len][val] stores the bit reverse of the number of bit length "len" and value "val"

local _lenToLiteralCode = {}
local _lenToExtraBits = {}
local _lenToExtraBitsLen = {}

local _dist256ToCode = {} -- For distance 1..256
local _dist256ToExtraBits = {} -- For distance 1..256
local _dist256ToExtraBitsLen = {} -- For distance 1..256

local _codeLengthHuffmanCodeOrder = {16, 17, 18,
	0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15}
local _literalCodeToBaseLen = { -- Size base for length codes 257..285
	3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
	35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258}
local _literalCodeToExtraBitsLen = { -- Extra bits for length codes 257..285
	0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
	3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0}
local _distCodeToBaseDist = { -- Offset base for distance codes 0..29
	[0] = 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
	257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
	8193, 12289, 16385, 24577}
local _distCodeToExtraBitsLen = { -- Extra bits for distance codes 0..29
	[0] = 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
	7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
	12, 12, 13, 13}

local _fixLitHuffmanLen
local _fixDistHuffmanLen

local _fixLitHuffmanCode
local _fixLitHuffmanSym
local _fixLitHuffmanLenCount

local _fixDistHuffmanCode
local _fixDistHuffmanSym
local _fixDistHuffmanLenCount
------------------------------------------------------------------------
------------------------------------------------------------------------

for i=0, 255 do
	_byteToChar[i] = string_char(i)
end

do
	local pow = 1
	for i=0, 31 do
		_pow2[i] = pow
		pow = pow*2
	end
end

for i=1, 9 do
	_reverseBitsTbl[i] = {}
	for j=0, _pow2[i+1]-1 do
		local res = 0
		local code = j
		for _=1, i do
			res = res - res%2 + (((res%2==1) or (code % 2) == 1) and 1 or 0) -- res | (code%2)
			code = (code-code%2)/2
			res = res*2
		end
		_reverseBitsTbl[i][j] = (res-res%2)/2
	end
end

do
	local a = 18
	local b = 16
	local c = 265
	local bitsLen = 1
	for len=3, 258 do
		if len <= 10 then
			_lenToLiteralCode[len] = len + 254
			_lenToExtraBitsLen[len] = 0
		elseif len == 258 then
			_lenToLiteralCode[len] = 285
			_lenToExtraBitsLen[len] = 0
		else
			if len > a then
				a = a + b
				b = b * 2
				c = c + 4
				bitsLen = bitsLen + 1
			end
			local t = len-a-1+b/2
			_lenToLiteralCode[len] = (t-(t%(b/8)))/(b/8) + c
			_lenToExtraBitsLen[len] = bitsLen
			_lenToExtraBits[len] = t % (b/8)
		end
	end
end


do
	_dist256ToCode[1] = 0
	_dist256ToCode[2] = 1
	_dist256ToExtraBitsLen[1] = 0
	_dist256ToExtraBitsLen[2] = 0

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
		_dist256ToCode[dist] = (dist <= a) and code or (code+1)
		_dist256ToExtraBitsLen[dist] = (bitsLen < 0) and 0 or bitsLen
		if b >= 8 then
			_dist256ToExtraBits[dist] = (dist-b/2-1) % (b/4)
		end
	end
end

---------------------------------------
--	Precalculated tables ends.
---------------------------------------
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
			buffer[bufferSize+1] = _byteToChar[cache % 256]
			buffer[bufferSize+2] = _byteToChar[((cache-cache%256)/256 % 256)]
			buffer[bufferSize+3] = _byteToChar[((cache-cache%65536)/65536 % 256)]
			buffer[bufferSize+4] = _byteToChar[((cache-cache%16777216)/16777216 % 256)]
			bufferSize = bufferSize + 4
			local rShiftMask = _pow2[32 - cacheBitRemaining + bitLength]
			cache = (code - code%rShiftMask)/rShiftMask
			cacheBitRemaining = cacheBitRemaining - 32
		end
	end

	local function Flush(lastTimeToUseWriter)
		local ret
		if lastTimeToUseWriter then
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
			buffer = nil
		else
			ret = table_concat(buffer)
			buffer = {ret}
			bufferSize = 1
		end
		return ret
	end

	return WriteBits, Flush
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

local function loadStrToTable(str, t, start, stop)
	start = (start < 1) and 1 or start
	stop = (stop > str:len()) and str:len() or stop
	if start > stop or start > str:len() or stop <= 0 then return end
	local i=start-1
	while i <= stop - 16 do
		local x1, x2, x3, x4, x5, x6, x7, x8,
			x9, x10, x11, x12, x13, x14, x15, x16 = string_byte(str, i+1, i+16)
		t[i+1]=x1
		t[i+2]=x2
		t[i+3]=x3
		t[i+4]=x4
		t[i+5]=x5
		t[i+6]=x6
		t[i+7]=x7
		t[i+8]=x8
		t[i+9]=x9
		t[i+10]=x10
		t[i+11]=x11
		t[i+12]=x12
		t[i+13]=x13
		t[i+14]=x14
		t[i+15]=x15
		t[i+16]=x16
		i = i + 16
	end
	i = i + 1
	while (i <= stop) do
		t[i] = string_byte(str, i, i)
		i = i + 1
	end
	return t
end

local function CompressBlockLZ77(level, strTable, hashTables, blockStart, blockEnd)
	if not level then
		level = 5
	end

	local config = _configuration_table[level]
	local config_use_lazy, config_good_prev_length, config_max_lazy_match, config_nice_length
		, config_max_hash_chain = config[1], config[2], config[3], config[4], config[5]

	local config_max_insert_length = (not config_use_lazy) and config_max_lazy_match or 2147483646
	local config_good_hash_chain = (config_max_hash_chain-config_max_hash_chain%4/4)

	local index = blockStart
	local indexEnd = blockEnd + (config_use_lazy and 1 or 0)
	local hash = (strTable[blockStart] or 0)*256 + (strTable[blockStart+1] or 0)

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

	while (index <= indexEnd) do
		prevLen = curLen
		prevDist = curDist
		curLen = 0

		hash = (hash*256+(strTable[index+2] or 0))%16777216

		local hashChain = hashTables[hash]
		if not hashChain then
			hashChain = {}
			hashTables[hash] = hashChain
		end
		local chainSize = #hashChain

		if (chainSize > 0 and index+2 <= blockEnd and (not config_use_lazy or prevLen < config_max_lazy_match)) then
			local iEnd = (config_use_lazy and prevLen >= config_good_prev_length)
				and (chainSize - config_good_hash_chain + 1) or 1
			if iEnd < 1 then iEnd = 1 end

			for i=chainSize, iEnd, -1 do
				local prev = hashChain[i]
				if index - prev > 32768 then
					break
				end
				if prev < index then
					local j = 3
					while (j < 258 and index + j < blockEnd) do
						if (strTable[prev+j] == strTable[index+j]) then
							j = j + 1
						else
							break
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
			local code = _lenToLiteralCode[prevLen]
			local lenExtraBitsLength = _lenToExtraBitsLen[prevLen]
			local distCode, distExtraBitsLength, distExtraBits
			if prevDist <= 256 then
				distCode = _dist256ToCode[prevDist]
				distExtraBits = _dist256ToExtraBits[prevDist]
				distExtraBitsLength =  _dist256ToExtraBitsLen[prevDist]
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
				local lenExtraBits = _lenToExtraBits[prevLen]
				lExtraBitTblSize = lExtraBitTblSize + 1
				lExtraBits[lExtraBitTblSize] = lenExtraBits
			end
			if distExtraBitsLength > 0 then
				dExtraBitTblSize = dExtraBitTblSize + 1
				dExtraBits[dExtraBitTblSize] = distExtraBits
			end

			for i=index+1, index+prevLen-(config_use_lazy and 2 or 1) do
				hash = (hash*256+(strTable[i+2] or 0))%16777216
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
			local code = strTable[config_use_lazy and (index-1) or index]
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
		local symbol = _codeLengthHuffmanCodeOrder[i]
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
				local extraBitsLength = _literalCodeToExtraBitsLen[code-256]
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
		local symbol = _codeLengthHuffmanCodeOrder[i]
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
				local extraBitsLength = _literalCodeToExtraBitsLen[code-256]
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
		local huffmanLength = _fixLitHuffmanLen[code]
		blockBitSize = blockBitSize + huffmanLength
		if code > 256 then -- Length code
			lengthCodeCount = lengthCodeCount + 1
			if code > 264 and code < 285 then -- Length code with extra bits
				local extraBitsLength = _literalCodeToExtraBitsLen[code-256]
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
		local huffmanCode = _fixLitHuffmanCode[code]
		local huffmanLength = _fixLitHuffmanLen[code]
		WriteBits(huffmanCode, huffmanLength)
		if code > 256 then -- Length code
			lengthCodeCount = lengthCodeCount + 1
			if code > 264 and code < 285 then -- Length code with extra bits
				lengthCodeWithExtraCount = lengthCodeWithExtraCount + 1
				local extraBits = lExtraBits[lengthCodeWithExtraCount]
				local extraBitsLength = _literalCodeToExtraBitsLen[code-256]
				WriteBits(extraBits, extraBitsLength)
			end
			-- Write distance code
			local distCode = dCodes[lengthCodeCount]
			local distHuffmanCode = _fixDistHuffmanCode[distCode]
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

function LibDeflate:Compress(str, level, start, stop)
	assert(type(str)=="string")
	assert(type(level)=="nil" or (type(level)=="number" and level >= 1 and level <= 8))
	assert(type(start)=="nil" or (type(start)=="number"))
	assert(type(stop)=="nil" or (type(stop)=="number"))

	start = start or 1
	start = (start < 1) and 1 or start
	stop = stop or str:len()
	stop = (stop > str:len()) and str:len() or stop
	if start > stop then
		start = 1
		stop = 0
	end

	local strTable = {}
	local hashTables = {}
	-- The maximum size of the first dynamic block is 64KB
	local INITIAL_BLOCK_SIZE = 64*1024
	-- The maximum size of the additional block is 32KB
	local ADDITIONAL_BLOCK_SIZE = 32*1024
	local isLastBlock = nil
	local blockStart
	local blockEnd
	local WriteBits, Flush = CreateWriter()
	local result

	local totalBitSize = 0
	while not isLastBlock do
		if not blockStart then
			blockStart = start
			blockEnd = start + INITIAL_BLOCK_SIZE
		else
			blockStart = blockEnd + 1
			blockEnd = blockEnd + ADDITIONAL_BLOCK_SIZE
		end

		if blockEnd >= stop then
			blockEnd = stop
			isLastBlock = true
		else
			isLastBlock = false
		end

		loadStrToTable(str, strTable, blockStart, (blockEnd+3 > stop) and stop or (blockEnd+3))
		-- +3 is needed for dynamic block

		local lCodes, lExtraBits, lCodesCount, dCodes, dExtraBits, dCodesCount =
			CompressBlockLZ77(level, strTable, hashTables, blockStart, blockEnd)

		local HLIT, HDIST, HCLEN, codeLensCodeLens, codeLensCodeCodes, rleCodes, rleExtraBits
			, lCodeLens, lCodeCodes, dCodeLens, dCodeCodes =
			GetBlockDynamicHuffmanHeader(lCodesCount, dCodesCount)
		local dynamicBlockBitSize = GetBlockDynamicHuffmanSize(
				lCodes, dCodes, HCLEN, codeLensCodeLens, rleCodes, lCodeLens, dCodeLens)
		local fixBlockBitSize = GetBlockFixHuffmanSize(lCodes, dCodes)

		if dynamicBlockBitSize < fixBlockBitSize then
			CompressBlockDynamicHuffman(WriteBits, isLastBlock,
					lCodes, lExtraBits, dCodes, dExtraBits, HLIT, HDIST, HCLEN,
					codeLensCodeLens, codeLensCodeCodes, rleCodes, rleExtraBits, lCodeLens, lCodeCodes, dCodeLens, dCodeCodes)
			totalBitSize = totalBitSize + dynamicBlockBitSize
		else
			CompressBlockFixHuffman(WriteBits, isLastBlock,
					lCodes, lExtraBits, dCodes, dExtraBits)
			totalBitSize = totalBitSize + fixBlockBitSize
			-- print("Choose Fix block because it is smaller! "..(dynamicBlockBitSize-fixBlockBitSize))
		end

		result = Flush(isLastBlock)
		assert(result:len()*8-totalBitSize < 8, ("sth wrong in the bitSize calculation, %d %d")
			:format(result:len()*8, totalBitSize))

		-- Memory clean up, so memory consumption does not always grow linearly, even if input string is > 64K.
		if not isLastBlock then
			for i=blockEnd-2*ADDITIONAL_BLOCK_SIZE+1, blockEnd-ADDITIONAL_BLOCK_SIZE do
				strTable[i] = nil
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
							local j = t[i]
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


	return result, totalBitSize
end

------------------------------------------------------------------------------
------------------------------------------------------------------------------
local function CreateReader(inputString, start, stop)
	local input = inputString
	local inputNextBytePos = start
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
		if (stop - inputNextBytePos + 1) * 8 + cacheBitRemaining < 0 then
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
		local code = cache % rShiftMask
		cache = (cache - code) / rShiftMask
		-- Reverse the bits
		code = _reverseBitsTbl[minLen][code]

		local count = huffmanLenCount[minLen]-- Number of codes of length len
		if code < count then
			return huffmanSymbol[code]
		end
		local index = count
		local first = count + count -- First code of length lenfirst = first + count
		code = code + code

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
		return (stop - inputNextBytePos + 1) * 8 + cacheBitRemaining
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
		return 0  -- Complete, but decode will fail
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
	repeat
		local symbol = Decode(litHuffmanLen, litHuffmanSym, litMinLen)
		if symbol < 0 or symbol > 285 then
			return -10 -- invalid literal/length or distance code in fixed or dynamic block
		elseif symbol < 256 then -- Literal
			bufferSize = bufferSize + 1
			buffer[bufferSize] = _byteToChar[symbol]
		elseif symbol > 256 then -- Length code
			symbol = symbol - 256
			local length = _literalCodeToBaseLen[symbol]
			length = (symbol >= 8) and (length + ReadBits(_literalCodeToExtraBitsLen[symbol])) or length
			symbol = Decode(distHuffmanLen, distHuffmanSym, distMinLen)
			if symbol < 0 or symbol > 29 then
				return -10 -- invalid literal/length or distance code in fixed or dynamic block
			end
			local dist = _distCodeToBaseDist[symbol]
			dist = (dist > 4) and (dist + ReadBits(_distCodeToExtraBitsLen[symbol])) or dist

			local charBufferIndex = bufferSize-dist
			if charBufferIndex < 0 then
				return -11 -- distance is too far back in fixed or dynamic block
			end
			for _=1, length do
				charBufferIndex = charBufferIndex + 1
				bufferSize = bufferSize + 1
				buffer[bufferSize] = buffer[charBufferIndex]
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
		end
	until symbol == 256

	state.bufferSize = bufferSize
	state.result = result

	return 0
end

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

	-- Check if len and lenComp are one's complement
	local tmpLen = len
	local tmpLenComp = lenComp
	for _=1, 16 do
		local bit1 = len % 2
		local bit2 = lenComp % 2
		if not (bit1 + bit2 == 1) then
			return -2 -- stored block length did not match one's complement
		end
		tmpLen = (tmpLen - bit1) / 2
		tmpLenComp = (tmpLenComp - bit2) / 2
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
	return DecodeUntilEndOfBlock(state, _fixLitHuffmanLenCount, _fixLitHuffmanSym, 7,
		_fixDistHuffmanLenCount, _fixDistHuffmanSym, 5)
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
		lengthLengths[_codeLengthHuffmanCodeOrder[index]] = ReadBits(3)
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
	if (litErr ~=0 and (litErr < 0 or nLen ~= (litHuffmanLenCount[0] or 0)+(litHuffmanLenCount[1] or 0))) then
		return -7   -- dynamic block code description: invalid literal/length code lengths
					-- Incomplete code ok only for single length 1 code
	end

	local distErr, distHuffmanLenCount, distHuffmanSym, distMinLen = ConstructInflateHuffman(distHuffmanLen, nDist, 15)
	if (distErr ~=0 and (distErr < 0 or nDist ~= (distHuffmanLenCount[0] or 0)+(distHuffmanLenCount[1] or 0))) then
		return -8   -- dynamic block code description: invalid distance code lengths,
					-- Incomplete code ok only for single length 1 code
	end

	-- Build buffman table for literal/length codes
	return DecodeUntilEndOfBlock(state, litHuffmanLenCount, litHuffmanSym, litMinLen
		, distHuffmanLenCount, distHuffmanSym, distMinLen)
end

function LibDeflate:Decompress(str, start, stop)
	-- WIP
	assert(type(str) == "string")

	start = start or 1
	stop = stop or str:len()
	local ReadBits, ReadBytes, Decode, ReaderBitsLeft, SkipToByteBoundary = CreateReader(str, start, stop)
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
	}

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

	local bitsLeft = ReaderBitsLeft()
	local byteLeft = (bitsLeft - bitsLeft % 8) / 8

	state.result = state.result..table_concat(state.buffer, "", 1, state.bufferSize)
	return state.result, byteLeft
end

function LibDeflate:Adler32(str, start, stop)
	assert(type(str) == "string")
	assert(type(start)=="nil" or type(start) == "number")
	assert(type(stop)=="nil" or type(stop) == "number")
	start = start or 1
	stop = stop or str:len()
	start = (start < 1) and 1 or start
	stop = (stop > str:len()) and str:len() or stop
	if start > stop or start > str:len() or stop <= 0 then return 1 end

	local i=start-1
	local a = 1
	local b = 0
	while i <= stop - 16 do
		local x1, x2, x3, x4, x5, x6, x7, x8,
			x9, x10, x11, x12, x13, x14, x15, x16 = string_byte(str, i+1, i+16)
		b = (b+16*a+16*x1+15*x2+14*x3+13*x4+12*x5+11*x6+10*x7+9*x8+8*x9+7*x10+6*x11+5*x12+4*x13+3*x14+2*x15+x16)%65521
		a = (a+x1+x2+x3+x4+x5+x6+x7+x8+x9+x10+x11+x12+x13+x14+x15+x16)%65521
		i =  i + 16
	end
	i = i + 1
	while (i <= stop) do
		local x = string_byte(str, i, i)
		a = (a + x) % 65521
		b = (b + a) % 65521
		i = i + 1
	end
	return b*65536+a
end

-- Fix huffman code
do
	_fixLitHuffmanLen = {}
	for sym=0, 143 do
		_fixLitHuffmanLen[sym] = 8
	end
	for sym=144, 255 do
		_fixLitHuffmanLen[sym] = 9
	end
	for sym=256, 279 do
	    _fixLitHuffmanLen[sym] = 7
	end
	for sym=280, 287 do
		_fixLitHuffmanLen[sym] = 8
	end

	_fixDistHuffmanLen = {}
	for dist=0, 31 do
		_fixDistHuffmanLen[dist] = 5
	end
	local status
	status, _fixLitHuffmanLenCount, _fixLitHuffmanSym = ConstructInflateHuffman(_fixLitHuffmanLen, 288, 9)
	assert(status == 0)
	status, _fixDistHuffmanLenCount, _fixDistHuffmanSym = ConstructInflateHuffman(_fixDistHuffmanLen, 32, 5)
	assert(status == 0)

	_fixLitHuffmanCode = GetHuffmanCodeFromBitLength(_fixLitHuffmanLenCount, _fixLitHuffmanLen, 287, 9)
	_fixDistHuffmanCode = GetHuffmanCodeFromBitLength(_fixDistHuffmanLenCount, _fixDistHuffmanLen, 31, 5)
end

-- For test. Don't use the functions in this table for real application.
-- Stuffs in this table is subject to change.
LibDeflate.internals = {
	loadStrToTable = loadStrToTable,
}

return LibDeflate