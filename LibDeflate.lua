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
	local MAJOR,MINOR = "LibDeflate", -1
	LibDeflate = LibStub:NewLibrary(MAJOR, MINOR)
	if not LibDeflate then
		return LibStub:GetLibrary(MAJOR)
	end
else
	LibDeflate = {}
end

-- local is faster than global
local assert = assert
local table_concat = table.concat
local table_sort = table.sort
local string_char = string.char
local string_byte = string.byte
local pairs = pairs

local function print() end

local function PrintTable(t, start, stop)
	local tmp = {}
	for i=start, stop do
		table.insert(tmp, tostring(t[i]))
	end
	_G.print(table_concat(tmp, " "))
end

---------------------------------------
--	Precalculated tables start.
---------------------------------------
local _lengthCodeToBaseLen = { -- Size base for length codes 257..285
	3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
	35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
local _literalCodeToExtraBitsLen = { -- Extra bits for length codes 265..285
	 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
local _distanceCodeToBaseDist = { -- Offset base for distance codes 0..29
	[0] = 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
	257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
	8193, 12289, 16385, 24577};
local _distanceCodeToExtraBitsLen = { -- Extra bits for distance codes 0..29
	[0] = 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
	7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
	12, 12, 13, 13};

local _twoBytesToChar = {}
local _byteToChar = {}
local _pow2 = {}
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

local _lengthToLiteralCode = {}
local _lengthToExtraBits = {}
local _lengthToExtraBitsLen = {}
do
	local a = 18
	local b = 16
	local c = 265
	local bitsLen = 1
	for len=3, 258 do
		if len <= 10 then
			_lengthToLiteralCode[len] = len + 254
			_lengthToExtraBitsLen[len] = 0
		elseif len == 258 then
			_lengthToLiteralCode[len] = 285
			_lengthToExtraBitsLen[len] = 0
		else
			if len > a then
				a = a + b
				b = b * 2
				c = c + 4
				bitsLen = bitsLen + 1
			end
			local t = len-a-1+b/2
			_lengthToLiteralCode[len] = (t-(t%(b/8)))/(b/8) + c
			_lengthToExtraBitsLen[len] = bitsLen
			_lengthToExtraBits[len] = t % (b/8)
		end
	end
end

local _distanceToCode = {} -- For distance 1..256
local _distanceToExtraBits = {} -- For distance 1..256
local _distanceToExtraBitsLen = {} -- For distance 1..256
do
	_distanceToCode[1] = 0
	_distanceToCode[2] = 1
	_distanceToExtraBitsLen[1] = 0
	_distanceToExtraBitsLen[2] = 0

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
		_distanceToCode[dist] = (dist <= a) and code or (code+1)
		_distanceToExtraBitsLen[dist] = (bitsLen < 0) and 0 or bitsLen
		if b >= 8 then
			_distanceToExtraBits[dist] = (dist-b/2-1) % (b/4)
		end
	end
end

for i=0,256*256-1 do
	_twoBytesToChar[i] = string_char(i%256)..string_char((i-i%256)/256)
end

_G.print(("Static memory used: %.2f MB"):format(collectgarbage("count")/1024))
---------------------------------------
--	Precalculated tables ends.
---------------------------------------

local function CreateWriter(oneBytePerElement)
	local _writeCompressedSize = 0
	local _writeRemainder = 0
	local _writeRemainderLength = 0
	local _writeBuffer = {}
	local _oneBytePerElement = oneBytePerElement

	local function WriteBits(code, length)
		_writeRemainder = _writeRemainder + code * _pow2[_writeRemainderLength] -- Overflow?
		_writeRemainderLength = length + _writeRemainderLength
		if _writeRemainderLength >= 32 then
			-- we have at least 4 bytes to store; bulk it
			if _oneBytePerElement then
				_writeBuffer[_writeCompressedSize+1] = _byteToChar[_writeRemainder % 256]
				_writeBuffer[_writeCompressedSize+2] = _byteToChar[((_writeRemainder-_writeRemainder%256)/256 % 256)]
				_writeBuffer[_writeCompressedSize+3] = _byteToChar[((_writeRemainder-_writeRemainder%65536)/65536 % 256)]
				_writeBuffer[_writeCompressedSize+4] = _byteToChar[((_writeRemainder-_writeRemainder%16777216)/16777216 % 256)]
				_writeCompressedSize = _writeCompressedSize + 4
			else
				_writeBuffer[_writeCompressedSize+1] = _twoBytesToChar[_writeRemainder % 65536]
				_writeBuffer[_writeCompressedSize+2] = _twoBytesToChar[((_writeRemainder-_writeRemainder%65536)/65536 % 65536)]
				_writeCompressedSize = _writeCompressedSize + 2
			end
			local rShiftMask = _pow2[32 - _writeRemainderLength + length]
			_writeRemainder = (code - code%rShiftMask)/rShiftMask
			_writeRemainderLength = _writeRemainderLength - 32
		end
	end

	local function Flush(lastUseWriter)
		local ret
		if lastUseWriter then
			if _writeRemainderLength > 0 then
				for _=1, _writeRemainderLength, 8 do
					_writeCompressedSize = _writeCompressedSize + 1
					_writeBuffer[_writeCompressedSize] = string_char(_writeRemainder % 256)
					_writeRemainder = (_writeRemainder-_writeRemainder%256)/256
				end
				_writeRemainder = 0
				_writeRemainderLength = 0
			end
			ret = table_concat(_writeBuffer)
			_writeBuffer = nil
		else
			ret = table_concat(_writeBuffer)
			_writeBuffer = {ret}
			_writeCompressedSize = 1
		end
		return ret
	end

	return WriteBits, Flush, _writeBuffer
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

local function SortByFirstThenSecond(a, b)
	return a[1] < b[1] or
		(a[1] == b[1] and a[2] < b[2])
	 -- This is important so our result is stable regardless of interpreter implementation.
end

--@treturn {table, table} symbol length table and symbol code table
local function GetHuffmanBitLengthAndCode(symCount, maxBitLength, maxSymbol, WriteBits)
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

		-- From RFC1951. Calculate huffman code from code bit length.
		local code = 0
		local nextCode = {}
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

local _codeLengthHuffmanCodeOrder = {16, 17, 18,
	0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15}

local function loadStrToTable(str, t, start, stop)
	local i=start-1
	while i <= stop do
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
	return t
end

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

local function CompressDynamicBlock(level, WriteBits, strTable, hashTables, blockStart, blockEnd, isLastBlock, str)
	if not level then
		level = 3
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
			local code = _lengthToLiteralCode[prevLen]
			local lenExtraBitsLength = _lengthToExtraBitsLen[prevLen]
			local distCode, distExtraBitsLength, distExtraBits
			if prevDist <= 256 then
				distCode = _distanceToCode[prevDist]
				distExtraBits = _distanceToExtraBits[prevDist]
				distExtraBitsLength =  _distanceToExtraBitsLen[prevDist]
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
				local lenExtraBits = _lengthToExtraBits[prevLen]
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

	-- Allow these to be garbaged collected earlier
	hashTables = nil -- luacheck: ignore 311
	strTable = nil -- luacheck: ignore 311

	lCodeTblSize = lCodeTblSize + 1
	lCodes[lCodeTblSize] = 256
	lCodesCount[256] = (lCodesCount[256] or 0) + 1
	local lCodeLens, lCodeCodes, maxNonZeroLenlCode = GetHuffmanBitLengthAndCode(lCodesCount, 15, 285)
	local dCodeLens, dCodeCodes, maxNonZeroLendCode = GetHuffmanBitLengthAndCode(dCodesCount, 15, 29)

	local rleCodes, rleExtraBits, rleCodesTblLen, rleCodesCount =
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
	for i=1, rleCodesTblLen do
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

	for i=1, lCodeTblSize do
		local code = lCodes[i]
		local huffmanCode = lCodeCodes[code]
		local huffmanLength = lCodeLens[code]
		WriteBits(huffmanCode, huffmanLength)
		if code > 256 then -- Length code
			lengthCodeCount = lengthCodeCount + 1
			if code > 264 and code < 285 then -- Length code with extra bits
				lengthCodeWithExtraCount = lengthCodeWithExtraCount + 1
				local extraBits = lExtraBits[lengthCodeWithExtraCount]
				local extraBitsLength = _literalCodeToExtraBitsLen[code-264]
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

function LibDeflate:Compress(str, level)
	local strLen = str:len()
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

	while not isLastBlock do
		if not blockStart then
			blockStart = 1
			blockEnd = INITIAL_BLOCK_SIZE
		else
			blockStart = blockEnd + 1
			blockEnd = blockEnd + ADDITIONAL_BLOCK_SIZE
		end

		if blockEnd >= strLen then
			blockEnd = strLen
			isLastBlock = true
		else
			isLastBlock = false
		end

		loadStrToTable(str, strTable, blockStart, blockEnd+3) -- +3 is needed

		CompressDynamicBlock(level, WriteBits, strTable, hashTables, blockStart, blockEnd, isLastBlock, str)

		result = Flush(isLastBlock)

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

	return result
end

------------------------------------------------------------------------------
------------------------------------------------------------------------------
local function CreateReader(inputString)
	assert(type(inputString)=="string")
	local input = inputString
	local inputSize = inputString:len()
	local inputNextBytePos = 1
	local cacheBitRemaining = 0
	local cache = 0

	local function SkipToNextByteBoundary()
		local prevBits = cacheBitRemaining
		cacheBitRemaining = (cacheBitRemaining - cacheBitRemaining%8)
		local rShiftMask = _pow2[prevBits-cacheBitRemaining]
		cache = (cache-cache%rShiftMask)/rShiftMask
	end

	local function ReadBits(length)
		assert(length >= 1 and length <= 16)
		local rShiftMask = _pow2[length]
		local code
		if length <= cacheBitRemaining then
			code = cache % rShiftMask
			cache = (cache - code) / rShiftMask
			cacheBitRemaining = cacheBitRemaining - length
		elseif (inputSize-inputNextBytePos+1)*8+cacheBitRemaining < length then
			error(("Out of input. Required: %d bytes. Have: %d bytes.")
				:format(length, (inputSize-inputNextBytePos+1)*8+cacheBitRemaining))
		else
			local lShiftMask = _pow2[cacheBitRemaining]
			local byte1, byte2, byte3, byte4 = string_byte(input, inputNextBytePos, inputNextBytePos+3)
			assert (byte1 ~=  nil)
			-- This requires lua number to be at least double ()
			cache = cache + (byte1+(byte2 or 0)*256+(byte3 or 0)*65536+(byte4 or 0)*16777216)*lShiftMask
			inputNextBytePos = inputNextBytePos + 4
			cacheBitRemaining = cacheBitRemaining + 32 - length
			if inputNextBytePos > inputSize then
				cacheBitRemaining = cacheBitRemaining - (inputNextBytePos-inputSize-1)*8
				inputNextBytePos = inputSize + 1
				input = nil -- Help garbage collector
			end
			code = cache % rShiftMask
			cache = (cache - code) / rShiftMask
			return code
		end

		return code
	end

	return ReadBits, SkipToNextByteBoundary
end

local function Decode(huffmanLenCount, huffmanSymbol, maxBitLength, ReadBits)
	assert(huffmanLenCount ~= nil)
	assert(huffmanSymbol ~= nil)
	assert(maxBitLength > 0)
	assert(ReadBits ~= nil)
	local code = 0 -- Len bits being decoded
	local first = 0 -- First code of length len
	local count -- Number of codes of length len
	local index = 0-- Index of first code of length len in symbol

	for len = 1, maxBitLength do
		code = code + ((ReadBits(1)==1) and (1 - code % 2) or 0) -- (code |= RadBits(1)) Get next bit
		count = huffmanLenCount[len] or 0
		if code - count < first then
			assert(huffmanSymbol[index+code-first] ~= nil
				, "decoded a code not in the huffman table.")
			return huffmanSymbol[index + (code - first)]
		end
		index = index + count
		first = first + count
		first = first * 2
		code = code * 2
	end
	return -10 -- Ran out of codes
end

local function ConstructInflateHuffman(huffmanLen, n, maxBitLength)
	local huffmanLenCount = {}
	for symbol = 0, n-1 do
		local len = huffmanLen[symbol] or 0
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
	return left, huffmanLenCount, huffmanSymbol
end

local function Codes(litHuffmanLen, litHuffmanSym, distHuffmanLen, distHuffmanSym, aheadBufferPointer, bufferPointer
	, ReadBits)
	local output = ""
	local aheadBuffer = aheadBufferPointer[1]
	local aheadSize = #aheadBuffer
	aheadBufferPointer[1] = nil
	local buffer = bufferPointer[1]
	local bufferSize = #buffer
	bufferPointer[1] = nil
	repeat
		local symbol = Decode(litHuffmanLen, litHuffmanSym, 15, ReadBits)
		if symbol < 0 then
			error("Negative code "..symbol)
			return symbol -- Invalid symbol
		elseif symbol >= 286 then
			error("Code too big "..symbol)
			return -10 -- Invalid fixed code
		elseif symbol < 256 then -- Literal
			bufferSize = bufferSize + 1
			buffer[bufferSize] = _byteToChar[symbol]
		elseif symbol > 256 then -- Length code
			symbol = symbol -- TODO
			local length = _lengthCodeToBaseLen[symbol-256]
			if symbol >= 265 and symbol < 285 then
				local extraBitsLen = _literalCodeToExtraBitsLen[symbol-264]
				length = length + ReadBits(extraBitsLen)
			end

			symbol = Decode(distHuffmanLen, distHuffmanSym, 15, ReadBits)
			if symbol < 0 then
				error ("Invalid dist code: "..symbol)
			end
			local dist = _distanceCodeToBaseDist[symbol]
			local distExtraBits = _distanceCodeToExtraBitsLen[symbol]
			if distExtraBits > 0 then
				dist = dist + ReadBits(distExtraBits)
			end

			for index=1, length do
				local charDist = dist-index+1
				local char
				if charDist > bufferSize + aheadSize then
					return -11 -- Distance too far back
				elseif charDist <= bufferSize then
					char = buffer[bufferSize-charDist+1]
				else
					char = aheadBuffer[aheadSize-(charDist-bufferSize)+1]
				end
				buffer[bufferSize+index] = char
			end
			bufferSize = bufferSize + length
		end

		if bufferSize >= 32768 then
			output = output..table_concat(aheadBuffer)
			aheadBuffer = buffer
			aheadSize = bufferSize
			buffer = {}
			bufferSize = 0
		end
	until symbol == 256

	return output, aheadBuffer, buffer
end

local function DecompressDynamicBlock(aheadBufferPointer, bufferPointer, ReadBits)
	local nLen = ReadBits(5) + 257
	local nDist = ReadBits(5) + 1
	local nCode = ReadBits(4) + 4
	if nLen > 286 or nDist > 30 then
		return -3 -- Bad count
	end

	local lengthLengths = {}

	for index=1, nCode do
		lengthLengths[_codeLengthHuffmanCodeOrder[index]] = ReadBits(3)
	end

	local err, lenLenHuffmanLenCount, lenLenHuffmanSym = ConstructInflateHuffman(lengthLengths, 19, 7)
	if err ~= 0 then -- Require complete code set here
		return -4
	end

	local litHuffmanLen = {}
	local distHuffmanLen = {}
	-- Read length/literal and distance code length tables
	local index = 0
	while index < nLen + nDist do
		local symbol -- Decoded value
		local len -- Last length to repeat

		symbol = Decode(lenLenHuffmanLenCount, lenLenHuffmanSym, 7, ReadBits)

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
					return -5 -- No last length
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
				return -6 -- Too many lengths!
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
		return -9 -- No end of block
	end

	local litErr, litHuffmanLenCount, litHuffmanSym = ConstructInflateHuffman(litHuffmanLen, nLen, 15)
	if (litErr ~=0 and (litErr < 0 or nLen ~= (litHuffmanLenCount[0] or 0)+(litHuffmanLenCount[1] or 0))) then
		return -7 -- Incomplete code ok only for single length 1 code
	end

	local distErr, distHuffmanLenCount, distHuffmanSym = ConstructInflateHuffman(distHuffmanLen, nDist, 15)
	if (distErr ~=0 and (distErr < 0 or nDist ~= (distHuffmanLenCount[0] or 0)+(distHuffmanLenCount[1] or 0))) then
		return -8 -- Incomplete code ok only for single length 1 code
	end

	-- Build buffman table for literal/length codes
	return Codes(litHuffmanLenCount, litHuffmanSym, distHuffmanLenCount, distHuffmanSym, aheadBufferPointer, bufferPointer
		, ReadBits)
end

function LibDeflate:Decompress(str) -- TODO: Unfinished
	-- WIP
	assert(type(str) == "string")
	local ReadBits = CreateReader(str)

	local isLastBlock
	local aheadBufferPointer = {{}}
	local bufferPointer = {{}}
	local result = ""

	while not isLastBlock do
		local blockResult
		isLastBlock = (ReadBits(1) == 1)
		local blockType = ReadBits(2) -- TODO
		blockResult, aheadBufferPointer[1], bufferPointer[1] = DecompressDynamicBlock(aheadBufferPointer, bufferPointer
		, ReadBits)
		result=result..blockResult
	end
	result=result..table_concat(aheadBufferPointer[1])..table_concat(bufferPointer[1])
	return result
end

return LibDeflate
