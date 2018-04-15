-- Author: Haoqian He (Github: SafeteeWoW)
-- License: GPLv3

require "bit"
--require "profiler"

local lib = {}

-- local is faster than global
local error = error
local assert = assert
local table_concat = table.concat
local table_sort = table.sort
local string_char = string.char
local string_byte = string.byte
local string_len = string.len
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local math_floor = math.floor
local bit_band = bit.band
local bit_bor = bit.bor
local bit_bxor = bit.bxor
local bit_bnot = bit.bnot
local bit_lshift = bit.lshift
local bit_rshift = bit.rshift

if not wipe then
	wipe = function(t)
		for k in pairs(t) do
			t[k] = nil
		end
	end
end

local SLIDING_WINDOW = 32768
local MIN_MATCH_LEN = 3
local MAX_MATCH_LEN = 258
local MAX_SYMBOL = 285
local MAX_CODE_LENGTH = 15
local BLOCK_SIZE = 32768

local function print() end

local function PrintTable(t)
	local tmp = {}
	for k,v in ipairs(t) do
		table.insert(tmp, v)
	end
	print(table_concat(tmp, " "))
end

--local _literalLengthCodeToBaseLength = {}
local _literalLengthCodeToExtraBitsLength = {}

local _lengthToLiteralLengthCode = {}
local _lengthToExtraBits = {}
local _lengthToExtraBitsLength = {}

local _distanceCodeToExtraBitsLength = {}

local _distanceToCode = {}
local _distanceToExtraBits = {}
local _distanceToExtraBitsLength = {}

for code=0, 285 do
	if code <= 255 then
		--_literalLengthCodeToBaseLength[code] = 1
		_literalLengthCodeToExtraBitsLength[code] = 0
	elseif code == 256 then
		--_literalLengthCodeToBaseLength[code] = 1
		_literalLengthCodeToExtraBitsLength[code] = 0
	elseif code <= 264 then
		--_literalLengthCodeToBaseLength[code] = code - 254
		_literalLengthCodeToExtraBitsLength[code] = 0
	elseif code <= 268 then
		--_literalLengthCodeToBaseLength[code] = (code-265)*2+11
		_literalLengthCodeToExtraBitsLength[code] = 1
	elseif code <= 272 then
		--_literalLengthCodeToBaseLength[code] = (code-269)*4+19
		_literalLengthCodeToExtraBitsLength[code] = 2
	elseif code <= 276 then
		--_literalLengthCodeToBaseLength[code] = (code-273)*8+35
		_literalLengthCodeToExtraBitsLength[code] = 3
	elseif code <= 280 then
		--_literalLengthCodeToBaseLength[code] = (code-277)*16+67
		_literalLengthCodeToExtraBitsLength[code] = 4
	elseif code <= 284 then
		--_literalLengthCodeToBaseLength[code] = (code-281)*32+131
		_literalLengthCodeToExtraBitsLength[code] = 5
	elseif code == 285 then
		--_literalLengthCodeToBaseLength[code] = 258
		_literalLengthCodeToExtraBitsLength[code] = 0
	end
end

for length=3, 258 do
	if length <= 10 then
		_lengthToLiteralLengthCode[length] = length + 254
		_lengthToExtraBitsLength[length] = 0
	elseif length <= 18 then
		_lengthToLiteralLengthCode[length] = math_floor((length-11)/2) + 265
		_lengthToExtraBitsLength[length] = 1
		_lengthToExtraBits[length] = (length-11) % 2
	elseif length <= 34 then
		_lengthToLiteralLengthCode[length] = math_floor((length-19)/4) + 269
		_lengthToExtraBitsLength[length] = 2
		_lengthToExtraBits[length] = (length-19) % 4
	elseif length <= 66 then
		_lengthToLiteralLengthCode[length] = math_floor((length-35)/8) + 273
		_lengthToExtraBitsLength[length] = 3
		_lengthToExtraBits[length] = (length-35) % 8
	elseif length <= 130 then
		_lengthToLiteralLengthCode[length] = math_floor((length-67)/16) + 277
		_lengthToExtraBitsLength[length] = 4
		_lengthToExtraBits[length] = (length-67) % 16
	elseif length <= 257 then
		_lengthToLiteralLengthCode[length] = math_floor((length-131)/32) + 281
		_lengthToExtraBitsLength[length] = 5
		_lengthToExtraBits[length] = (length-131) % 32
	elseif length == 258 then
		_lengthToLiteralLengthCode[length] = 285
		_lengthToExtraBitsLength[length] = 0
	end
end

for dist=1, 32768 do
	if dist <= 4 then
		_distanceToCode[dist] = dist - 1
		_distanceToExtraBitsLength[dist] = 0
	elseif dist <= 8 then
		_distanceToCode[dist] = math_floor((dist - 5)/2) + 4
		_distanceToExtraBitsLength[dist] = 1
		_distanceToExtraBits[dist] = (dist-5) % 2
	elseif dist <= 16 then
		_distanceToCode[dist] = math_floor((dist - 9)/4) + 6
		_distanceToExtraBitsLength[dist] = 2
		_distanceToExtraBits[dist] = (dist-9) % 4
	elseif dist <= 32 then
		_distanceToCode[dist] = math_floor((dist - 17)/8) + 8
		_distanceToExtraBitsLength[dist] = 3
		_distanceToExtraBits[dist] = (dist-17) % 8
	elseif dist <= 64 then
		_distanceToCode[dist] = math_floor((dist - 33)/16) + 10
		_distanceToExtraBitsLength[dist] = 4
		_distanceToExtraBits[dist] = (dist-33) % 16
	elseif dist <= 128 then
		_distanceToCode[dist] = math_floor((dist - 65)/32) + 12
		_distanceToExtraBitsLength[dist] = 5
		_distanceToExtraBits[dist] = (dist-65) % 32
	elseif dist <= 256 then
		_distanceToCode[dist] = math_floor((dist - 129)/64) + 14
		_distanceToExtraBitsLength[dist] = 6
		_distanceToExtraBits[dist] = (dist-129) % 64
	elseif dist <= 512 then
		_distanceToCode[dist] = math_floor((dist - 257)/128) + 16
		_distanceToExtraBitsLength[dist] = 7
		_distanceToExtraBits[dist] = (dist-257) % 128
	elseif dist <= 1024 then
		_distanceToCode[dist] = math_floor((dist - 513)/256) + 18
		_distanceToExtraBitsLength[dist] = 8
		_distanceToExtraBits[dist] = (dist-513) % 256
	elseif dist <= 2048 then
		_distanceToCode[dist] = math_floor((dist - 1025)/512) + 20
		_distanceToExtraBitsLength[dist] = 9
		_distanceToExtraBits[dist] = (dist-1025) % 512
	elseif dist <= 4096 then
		_distanceToCode[dist] = math_floor((dist - 2049)/1024) + 22
		_distanceToExtraBitsLength[dist] = 10
		_distanceToExtraBits[dist] = (dist-2049) % 1024
	elseif dist <= 8192 then
		_distanceToCode[dist] = math_floor((dist - 4097)/2048) + 24
		_distanceToExtraBitsLength[dist] = 11
		_distanceToExtraBits[dist] = (dist-4097) % 2048
	elseif dist <= 16384 then
		_distanceToCode[dist] = math_floor((dist - 8193)/4096) + 26
		_distanceToExtraBitsLength[dist] = 12
		_distanceToExtraBits[dist] = (dist-8193) % 4096
	elseif dist <= 32768 then
		_distanceToCode[dist] = math_floor((dist - 16385)/8192) + 28
		_distanceToExtraBitsLength[dist] = 13
		_distanceToExtraBits[dist] = (dist-16385) % 8192
	end
end

local _writeCompressedSize = nil
local _writeRemainder = nil
local _writeRemainderLength = nil
local _writeBuffer = nil
local function WriteBitsInit(buffer)
	wipe(buffer)
	_writeCompressedSize = 0
	_writeRemainder = 0
	_writeRemainderLength = 0
	_writeBuffer = buffer
end

local _byteToChar = {}
for i=0, 255 do
	_byteToChar[i] = string_char(i)
end

local _twoBytesToChar = {}
for i=0,256*256-1 do
	_twoBytesToChar[i] = string_char(i%256)..string_char((i-i%256)/256)
end

local function WriteBits(code, length)
	_writeRemainder = _writeRemainder + bit_lshift(code, _writeRemainderLength) -- Overflow?
	_writeRemainderLength = length + _writeRemainderLength
	if _writeRemainderLength >= 32 then
		-- we have at least 4 bytes to store; bulk it
		_writeBuffer[_writeCompressedSize+1] = _twoBytesToChar[_writeRemainder % 65536]
		_writeBuffer[_writeCompressedSize+2] = _twoBytesToChar[((_writeRemainder-_writeRemainder%65536)/65536 % 65536)]
		_writeCompressedSize = _writeCompressedSize + 2
		_writeRemainder = bit_rshift(code, 32 - _writeRemainderLength + length)
		_writeRemainderLength = _writeRemainderLength - 32
	end
end

local function WriteRemainingBits()
	if _writeRemainderLength > 0 then
		for i=1, _writeRemainderLength, 8 do
			_writeCompressedSize = _writeCompressedSize + 1
			_writeBuffer[_writeCompressedSize] = string_char(bit_band(_writeRemainder, 255))
			_writeRemainder = bit_rshift(_writeRemainder, 8)
		end
		_writeRemainder = 0
		_writeRemainderLength = 0
	end
end

local _readBytePos = nil
local _readBitPos = nil
local _readByte = nil
local _readString = nil

local function ReadBitsInit(dataString)
	_readBytePos = 1
	_readBitPos = 0
	_readByte = string_byte(dataString, 1, 1)
	_readString = dataString
end

local function ReadBitsGoToNextByte()
	if (_readBitPos > 0) then
		_readBytePos = _readBytePos + 1
		_readBitPos = 0
	end
end

local function ReadBits(length)
	assert(length >= 1 and length <= 16)
	local code
	if (_readBitPos + length <= 8) then
		local code = bit_band(bit_rshift(_readByte, _readBitPos), (bit_lshift(1, length)-1))
		if _readBitPos + length < 8 then
			_readBitPos = _readBitPos + length
		else
			_readBitPos = 0
			_readBytePos = _readBytePos + 1
			_readByte = string_byte(_readString, _readBytePos, _readBytePos)
		end
	elseif (_readBitPos + length <= 16) then
		local byte1 = string_byte(_readString, _readBytePos + 1, _readBytePos + 1)
		local byte = bit_lshift(byte1, 8) + _readByte
		code = bit_band(bit_rshift(byte, _readBitPos), (bit_lshift(1, length)-1))
		if _readBitPos + length < 16 then
			_readBitPos = _readBitPos + length - 8
			_readBytePos = _readBytePos + 1
			_readByte = byte1
		else
			_readBitPos = 0
			_readBytePos = _readBytePos + 2
			_readByte = string_byte(_readString, _readBytePos, _readBytePos)
		end
	else
		local byte1, byte2 = string_byte(_readString, _readBytePos+1, _readBytePos + 2)
		local byte = bit_lshift(byte2, 16) + bit_lshift(byte1, 8) + _readByte
		code = bit_band(bit_rshift(byte, _readBitPos), (bit_lshift(1, length)-1))
		_readBitPos = _readBitPos + length - 16
		_readBytePos = _readBytePos + 2
		_readByte = byte2
	end
	return code
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
		(a[1] == b[1] and a[2] < b[2]) -- This is important so our result is stable regardless of interpreter implementation.
end

--@treturn {table, table} symbol length table and symbol code table
local function GetHuffmanBitLengthAndCode(symCount, maxBitLength, maxSymbol)
	local heapSize = 0
	local leafs = {}
	local heap = {}
	local symbolBitLength = {}
	local symbolCode = {}
	local bitLengthCount = {}

	local maxNonZeroLenSym = -1

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
				bitLengthCount[bitLength+1] = (bitLengthCount[bitLength+1] or 0) + 2 -- move one overflow item as its brother
				bitLengthCount[maxBitLength] = bitLengthCount[maxBitLength] - 1
				overflow = overflow - 2
			until (overflow <= 0)

			-- Update symbolBitLength
			local index = 1
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
				local code = nextCode[len]
				nextCode[len] = code + 1
				
				-- Reverse the bits of "code"
				local res = 0
				for i=1, len do
					res = bit_bor(res, code % 2)
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
		local len = (code <= maxNonZeroLenlCode) and (lcodeLens[code] or 0) or ((code <= maxCode) and (dcodeLens[code-maxNonZeroLenlCode-1] or 0) or nil)
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

local _strTable = {}
local _strLen = 0

local _niceLength; -- quit search above this match length
local _max_chain;

local function FindPairs(hashTables, hash, index)
	local dist = 0
	local len = 0
	local hashHead = hashTables[hash]
	
	local prevHead = nil
	local head = hashHead
	local chain = 1

	while (head and chain <= _max_chain) do
		local prev = head[1]
		if chain == _max_chain then
			head[2] = nil
		end
		if index - prev > SLIDING_WINDOW then
			head[2] = nil
			if not prevHead then 
				hashTables[hash] = nil
			else 
				prevHead[2] = nil
			end
			break
		end
		head = head[2]
		chain = chain + 1
		if prev and prev < index then
			local j = 0
			repeat
				if (_strTable[prev+j] == _strTable[index+j]) then
					j = j + 1
				else
					break
				end
			until (j >= 258 or index+j > _strLen)
			if j > len then
				len = j
				dist = index - prev
			end
			if len >= _niceLength then
				break
			end
		end	
	end

	return len, dist
end


local function strToTable(str, t)
	wipe(t)
	for i=0, str:len()-16, 16 do
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
	end
	for i=math.floor(str:len()/16)*16+1, str:len() do
		t[i]=string_byte(str, i)
	end
	return t
end

--[[
while (i <= strLen) do
	local len, dist
	if (i+2 <= strLen) then
		len, dist, hash = FastFindPairs(hashTables, hash, i)
	end
	if len and (len == 3 and dist < 4096 or len > 3) then
		local code = _lengthToLiteralLengthCode[len]
		local distCode = _distanceToCode[dist]
		if not distCode then print("nil distcode", dist) end

		local lenExtraBitsLength = _lengthToExtraBitsLength[len]
		local distExtraBitsLength = _distanceToExtraBitsLength[dist]

		lCodeTblSize = lCodeTblSize + 1
		lCodes[lCodeTblSize] = code
		lCodesCount[code] = (lCodesCount[code] or 0) + 1
		
		dCodeTblSize = dCodeTblSize + 1
		dCodes[dCodeTblSize] = distCode
		dCodesCount[distCode] = (dCodesCount[distCode] or 0) + 1
		if lenExtraBitsLength > 0 then
			local lenExtraBits = _lengthToExtraBits[len]
			lExtraBitTblSize = lExtraBitTblSize + 1
			lExtraBits[lExtraBitTblSize] = lenExtraBits
		end
		if distExtraBitsLength > 0 then
			local distExtraBits = _distanceToExtraBits[dist]
			dExtraBitTblSize = dExtraBitTblSize + 1
			dExtraBits[dExtraBitTblSize] = distExtraBits
		end
		i = i + len
	else
		local code = _strTable[i]
		lCodeTblSize = lCodeTblSize + 1
		lCodes[lCodeTblSize] = code
		lCodesCount[code] = (lCodesCount[code] or 0) + 1
		i = i + 1
	end
end

--]]

_niceLength = 32
_max_chain = 32
local _max_lazy_match = 32

function lib:Compress(str)
	--collectgarbage("stop")
	local time1 = os.clock()
	strToTable(str, _strTable) -- TODO: Fix memory usage when file is very large.
	_strLen = str:len()
	print("time_read_string", os.clock()-time1)
	local time2 = os.clock()
	--for i=1, str:len() do
	--  assert(strTable[i] == string_byte(str, i, i), "error") end
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
	

	local index = 1
	local strLen = str:len()
	local hashTables = {}
	
	local hash = 0
	hash = bit_band(bit_bxor(bit_lshift(hash, 5), _strTable[1] or 0), 32767)
	hash = bit_band(bit_bxor(bit_lshift(hash, 5), _strTable[2] or 0), 32767)
	

	local matchAvailable = false
	local prevLen = 0
	local prevDist = 0
	local curLen = 0
	local curDist = 0
	local hashIndex = 0
	
	local useLazyEvaluation = false
	local indexEnd = strLen + (useLazyEvaluation and 1 or 0)
	while (index <= indexEnd) do
		prevLen = curLen
		prevDist = curDist
		curLen = 0
		hash = bit_bxor(hash*32, _strTable[index+2] or 0) % 32768
		if (index+2 <= strLen and (not useLazyEvaluation or prevLen < _max_lazy_match)) then
			curLen, curDist = FindPairs(hashTables, hash, index) -- TODO: Put update hash out of FastFindPairs
		end
		hashIndex = index
		hashTables[hash] = {index, hashTables[hash]}
		if not useLazyEvaluation then
			prevLen, prevDist = curLen, curDist
		end
		if ((not useLazyEvaluation or matchAvailable) and (prevLen > 3 or (prevLen == 3 and prevDist < 4096)) and curLen <= prevLen )then
			local code = _lengthToLiteralLengthCode[prevLen]
			local distCode = _distanceToCode[prevDist]

			local lenExtraBitsLength = _lengthToExtraBitsLength[prevLen]
			local distExtraBitsLength = _distanceToExtraBitsLength[prevDist]

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
				local distExtraBits = _distanceToExtraBits[prevDist]
				dExtraBitTblSize = dExtraBitTblSize + 1
				dExtraBits[dExtraBitTblSize] = distExtraBits
			end
			
			for i=index+1, index+prevLen-(useLazyEvaluation and 2 or 1) do
				hash = bit_bxor(hash*32, _strTable[i+2] or 0) % 32768
				hashTables[hash] = {i, hashTables[hash]}
				hashIndex = i
			end
			index = index + prevLen - (useLazyEvaluation and 1 or 0)
			matchAvailable = false
		elseif (not useLazyEvaluation) or matchAvailable then
			local code = _strTable[useLazyEvaluation and (index-1) or index]
			lCodeTblSize = lCodeTblSize + 1
			lCodes[lCodeTblSize] = code
			lCodesCount[code] = (lCodesCount[code] or 0) + 1
			index = index + 1
		else
			matchAvailable = true
			index = index + 1
		end
	end
	

	print("time_find_pairs", os.clock()-time2)
	local time3 = os.clock()
	
	lCodeTblSize = lCodeTblSize + 1
	lCodes[lCodeTblSize] = 256
	lCodesCount[256] = (lCodesCount[256] or 0) + 1
	local lCodeLens, lCodeCodes, maxNonZeroLenlCode = GetHuffmanBitLengthAndCode(lCodesCount, 15, 285)
	local dCodeLens, dCodeCodes, maxNonZeroLendCode = GetHuffmanBitLengthAndCode(dCodesCount, 15, 29)

	print("time_contruct_table1", os.clock()-time3)
	--print("maxNonZeroLenlCode", maxNonZeroLenlCode, "maxNonZeroLendCode", maxNonZeroLendCode)
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
	print("time_contruct_table2", os.clock()-time3)
	local time4 = os.clock()
	local outputBuffer = {}
	WriteBitsInit(outputBuffer)
	WriteBits(1, 1) -- Last block marker
	WriteBits(2, 2) -- Dynamic Huffman Code

	WriteBits(HLIT, 5)
	WriteBits(HDIST, 5)
	WriteBits(HCLEN, 4)

	for i = 1, HCLEN+4 do
		local symbol = _codeLengthHuffmanCodeOrder[i]
		local length = codeLensCodeLens[symbol] or 0
		--print(symbol, length)
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

	for _, code in ipairs(lCodes) do
		local huffmanCode = lCodeCodes[code]
		local huffmanLength = lCodeLens[code]
		WriteBits(huffmanCode, huffmanLength)
		--print(code, huffmanCode, huffmanLength)
		if code > 256 then -- Length code
			lengthCodeCount = lengthCodeCount + 1
			if code > 264 and code < 285 then -- Length code with extra bits
				lengthCodeWithExtraCount = lengthCodeWithExtraCount + 1
				local extraBits = lExtraBits[lengthCodeWithExtraCount]
				local extraBitsLength = _literalLengthCodeToExtraBitsLength[code]
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
				local distExtraBitsLength = bit_rshift(distCode, 1) - 1
				WriteBits(distExtraBits, distExtraBitsLength)
			end
		end
	end

	WriteRemainingBits()
	print("time_write_bits", os.clock()-time4)
	local time5 = os.clock()
	local result = table_concat(outputBuffer)
	print("time_table_concat", os.clock()-time5)
	--collectgarbage("restart")
	--local time4 = os.clock()
	return result
end

return lib
