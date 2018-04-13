-- Author: Haoqian He (Github: SafeteeWow)
-- License: GPLv3

require "bit"
require "profiler"

local lib = {}

-- local is faster than global
local CreateFrame = CreateFrame
local type = type
local tostring = tostring
local select = select
local next = next
local loadstring = loadstring
local error = error
local setmetatable = setmetatable
local rawset = rawset
local assert = assert
local table_insert = table.insert
local table_remove = table.remove
local table_concat = table.concat
local table_sort = table.sort
local string_char = string.char
local string_byte = string.byte
local string_len = string.len
local string_sub = string.sub
local unpack = unpack
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local math_modf = math.modf
local math_floor = math.floor
local bit_band = bit.band
local bit_bor = bit.bor
local bit_bxor = bit.bxor
local bit_bnot = bit.bnot
local bit_lshift = bit.lshift
local bit_rshift = bit.rshift

local SLIDING_WINDOW = 32768
local MIN_MATCH_LEN = 3
local MAX_MATCH_LEN = 258
local MAX_SYMBOL = 285
local MAX_CODE_LENGTH = 15
local BLOCK_SIZE = 32768
local str = "As mentioned above,there are many kinds of wireless systems other than cellular."
local END_MARKER = function () end


local function wipe(t)
  for k in pairs(t) do
    t[k] = nil
  end
  for k in pairs(t) do
    t[k] = nil
  end
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

local power2 = {}
for i=0, 31 do
  power2[i] = bit_lshift(1, i)
end

local function log2Floor(n)
  for i=0, 31 do
    if power2[i] >= n then
      return i
    end
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

-- From LibCompress
-- Authors: jjsheets and Galmok of European Stormrage (Horde)
-- Email : sheets.jeff@gmail.com and galmok@gmail.com
-- Licence: GPL version 2 (General Public License)
local _writeCompressedSize = nil
local _writeRemainder = nil
local _writeRemainderLength = nil
local _writeBuffer = nil
local _writeDebugIndex = 0
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
local function WriteBits(code, length) -- TODO: Write to buffer every 32 bits.
  --assert(code, "WriteBits: nil code")
  --assert(length, "WriteBits: nil length")
  --assert(length>=1 and length <= 16, "WriteBits: Invalid length "..length)
  --_writeDebugIndex = _writeDebugIndex + 1
  _writeRemainder = _writeRemainder + bit_lshift(code, _writeRemainderLength) -- Overflow?
  _writeRemainderLength = length + _writeRemainderLength
  if _writeRemainderLength >= 32 then
    -- we have at least 4 bytes to store; bulk it
    _writeBuffer[_writeCompressedSize+1] = _byteToChar[_writeRemainder % 256]
    _writeBuffer[_writeCompressedSize+2] = _byteToChar[((_writeRemainder-_writeRemainder%256)/256 % 256)]
    _writeBuffer[_writeCompressedSize+3] = _byteToChar[((_writeRemainder-_writeRemainder%65536)/65536 % 256)]
    _writeBuffer[_writeCompressedSize+4] = _byteToChar[((_writeRemainder-_writeRemainder%16777216)/16777216 % 256)]
    _writeCompressedSize = _writeCompressedSize + 4
    _writeRemainder = bit_rshift(code, 32 - _writeRemainderLength + length)
    _writeRemainderLength = _writeRemainderLength - 32
  else

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

local function FindPairs(str, pos) -- TODO: Fix algorithm
  local len = MIN_MATCH_LEN - 1
  local dist = 0

  local startPos = pos - SLIDING_WINDOW
  if startPos < 1 then
    startPos = 1
  end

  local strLen = str:len()
  for i = startPos, pos-1 do
    for j = MAX_MATCH_LEN, len+1, -1 do
      if pos + j -1 <= strLen then
        if str:sub(i, i+j-1) == str:sub(pos, pos+j-1) then
          if j > len then
            len = j
            dist = pos - i
          end
        end
      end
    end
  end

  if len >= MIN_MATCH_LEN then
    return len, dist
  end
end

--- Push an element into a max heap
-- Assume element is a table and we compare it using its first value table[1]
local function MinHeapPush(heap, e, heapSize)
  heapSize = heapSize + 1
  heap[heapSize] = e
  local pos = heapSize
  local parentPos = math_floor(pos/2)

  while (parentPos >= 1 and heap[parentPos][1] > e[1]) do
    local t = heap[parentPos]
    heap[parentPos] = e
    heap[pos] = t
    pos = parentPos
    parentPos = math_floor(parentPos/2)
  end
end

--- Pop an element from a max heap
-- Assume element is a table and we compare it using its first value table[1]
-- Note: This function does not change table size
local function MinHeapPop(heap, heapSize)
  local top = heap[1]
  local e = heap[heapSize]
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
      if rightChild[1] < e[1] then
        heap[rightChildPos] = e
        heap[pos] = rightChild
        pos = rightChildPos
        leftChildPos = pos*2
        rightChildPos = leftChildPos + 1
      else
        break
      end
    else
      if leftChild[1] < e[1] then
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

--[[

tree[1]: weight

tree[2]: left child

tree[3]: right child

tree[4]: parent

tree[5]: code length

tree[6]: huffman code

--]]

local function SortByFirstThenSecond(a, b)
  return a[1] < b[1] or
    (a[1] == b[1] and a[2] < b[2]) -- This is important so our result is stable regardless of interpreter implementation.
end

local function bitReverse(code, len)
  local res = 0
  repeat
    res = bit_bor(res, code % 2)
    code = bit_rshift(code, 1)
    res = bit_lshift(res, 1)
    len = len - 1
  until (len <= 0)
  return bit_rshift(res, 1)
end

--@treturn {table, table} symbol length table and symbol code table
local function GetHuffmanBitLengthAndCode(dataTable, maxBitLength, maxSymbol)
  if not dataTable[1] then
    return {}, {}
  end
  local symbolCount = {}
  local heapSize = 0
  local totalNodeCount = 0

  for _, symbol in ipairs(dataTable) do
    symbolCount[symbol] = (symbolCount[symbol] or 0) + 1
  end

  -- Create Heap for constructing Huffman tree
  local leafs = {}
  local heap = {}
  local symbolBitLength = {}
  local symbolCode = {}

  local bitLengthCount = {}

  local uniqueSymbols = 0
  for symbol, count in pairs(symbolCount) do
    uniqueSymbols = uniqueSymbols + 1
    leafs[uniqueSymbols] = {count, symbol, 0, 0, 0, 0} 
  end

  if (uniqueSymbols == 0) then
    return {}, {}  -- TODO: Shouldn't happen
  elseif (uniqueSymbols == 1) then -- Special case
    symbolBitLength[leafs[1][2]] = 1
    symbolCode[leafs[1][2]] = 1
    return symbolBitLength, symbolCode
  else
    table_sort(leafs, SortByFirstThenSecond)
    heapSize = #leafs
    totalNodeCount = heapSize
    for i=1, heapSize do
      heap[i] = leafs[i]
    end

    while (heapSize > 1) do
      local leftChild = MinHeapPop(heap, heapSize) -- Note: pop does not change table size
      heapSize = heapSize - 1
      local rightChild = MinHeapPop(heap, heapSize) -- Note: pop does not change table size
      heapSize = heapSize - 1
      local newNode = {leftChild[1]+rightChild[1], leftChild, rightChild} -- TODO: Remove one pop for better performance
      leftChild[4] = newNode
      rightChild[4] = newNode
      MinHeapPush(heap, newNode, heapSize)
      heapSize = heapSize + 1
      totalNodeCount = totalNodeCount + 1
    end


    local overflow = 0 -- Number of leafs whose bit length is greater than 15.
    -- Deflate does not allow any bit length greater than 15.

    -- Calculate bit length of all nodes
    local fifo = {heap[1]}
    local pointer = 1
    while (fifo[pointer]) do -- Breath first search
      local e = fifo[pointer]
      if type(e[2]) == "table" then
        table_insert(fifo, e[2])
      end
      if type(e[3]) == "table" then
        table_insert(fifo, e[3])
      end

      local parent = e[4]
      local bitLength = parent and (parent[5] + 1) or 0

      if type(e[2]) ~= "table" then
        symbolBitLength[ e[2] ] = bitLength
        if (bitLength > maxBitLength) then
          overflow = overflow + 1
          bitLength = maxBitLength
        end
        bitLengthCount[bitLength] = (bitLengthCount[bitLength] or 0) + 1
      end
      e[5] = bitLength
      pointer = pointer + 1
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
        bitLengthCount[bitLength+1] = bitLengthCount[bitLength+1] + 2 -- move one overflow item as its brother
        bitLengthCount[maxBitLength] = bitLengthCount[maxBitLength] - 1
        overflow = overflow - 2
      until (overflow <= 0)

      -- Update symbolBitLength
      local leafPointer = 1
      for bitLength = maxBitLength, 1, -1 do
        local n = bitLengthCount[bitLength] or 0
        while (n > 0) do
          local symbol = leafs[leafPointer][2]
          symbolBitLength[symbol] = bitLength
          n = n - 1
          leafPointer = leafPointer + 1
        end
      end
      --print(leafPointer, uniqueSymbols)
    end

    -- From RFC1951. Calculate huffman code from code bit length.
    local code = 0
    local nextCode = {}
    for bitLength = 1, maxBitLength do
      code = (code+(bitLengthCount[bitLength-1] or 0))*2
      nextCode[bitLength] = code
    end
    for symbol = 0, maxSymbol do
      local bitLength = symbolBitLength[symbol]
      if bitLength then
        local nextLen = nextCode[bitLength]
        if not nextLen then error("nil nextLen "..bitLength.." "..maxBitLength.." "..overflow) end
        symbolCode[symbol] = bitReverse(nextLen, bitLength)
        nextCode[bitLength] = nextLen + 1
      end
    end
    return symbolBitLength, symbolCode
  end



end

local function RunLengthEncodeSymbolBitLength(symbolBitLength, maxSymbol)
  assert(maxSymbol > 0)
  local runLengthEncodes = {}
  local runLengthExtraBits = {}
  local i = 0
  local prevLength = nil
  local lengthDuplicateCount = 0
  local lastNonZeroSymbol = 0
  for i = 0, maxSymbol+1 do
    local length = symbolBitLength[i] or 0
    if length > maxSymbol then
      length = nil -- nil length indicates trailing process
    end
    if length and length ~= 0 then
      lastNonZeroSymbol = i
    end
    if length == prevLength then
      lengthDuplicateCount = lengthDuplicateCount + 1
      if length ~= 0 and lengthDuplicateCount == 6 then
        table_insert(runLengthEncodes, 16)
        table_insert(runLengthExtraBits, 3)
        lengthDuplicateCount = 0
      elseif length == 0 and lengthDuplicateCount == 138 then
        table_insert(runLengthEncodes, 18)
        table_insert(runLengthExtraBits, 127)
        lengthDuplicateCount = 0
      end
    else
      if prevLength then
        if lengthDuplicateCount < 3 then
          for i=1, lengthDuplicateCount do
            table_insert(runLengthEncodes, prevLength)
          end
        elseif prevLength ~= 0 then
          table_insert(runLengthEncodes, 16)
          table_insert(runLengthExtraBits, lengthDuplicateCount-3)
        elseif length then -- Discard trailing 0s'
          if lengthDuplicateCount <= 10 then
            table_insert(runLengthEncodes, 17)
            table_insert(runLengthExtraBits, lengthDuplicateCount-3)
        else
          table_insert(runLengthEncodes, 18)
          table_insert(runLengthExtraBits, lengthDuplicateCount-11)
        end
        end
      end
      if length and length ~= 0 then
        table_insert(runLengthEncodes, length)
        lengthDuplicateCount = 0
      else
        lengthDuplicateCount = 1
      end
      prevLength = length
    end
  end
  return runLengthEncodes, runLengthExtraBits, lastNonZeroSymbol + 1
end

local _codeLengthHuffmanCodeOrder = {16, 17, 18,
  0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15}
local function WriteCodeLengthHuffmanCode(codeLengthHuffmanCodeLength)

end

-- TODO: The code length repeat codes can cross from HLIT + 257 to the HDIST + 1 code lengths.
-- In other words, all code lengths form a single sequence of HLIT + HDIST + 258 values.
local function WriteEncodedHuffmanLength(encodedHuffmanLength, encodedHuffmanExtraBits, codeLengthHuffmanCodeLength, codeLengthHuffmanCode)
  local extraBitsPointer = 1
  for code=0, 18 do
    local huffmanCode = codeLengthHuffmanCode[code]
    local huffmanLength = codeLengthHuffmanCodeLength[code]
    if huffmanCode then
    --print(code, huffmanCode, huffmanLength)
    end
  end
  for _, code in ipairs(encodedHuffmanLength) do
    --print(code)
    local huffmanCode = codeLengthHuffmanCode[code]
    local huffmanLength = codeLengthHuffmanCodeLength[code]
    WriteBits(huffmanCode, huffmanLength)
    if code >= 16 then
      local extraBits = encodedHuffmanExtraBits[extraBitsPointer]
      if code == 16 then
        WriteBits(extraBits, 2)
      elseif code == 17 then
        WriteBits(extraBits, 3)
      else
        WriteBits(extraBits, 7)
      end
      extraBitsPointer = extraBitsPointer + 1
    end
  end
  --print("---------------------------------")
end
local strTable = {}
local function Update(hashTable, hashTable2, hash, i, strLen, str)
  local dist = 0
  local len = 0
  hash = bit_bxor(hash*32, strTable[i+2]) %32768
  local prev = hashTable[hash]

  local foundMatch = false
  if prev and i-prev <= SLIDING_WINDOW then
    dist = i-prev
    repeat
      if (strTable[prev+len] == strTable[i+len]) then
        len = len + 1
      else
        break
      end
    until (len >= 258 or i+len >= strLen)

    if (len >= 3) then
      for j=i+1, i+len-1 do
        hash = bit_bxor(hash*32, strTable[j+2] or 0) % 32768 -- TODO: Fix or 0
        hashTable2[hash] = hashTable[hash]
        hashTable[hash] = hash
        foundMatch = true
      end
    end

  end

  
  if not foundMatch then
    len = 0
    local prev2 = hashTable2[hash]

    local foundMatch = false
    if prev2 and i-prev2 <= SLIDING_WINDOW then
      dist = i-prev2

      repeat
        if (strTable[prev2+len] == strTable[i+len]) then
          len = len + 1
        else
          break
        end
      until (len >= 258 or i+len >= strLen)

      if (len >= 3) then
        for j=i+1, i+len-1 do
          hash = bit_bxor(hash*32, strTable[j+2] or 0) % 32768 -- TODO: "or 0", wtf?
          hashTable2[hash] = hashTable[hash]
          hashTable[hash] = hash
          foundMatch = true
        end
      end

    end
  end
  hashTable2[hash] = hashTable[hash]
  hashTable[hash] = i

  return len, dist, hash
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

function lib:Compress(str)
  local time1 = os.clock()
  strToTable(str, strTable) -- TODO: Fix memory usage when file is very large.
  print("time_read_string", os.clock()-time1)
  local time2 = os.clock()
  --for i=1, str:len() do
  --  assert(strTable[i] == string_byte(str, i, i), "error") end
  local literalLengthCode = {}
  local distanceCode = {}
  local lengthExtraBits = {}
  local distanceExtraBits = {}

  local i = 1
  local strLen = str:len()
  local hashTable = {}
  local hashTable2 = {}
  --local hashTable2 = {}
  local hash = 0
  if (strLen >= 1) then
    hash = bit_band(bit_bxor(bit_lshift(hash, 5), strTable[1]), 32767)
  end
  if (strLen >= 2) then
    hash = bit_band(bit_bxor(bit_lshift(hash, 5), strTable[2]), 32767)
  end
  while (i <= strLen) do
    --local len, dist = FindPairs(str, i)
    local len, dist
    if (i+2 <= strLen) then
      len, dist, hash = Update(hashTable, hashTable2, hash, i, strLen, str)
    end
    --len, dist = FindPairs(str, i)
    if len and (len == 3 and dist < 4096 or len > 3) then
      --print("pair", i, len, dist)
      local code = _lengthToLiteralLengthCode[len]
      assert (code > 256 and code <= 285, "Invalid code")
      local distCode = _distanceToCode[dist]

      local lenExtraBitsLength = _lengthToExtraBitsLength[len]
      local distExtraBitsLength = _distanceToExtraBitsLength[dist]

      table_insert(literalLengthCode, code)
      table_insert(distanceCode, distCode)
      if lenExtraBitsLength > 0 then
        local lenExtraBits = _lengthToExtraBits[len]
        table_insert(lengthExtraBits, lenExtraBits)
      end
      if not distExtraBitsLength then print(dist) end
      if distExtraBitsLength > 0 then
        local distExtraBits = _distanceToExtraBits[dist]
        table_insert(distanceExtraBits, distExtraBits)
      end
      i = i + len
    else
      table_insert(literalLengthCode, strTable[i])
      i = i + 1
    end
    --print(i)
  end

  print("time_find_pairs", os.clock()-time2)
  local time3 = os.clock()
  table_insert(literalLengthCode, 256)
  local literalLengthHuffmanLength, literalLengthHuffmanCode = GetHuffmanBitLengthAndCode(literalLengthCode, 15, 285)
  local distanceHuffmanLength, distanceHuffmanCode = GetHuffmanBitLengthAndCode(distanceCode, 15, 29)

  local encodedLiteralLengthHuffmanLength, encodedLiteralLengthHuffmanLengthExtraBits, encodedLiteralLengthHuffmanLengthCount =
    RunLengthEncodeSymbolBitLength(literalLengthHuffmanLength, 285)
  local encodedDistanceHuffmanLength, encodedDistanceHuffmanLengthExtraBits, encodedDistanceHuffmanLengthCount =
    RunLengthEncodeSymbolBitLength(distanceHuffmanLength, 29)

  local encodedBothLengthCodes = {}
  for _, v in ipairs(encodedLiteralLengthHuffmanLength) do
    table_insert(encodedBothLengthCodes, v)
  end
  for _, v in ipairs(encodedDistanceHuffmanLength) do
    table_insert(encodedBothLengthCodes, v)
  end
  local codeLengthHuffmanCodeLength, codeLengthHuffmanCode = GetHuffmanBitLengthAndCode(encodedBothLengthCodes, 7, 18)

  local HCLEN = 0
  for i=1, 19 do
    local symbol = _codeLengthHuffmanCodeOrder[i]
    local length = codeLengthHuffmanCodeLength[symbol] or 0
    if length ~= 0 then
      HCLEN = i
    end
  end

  HCLEN = HCLEN - 4
  local HLIT = encodedLiteralLengthHuffmanLengthCount - 257 -- # of Literal/Length codes - 257 (257 - 286)
  local HDIST = encodedDistanceHuffmanLengthCount - 1 -- # of Distance codes - 1 (1 - 32)
  if HDIST < 0 then HDIST = 0 end
  print("time_contruct_table", os.clock()-time3)
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
    local length = codeLengthHuffmanCodeLength[symbol] or 0
    --print(symbol, length)
    WriteBits(length, 3)
  end

  WriteEncodedHuffmanLength(encodedLiteralLengthHuffmanLength, encodedLiteralLengthHuffmanLengthExtraBits
    , codeLengthHuffmanCodeLength, codeLengthHuffmanCode)

  if HDIST == 0 then -- TODO: Fix
    if encodedDistanceHuffmanLengthCount == 0 then
      WriteBits(0, 1)
  else
    WriteBits(1, 1)
  end
  else
    WriteEncodedHuffmanLength(encodedDistanceHuffmanLength, encodedDistanceHuffmanLengthExtraBits
      , codeLengthHuffmanCodeLength, codeLengthHuffmanCode)
  end

  local lengthCodeCount = 0
  local lengthCodeWithExtraCount = 0
  local distCodeWithExtraCount = 0

  for _, code in ipairs(literalLengthCode) do
    local huffmanCode = literalLengthHuffmanCode[code]
    local huffmanLength = literalLengthHuffmanLength[code]
    if code <= 256 then -- Literal/end of block
      WriteBits(huffmanCode, huffmanLength)
      --print(code, huffmanCode, huffmanLength)
    else -- Length code
      lengthCodeCount = lengthCodeCount + 1
      WriteBits(huffmanCode, huffmanLength)
      if code > 264 and code < 285 then -- Length code with extra bits
        lengthCodeWithExtraCount = lengthCodeWithExtraCount + 1
        local extraBits = lengthExtraBits[lengthCodeWithExtraCount]
        local extraBitsLength = _literalLengthCodeToExtraBitsLength[code]
        WriteBits(extraBits, extraBitsLength)
      end
      -- Write distance code
      local distCode = distanceCode[lengthCodeCount]
      local distHuffmanCode = distanceHuffmanCode[distCode]
      local distHuffmanLength = distanceHuffmanLength[distCode]
      WriteBits(distHuffmanCode, distHuffmanLength)

      if distCode > 3 then -- dist code with extra bits
        distCodeWithExtraCount = distCodeWithExtraCount + 1
        local distExtraBits = distanceExtraBits[distCodeWithExtraCount]
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
  --local time4 = os.clock()
  return result
end

return lib