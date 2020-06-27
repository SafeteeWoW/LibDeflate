--[[
zlib License

(C) 2018-2020 Haoqian He

This software is provided 'as-is', without any express or implied
warranty.  In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.

--]]


-- Run this tests at the folder where LibDeflate.lua located, like this.
-- lua tests/Test.lua
-- Don't run two "tests/Test.lua" at the same time,
-- because they will conflict!!!

package.path = ("?.lua;tests/LibCompress/?.lua;")..(package.path or "")

do
	local test_lua = io.open("tests/Test.lua")
	assert(test_lua
		, "Must run this script in the root folder of LibDeflate repository")
	test_lua:close()
end

local old_globals = {}
for k, v in pairs(_G) do
	old_globals[k] = v
end
local LibDeflate = require("LibDeflate")
for k, v in pairs(_G) do
	assert(v == old_globals[k], "LibDeflate global leak at key: "..tostring(k))
end
for k, v in pairs(old_globals) do
	assert(v == _G[k], "LibDeflate global leak at key: "..tostring(k))
end

-- UnitTests
local lu = require("luaunit")
assert(lu)

local assert = assert
local loadstring = loadstring or load
local math = math
local string = string
local table = table
local collectgarbage = collectgarbage
local os = os
local type = type
local io = io
local print = print
local tostring = tostring
local string_char = string.char
local string_byte = string.byte
local string_len = string.len
local string_sub = string.sub
local unpack = unpack or table.unpack
local table_insert = table.insert
local table_concat = table.concat

math.randomseed(0) -- I don't like true random tests that I cant 100% reproduce.

local _pow2 = {}
do
	local pow = 1
	for i = 0, 32 do
		_pow2[i] = pow
		pow = pow * 2
	end
end

local function DeepCopy(obj)
    local SearchTable = {} -- luacheck: ignore

    local function Func(object)
        if type(object) ~= "table" then
            return object
        end
        local NewTable = {}
        SearchTable[object] = NewTable
        for k, v in pairs(object) do
            NewTable[Func(k)] = Func(v)
        end

        return setmetatable(NewTable, getmetatable(object))
    end

    return Func(obj)
end

local function GetTableSize(t)
	local size = 0
	for _, _ in pairs(t) do
		size = size + 1
	end
	return size
end

local HexToString
local HalfByteToHex
do
	local _byte0 = string_byte("0", 1)
	local _byte9 = string_byte("9", 1)
	local _byteA = string_byte("A", 1)
	local _byteF = string_byte("F", 1)
	local _bytea = string_byte("a", 1)
	local _bytef = string_byte("f", 1)
	function HexToString(str)
		local t = {}
		local val = 1
		for i=1, str:len()+1 do
			local b = string_byte(str, i, i) or -1
			if b >= _byte0 and b <= _byte9 then
				val = val*16 + b - _byte0
			elseif b >= _byteA and b <= _byteF then
				val = val*16 + b - _byteA + 10
			elseif b >= _bytea and b <= _bytef then
				val = val*16 + b - _bytea + 10
			elseif val ~= 1 and val < 32 then  -- one digit followed by delimiter
	            val = val + 240                 -- make it look like two digits
			end
			if val > 255 then
				t[#t+1] = string_char(val % 256)
				val = 1
			end
		end
		return table.concat(t)
	end
	assert(HexToString("f") == string_char(15))
	assert(HexToString("1f") == string_char(31))
	assert(HexToString("1f 2") == string_char(31)..string_char(2))
	assert(HexToString("1f 22") == string_char(31)..string_char(34))
	assert(HexToString("F") == string_char(15))
	assert(HexToString("1F") == string_char(31))
	assert(HexToString("1F 2") == string_char(31)..string_char(2))
	assert(HexToString("1F 22") == string_char(31)..string_char(34))

	assert(HexToString("a") == string_char(10))
	assert(HexToString("1a") == string_char(26))
	assert(HexToString("1a 90") == string_char(26)..string_char(144))
	assert(HexToString("1a 9") == string_char(26)..string_char(9))
	assert(HexToString("A") == string_char(10))
	assert(HexToString("1A") == string_char(26))
	assert(HexToString("1A 09") == string_char(26)..string_char(9))
	assert(HexToString("1A 00") == string_char(26)..string_char(0))

	function HalfByteToHex(half_byte)
		assert (half_byte >= 0 and half_byte < 16)
		if half_byte < 10 then
			return string_char(_byte0 + half_byte)
		else
			return string_char(_bytea + half_byte-10)
		end
	end
end

local function StringToHex(str)
	if not str then
		return "nil"
	end
	local tmp = {}
	for i = 1, str:len() do
		local b = string_byte(str, i, i)
		if b < 16 then
			tmp[#tmp+1] = "0"..HalfByteToHex(b)
		else
			tmp[#tmp+1] = HalfByteToHex((b-b%16)/16)..HalfByteToHex(b%16)
		end
	end
	return table.concat(tmp, " ")
end
assert (StringToHex("\000"), "00")
assert (StringToHex("\000\255"), "00 ff")
assert (StringToHex(HexToString("05 e0 81 91 24 cb b2 2c 49 e2 0f 2e 8b 9a"
	.." 47 56 9f fb fe ec d2 ff 1f"))
	== "05 e0 81 91 24 cb b2 2c 49 e2 0f 2e 8b 9a 47 56 9f fb fe ec d2 ff 1f")

-- Return a string with limited size
local function StringForPrint(str)
	if str:len() < 101 then
		return str
	else
		return str:sub(1, 101)..(" (%d more characters not shown)")
			:format(str:len()-101)
	end
end

local function OpenFile(filename, mode)
	local f = io.open(filename, mode)
	lu.assertNotNil(f, ("Cannot open the file: %s, with mode: %s")
		:format(filename, mode))
	return f
end

local function GetFileData(filename)
	local f = OpenFile(filename, "rb")
	local str = f:read("*all")
	f:close()
	return str
end

local function WriteToFile(filename, data)
	local f = io.open(filename, "wb")
	lu.assertNotNil(f, ("Cannot open the file: %s, with mode: %s")
		:format(filename, "wb"))
	f:write(data)
	f:flush()
	f:close()
end

local function GetLimitedRandomString(strlen)
	local randoms = {}
	for _=1, 7 do
		randoms[#randoms+1] = string.char(math.random(1, 255))
	end
	local tmp = {}
	for _=1, strlen do
		tmp[#tmp+1] = randoms[math.random(1, 7)]
	end
	return table.concat(tmp)
end

local function GetRandomString(strlen)
	local tmp = {}
	for _=1, strlen do
		tmp[#tmp+1] = string_char(math.random(0, 255))
	end
	return table.concat(tmp)
end

-- Get a random string with at least 256 len which includes all characters
local function GetRandomStringUniqueChars(strlen)
	local taken = {}
	local tmp = {}
	for i=0, (strlen < 256) and strlen-1 or 255 do
		local rand = math.random(1, 256-i)
		local count = 0
		for j=0, 255 do
			if (not taken[j]) then
				count = count + 1
			end
			if count == rand then
				taken[j] = true
				tmp[#tmp+1] = string_char(j)
				break
			end
		end
	end
	if strlen > 256 then
		for _=1, strlen-256 do
			table_insert(tmp, math.random(1, #tmp+1)
				, string_char(math.random(0, 255)))
		end
	end
	return table_concat(tmp)
end
assert(GetRandomStringUniqueChars(3):len() == 3)
assert(GetRandomStringUniqueChars(255):len() == 255)
assert(GetRandomStringUniqueChars(256):len() == 256)
assert(GetRandomStringUniqueChars(500):len() == 500)
do
	local taken = {}
	local str = GetRandomStringUniqueChars(256)
	for i=1, 256 do
		local byte = string_byte(str, i, i)
		assert(not taken[byte])
		taken[byte] = true
	end
end

-- Repeatedly collect memory garbarge until memory usage no longer changes
local function FullMemoryCollect()
	local memory_used = collectgarbage("count")
	local last_memory_used
	local stable_count = 0
	repeat
		last_memory_used = memory_used
		collectgarbage("collect")
		memory_used = collectgarbage("count")

		if memory_used >= last_memory_used then
			stable_count = stable_count + 1
		else
			stable_count = 0
		end
	until stable_count == 10
	-- Stop full memory collect until memory does not decrease for 10 times.
end

local function RunProgram(program, input_filename, stdout_filename)
	local stderr_filename = stdout_filename..".stderr"
	local status, _, ret = os.execute(program.." "..input_filename
		.. "> "..stdout_filename.." 2> "..stderr_filename)
	local returned_status
	if type(status) == "number" then -- lua 5.1
		returned_status = status
	else -- Lua 5.2/5.3
		returned_status = ret
		if not status and ret == 0 then
			returned_status = -1
			-- Lua bug on Windows when the returned value is -1, ret is 0
		end
	end
	local stdout = GetFileData(stdout_filename)
	local stderr = GetFileData(stderr_filename)
	return returned_status, stdout, stderr
end

local function AssertLongStringEqual(actual, expected, msg)
	if actual ~= expected then
		lu.assertNotNil(actual, ("%s actual is nil"):format(msg or ""))
		lu.assertNotNil(expected, ("%s expected is nil"):format(msg or ""))
		local diff_index = 1
		for i=1, math.max(expected:len(), actual:len()) do
			if string_byte(actual, i, i) ~= string_byte(expected, i, i) then
				diff_index = i
				break
			end
		end
		local actual_msg = string.format(
			"%s actualLen: %d, expectedLen:%d, first difference at: %d,"
			.." actualByte: %s, expectByte: %s", msg or "", actual:len()
			, expected:len(), diff_index,
			string.byte(actual, diff_index) or "nil",
			string.byte(expected, diff_index) or "nil")
		lu.assertTrue(false, actual_msg)
	end
end

local function MemCheckAndBenchmarkFunc(lib, func_name, ...)
	local memory_before
	local memory_running
	local memory_after
	local start_time
	local elapsed_time
	local ret
	FullMemoryCollect()
	memory_before =  math.floor(collectgarbage("count")*1024)
	FullMemoryCollect()
	start_time = os.clock()
	elapsed_time = -1
	local repeat_count = 0
	while elapsed_time < 0.015 do
		ret = {lib[func_name](lib, ...)}
		elapsed_time = os.clock() - start_time
		repeat_count = repeat_count + 1
	end
	memory_running = math.floor(collectgarbage("count")*1024)
	FullMemoryCollect()
	memory_after = math.floor(collectgarbage("count")*1024)
	local memory_used = memory_running - memory_before
	local memory_leaked = memory_after - memory_before

	return memory_leaked, memory_used
		, elapsed_time*1000/repeat_count, unpack(ret)
end

local function GetFirstBlockType(compressed_data, isZlib)
	local first_block_byte_index = 1
	if isZlib then
		local byte2 = string.byte(compressed_data, 2, 2)
		local has_dict = ((byte2-byte2%32)/32)%2
		if has_dict == 1 then
			first_block_byte_index = 7
		else
			first_block_byte_index = 3
		end
	end
	local first_byte = string.byte(compressed_data
		, first_block_byte_index, first_block_byte_index)
	local bit3 = first_byte % 8
	return (bit3 - bit3 % 2) / 2
end

local function PutRandomBitsInPaddingBits(compressed_data, padding_bitlen)
	if padding_bitlen > 0 then
		local len = #compressed_data
		local last_byte = string.byte(compressed_data, len)
		local random_last_byte = math.random(0, 255)
		random_last_byte = random_last_byte
			- random_last_byte % _pow2[8-padding_bitlen]
		random_last_byte = random_last_byte
			+ last_byte % _pow2[8-padding_bitlen]
		compressed_data = compressed_data:sub(1, len-1)
			..string.char(random_last_byte)
	end
	return compressed_data
end

local dictionary32768_str = GetFileData("tests/dictionary32768.txt")
local dictionary32768 = LibDeflate:CreateDictionary(dictionary32768_str
	, 32768, 4072834167)

local _CheckCompressAndDecompressCounter = 0
local function CheckCompressAndDecompress(string_or_filename, is_file, levels
	, strategy, output_prefix)

	-- For 100% code coverage
	if _CheckCompressAndDecompressCounter % 3 == 0 then
		LibDeflate.internals.InternalClearCache()
	end
	if _CheckCompressAndDecompressCounter % 2 == 0 then
		-- Init cache table in these functions
		-- , to help memory leak check in the following codes.
		LibDeflate:EncodeForWoWAddonChannel("")
		LibDeflate:EncodeForWoWChatChannel("")
	else
		LibDeflate:DecodeForWoWAddonChannel("")
		LibDeflate:DecodeForWoWChatChannel("")
	end
	_CheckCompressAndDecompressCounter = _CheckCompressAndDecompressCounter + 1

	local origin
	if is_file then
		origin = GetFileData(string_or_filename)
	else
		origin = string_or_filename
	end

	FullMemoryCollect()
	local total_memory_before = math.floor(collectgarbage("count")*1024)

	do
		if levels == "all" then
			levels = {0,1,2,3,4,5,6,7,8,9}
		else
			levels = levels or {1}
		end

		local compress_filename
		local decompress_filename

		if output_prefix then
			compress_filename = output_prefix..".compress"
			decompress_filename = output_prefix..".decompress"
		else
			if is_file then
				compress_filename = string_or_filename..".compress"
			else
				compress_filename = "tests/string.compress"
			end
			decompress_filename = compress_filename..".decompress"
		end

		for i=1, #levels+1 do -- also test level == nil
			local level = levels[i]
			local configs = {level = level, strategy = strategy}

			print(
				(">>>>> %s: %s size: %d B Level: %s Strategy: %s")
				:format(is_file and "File" or "String",
					string_or_filename:sub(1, 40),  origin:len()
					,tostring(level), tostring(strategy)
				))
			local compress_to_run = {
				{"CompressDeflate", origin, configs},
				{"CompressDeflateWithDict", origin, dictionary32768
					, configs},
				{"CompressZlib", origin, configs},
				{"CompressZlibWithDict", origin, dictionary32768, configs},
			}

			for j, compress_running in ipairs(compress_to_run) do
			-- Compress by raw deflate
				local compress_func_name = compress_running[1]
				local compress_memory_leaked, compress_memory_used
					, compress_time, compress_data, compress_pad_bitlen =
					MemCheckAndBenchmarkFunc(LibDeflate
						, unpack(compress_running))

				if compress_running[1]:find("Deflate") then
					lu.assertTrue(0 <= compress_pad_bitlen
						and compress_pad_bitlen < 8
						, compress_func_name)
					-- put random value in the padding bits,
					-- to see if it is still okay to decompress

				else
					lu.assertEquals(compress_pad_bitlen, 0
						, compress_func_name)
				end

				-- Test encoding
				local compress_data_WoW_addon_encoded =
					LibDeflate:EncodeForWoWAddonChannel(compress_data)
				AssertLongStringEqual(
					LibDeflate:DecodeForWoWAddonChannel(
						compress_data_WoW_addon_encoded), compress_data
						, compress_func_name)

				local compress_data_data_WoW_chat_encoded =
					LibDeflate:EncodeForWoWChatChannel(compress_data)
				AssertLongStringEqual(
					LibDeflate:DecodeForWoWChatChannel(
						compress_data_data_WoW_chat_encoded), compress_data
						, compress_func_name)

				-- Put random bits in the padding bits of compressed data.
				-- to see if decompression still works.
				compress_data = PutRandomBitsInPaddingBits(compress_data
					, compress_pad_bitlen)
				local isZlib = compress_func_name:find("Zlib")
				if strategy == "fixed" then
					lu.assertEquals(GetFirstBlockType(compress_data, isZlib)
					, (level == 0) and 0 or 1,
					compress_func_name.." "..tostring(level))
				elseif strategy == "dynamic" then
					lu.assertEquals(GetFirstBlockType(compress_data, isZlib)
					, (level == 0) and 0 or 2,
					compress_func_name.." "..tostring(level))
				elseif strategy == "huffman_only" then  -- luacheck: ignore
					-- Emtpy
				elseif strategy == nil then -- luacheck: ignore
					-- Empty
				else
					lu.assertTrue(false, "Unexpected strategy: "
						..tostring(strategy))
				end
				WriteToFile(compress_filename, compress_data)

				if not compress_running[1] == "CompressDeflate" then
					local returnedStatus_puff, stdout_puff =
						RunProgram("puff -w ", compress_filename
							, decompress_filename)
					lu.assertEquals(returnedStatus_puff, 0
						, compress_func_name
						.." puff decompression failed with code "
						..returnedStatus_puff)
					AssertLongStringEqual(stdout_puff, origin
						, "puff fails with "..compress_func_name)
				end

				local decompress_to_run = {
					{"DecompressDeflate", compress_data},
					{"DecompressDeflateWithDict", compress_data
						, dictionary32768, configs},

					{"DecompressZlib", compress_data, configs},
					{"DecompressZlibWithDict", compress_data
						, dictionary32768, configs},
				}
				lu.assertEquals(#decompress_to_run, #compress_to_run)

				local zdeflate_decompress_to_run = {
					"zdeflate -d <",
					"zdeflate -d --dict tests/dictionary32768.txt <",
					"zdeflate --zlib -d <",
					"zdeflate --zlib -d --dict tests/dictionary32768.txt <",
				}
				lu.assertEquals(#zdeflate_decompress_to_run, #compress_to_run)

				-- Try decompress by zdeflate
				-- zdeflate is a C program calling zlib library
				-- which is modifed from zlib example.
				-- zdeflate can do all compression and decompression doable
				-- by LibDeflate (except encode and decode)
				local returnedStatus_zdeflate, stdout_zdeflate
					, stderr_zdeflate =
					RunProgram(zdeflate_decompress_to_run[j], compress_filename
						, decompress_filename)
				lu.assertEquals(returnedStatus_zdeflate, 0
					, compress_func_name
					..":zdeflate decompression failed with msg "
					..stderr_zdeflate)
				AssertLongStringEqual(stdout_zdeflate, origin
					, compress_func_name
					.."zdeflate decompress result not match origin string.")

				-- Try decompress by LibDeflate
				local decompress_memory_leaked, decompress_memory_used,
					decompress_time, decompress_data,
					decompress_unprocess_byte =
					MemCheckAndBenchmarkFunc(LibDeflate
						, unpack(decompress_to_run[j]))
				AssertLongStringEqual(decompress_data, origin
					, compress_func_name
					.." LibDeflate decompress result not match origin string.")
				lu.assertEquals(decompress_unprocess_byte, 0
					, compress_func_name
					.." Unprocessed bytes after LibDeflate decompression "
						..tostring(decompress_unprocess_byte))

				print(
					("%s:   Size : %d B,Time: %.3f ms, "
						.."Speed: %.0f KB/s, Memory: %d B,"
						.." Mem/input: %.2f, (memleak?: %d B) padbit: %d\n")
						:format(compress_func_name
						, compress_data:len(), compress_time
						, compress_data:len()/compress_time
						, compress_memory_used
						, compress_memory_used/origin:len()
						, compress_memory_leaked
						, compress_pad_bitlen
					),
					("%s:   cRatio: %.2f,Time: %.3f ms"
						..", Speed: %.0f KB/s, Memory: %d B,"
						.." Mem/input: %.2f, (memleak?: %d B)"):format(
						decompress_to_run[j][1]
						, origin:len()/compress_data:len(), decompress_time
						, decompress_data:len()/decompress_time
						, decompress_memory_used
						, decompress_memory_used/origin:len()
						, decompress_memory_leaked
					)
				)
			end
			print("")
		end

		-- Use all avaiable strategies of zdeflate to compress the data
		-- , and see if LibDeflate can decompress it.
		local tmp_filename = "tests/tmp.tmp"
		WriteToFile(tmp_filename, origin)

		local zdeflate_level, zdeflate_strategy
		local strategies = {"--filter", "--huffman", "--rle"
			, "--fix", "--default"}
		local unique_compress = {}
		local uniques_compress_count = 0
		for level=0, 8 do
			zdeflate_level = "-"..level
			for j=1, #strategies do
				zdeflate_strategy = strategies[j]
				local status, stdout, stderr =
					RunProgram("zdeflate "..zdeflate_level
					.." "..zdeflate_strategy
					.." < ", tmp_filename, tmp_filename..".out")
				lu.assertEquals(status, 0
				, ("zdeflate cant compress the file? "
					.."stderr: %s level: %s, strategy: %s")
					:format(stderr, zdeflate_level, zdeflate_strategy))
				if not unique_compress[stdout] then
					unique_compress[stdout] = true
					uniques_compress_count = uniques_compress_count + 1
					local decompressData =
						LibDeflate:DecompressDeflate(stdout)
					AssertLongStringEqual(decompressData, origin,
						("My decompress fail to decompress "
						.."at zdeflate level: %s, strategy: %s")
						:format(level, zdeflate_strategy))
				end
			end
		end
		print(
			(">>>>> %s: %s size: %d B\n")
				:format(is_file and "File" or "String"
				, string_or_filename:sub(1, 40), origin:len()),
			("Full decompress coverage test ok. unique compresses: %d\n")
				:format(uniques_compress_count),
			"\n")
	end

	FullMemoryCollect()
	local total_memory_after = math.floor(collectgarbage("count")*1024)

	local total_memory_difference = total_memory_before - total_memory_after

	if total_memory_difference > 0 then
		local ignore_leak_jit = ""
		if _G.jit then
			ignore_leak_jit = " (Ignore when the test is run by LuaJIT)"
		end
		print(
			(">>>>> %s: %s size: %d B\n")
				:format(is_file and "File" or "String"
				, string_or_filename:sub(1, 40), origin:len()),
			("Actual Memory Leak in the test: %d"..ignore_leak_jit.."\n")
				:format(total_memory_difference),
			"\n")
		-- ^If above "leak" is very small
		-- , it is very likely that it is false positive.
		if not _G.jit and total_memory_difference > 64 then
			-- Lua JIT has some problems to garbage collect stuffs
			-- , so don't consider as failure.
			lu.assertTrue(false
			, ("Fail the test because too many actual "
				.."Memory Leak in the test: %d")
				:format(total_memory_difference))
		end
	end

	return 0
end

local function CheckCompressAndDecompressString(str, levels, strategy)
	return CheckCompressAndDecompress(str, false, levels, strategy)
end

local function CheckCompressAndDecompressFile(inputFileName, levels, strategy
	, output_prefix)
	return CheckCompressAndDecompress(inputFileName, true, levels, strategy
									  , output_prefix)
end

local function CheckDecompressIncludingError(compress, decompress, is_zlib)
	assert (is_zlib == true or is_zlib == nil)
	local d, decompress_status
	if is_zlib then
		d, decompress_status = LibDeflate:DecompressZlib(compress)
	else
		d, decompress_status = LibDeflate:DecompressDeflate(compress)
	end
	lu.assertTrue(type(d) == "string" or type(d) == "nil")
	lu.assertEquals(type(decompress_status), "number")
	lu.assertEquals(decompress_status % 1, 0)
	if d ~= decompress then
		lu.assertTrue(false, ("My decompress does not match expected result."
			.."expected: %s, actual: %s, Returned status of decompress: %d")
			:format(StringForPrint(StringToHex(d))
			, StringForPrint(StringToHex(decompress)), decompress_status))
	else
		-- Check my decompress result with "puff"
		local input_filename = "tests/tmpFile"
		local inputFile = io.open(input_filename, "wb")
		inputFile:setvbuf("full")
		inputFile:write(compress)
		inputFile:flush()
		inputFile:close()
		local returned_status_puff, stdout_puff =
			RunProgram("puff -w", input_filename
			, input_filename..".decompress")
		local returnedStatus_zdeflate, stdout_zdeflate =
			RunProgram(is_zlib and "zdeflate --zlib -d <"
			or "zdeflate -d <", input_filename, input_filename..".decompress")
		if not d then
			if not is_zlib then
				if returned_status_puff ~= 0
					and returnedStatus_zdeflate ~= 0 then
					print((">>>> %q cannot be decompress as expected")
					:format((StringForPrint(StringToHex(compress)))))
				elseif returned_status_puff ~= 0
					and returnedStatus_zdeflate == 0 then
					lu.assertTrue(false,
					(">>>> %q puff error but not zdeflate?")
					:format((StringForPrint(StringToHex(compress)))))
				elseif returned_status_puff == 0
					and returnedStatus_zdeflate ~= 0 then
					lu.assertTrue(false,
					(">>>> %q zdeflate error but not puff?")
					:format((StringForPrint(StringToHex(compress)))))
				else
					lu.assertTrue(false,
					(">>>> %q my decompress error, but not puff or zdeflate")
					:format((StringForPrint(StringToHex(compress)))))
				end
			else
				if returnedStatus_zdeflate ~= 0 then
					print((">>>> %q cannot be zlib decompress as expected")
					:format(StringForPrint(StringToHex(compress))))
				else
					lu.assertTrue(false,
					(">>>> %q my decompress error, but not zdeflate")
					:format((StringForPrint(StringToHex(compress)))))
				end
			end

		else
			AssertLongStringEqual(d, stdout_zdeflate)
			if not is_zlib then
				AssertLongStringEqual(d, stdout_puff)
			end
			print((">>>> %q is decompressed to %q as expected")
				:format(StringForPrint(StringToHex(compress))
				, StringForPrint(StringToHex(d))))
		end
	end
end

local function CheckZlibDecompressIncludingError(compress, decompress)
	return CheckDecompressIncludingError(compress, decompress, true)
end

local function CreateDictionaryWithoutVerify(str)
	-- Dont do this in the real program.
	-- Dont calculate adler32 in runtime. Do hardcode it as constant.
	-- This is just for test purpose
	local dict = LibDeflate:CreateDictionary(str, #str, LibDeflate:Adler32(str))
	return dict
end

local function CreateAndCheckDictionary(str)
	local strlen = #str
	local dictionary = CreateDictionaryWithoutVerify(str)

	lu.assertTrue(LibDeflate.internals.IsValidDictionary(dictionary))
	for i=1, strlen do
		lu.assertEquals(dictionary.string_table[i], string_byte(str, i, i))
	end
	lu.assertEquals(dictionary.strlen, str:len())
	for i=1, strlen-2 do
		local hash = string_byte(str, i, i)*65536
			+ string_byte(str, i+1, i+1)*256
			+ string_byte(str, i+2, i+2)
		local hash_chain = dictionary.hash_tables[hash]
		lu.assertNotNil(hash_chain, "nil hash_chain?")
		local found = false
		for j = 1, #hash_chain do
			if hash_chain[j] == i-strlen then
				found = true
				break
			end
		end
		lu.assertTrue(found
		, ("hash index %d not found in dictionary hash_table."):format(i))
	end
	return dictionary
end



-- the input dictionary must can make compressed data smaller.
-- otherwise, set dontCheckEffectivenss
local function CheckDictEffectiveness(str, dictionary, dict_str
	, dontCheckEffectiveness)
	local configs = {level = 7}
	local compress_dict = LibDeflate:CompressDeflateWithDict(str
		, dictionary, configs)
	local decompressed_dict =
		LibDeflate:DecompressDeflateWithDict(compress_dict, dictionary)
	AssertLongStringEqual(decompressed_dict, str)

	local compress_no_dict = LibDeflate:CompressDeflate(str, configs)
	local decompressed_no_dict =
		LibDeflate:DecompressDeflate(compress_no_dict)
	AssertLongStringEqual(decompressed_no_dict, str)

	local byte_smaller_with_dict = compress_no_dict:len()
		- compress_dict:len()
	if not dontCheckEffectiveness then
		lu.assertTrue(byte_smaller_with_dict > 0)
		print((">>> %d bytes smaller with (deflate dict) "..
			"DICT: %s, DATA: %s")
			:format(byte_smaller_with_dict
				, StringForPrint(dict_str), StringForPrint(str)))
	end

	local zlib_compress_dict = LibDeflate:
		CompressZlibWithDict(str, dictionary, configs)
	local zlib_decompressed_dict =
		LibDeflate:DecompressZlibWithDict(zlib_compress_dict, dictionary)
	AssertLongStringEqual(zlib_decompressed_dict, str)

	local zlib_compress_no_dict = LibDeflate:CompressZlib(str, configs)
	local zlib_decompressed_no_dict =
		LibDeflate:DecompressZlib(zlib_compress_no_dict)
	AssertLongStringEqual(zlib_decompressed_no_dict, str)

	local zlib_byte_smaller_with_dict = zlib_compress_no_dict:len()
		- zlib_compress_dict:len()
	-- for zlib with dict, 4 extra bytes needed to store
	-- the adler32 of dictionary
	if not dontCheckEffectiveness then
		lu.assertTrue(zlib_byte_smaller_with_dict > -4)
		print((">>> %d bytes smaller with (zlib dict) DICT: %s DATA: %s")
			:format(zlib_byte_smaller_with_dict
			, StringForPrint(dict_str), StringForPrint(str)))
	end

	return compress_dict, compress_no_dict
		, zlib_compress_dict, zlib_compress_no_dict
end

-- Commandline
local arg = _G.arg
if arg and #arg >= 1 and type(arg[0]) == "string" then
	if #arg >= 2 and arg[1] == "-o" then
	-- For testing purpose (test_from_random_files_in_disk.py),
	-- check if the file can be opened by lua
		local input = arg[2]
		local inputFile = io.open(input, "rb")
		if not inputFile then
			os.exit(1)
		end
		inputFile.close()
		os.exit(0)
	elseif #arg >= 3 and arg[1] == "-c" then
	-- For testing purpose (test_from_random_files_in_disk.py)
	-- , check the if a file can be correctly compress and decompress to origin
		os.exit(CheckCompressAndDecompressFile(arg[2], "all", nil
				, "tests/tmp"))
	end
end

-------------------------------------------------------------------------
-- LibCompress encode code to help verity encode code in LibDeflate -----
-------------------------------------------------------------------------
local LibCompressEncoder = {}
do
	local gsub_escape_table = {
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
		return str:gsub("([%z%(%)%.%%%+%-%*%?%[%]%^%$])",  gsub_escape_table)
	end

	function LibCompressEncoder:GetEncodeTable(reservedChars, escapeChars
			, mapChars)
		reservedChars = reservedChars or ""
		escapeChars = escapeChars or ""
		mapChars = mapChars or ""

		-- select a default escape character
		if escapeChars == "" then
			return nil, "No escape characters supplied"
		end

		if #reservedChars < #mapChars then
			return nil, "Number of reserved characters must be at least "
				.."as many as the number of mapped chars"
		end

		if reservedChars == "" then
			return nil, "No characters to encode"
		end

		-- list of characters that must be encoded
		local encodeBytes = reservedChars..escapeChars..mapChars

		-- build list of bytes not available as a suffix to a prefix byte
		local taken = {}
		for i = 1, string_len(encodeBytes) do
			taken[string_sub(encodeBytes, i, i)] = true
		end

		-- allocate a table to hold encode/decode strings/functions
		local codecTable = {}

		-- the encoding can be a single gsub,
		-- but the decoding can require multiple gsubs
		local decode_func_string = {}

		local encode_search = {}
		local encode_translate = {}
		local encode_func
		local decode_search = {}
		local decode_translate = {}
		local decode_func
		local c, r, to, from
		local escapeCharIndex, escapeChar = 0

		-- map single byte to single byte
		if #mapChars > 0 then
			for i = 1, #mapChars do
				from = string_sub(reservedChars, i, i)
				to = string_sub(mapChars, i, i)
				encode_translate[from] = to
				table_insert(encode_search, from)
				decode_translate[to] = from
				table_insert(decode_search, to)
			end
			codecTable["decode_search"..tostring(escapeCharIndex)]
				= "([".. escape_for_gsub(table_concat(decode_search)).."])"
			codecTable["decode_translate"..tostring(escapeCharIndex)] =
				decode_translate
			table_insert(decode_func_string, "str = str:gsub(self.decode_search"
				..tostring(escapeCharIndex)..", self.decode_translate"
				..tostring(escapeCharIndex)..");")
		end

		-- map single byte to double-byte
		escapeCharIndex = escapeCharIndex + 1
		escapeChar = string_sub(escapeChars, escapeCharIndex, escapeCharIndex)
		r = 0 -- suffix char value to the escapeChar
		decode_search = {}
		decode_translate = {}
		for i = 1, string_len(encodeBytes) do
			c = string_sub(encodeBytes, i, i)
			if not encode_translate[c] then
				-- this loop will update escapeChar and r
				while r >= 256 or taken[string_char(r)] do -- Defliate patch
				-- bug in LibCompress r81
				-- while r < 256 and taken[string_char(r)] do
					r = r + 1
					if r > 255 then -- switch to next escapeChar
						if escapeChar == "" then
							-- we are out of escape chars and we need more!
							return nil, "Out of escape characters"
						end

						codecTable["decode_search"..tostring(escapeCharIndex)] =
							escape_for_gsub(escapeChar)
							.."(["..
							escape_for_gsub(table_concat(decode_search)).."])"
						codecTable["decode_translate"
							..tostring(escapeCharIndex)] = decode_translate
						table_insert(decode_func_string,
							"str = str:gsub(self.decode_search"
							..tostring(escapeCharIndex)
							..", self.decode_translate"
							..tostring(escapeCharIndex)..");")

						escapeCharIndex  = escapeCharIndex + 1
						escapeChar = string_sub(escapeChars
							, escapeCharIndex, escapeCharIndex)

						r = 0
						decode_search = {}
						decode_translate = {}
					end
				end
				encode_translate[c] = escapeChar..string_char(r)
				table_insert(encode_search, c)
				decode_translate[string_char(r)] = c
				table_insert(decode_search, string_char(r))
				r = r + 1
			end
		end

		if r > 0 then
			codecTable["decode_search"..tostring(escapeCharIndex)] =
				escape_for_gsub(escapeChar)
				.."([".. escape_for_gsub(table_concat(decode_search)).."])"
			codecTable["decode_translate"..tostring(escapeCharIndex)] =
				decode_translate
			table_insert(decode_func_string,
				"str = str:gsub(self.decode_search"..tostring(escapeCharIndex)
				..", self.decode_translate"..tostring(escapeCharIndex)..");")
		end

		-- change last line from "str = ...;" to "return ...;";
		decode_func_string[#decode_func_string] =
			decode_func_string[#decode_func_string]
			:gsub("str = (.*);", "return %1;")
		decode_func_string = "return function(self, str) "
			..table_concat(decode_func_string).." end"

		encode_search = "(["
			.. escape_for_gsub(table_concat(encode_search)).."])"
		decode_search = escape_for_gsub(escapeChars)
			.."([".. escape_for_gsub(table_concat(decode_search)).."])"

		encode_func = assert(loadstring(
			"return function(self, str) "
			.."return str:gsub(self.encode_search, "
			.."self.encode_translate); end"))()
		decode_func = assert(loadstring(decode_func_string))()

		codecTable.encode_search = encode_search
		codecTable.encode_translate = encode_translate
		codecTable.Encode = encode_func
		codecTable.decode_search = decode_search
		codecTable.decode_translate = decode_translate
		codecTable.Decode = decode_func

		codecTable.decode_func_string = decode_func_string -- to be deleted
		return codecTable
	end

	-- Addons: Call this only once and reuse the returned
	-- table for all encodings/decodings.
	function LibCompressEncoder:GetAddonEncodeTable(reservedChars
		, escapeChars, mapChars )
		reservedChars = reservedChars or ""
		escapeChars = escapeChars or ""
		mapChars = mapChars or ""
		-- Following byte values are not allowed:
		-- \000
		if escapeChars == "" then
			escapeChars = "\001"
		end
		return self:GetEncodeTable( (reservedChars or "").."\000"
			, escapeChars, mapChars)
	end

	-- Addons: Call this only once and reuse the returned
	-- table for all encodings/decodings.
	function LibCompressEncoder:GetChatEncodeTable(reservedChars
		, escapeChars, mapChars)
		reservedChars = reservedChars or ""
		escapeChars = escapeChars or ""
		mapChars = mapChars or ""
		local r = {}
		for i = 128, 255 do
			table_insert(r, string_char(i))
		end
		reservedChars = "sS\000\010\013\124%"
			..table_concat(r)..(reservedChars or "")
		if escapeChars == "" then
			escapeChars = "\029\031"
		end
		if mapChars == "" then
			mapChars = "\015\020";
		end
		return self:GetEncodeTable(reservedChars, escapeChars, mapChars)
	end
end

local _libcompress_addon_codec = LibCompressEncoder:GetAddonEncodeTable()
local _libcompress_chat_codec = LibCompressEncoder:GetChatEncodeTable()

-- Check if LibDeflate's encoding works properly
local function CheckEncodeAndDecode(str, reserved_chars, escape_chars
	, map_chars)
	if reserved_chars then
		local encode_decode_table_libcompress =
			LibCompressEncoder:GetEncodeTable(reserved_chars
			, escape_chars, map_chars)
		local encode_decode_table, message =
			LibDeflate:CreateCodec(reserved_chars
			, escape_chars, map_chars)
		if not encode_decode_table then
			print(message)
		end
		local encoded_libcompress = encode_decode_table_libcompress:Encode(str)
		local encoded = encode_decode_table:Encode(str)
		AssertLongStringEqual(encoded, encoded_libcompress
			, "Encoded result does not match libcompress")
		AssertLongStringEqual(encode_decode_table:Decode(encoded), str
			, "Encoded str cant be decoded to origin")
	end

	local encoded_addon = LibDeflate:EncodeForWoWAddonChannel(str)
	local encoded_addon_libcompress =
		_libcompress_addon_codec:Encode(str)
	AssertLongStringEqual(encoded_addon, encoded_addon_libcompress
		, "Encoded addon channel result does not match libcompress")
	AssertLongStringEqual(LibDeflate:DecodeForWoWAddonChannel(encoded_addon)
		, str, "Encoded for addon channel str cant be decoded to origin")

	local encoded_chat = LibDeflate:EncodeForWoWChatChannel(str)
	local encoded_chat_libcompress = _libcompress_chat_codec:Encode(str)
	AssertLongStringEqual(encoded_chat, encoded_chat_libcompress
		, "Encoded chat channel result does not match libcompress")
	AssertLongStringEqual(LibDeflate:DecodeForWoWChatChannel(encoded_chat), str
		, "Encoded for chat channel str cant be decoded to origin")
end

--------------------------------------------------------------
-- Actual Tests Start ----------------------------------------
--------------------------------------------------------------
TestBasicStrings = {}
	function TestBasicStrings:TestEmpty()
		CheckCompressAndDecompressString("", "all")
	end
	function TestBasicStrings:TestAllLiterals1()
		CheckCompressAndDecompressString("ab", "all")
	end
	function TestBasicStrings:TestAllLiterals2()
		CheckCompressAndDecompressString("abcdefgh", "all")
	end
	function TestBasicStrings:TestAllLiterals3()
		local t = {}
		for i=0, 255 do
			t[#t+1] = string.char(i)
		end
		local str = table.concat(t)
		CheckCompressAndDecompressString(str, "all")
	end

	function TestBasicStrings:TestRepeat()
		CheckCompressAndDecompressString("aaaaaaaaaaaaaaaaaa", "all")
	end

	function TestBasicStrings:TestLongRepeat()
		local repeated = {}
		for i=1, 100000 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end

TestMyData = {}
	function TestMyData:TestItemStrings()
		CheckCompressAndDecompressFile("tests/data/itemStrings.txt", "all")
	end

	function TestMyData:TestSmallTest()
		CheckCompressAndDecompressFile("tests/data/smalltest.txt", "all")
	end

	function TestMyData:TestReconnectData()
		CheckCompressAndDecompressFile("tests/data/reconnectData.txt", "all")
	end

TestThirdPartySmall = {}
	function TestThirdPartySmall:TestEmpty()
		CheckCompressAndDecompressFile("tests/data/3rdparty/empty", "all")
	end

	function TestThirdPartySmall:TestX()
		CheckCompressAndDecompressFile("tests/data/3rdparty/x", "all")
	end

	function TestThirdPartySmall:TestXYZZY()
		CheckCompressAndDecompressFile("tests/data/3rdparty/xyzzy", "all")
	end

TestThirdPartyMedium = {}
	function TestThirdPartyMedium:Test10x10y()
		CheckCompressAndDecompressFile("tests/data/3rdparty/10x10y", "all")
	end

	function TestThirdPartyMedium:TestQuickFox()
		CheckCompressAndDecompressFile("tests/data/3rdparty/quickfox", "all")
	end

	function TestThirdPartyMedium:Test64x()
		CheckCompressAndDecompressFile("tests/data/3rdparty/64x", "all")
	end

	function TestThirdPartyMedium:TestUkkonoona()
		CheckCompressAndDecompressFile("tests/data/3rdparty/ukkonooa", "all")
	end

	function TestThirdPartyMedium:TestMonkey()
		CheckCompressAndDecompressFile("tests/data/3rdparty/monkey", "all")
	end

	function TestThirdPartyMedium:TestRandomChunks()
		CheckCompressAndDecompressFile("tests/data/3rdparty/random_chunks"
			, "all")
	end

	function TestThirdPartyMedium:TestGrammerLsp()
		CheckCompressAndDecompressFile("tests/data/3rdparty/grammar.lsp"
			, "all")
	end

	function TestThirdPartyMedium:TestXargs1()
		CheckCompressAndDecompressFile("tests/data/3rdparty/xargs.1", "all")
	end

	function TestThirdPartyMedium:TestRandomOrg10KBin()
		CheckCompressAndDecompressFile("tests/data/3rdparty/random_org_10k.bin"
			, "all")
	end

	function TestThirdPartyMedium:TestCpHtml()
		CheckCompressAndDecompressFile("tests/data/3rdparty/cp.html", "all")
	end

	function TestThirdPartyMedium:TestBadData1Snappy()
		CheckCompressAndDecompressFile("tests/data/3rdparty/baddata1.snappy"
			, "all")
	end

	function TestThirdPartyMedium:TestBadData2Snappy()
		CheckCompressAndDecompressFile("tests/data/3rdparty/baddata2.snappy"
			, "all")
	end

	function TestThirdPartyMedium:TestBadData3Snappy()
		CheckCompressAndDecompressFile("tests/data/3rdparty/baddata3.snappy"
			, "all")
	end

	function TestThirdPartyMedium:TestSum()
		CheckCompressAndDecompressFile("tests/data/3rdparty/sum", "all")
	end

Test_64K = {}
	function Test_64K:Test64KFile()
		CheckCompressAndDecompressFile("tests/data/64k.txt", "all")
	end
	function Test_64K:Test64KFilePlus1()
		CheckCompressAndDecompressFile("tests/data/64kplus1.txt", "all")
	end
	function Test_64K:Test64KFilePlus2()
		CheckCompressAndDecompressFile("tests/data/64kplus2.txt", "all")
	end
	function Test_64K:Test64KFilePlus3()
		CheckCompressAndDecompressFile("tests/data/64kplus3.txt", "all")
	end
	function Test_64K:Test64KFilePlus4()
		CheckCompressAndDecompressFile("tests/data/64kplus4.txt", "all")
	end
	function Test_64K:Test64KFileMinus1()
		CheckCompressAndDecompressFile("tests/data/64kminus1.txt", "all")
	end
	function Test_64K:Test64KRepeated()
		local repeated = {}
		for i=1, 65536 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test_64K:Test64KRepeatedPlus1()
		local repeated = {}
		for i=1, 65536+1 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test_64K:Test64KRepeatedPlus2()
		local repeated = {}
		for i=1, 65536+2 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test_64K:Test64KRepeatedPlus3()
		local repeated = {}
		for i=1, 65536+3 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test_64K:Test64KRepeatedPlus4()
		local repeated = {}
		for i=1, 65536+4 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test_64K:Test64KRepeatedMinus1()
		local repeated = {}
		for i=1, 65536-1 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test_64K:Test64KRepeatedMinus2()
		local repeated = {}
		for i=1, 65536-2 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end

-- > 64K
TestThirdPartyBig = {}
	function TestThirdPartyBig:TestBackward65536()
		CheckCompressAndDecompressFile("tests/data/3rdparty/backward65536"
			, "all")
	end
	function TestThirdPartyBig:TestHTML()
		CheckCompressAndDecompressFile("tests/data/3rdparty/html"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestPaper100kPdf()
		CheckCompressAndDecompressFile("tests/data/3rdparty/paper-100k.pdf"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestGeoProtodata()
		CheckCompressAndDecompressFile("tests/data/3rdparty/geo.protodata"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestFireworksJpeg()
		CheckCompressAndDecompressFile("tests/data/3rdparty/fireworks.jpeg"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestAsyoulik()
		CheckCompressAndDecompressFile("tests/data/3rdparty/asyoulik.txt"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestCompressedRepeated()
		CheckCompressAndDecompressFile(
			"tests/data/3rdparty/compressed_repeated", {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestAlice29()
		CheckCompressAndDecompressFile("tests/data/3rdparty/alice29.txt"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestQuickfox_repeated()
		CheckCompressAndDecompressFile("tests/data/3rdparty/quickfox_repeated"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestKppknGtb()
		CheckCompressAndDecompressFile("tests/data/3rdparty/kppkn.gtb"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestZeros()
		CheckCompressAndDecompressFile("tests/data/3rdparty/zeros"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestMapsdatazrh()
		CheckCompressAndDecompressFile("tests/data/3rdparty/mapsdatazrh"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestHtml_x_4()
		CheckCompressAndDecompressFile("tests/data/3rdparty/html_x_4"
			, {0,1,2,3,4})
	end
	function TestThirdPartyBig:TestLcet10()
		CheckCompressAndDecompressFile("tests/data/3rdparty/lcet10.txt"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestPlrabn12()
		CheckCompressAndDecompressFile("tests/data/3rdparty/plrabn12.txt"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:TestUrls10K()
		CheckCompressAndDecompressFile("tests/data/3rdparty/urls.10K"
			, {0,1,2,3,4,5})
	end
	function TestThirdPartyBig:Testptt5()
		CheckCompressAndDecompressFile("tests/data/3rdparty/ptt5"
			, {0,1,2,3,4})
	end
	function TestThirdPartyBig:TestKennedyXls()
		CheckCompressAndDecompressFile("tests/data/3rdparty/kennedy.xls"
			, {0,1,2,3,4})
	end

TestWoWData = {}
	function TestWoWData:TestWarlockWeakAuras()
		CheckCompressAndDecompressFile("tests/data/warlockWeakAuras.txt"
			, {0,1,2,3,4})
	end
	function TestWoWData:TestTotalRp3Data()
		CheckCompressAndDecompressFile("tests/data/totalrp3.txt"
			, {0,1,2,3,4})
	end

TestDecompress = {}
	-- Test from puff
	function TestDecompress:TestStoreEmpty()
		CheckDecompressIncludingError("\001\000\000\255\255", "")
	end
	function TestDecompress:TestStore1()
		CheckDecompressIncludingError("\001\001\000\254\255\010", "\010")
	end
	function TestDecompress:TestStore2()
		local t = {}
		for i=1, 65535 do
			t[i] = "a"
		end
		local str = table.concat(t)
		CheckDecompressIncludingError("\001\255\255\000\000"..str, str)
	end
	function TestDecompress:TestStore3()
		local t = {}
		for i=1, 65535 do
			t[i] = "a"
		end
		local str = table.concat(t)
		CheckDecompressIncludingError("\000\255\255\000\000"..str
			.."\001\255\255\000\000"..str, str..str)
	end
	function TestDecompress:TestStore4()
		-- 0101 00fe ff31
		CheckDecompressIncludingError("\001\001\000\254\255\049", "1")
	end
	function TestDecompress:TestStore5()
		local size = 0x5555
		local str = GetLimitedRandomString(size)
		CheckDecompressIncludingError("\001\085\085\170\170"..str, str)
	end

	function TestDecompress:TestStoreRandom()
		for _ = 1, 20 do
			local size = math.random(1, 65535)
			local str = GetLimitedRandomString(size)
			CheckDecompressIncludingError("\001"..string.char(size%256)
				..string.char((size-size%256)/256)
				..string.char(255-size%256)
				..string.char(255-(size-size%256)/256)..str, str)
		end
	end
	function TestDecompress:TestFix1()
		CheckDecompressIncludingError("\003\000", "")
	end
	function TestDecompress:TestFix2()
		CheckDecompressIncludingError("\051\004\000", "1")
	end
	function TestDecompress:TestFixThenStore1()
		local t = {}
		for i=1, 65535 do
			t[i] = "a"
		end
		local str = table.concat(t)
		CheckDecompressIncludingError("\050\004\000\255\255\000\000"
			..str.."\001\255\255\000\000"..str, "1"..str..str)
	end
	function TestDecompress:TestIncomplete()
		-- Additonal 1 byte after the end of compression data
		CheckDecompressIncludingError("\001\001\000\254\255\010\000", "\010")
	end
	function TestDecompress:TestStoreSizeTooBig()
		CheckDecompressIncludingError("\001\001\000\254\255", nil)
		CheckDecompressIncludingError("\001\002\000\253\255\001", nil)
	end
	function TestDecompress:TestEmtpy()
		CheckDecompressIncludingError("", nil)
	end
	function TestDecompress:TestOneByte()
		for i=0, 255 do
			CheckDecompressIncludingError(string.char(i), nil)
		end
	end
	function TestDecompress:TestPuffReturn2()
		CheckDecompressIncludingError("\000", nil)
		CheckDecompressIncludingError("\002", nil)
		CheckDecompressIncludingError("\004", nil)
		CheckDecompressIncludingError(HexToString("00 01 00 fe ff"), nil)
		CheckDecompressIncludingError(
			HexToString("04 80 49 92 24 49 92 24 0f b4 ff ff c3 04"), nil)
	end
	function TestDecompress:TestPuffReturn245()
		CheckDecompressIncludingError(HexToString(
			"0c c0 81 00 00 00 00 00 90 ff 6b 04"), nil)
	end
	function TestDecompress:TestPuffReturn246()
		CheckDecompressIncludingError(HexToString("1a 07"), nil)
		CheckDecompressIncludingError(HexToString("02 7e ff ff"), nil)
		CheckDecompressIncludingError(HexToString(
			"04 c0 81 08 00 00 00 00 20 7f eb 0b 00 00"), nil)
	end
	function TestDecompress:TestPuffReturn247()
		CheckDecompressIncludingError(HexToString(
			"04 00 24 e9 ff 6d"), nil)
	end
	function TestDecompress:TestPuffReturn248()
		CheckDecompressIncludingError(HexToString(
			"04 80 49 92 24 49 92 24 0f b4 ff ff c3 84"), nil)
	end
	function TestDecompress:TestPuffReturn249()
		CheckDecompressIncludingError(HexToString(
			"04 80 49 92 24 49 92 24 71 ff ff 93 11 00"), nil)
	end
	function TestDecompress:TestPuffReturn250()
		CheckDecompressIncludingError(HexToString(
			"04 00 24 e9 ff ff"), nil)
	end
	function TestDecompress:TestPuffReturn251()
		CheckDecompressIncludingError(HexToString("04 00 24 49"), nil)
	end
	function TestDecompress:TestPuffReturn252()
		CheckDecompressIncludingError(HexToString("04 00 fe ff"), nil)
	end
	function TestDecompress:TestPuffReturn253()
		CheckDecompressIncludingError(HexToString("fc 00 00"), nil)
	end
	function TestDecompress:TestPuffReturn254()
		CheckDecompressIncludingError(HexToString("00 00 00 00 00"), nil)
	end
	function TestDecompress:TestZlibCoverSupport()
		CheckDecompressIncludingError(HexToString("63 00"), nil)
		CheckDecompressIncludingError(HexToString("63 18 05"), nil)
		CheckDecompressIncludingError(
			HexToString("63 18 68 30 d0 0 0"), ("\000"):rep(257))
		CheckDecompressIncludingError(HexToString("3 00"), "")
		CheckDecompressIncludingError("", nil)
		CheckDecompressIncludingError("", nil, true)
	end
	function TestDecompress:TestZlibCoverWrap()
		CheckZlibDecompressIncludingError(
			HexToString("77 85"), nil) -- Bad zlib header
		CheckZlibDecompressIncludingError(
			HexToString("70 85"), nil) -- Bad zlib header
		CheckZlibDecompressIncludingError(
			HexToString("88 9c"), nil) -- Bad window size
		CheckZlibDecompressIncludingError(
			HexToString("f8 9c"), nil) -- Bad window size
		CheckZlibDecompressIncludingError(
			HexToString("78 90"), nil) -- Bad zlib header check
		CheckZlibDecompressIncludingError(
			HexToString("78 9c 63 00 00 00 01 00 01"), "\000") -- check Adler32
		CheckZlibDecompressIncludingError(
			HexToString("78 9c 63 00 00 00 01 00"), nil) -- Adler32 incomplete
		CheckZlibDecompressIncludingError(
			HexToString("78 9c 63 00 00 00 01 00 02"), nil) -- wrong Adler32
		CheckZlibDecompressIncludingError(
			HexToString("78 9c 63 0"), nil) -- no Adler32
	end
	function TestDecompress:TestZlibCoverInflate()
		CheckDecompressIncludingError(
			HexToString("0 0 0 0 0"), nil) -- invalid store block length
		CheckDecompressIncludingError(
			HexToString("3 0"), "", nil) -- Fixed block
		CheckDecompressIncludingError(
			HexToString("6"), nil) -- Invalid block type
		CheckDecompressIncludingError(
			HexToString("1 1 0 fe ff 0"), "\000") -- Stored block
		CheckDecompressIncludingError(
			HexToString("fc 0 0"), nil) -- Too many length or distance symbols
		CheckDecompressIncludingError(
			HexToString("4 0 fe ff"), nil) -- Invalid code lengths set
		CheckDecompressIncludingError(
			HexToString("4 0 24 49 0"), nil) -- Invalid bit length repeat
		CheckDecompressIncludingError(
			HexToString("4 0 24 e9 ff ff"), nil) -- Invalid bit length repeat
		-- Invalid code: missing end of block
		CheckDecompressIncludingError(
			HexToString("4 0 24 e9 ff 6d"), nil)
		-- Invalid literal/lengths set
		CheckDecompressIncludingError(
			HexToString("4 80 49 92 24 49 92 24 71 ff ff 93 11 0"), nil)
		CheckDecompressIncludingError(
			HexToString("4 80 49 92 24 49 92 24 71 ff ff 93 11 0"), nil)
		-- Invalid distance set
		CheckDecompressIncludingError(
			HexToString("4 80 49 92 24 49 92 24 f b4 ff ff c3 84"), nil)
		-- Invalid literal/length code
		CheckDecompressIncludingError(
			HexToString("4 c0 81 8 0 0 0 0 20 7f eb b 0 0"), nil)
		CheckDecompressIncludingError(
			HexToString("2 7e ff ff"), nil) -- Invalid distance code
		-- Invalid distance too far
		CheckDecompressIncludingError(
			HexToString("c c0 81 0 0 0 0 0 90 ff 6b 4 0"), nil)
		-- incorrect data check
		CheckDecompressIncludingError(
			HexToString("1f 8b 8 0 0 0 0 0 0 0 3 0 0 0 0 1"), nil)
		-- incorrect length check
		CheckDecompressIncludingError(
			HexToString("1f 8b 8 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 1"), nil)
		-- pull 17
		CheckDecompressIncludingError(
			HexToString("5 c0 21 d 0 0 0 80 b0 fe 6d 2f 91 6c"), "")
		-- long code
		CheckDecompressIncludingError(
		HexToString(
		"05 e0 81 91 24 cb b2 2c 49 e2 0f 2e 8b 9a 47 56 9f fb fe ec d2 ff 1f")
		, "")
		-- extra length
		CheckDecompressIncludingError(
			HexToString("ed c0 1 1 0 0 0 40 20 ff 57 1b 42 2c 4f")
			, ("\000"):rep(516))
		-- long distance and extra
		CheckDecompressIncludingError(
		HexToString(
		"ed cf c1 b1 2c 47 10 c4 30 fa 6f 35 1d 1 82 59 3d fb be 2e 2a fc f c")
			, ("\000"):rep(518))
		-- Window end
		CheckDecompressIncludingError(
		HexToString(
		"ed c0 81 0 0 0 0 80 a0 fd a9 17 a9 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0")
			, nil)
		-- inflate_fast TYPE return
		CheckDecompressIncludingError(HexToString("2 8 20 80 0 3 0"), "")
		-- Window wrap
		CheckDecompressIncludingError(HexToString("63 18 5 40 c 0")
			, ("\000"):rep(262))
	end
	function TestDecompress:TestZlibCoverFast()
		-- fast length extra bits
		CheckDecompressIncludingError(
		HexToString(
		"e5 e0 81 ad 6d cb b2 2c c9 01 1e 59 63 ae 7d ee fb 4d fd b5 35 41 68")
		, nil)
		-- fast distance extra bits
		CheckDecompressIncludingError(
		HexToString(
		"25 fd 81 b5 6d 59 b6 6a 49 ea af 35 6 34 eb 8c b9 f6 b9 1e ef 67 49"
		, nil))
		 -- Fast invalid distance code
		CheckDecompressIncludingError(HexToString("3 7e 0 0 0 0 0"), nil)
		-- Fast literal/length code
		CheckDecompressIncludingError(HexToString("1b 7 0 0 0 0 0"), nil)
		-- fast 2nd level codes and too far back
		CheckDecompressIncludingError(
		HexToString(
		"d c7 1 ae eb 38 c 4 41 a0 87 72 de df fb 1f b8 36 b1 38 5d ff ff 0")
		, nil)
		-- Very common case
		CheckDecompressIncludingError(
			HexToString("63 18 5 8c 10 8 0 0 0 0")
			, ("\000"):rep(258)..("\000\001"):rep(4))
		-- Continous and wrap aroudn window
		CheckDecompressIncludingError(
			HexToString("63 60 60 18 c9 0 8 18 18 18 26 c0 28 0 29 0 0 0")
			, ("\000"):rep(261)..("\144")..("\000"):rep(6)..("\144\000"))
		-- Copy direct from output
		CheckDecompressIncludingError(
			HexToString("63 0 3 0 0 0 0 0"), ("\000"):rep(6))
	end
	function TestDecompress:TestAdditionalCoverage()
		-- no zlib FLG
		CheckZlibDecompressIncludingError(HexToString("78"), nil)
		-- Stored block no len
		CheckDecompressIncludingError(HexToString("1"), nil)
		-- Stored block no len comp
		CheckDecompressIncludingError(HexToString("1 1 0"), nil)
		-- Stored block not one's complement
		CheckDecompressIncludingError(HexToString("1 1 0 ff ff 0"), nil)
		-- Stored block not one's complement
		CheckDecompressIncludingError(HexToString("1 1 0 fe fe 0"), nil)
		CheckDecompressIncludingError(
			HexToString("1 34 43 cb bc")..("\000"):rep(17204)
			, ("\000"):rep(17204)) -- Stored block
		-- Stored block with 1 less byte
		CheckDecompressIncludingError(
			HexToString("1 34 43 cb bc")..("\000"):rep(17203), nil)
		CheckDecompressIncludingError(
			HexToString("1 34 43 cb bc")..("\000"):rep(17202), nil)
	end

	function TestDecompress:Test2ndReturn()
		for _ = 1, 10 do
			local str = GetLimitedRandomString(math.random(100, 300))
			local compressed = LibDeflate:CompressDeflate(str)
			local extra_len = math.random(1, 10)
			local extra = GetLimitedRandomString(extra_len)
			compressed = compressed..extra
			local decompressed, unprocessed =
				LibDeflate:DecompressDeflate(compressed)
			AssertLongStringEqual(str, decompressed)
			lu.assertEquals(unprocessed, extra_len)
		end
		for _ = 1, 10 do
			local dict = CreateDictionaryWithoutVerify(
				GetLimitedRandomString(math.random(100, 300)))
			local str = GetLimitedRandomString(math.random(100, 300))
			local compressed = LibDeflate:CompressDeflateWithDict(str, dict)
			local extra_len = math.random(1, 10)
			local extra = GetLimitedRandomString(extra_len)
			compressed = compressed..extra
			local decompressed, unprocessed =
				LibDeflate:DecompressDeflateWithDict(compressed, dict)
			AssertLongStringEqual(str, decompressed)
			lu.assertEquals(unprocessed, extra_len)
		end
		for _ = 1, 10 do
			local str = GetLimitedRandomString(math.random(100, 300))
			local compressed = LibDeflate:CompressZlib(str)
			local extra_len = math.random(1, 10)
			local extra = GetLimitedRandomString(extra_len)
			compressed = compressed..extra
			local decompressed, unprocessed =
				LibDeflate:DecompressZlib(compressed)
			AssertLongStringEqual(str, decompressed)
			lu.assertEquals(unprocessed, extra_len)
		end
		for _ = 1, 10 do
			local dict = CreateDictionaryWithoutVerify(
				GetLimitedRandomString(math.random(100, 300)))
			local str = GetLimitedRandomString(math.random(100, 300))
			local compressed = LibDeflate:CompressZlibWithDict(str, dict)
			local extra_len = math.random(1, 10)
			local extra = GetLimitedRandomString(extra_len)
			compressed = compressed..extra
			local decompressed, unprocessed =
				LibDeflate:DecompressZlibWithDict(compressed, dict)
			AssertLongStringEqual(str, decompressed)
			lu.assertEquals(unprocessed, extra_len)
		end
	end

	function TestDecompress:TestDecompressWithDict()
		local dict = CreateDictionaryWithoutVerify("abcdefgh")
		-- local adler32 = LibDeflate:Adler32("abcdefgh")
		-- adler == 0x0e000325
		lu.assertEquals(LibDeflate:DecompressZlib(
			HexToString("78 9c 63 00 00 00 01 00 01")), "\000")
		-- The data needs dictionary, but calling
		-- DecompressZlib instead of DecompressZlibWithDict
		lu.assertEquals(LibDeflate:DecompressZlib(
			HexToString("78 bb 63 00 00 00 01 00 01")), nil)
		lu.assertEquals(LibDeflate:DecompressZlib(
			HexToString("78 bb 25 03 00 0e 63 00 00 00 01 00 01")), nil)
		lu.assertEquals(LibDeflate:DecompressZlibWithDict(
			HexToString("78 bb 0e 00 03 25 63 00 00 00 01 00 01"), dict)
			, "\000")

		-- input ends before dictionary adler32 is read.
		lu.assertEquals(LibDeflate:DecompressZlibWithDict(
			HexToString("78 bb 0e 00 03 "), dict)
			, nil)
		lu.assertEquals(LibDeflate:DecompressZlibWithDict(
			HexToString("78 bb 0e 00 "), dict)
			, nil)
		lu.assertEquals(LibDeflate:DecompressZlibWithDict(
			HexToString("78 bb 0e "), dict)
			, nil)
		lu.assertEquals(LibDeflate:DecompressZlibWithDict(
			HexToString("78 bb "), dict)
			, nil)

		-- adler32 does not match
		lu.assertEquals(LibDeflate:DecompressZlibWithDict(
			HexToString("78 bb 25 03 00 0e 63 00 00 00 01 00 01"), dict)
			, nil)
		lu.assertEquals(LibDeflate:DecompressZlibWithDict(
			HexToString("78 bb 0e 00 03 26 63 00 00 00 01 00 01"), dict)
			, nil)
	end

TestInternals = {}
	-- Test from puff
	function TestInternals:TestLoadString()
		local LoadStringToTable = LibDeflate.internals.LoadStringToTable
		local tmp
		for _=1, 50 do
			local t = {}
			local strlen = math.random(0, 1000)
			local str = GetLimitedRandomString(strlen)
			local uncorruped_data = {}
			for i=1, strlen do
				uncorruped_data[i] = math.random(1, 12345)
				t[i] = uncorruped_data[i]
			end
			local start
			local stop
			if strlen >= 1 then
				start = math.random(1, strlen)
				stop = math.random(1, strlen)
			else
				start = 1
				stop = 0
			end
			if start > stop then
				tmp = start
				start = stop
				stop = tmp
			end
			local offset = math.random(0, strlen)
			LoadStringToTable(str, t, start, stop, offset)
			for i=-1000, 2000 do
				if i < start-offset or i > stop-offset then
					lu.assertEquals(t[i], uncorruped_data[i]
						, "loadStr corrupts unintended location")
				else
					lu.assertEquals(t[i], string_byte(str, i+offset)
					, ("loadStr gives wrong data!, start=%d, stop=%d, i=%d")
						:format(start, stop, i))
				end
			end
		end
	end

	function TestInternals:TestSimpleRandom()
		for _=1, 30 do
			local strlen = math.random(0, 1000)
			local str = GetLimitedRandomString(strlen)
			local level = (math.random() < 0.5) and (math.random(1, 8)) or nil
			local expected = str
			local configs = {level = level}
			local compress = LibDeflate:CompressDeflate(str, configs)
			local _, actual = pcall(function() return LibDeflate
				:DecompressDeflate(compress) end)
			if expected ~= actual then
				local strDumpFile = io.open("fail_random.tmp", "wb")
				if (strDumpFile) then
					strDumpFile:write(str)
					print(("Failed test has been dumped to fail_random.tmp,"
						.. "with level=%s"):
						format(tostring(level)))
					strDumpFile:close()
					if type(actual) == "string" then
						print(("Error msg is:\n"), actual:sub(1, 100))
					end
				end
				lu.assertEquals(false, "My decompress does not match origin.")
			end
		end
	end

	function TestInternals:TestAdler32()
		lu.assertEquals(LibDeflate:Adler32(""), 1)
		lu.assertEquals(LibDeflate:Adler32("1"), 0x00320032)
		lu.assertEquals(LibDeflate:Adler32("12"), 0x00960064)
		lu.assertEquals(LibDeflate:Adler32("123"), 0x012D0097)
		lu.assertEquals(LibDeflate:Adler32("1234"), 0x01F800CB)
		lu.assertEquals(LibDeflate:Adler32("12345"), 0x02F80100)
		lu.assertEquals(LibDeflate:Adler32("123456"), 0x042E0136)
		lu.assertEquals(LibDeflate:Adler32("1234567"), 0x059B016D)
		lu.assertEquals(LibDeflate:Adler32("12345678"), 0x074001A5)
		lu.assertEquals(LibDeflate:Adler32("123456789"), 0x091E01DE)
		lu.assertEquals(LibDeflate:Adler32("1234567890"), 0x0B2C020E)
		lu.assertEquals(LibDeflate:Adler32("1234567890a"), 0x0D9B026F)
		lu.assertEquals(LibDeflate:Adler32("1234567890ab"), 0x106C02D1)
		lu.assertEquals(LibDeflate:Adler32("1234567890abc"), 0x13A00334)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcd"), 0x17380398)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcde"), 0x1B3503FD)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcdef"), 0x1F980463)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefg"), 0x1F9E0466)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefgh"), 0x246C04CE)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefghi"), 0x29A30537)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefghij"), 0x2F4405A1)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefghijk"), 0x3550060C)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefghijkl")
			, 0x3BC80678)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefghijklm")
			, 0x42AD06E5)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefghijklmn")
			, 0x4A000753)
		lu.assertEquals(LibDeflate:Adler32(
			"1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
			, 0x8C40150C)
		local adler32Test = GetFileData("tests/data/adler32Test.txt")
		lu.assertEquals(LibDeflate:Adler32(adler32Test), 0x5D9BAF5D)
		local adler32Test2 = GetFileData("tests/data/adler32Test2.txt")
		lu.assertEquals(LibDeflate:Adler32(adler32Test2), 0xD6A07E29)
	end

	function TestInternals:TestLibStub()
		-- Start of LibStub
		local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2
		-- NOTE: It is intended that LibStub is global
		LibStub = _G[LIBSTUB_MAJOR]

		if not LibStub or LibStub.minor < LIBSTUB_MINOR then
			LibStub = LibStub or {libs = {}, minors = {} }
			_G[LIBSTUB_MAJOR] = LibStub
			LibStub.minor = LIBSTUB_MINOR
			function LibStub:NewLibrary(major, minor)
				assert(type(major) ==
					"string"
					, "Bad argument #2 to `NewLibrary' (string expected)")
				minor = assert(tonumber(string.match(minor, "%d+"))
				, "Minor version must either be a number or contain a number.")

				local oldminor = self.minors[major]
				if oldminor and oldminor >= minor then return nil end
				self.minors[major], self.libs[major] =
					minor, self.libs[major] or {}
				return self.libs[major], oldminor
			end
			function LibStub:GetLibrary(major, silent)
				if not self.libs[major] and not silent then
					error(("Cannot find a library instance of %q.")
					:format(tostring(major)), 2)
				end
				return self.libs[major], self.minors[major]
			end
			function LibStub:IterateLibraries() return pairs(self.libs) end
			setmetatable(LibStub, { __call = LibStub.GetLibrary })
		end
		-- End of LibStub
		local LibStub = _G.LibStub
		lu.assertNotNil(LibStub, "LibStub not in global?")
		local MAJOR = "LibDeflate"
		CheckCompressAndDecompressString("aaabbbcccddddddcccbbbaaa", "all")
		lu.assertNotNil(package.loaded["LibDeflate"]
			, "LibDeflate is not loaded")
		package.loaded["LibDeflate"] = nil
		-- Not sure if luaconv can recognize code in dofile()
		-- let's just use require
		LibDeflate = require("LibDeflate")
		lu.assertNotNil(package.loaded["LibDeflate"]
			, "LibDeflate is not loaded")
		lu.assertNotNil(LibDeflate, "LibStub does not return LibDeflate")
		lu.assertEquals(LibStub:GetLibrary(MAJOR, true), LibDeflate
			, "Cant find LibDeflate in LibStub.")
		CheckCompressAndDecompressString("aaabbbcccddddddcccbbbaaa", "all")
		------------------------------------------------------
		FullMemoryCollect()
		local memory1 = math.floor(collectgarbage("collect")*1024)
		lu.assertNotNil(package.loaded["LibDeflate"]
			, "LibDeflate is not loaded")
		package.loaded["LibDeflate"] = nil
		-- Not sure if luaconv can recognize code in dofile()
		-- let's just use require
		local LibDeflateTmp = require("LibDeflate")
		lu.assertNotNil(package.loaded["LibDeflate"]
			, "LibDeflate is not loaded")
		lu.assertEquals(LibDeflateTmp, LibDeflate
			, "LibStub unexpectedly recreates the library.")
		lu.assertNotNil(LibDeflate, "LibStub does not return LibDeflate")
		lu.assertEquals(LibStub:GetLibrary(MAJOR, true), LibDeflate
			, "Cant find LibDeflate in LibStub.")
		CheckCompressAndDecompressString("aaabbbcccddddddcccbbbaaa", "all")
		FullMemoryCollect()
		local memory2 = math.floor(collectgarbage("collect")*1024)
		if not _G.jit then
			lu.assertTrue((memory2 - memory1 <= 32)
			, ("Too much Memory leak after LibStub without update: %d")
				:format(memory2-memory1))
		end
		----------------------------------------------------
		LibStub.minors[MAJOR] = -1000
		FullMemoryCollect()
		local memory3 = math.floor(collectgarbage("collect")*1024)
		lu.assertNotNil(package.loaded["LibDeflate"]
			, "LibDeflate is not loaded")
		package.loaded["LibDeflate"] = nil
		-- Not sure if luaconv can recognize code in dofile()
		-- let's just use require
		LibDeflateTmp = require("LibDeflate")
		lu.assertNotNil(package.loaded["LibDeflate"]
			, "LibDeflate is not loaded")
		CheckCompressAndDecompressString("aaabbbcccddddddcccbbbaaa", "all")
		FullMemoryCollect()
		local memory4 = math.floor(collectgarbage("collect")*1024)
		lu.assertEquals(LibDeflateTmp, LibDeflate
			, "LibStub unexpectedly recreates the library.")
		lu.assertTrue(LibStub.minors[MAJOR] > -1000
			, "LibDeflate is not updated.")
		if not _G.jit then
			lu.assertTrue((memory4 - memory3 <= 100)
				, ("Too much Memory leak after LibStub update: %d")
				:format(memory4-memory3))
		end
	end

	function TestInternals:TestByteTo6bitChar()
		local _byte_to_6bit_char = LibDeflate.internals._byte_to_6bit_char
		lu.assertNotNil(_byte_to_6bit_char)
		lu.assertEquals(GetTableSize(_byte_to_6bit_char), 64)
		for i= 0, 25 do
			lu.assertEquals(_byte_to_6bit_char[i],
				string.char(string.byte("a", 1) + i))
		end
		for i = 26, 51 do
			lu.assertEquals(_byte_to_6bit_char[i],
				string.char(string.byte("A", 1) + i - 26))
		end
		for i = 52, 61 do
			lu.assertEquals(_byte_to_6bit_char[i],
				string.char(string.byte("0", 1) + i - 52))
		end
		lu.assertEquals(_byte_to_6bit_char[62], "(")
		lu.assertEquals(_byte_to_6bit_char[63], ")")
	end

	function TestInternals:Test6BitToByte()
		local _6bit_to_byte = LibDeflate.internals._6bit_to_byte
		lu.assertNotNil(_6bit_to_byte)
		lu.assertEquals(GetTableSize(_6bit_to_byte), 64)
		for i = string.byte("a", 1), string.byte("z", 1) do
			lu.assertEquals(_6bit_to_byte[i], i - string.byte("a", 1))
		end
		for i = string.byte("A", 1), string.byte("Z", 1) do
			lu.assertEquals(_6bit_to_byte[i], i - string.byte("A", 1) + 26)
		end
		for i = string.byte("0", 1), string.byte("9", 1) do
			lu.assertEquals(_6bit_to_byte[i], i - string.byte("0", 1) + 52)
		end
		lu.assertEquals(_6bit_to_byte[string.byte("(", 1)], 62)
		lu.assertEquals(_6bit_to_byte[string.byte(")", 1)], 63)
	end

TestPresetDict = {}
	function TestPresetDict:TestExample()
		local dict_str = [[ilvl::::::::110:::1517:3336:3528:3337]]
		local dictionary = CreateAndCheckDictionary(dict_str)
		local fileData = GetFileData("tests/data/itemStrings.txt")
		CheckDictEffectiveness(fileData, dictionary, dict_str)
	end

	function TestPresetDict:TestEmptyString()
		for i=1, 16 do
			local dict_str = GetRandomString(i)
			local dictionary = CreateAndCheckDictionary(dict_str)
			CheckDictEffectiveness("", dictionary, dict_str, true)
		end
	end

	function TestPresetDict:TestCheckDictRandomComplete()
		for _ = 1, 10 do
			local dict_str = GetRandomStringUniqueChars(
				256+math.random(0, 1000))
			CreateAndCheckDictionary(dict_str)
		end
	end

	-- Test if last two bytes in the dictionary are hashed, with dict size 3.
	function TestPresetDict:TestLength3String1()
		for _ = 1, 10 do
			local dict_str = GetRandomStringUniqueChars(3)
			local dictionary = CreateAndCheckDictionary(dict_str)
			local str = dict_str
			local compress_dict =
				CheckDictEffectiveness(str, dictionary, dict_str)
			lu.assertTrue(compress_dict:len() <= 4)
		end
	end

	-- Test if last two bytes in the dictionary is hashed, with dict size 2
	function TestPresetDict:TestLength3String2()
		for _ = 1, 10 do
			local str = GetRandomStringUniqueChars(3)
			local dict_str = str:sub(1, 2)
			str = str:sub(3, 3)..str
			local dictionary = CreateAndCheckDictionary(dict_str)

			local compress_dict =
				CheckDictEffectiveness(str, dictionary, dict_str)
			lu.assertTrue(compress_dict:len() <= 5)
		end
	end

	-- Test if last two bytes in the dictionary is hashed, with dict size 1
	function TestPresetDict:TestLength3String3()
		for _ = 1, 10 do
			local str = GetRandomStringUniqueChars(3)
			local dict_str = str:sub(1, 1)
			str = str:sub(2, 3)..str
			local dictionary = CreateAndCheckDictionary(dict_str)

			local compress_dict =
				CheckDictEffectiveness(str, dictionary, dict_str)
			lu.assertTrue(compress_dict:len() <= 6)
		end
	end

	function TestPresetDict:TestLength257String()
		for _ = 1, 10 do
			local dict_str = GetRandomStringUniqueChars(257)
			local dictionary = CreateAndCheckDictionary(dict_str)
			local str = dict_str
			local compress_dict =
				CheckDictEffectiveness(str, dictionary, dict_str)
			lu.assertTrue(compress_dict:len() <= 5)
		end
	end

	function TestPresetDict:TestLength258String()
		for _ = 1, 10 do
			local dict_str = GetRandomStringUniqueChars(258)
			local dictionary = CreateAndCheckDictionary(dict_str)
			local str = dict_str
			local compress_dict =
				CheckDictEffectiveness(str, dictionary, dict_str)
			lu.assertTrue(compress_dict:len() <= 4)
		end
	end

	function TestPresetDict:TestLength259String()
		for _ = 1, 10 do
			local dict_str = GetRandomStringUniqueChars(259)
			local dictionary = CreateAndCheckDictionary(dict_str)
			local str = dict_str
			local compress_dict =
				CheckDictEffectiveness(str, dictionary, dict_str)
			lu.assertTrue(compress_dict:len() <= 5)
		end
	end

	function TestPresetDict:TestIsEqualAdler32()
		local IsEqualAdler32 = LibDeflate.internals.IsEqualAdler32
		lu.assertTrue(IsEqualAdler32(4072834167, -222133129))
		for _ = 1, 30 do
			local rand = math.random(0, 1000)
			lu.assertTrue(IsEqualAdler32(rand, rand))
			lu.assertTrue(IsEqualAdler32(rand+256*256*256*256, rand))
			lu.assertTrue(IsEqualAdler32(rand, rand+256*256*256*256))
			lu.assertTrue(IsEqualAdler32(rand-256*256*256*256, rand))
			lu.assertTrue(IsEqualAdler32(rand, rand-256*256*256*256))
			lu.assertTrue(IsEqualAdler32(rand+256*256*256*256
				, rand+256*256*256*256))
		end
	end

TestEncode = {}
	function TestEncode:TestBasic()
		CheckEncodeAndDecode("")
		for i=0, 255 do
			CheckEncodeAndDecode(string_char(i))
		end

	end

	function TestEncode:TestRandom()
		for _ = 0, 200 do
			local str = GetRandomStringUniqueChars(math.random(256, 1000))
			CheckEncodeAndDecode(str)
		end
	end

	-- Bug in LibCompress:GetEncodeTable()
	-- version LibCompress Revision 81
	-- Date: 2018-02-25 06:31:34 +0000 (Sun, 25 Feb 2018)
	function TestEncode:TestLibCompressEncodeBug()
		local reservedChars =
		"\132\109\114\143\11\32\153\92\230\66\131\127\87\106\89\142\55\228\56"
		.."\158\151\53\48\13\71\9\37\208\101\42\217\76\19\250\125\214\146\14"
		.."\215\204\249\223\165\45\222\120\161\65\28\144\196\12\43\116\242\179"
		.."\194\1\253\147\121\99\3\107\96\67\27\44\100\148\130\221\138\85\129"
		.."\166\185\246\239\50\218\94\157\90\81\134\80\175\186\79\122\93\190"
		.."\150\154\183\91\152\70\234\169\126\108\251\6\2\22\95\233\180\105"
		.."\119\38\229\171\29\192\219\21\241\74\207\159\117\247\72\237\110"
		.."\78\118"
		local escapedChars = "\145\54"
		for _ = 1, 10 do
			local str = GetRandomStringUniqueChars(1000)
			CheckEncodeAndDecode(str, reservedChars, escapedChars, "")
		end
	end
	function TestEncode:TestRandomComplete1()
		for _ = 0, 30 do
			local tmp = GetRandomStringUniqueChars(256)
			local reserved = tmp:sub(1, 10)
			local escaped = tmp:sub(11, 11)
			local mapped = tmp:sub(12, 12+math.random(0, 9))
			local str = GetRandomStringUniqueChars(math.random(256, 1000))
			CheckEncodeAndDecode(str, reserved, escaped, mapped)
		end
	end

	function TestEncode:TestRandomComplete2()
		for _ = 0, 30 do
			local tmp = GetRandomStringUniqueChars(256)
			local reserved = tmp:sub(1, 10)
			local escaped = tmp:sub(11, 11)
			local str = GetRandomStringUniqueChars(math.random(256, 1000))
			CheckEncodeAndDecode(str, reserved, escaped, "")
		end
	end

	function TestEncode:TestRandomComplete3()
		for _ = 0, 30 do
			local tmp = GetRandomStringUniqueChars(256)
			local reserved = tmp:sub(1, 130) -- Over half chractrs escaped
			local escaped = tmp:sub(131, 132) -- Two escape char needed.
			local mapped = tmp:sub(133, 133+math.random(0, 20))
			local str = GetRandomStringUniqueChars(math.random(256, 1000))
			CheckEncodeAndDecode(str, reserved, escaped, mapped)
		end
	end

	function TestEncode:TestRandomComplete4()
		for _ = 0, 30 do
			local tmp = GetRandomStringUniqueChars(256)
			local reserved = tmp:sub(1, 130) -- Over half chractrs escaped
			local escaped = tmp:sub(131, 132) -- Two escape char needed.
			local str = GetRandomStringUniqueChars(math.random(256, 1000))
			CheckEncodeAndDecode(str, reserved, escaped, "")
		end
	end

	local function CheckEncodeForPrint(str)
		AssertLongStringEqual(LibDeflate:DecodeForPrint(LibDeflate
			:EncodeForPrint(str))
			, str)
		-- test prefixed and trailig control characters or space.
		for _, byte in pairs({0, 1, 9, 10, 11, 12, 13, 31, 32, 127}) do
			local char = string.char(byte)
			AssertLongStringEqual(LibDeflate:DecodeForPrint(LibDeflate
				:EncodeForPrint(str)..char)
				, str)
			AssertLongStringEqual(LibDeflate:DecodeForPrint(LibDeflate
				:EncodeForPrint(str)..char..char)
				, str)
			AssertLongStringEqual(LibDeflate:DecodeForPrint(LibDeflate
				:EncodeForPrint(str)..char..char..char)
				, str)
			AssertLongStringEqual(LibDeflate:DecodeForPrint(char..LibDeflate
				:EncodeForPrint(str))
				, str)
			AssertLongStringEqual(LibDeflate:DecodeForPrint(char..char..
				LibDeflate:EncodeForPrint(str))
				, str)
		end

	end
	function TestEncode:TestEncodeForPrint()
		CheckEncodeForPrint("")
		for _ = 1, 100 do
			CheckEncodeForPrint(GetRandomStringUniqueChars(
				math.random(1, 10)))
		end
		for i = 0, 255 do
			CheckEncodeForPrint(string.char(i))
		end
		for _ = 1, 400 do
			CheckEncodeForPrint(GetRandomStringUniqueChars(
				math.random(100, 1000)))
		end
		local encode_6bit_weakaura =
			GetFileData("tests/data/reference/encode_6bit_weakaura.txt")
		local decode_6bit_weakaura =
			GetFileData("tests/data/reference/decode_6bit_weakaura.txt")
		AssertLongStringEqual(LibDeflate:EncodeForPrint(decode_6bit_weakaura)
			, encode_6bit_weakaura)
	end
	function TestEncode:TestDecodeForPrintErrors()
		for i = 0, 255 do
			if string.char(i):find("[%c ]") then
				lu.assertEquals(LibDeflate:DecodeForPrint(string.char(i)), "")
			else
				lu.assertNil(LibDeflate:DecodeForPrint(string.char(i)))
			end
		end
		for i = 0, 255 do
			if not LibDeflate.internals._6bit_to_byte[i] then
				lu.assertNil(LibDeflate:DecodeForPrint(("1"
					..string.char(i)):rep(100).."1"))
			end
		end
		-- Test multiple string lengths.
		for i = 0, 255 do
			for reps = 1, 16 do
				if not LibDeflate.internals._6bit_to_byte[i] then
					lu.assertNil(LibDeflate:DecodeForPrint("2"..(
						string.char(i)):rep(reps).."3"))
				end
			end
		end
	end

	function TestEncode:TestDecodeError()
		for _ = 0, 100 do
			local tmp = GetRandomStringUniqueChars(256)
			local reserved = tmp:sub(1, 10)
			local escaped = tmp:sub(11, 11)
			local str = GetRandomStringUniqueChars(math.random(256, 1000))
			local t = LibDeflate:CreateCodec(reserved, escaped, "")
			local encode_funcs = {
					{t.Encode, t},
					{LibDeflate.EncodeForWoWAddonChannel, LibDeflate},
					{LibDeflate.EncodeForWoWChatChannel, LibDeflate},
			}
			local decode_funcs = {
					{t.Decode, t},
					{LibDeflate.DecodeForWoWAddonChannel, LibDeflate},
					{LibDeflate.DecodeForWoWChatChannel, LibDeflate},
			}
			local reserved_chars = {
				reserved,
				"\000",
				"sS\000\010\013\124%",
			}
			for j, func in ipairs(encode_funcs) do
				local encoded = func[1](func[2], str)
				reserved = reserved_chars[j]
				local random = math.random(1, #reserved)
				local reserved_char = reserved:sub(random, random)
				random = math.random(1, #encoded)
				encoded = encoded:sub(1, random-1)
					..reserved_char..encoded:sub(random, #encoded)
				lu.assertNil(decode_funcs[j][1](decode_funcs[j][2], encoded))
			end
		end
	end
	function TestEncode:TestFailCreateCodec()
		local t, err
		t, err = LibDeflate:CreateCodec("1", "", "2")
		lu.assertNil(t)
		lu.assertEquals(err, "No escape characters supplied.")
		t, err = LibDeflate:CreateCodec("1", "a", "23")
		lu.assertNil(t)
		lu.assertEquals(err, "The number of reserved characters must be"
			.." at least as many as the number of mapped chars.")
		t, err = LibDeflate:CreateCodec("", "1", "")
		lu.assertNil(t)
		lu.assertEquals(err, "No characters to encode.")
		t, err = LibDeflate:CreateCodec("1", "2", "1")
		lu.assertNil(t)
		lu.assertEquals(err, "There must be no duplicate characters in the"
			.." concatenation of reserved_chars, escape_chars and"
			.." map_chars.")
		t, err = LibDeflate:CreateCodec("2", "1", "1")
		lu.assertNil(t)
		lu.assertEquals(err, "There must be no duplicate characters in the"
			.." concatenation of reserved_chars, escape_chars and"
			.." map_chars.")
		t, err = LibDeflate:CreateCodec("1", "1", "2")
		lu.assertNil(t)
		lu.assertEquals(err, "There must be no duplicate characters in the"
			.." concatenation of reserved_chars, escape_chars and"
			.." map_chars.")
		local r = {}
		for i = 128, 255 do
			r[#r+1] = string.char(i)
		end
		local reserved_chars = "sS\000\010\013\124%"..table_concat(r)
		t, err = LibDeflate:CreateCodec(reserved_chars, "\029"
			, "\015\020")
		lu.assertNil(t)
		lu.assertEquals(err, "Out of escape characters.")
		t, err = LibDeflate:CreateCodec(reserved_chars, "\029\031"
			, "\015\020")
		lu.assertIsTable(t)
		lu.assertNil(err)
	end

TestCompressStrategy = {}
	function TestCompressStrategy:TestHtml_x_4Fixed()
		CheckCompressAndDecompressFile("tests/data/3rdparty/html_x_4"
			, {0,1,3,4}, "fixed")
	end
	function TestCompressStrategy:TestHtml_x_4HuffmanOnly()
		CheckCompressAndDecompressFile("tests/data/3rdparty/html_x_4"
			, {0,1,3,4}, "huffman_only")
	end
	function TestCompressStrategy:TestHtml_x_4Dynamic()
		CheckCompressAndDecompressFile("tests/data/3rdparty/html_x_4"
			, {0,1,2,3,4}, "dynamic")
	end
	function TestCompressStrategy:TestAsyoulikFixed()
		CheckCompressAndDecompressFile("tests/data/3rdparty/asyoulik.txt"
			, {0,1,3,4}, "fixed")
	end
	function TestCompressStrategy:TestAsyoulikHuffmanOnly()
		CheckCompressAndDecompressFile("tests/data/3rdparty/asyoulik.txt"
			, {0,1,3,4}, "huffman_only")
	end
	function TestCompressStrategy:TestAsyoulikDynamic()
		CheckCompressAndDecompressFile("tests/data/3rdparty/asyoulik.txt"
			, {0,1,3,4}, "dynamic")
	end

	-- Some hard coded compresses length here.
	-- Modify if algorithm changes.
	-- (I don't think it will happen in the future though)
	function TestCompressStrategy:TestIsFixedStrategyInEffect()
		local str = ""
		for i=0, 255 do
			str = str..string.char(i)
		end
		for i=255, 0, -1 do
			str = str..string.char(i)
		end

		lu.assertEquals(
			LibDeflate:CompressDeflate(str):len(), 517)
		lu.assertEquals(
			GetFirstBlockType(
				LibDeflate:CompressDeflate(str, {strategy = "fixed"}), false)
			, 1)
		lu.assertEquals(
			LibDeflate:CompressDeflate(str, {strategy = "fixed"}):len()
			, 542)
		lu.assertEquals(
			GetFirstBlockType(
				LibDeflate:CompressZlib(str, {strategy = "fixed"}, true))
			, 1)
		lu.assertEquals(
			LibDeflate:CompressZlib(str, {strategy = "fixed"}):len()
			, 548)
	end
	function TestCompressStrategy:TestIsHuffmanOnlyStrategyInEffect()
		local str = ("a"):rep(1000)
		lu.assertEquals(
			LibDeflate:CompressDeflate(str):len()
			, 10)
		lu.assertEquals(
			LibDeflate:CompressDeflate(str, {strategy = "huffman_only"}):len()
			, 138)
		lu.assertEquals(
			LibDeflate:CompressZlib(str):len()
			,16)
		lu.assertEquals(
			LibDeflate:CompressZlib(str, {strategy = "huffman_only"}):len()
			, 144)
	end
	function TestCompressStrategy:TestIsDynamicStrategyInEffect()
		local str = ""
		for i=0, 255 do
			str = str..string.char(i)
		end
		for i=255, 0, -1 do
			str = str..string.char(i)
		end

		lu.assertEquals(
			LibDeflate:CompressDeflate(str):len(), 517)
		lu.assertEquals(
			GetFirstBlockType(
				LibDeflate:CompressDeflate(str, {strategy = "dynamic"}), false)
			, 2)
		lu.assertEquals(
			LibDeflate:CompressDeflate(str, {strategy = "dynamic"}):len()
			, 536)
		lu.assertEquals(
			GetFirstBlockType(
				LibDeflate:CompressZlib(str, {strategy = "dynamic"}, true))
			, 2)
		lu.assertEquals(
			LibDeflate:CompressZlib(str, {strategy = "dynamic"}):len()
			, 542)
	end

TestErrors = {}
	local function TestCorruptedDictionary(msg_prefix, func, dict)
		-- Test corrupted dictionary
		local backup = DeepCopy(dict)
		for i = 1, 100 do
			if i == 1 then
				dict = nil
			elseif i == 2 then
				dict.string_table = 1
			elseif i == 3 then
				dict.string_table = nil
			elseif i == 4 then
				dict.strlen = {}
			elseif i == 5 then
				dict.strlen = 32769
			elseif i == 6 then
				dict.string_table[#dict.string_table+1] = 97
			elseif i == 7 then
				dict.hash_tables = 1
			elseif i == 8 then
				dict.hash_tables = nil
			elseif i == 9 then
				dict.adler32 = nil
			else
				break
			end
			if i == 1 then
				lu.assertErrorMsgContains(
					msg_prefix
					.."'dictionary' - table expected got 'nil'."
					, function() return func(dict) end)
			else
				lu.assertErrorMsgContains(
					msg_prefix
					.."'dictionary' - corrupted dictionary."
					, function() return func(dict) end)
			end
			dict = backup
			backup = DeepCopy(dict)
			func(dict)
		end
	end

	-- arguments to "func": str, dictionary, configs
	local function TestInvalidCompressDecompressArgs(msg_prefix, func
		, check_dictionary, check_configs)
		lu.assertErrorMsgContains(
			msg_prefix
			.."'str' - string expected got 'nil'."
			, function() return func() end)
		lu.assertErrorMsgContains(
			msg_prefix
			.."'str' - string expected got 'table'."
			, function() return func({}) end)
		local str = GetRandomString(0, 5)
		local dict = CreateDictionaryWithoutVerify(
			GetRandomString(math.random(1, 32768)))
		if check_dictionary then
			TestCorruptedDictionary(msg_prefix,
				function(dict2) return func(str, dict2, {}) end, dict)
		else
			func(str, nil, {})
		end
		if check_configs then
			func(str, dict, nil)
			func(str, dict, {})
			lu.assertErrorMsgContains(
				(
				msg_prefix
				.."'configs' - nil or table expected got '%s'.")
				:format(type(1))
				, function() return func(str, dict, 1) end)
			for i = 0, 9 do
				func(str, dict, {level = i})
			end
			local strategies = {"fixed", "huffman_only", "dynamic"}
			for _, strategy in ipairs(strategies) do
				func(str, dict, {strategy = strategy})
				func(str, dict, {level = math.random(0, 9) -- NOTE: here
					, strategy = strategy})
			end
			lu.assertErrorMsgContains(
				msg_prefix
				.."'configs' - unsupported table key in the configs:"
				.." 'not_a_key'."
				, function() return func(str, dict, {not_a_key=1}) end)
			lu.assertErrorMsgContains(
				msg_prefix
				.."'configs' - unsupported 'level': 10."
				, function() return func(str, dict, {level=10}) end)
			lu.assertErrorMsgContains(
				msg_prefix
				.."'configs' - unsupported 'strategy': 'dne'."
				, function() return func(str, dict, {strategy="dne"}) end)
		else
			func(str, dict, 1)
		end
	end

	function TestErrors:TestAdler32()
		lu.assertErrorMsgContains("Usage: LibDeflate:Adler32(str): 'str'"
			.." - string expected got 'nil'."
			, function() LibDeflate:Adler32() end)
		lu.assertErrorMsgContains("Usage: LibDeflate:Adler32(str): 'str'"
			.." - string expected got 'table'."
			, function() LibDeflate:Adler32({}) end)
		LibDeflate:Adler32("") -- No error
	end
	function TestErrors:TestCreateDictionary()
		LibDeflate:CreateDictionary("1", 1, 0x00320032)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:CreateDictionary(str, strlen, adler32):"
			.." 'str' - string expected got 'nil'."
			, function() LibDeflate:CreateDictionary(nil, 1, 0x00320032) end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:CreateDictionary(str, strlen, adler32):"
			.." 'str' - string expected got 'table'."
			, function() LibDeflate:CreateDictionary({}, 1, 0x00320032) end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:CreateDictionary(str, strlen, adler32):"
			.." 'strlen' - number expected got 'nil'."
			, function() LibDeflate:CreateDictionary("1", nil, 0x00320032) end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:CreateDictionary(str, strlen, adler32):"
			.." 'adler32' - number expected got 'nil'."
			, function() LibDeflate:CreateDictionary("1", 1, nil) end)
		lu.assertEquals(LibDeflate:Adler32(""), 1)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:CreateDictionary(str, strlen, adler32):"
			.." 'str' - Empty string is not allowed."
			, function() LibDeflate:CreateDictionary("", 0, 1) end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:CreateDictionary(str, strlen, adler32):"
			.." 'str' - string longer than 32768 bytes is not allowed."
			 .." Got 32769 bytes."
			, function() LibDeflate:CreateDictionary(("\000"):rep(32769)
					, 32769, LibDeflate:Adler32(("\000"):rep(32769))) end)
				-- ^ Dont calculate Adler32 in run-time in real problem plz.
		LibDeflate:CreateDictionary(("\000"):rep(32768)
					, 32768, LibDeflate:Adler32(("\000"):rep(32768)))
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:CreateDictionary(str, strlen, adler32):"
			.." 'strlen' does not match the actual length of 'str'."
			.." 'strlen': 32767, '#str': 32768 ."
			.." Please check if 'str' is modified unintentionally."
			, function() LibDeflate:CreateDictionary(("\000"):rep(32768)
						, 32767, LibDeflate:Adler32(("\000"):rep(32768))) end)
		-- ^ Dont calculate Adler32 in run-time in real problem plz.
		lu.assertErrorMsgContains(
			("Usage: LibDeflate:CreateDictionary(str, strlen, adler32):"
				.." 'adler32' does not match the actual adler32 of 'str'."
				.." 'adler32': %u, 'Adler32(str)': %u ."
				.." Please check if 'str' is modified unintentionally.")
				:format(LibDeflate:Adler32(("\000"):rep(32768))+1
					, LibDeflate:Adler32(("\000"):rep(32768)))
			, function() LibDeflate:CreateDictionary(("\000"):rep(32768)
					, 32768, LibDeflate:Adler32(("\000"):rep(32768))+1) end)
	end
	function TestErrors:TestCompressDeflate()
		TestInvalidCompressDecompressArgs(
			"Usage: LibDeflate:CompressDeflate(str, configs): "
			, function(str, _, configs)
				return LibDeflate:CompressDeflate(str, configs) end
			, false, true)
	end
	function TestErrors:TestCompressDeflateWithDict()
		TestInvalidCompressDecompressArgs(
			"Usage: LibDeflate:CompressDeflateWithDict"
			.."(str, dictionary, configs): "
			, function(str, dictionary, configs)
				return LibDeflate:
					CompressDeflateWithDict(str, dictionary, configs) end
			, true, true)
	end
	function TestErrors:TestCompressZlib()
		TestInvalidCompressDecompressArgs(
			"Usage: LibDeflate:CompressZlib(str, configs): "
			, function(str, _, configs)
				return LibDeflate:CompressZlib(str, configs) end
			, false, true)
	end
	function TestErrors:TestCompressZlibWithDict()
		TestInvalidCompressDecompressArgs(
			"Usage: LibDeflate:CompressZlibWithDict"
			.."(str, dictionary, configs): "
			, function(str, dictionary, configs)
				return LibDeflate:
					CompressZlibWithDict(str, dictionary, configs) end
			, true, true)
	end
	function TestErrors:TestDecompressDeflate()
		TestInvalidCompressDecompressArgs(
			"Usage: LibDeflate:DecompressDeflate(str): "
			, function(str, _, _)
				return LibDeflate:DecompressDeflate(str) end
			, false, false)
	end
	function TestErrors:TestDecompressZlib()
		TestInvalidCompressDecompressArgs(
			"Usage: LibDeflate:DecompressZlib(str): "
			, function(str, _, _)
				return LibDeflate:DecompressZlib(str) end
			, false, false)
	end
	function TestErrors:TestDecompressDeflateWithDict()
		TestInvalidCompressDecompressArgs(
			"Usage: LibDeflate:DecompressDeflateWithDict(str, dictionary): "
			, function(str, dict, _)
				return LibDeflate:DecompressDeflateWithDict(str, dict) end
			, true, false)
	end
	function TestErrors:TestDecompressZlibWithDict()
		TestInvalidCompressDecompressArgs(
			"Usage: LibDeflate:DecompressZlibWithDict(str, dictionary): "
			, function(str, dict, _)
				return LibDeflate:DecompressZlibWithDict(str, dict) end
			, true, false)
	end
	function TestErrors:TestCreateCodec()
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:CreateCodec(reserved_chars,"
			.." escape_chars, map_chars):"
			.." All arguments must be string."
			, function()
				LibDeflate:CreateCodec(nil, "", "")
			end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:CreateCodec(reserved_chars,"
			.." escape_chars, map_chars):"
			.." All arguments must be string."
			, function()
				LibDeflate:CreateCodec("", nil, "")
			end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:CreateCodec(reserved_chars,"
			.." escape_chars, map_chars):"
			.." All arguments must be string."
			, function()
				LibDeflate:CreateCodec("", "", nil)
			end)
		local t, err = LibDeflate:CreateCodec("1", "2", "")
		lu.assertNil(err)
	end
	function TestErrors:TestEncodeDecode()
		local codec = LibDeflate:CreateCodec("\000", "\001", "")
		lu.assertErrorMsgContains(
			"Usage: codec:Encode(str):"
			.." 'str' - string expected got 'nil'."
			, function() codec:Encode() end)
		lu.assertErrorMsgContains(
			"Usage: codec:Decode(str):"
			.." 'str' - string expected got 'nil'."
			, function() codec:Decode() end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:EncodeForWoWAddonChannel(str):"
			.." 'str' - string expected got 'nil'."
			, function() LibDeflate:EncodeForWoWAddonChannel() end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:DecodeForWoWAddonChannel(str):"
			.." 'str' - string expected got 'nil'."
			, function() LibDeflate:DecodeForWoWAddonChannel() end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:EncodeForWoWChatChannel(str):"
			.." 'str' - string expected got 'nil'."
			, function() LibDeflate:EncodeForWoWChatChannel() end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:DecodeForWoWChatChannel(str):"
			.." 'str' - string expected got 'nil'."
			, function() LibDeflate:DecodeForWoWChatChannel() end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:EncodeForPrint(str):"
			.." 'str' - string expected got 'nil'."
			, function() LibDeflate:EncodeForPrint() end)
		lu.assertErrorMsgContains(
			"Usage: LibDeflate:DecodeForPrint(str):"
			.." 'str' - string expected got 'nil'."
			, function() LibDeflate:DecodeForPrint() end)
	end



local lua_program = "lua"
local function RunCommandline(args, stdin)
	local input_filename = "tests/test.stdin"
	if stdin then
		WriteToFile(input_filename, stdin)
	else
		WriteToFile(input_filename, "")
	end
	local stdout_filename = "tests/test.stderr"
	local stderr_filename = "tests/test.stdout"
	local libdeflate_file = "./LibDeflate.lua"
	if os.getenv("OS") and os.getenv("OS"):find("Windows") then
		libdeflate_file = "LibDeflate.lua"
	end
	local status, _, ret = os.execute(lua_program.." "..libdeflate_file.." "
		..args.." >"..input_filename
		.. "> "..stdout_filename.." 2> "..stderr_filename)

	local returned_status
	if type(status) == "number" then -- lua 5.1
		returned_status = status
	else -- Lua 5.2/5.3
		returned_status = ret
		if not status and ret == 0 then
			returned_status = -1
			-- Lua bug on Windows when the returned value is -1, ret is 0
		end
	end

	local stdout = GetFileData(stdout_filename)
	local stderr = GetFileData(stderr_filename)
	return returned_status, stdout, stderr
end

TestCommandLine = {}
	function TestCommandLine:TestHelp()
		local returned_status, stdout, stderr = RunCommandline("-h")
		lu.assertEquals(returned_status, 0)

		local str = LibDeflate._COPYRIGHT
			.."\nUsage: lua LibDeflate.lua [OPTION] [INPUT] [OUTPUT]\n"
			.."  -0    store only. no compression.\n"
			.."  -1    fastest compression.\n"
			.."  -9    slowest and best compression.\n"
			.."  -d    do decompression instead of compression.\n"
			.."  --dict <filename> specify the file that contains"
			.." the entire preset dictionary.\n"
			.."  -h    give this help.\n"
			.."  --strategy <fixed/huffman_only/dynamic>"
			.." specify a special compression strategy.\n"
			.."  -v    print the version and copyright info.\n"
			.."  --zlib  use zlib format instead of raw deflate.\n"

		if stdout:find(str, 1, true) then
			lu.assertStrContains(stdout, str)
		else
			str = str:gsub("\n", "\r\n")
			lu.assertStrContains(stdout, str)
		end
		lu.assertEquals(stderr, "")
	end

	function TestCommandLine:TestCopyright()
		local returned_status, stdout, stderr = RunCommandline("-v")
		lu.assertEquals(returned_status, 0)

		local str = LibDeflate._COPYRIGHT

		if stdout:find(str, 1, true) then
			lu.assertStrContains(stdout, str)
		else
			str = str:gsub("\n", "\r\n")
			lu.assertStrContains(stdout, str)
		end
		lu.assertEquals(stderr, "")
	end

	function TestCommandLine:TestErrors()
		local returned_status, stdout, stderr

		returned_status, stdout, stderr =
			RunCommandline("-invalid")
		lu.assertNotEquals(returned_status, 0)
		lu.assertEquals(stdout, "")
		lu.assertStrContains(stderr, ("LibDeflate: Invalid argument: %s")
				:format("-invalid"))

		returned_status, stdout, stderr =
			RunCommandline("tests/data/reference/item_strings.txt --dict")
		lu.assertNotEquals(returned_status, 0)
		lu.assertEquals(stdout, "")
		lu.assertStrContains(stderr, "You must speicify the dict filename")

		returned_status, stdout, stderr =
			RunCommandline("tests/data/reference/item_strings.txt --dict DNE")
		lu.assertNotEquals(returned_status, 0)
		lu.assertEquals(stdout, "")
		lu.assertStrContains(stderr,
			("LibDeflate: Cannot read the dictionary file '%s':")
			:format("DNE"))

		returned_status, stdout, stderr =
			RunCommandline("DNE DNE")
		lu.assertNotEquals(returned_status, 0)
		lu.assertEquals(stdout, "")
		lu.assertStrContains(stderr, "LibDeflate: Cannot read the file 'DNE':")

		returned_status, stdout, stderr =
			RunCommandline("tests/data/reference/item_strings.txt ..")
		lu.assertNotEquals(returned_status, 0)
		lu.assertEquals(stdout, "")
		lu.assertStrContains(stderr, "LibDeflate: Cannot write the file '..':")

		returned_status, stdout, stderr =
			RunCommandline("tests/data/reference/item_strings.txt")
		lu.assertNotEquals(returned_status, 0)
		lu.assertEquals(stdout, "")
		lu.assertStrContains(stderr, "LibDeflate:"
			.." You must specify both input and output files.")

		returned_status, stdout, stderr =
			RunCommandline("-d tests/data/reference/item_strings.txt"
						.." tests/test_commandline.tmp")
		lu.assertNotEquals(returned_status, 0)
		lu.assertEquals(stdout, "")
		lu.assertStrContains(stderr, "LibDeflate: Decompress fails.")
	end

	function TestCommandLine:TestCompressAndDecompress()
		local funcs = {"CompressDeflate", "CompressDeflateWithDict"
					, "CompressZlib", "CompressZlibWithDict"
					, "DecompressDeflate", "DecompressDeflateWithDict"
					, "DecompressZlib", "DecompressZlibWithDict"}
		local args = {"", "--dict tests/dictionary32768.txt"
					, "--zlib", "--zlib --dict tests/dictionary32768.txt"
					, "-d", "-d --dict tests/dictionary32768.txt"
					, "-d --zlib", "-d --zlib --dict tests/dictionary32768.txt"}
		local inputs = {"tests/data/reference/item_strings.txt"
						,"tests/data/reference/item_strings.txt"
						, "tests/data/reference/item_strings.txt"
						, "tests/data/reference/item_strings.txt"
						, "tests/data/reference/item_strings_deflate.txt"
					, "tests/data/reference/item_strings_deflate_with_dict.txt"
				, "tests/data/reference/item_strings_zlib.txt"
				, "tests/data/reference/item_strings_zlib_with_dict.txt"}
		local addition_args = {
			"-0 "
			, "-1 --strategy huffman_only"
			, "-5 --strategy dynamic"
			, "-9 --strategy fixed"
			, ""
		}
		local addition_configs = {
			{level = 0}
			, {level = 1, strategy = "huffman_only"}
			, {level = 5, strategy = "dynamic"}
			, {level = 9, strategy = "fixed"}
			, nil
		}
		for k, func_name in ipairs(funcs) do
			local configs
			local addition_arg
			for i = 1, #addition_args do
				configs = addition_configs[i]
				addition_arg = addition_args[i]
				if not configs then
					print(("Testing TestCommandline: %s")
						:format(func_name))
				else
					print(
					("Testing TestCommandline: %s level: %s strategy: %s")
						:format(func_name, tostring(configs.level)
						, tostring(configs.strategy)))
				end
				local returned_status, stdout, stderr =
					RunCommandline(args[k].." "..addition_arg
							.." "..inputs[k]
							.." tests/test_commandline.tmp")
				lu.assertEquals(stdout, "")
				lu.assertStrContains(stderr, ("Successfully writes %d bytes")
					:format(GetFileData("tests/test_commandline.tmp"):len()))
				lu.assertEquals(returned_status, 0)
				local result
				if func_name:find("Dict") then
					result = LibDeflate[func_name](LibDeflate, GetFileData(
						inputs[k]), dictionary32768, configs)
				else
					result = LibDeflate[func_name](LibDeflate, GetFileData(
						inputs[k]), configs)
				end
				lu.assertNotNil(result)
				lu.assertEquals(GetFileData("tests/test_commandline.tmp")
					, result)
			end
		end
	end

TestCompressRatio = {}
	-- May need to modify number if algorithm changes.
	function TestCompressRatio:TestSmallTest()
		-- avoid github auto CRLF problem by removing \n in the file.
		local fileData = GetFileData("tests/data/smalltest_no_newline.txt")
		lu.assertEquals(fileData:len(), 28453)
		lu.assertTrue(LibDeflate:CompressDeflate(fileData, {level=0}):len()
			<= 28458)
		lu.assertTrue(LibDeflate:CompressDeflate(fileData, {level=1}):len()
			<= 7467)
		lu.assertTrue(LibDeflate:CompressDeflate(fileData, {level=2}):len()
			<= 7011)
		lu.assertTrue(LibDeflate:CompressDeflate(fileData, {level=3}):len()
			<= 6740)
		lu.assertTrue(LibDeflate:CompressDeflate(fileData, {level=4}):len()
			<= 6401)
		lu.assertTrue(LibDeflate:CompressDeflate(fileData, {level=5}):len()
			<= 5992)
		lu.assertTrue(LibDeflate:CompressDeflate(fileData, {level=6}):len()
			<= 5884)
		lu.assertTrue(LibDeflate:CompressDeflate(fileData, {level=7}):len()
			<= 5829)
		lu.assertTrue(LibDeflate:CompressDeflate(fileData, {level=8}):len()
			<= 5820)
		lu.assertTrue(LibDeflate:CompressDeflate(fileData, {level=9}):len()
			<= 5820)
	end

TestExported = {}
	function TestExported:TestExported()
		local exported = {
			EncodeForWoWChatChannel = "function",
			_COPYRIGHT = "string",
			DecodeForWoWAddonChannel = "function",
			CompressDeflate  = "function",
			DecompressDeflate = "function",
			CompressDeflateWithDict = "function",
			DecompressZlibWithDict = "function",
			CreateCodec = "function",
			DecodeForWoWChatChannel = "function",
			internals = "table",
			_VERSION = "string",
			_MAJOR = "string",
			_MINOR = "number",
			Adler32 = "function",
			CreateDictionary = "function",
			CompressZlibWithDict = "function",
			EncodeForPrint = "function",
			CompressZlib = "function",
			DecodeForPrint = "function",
			DecompressDeflateWithDict = "function",
			EncodeForWoWAddonChannel = "function",
			DecompressZlib = "function",
		}
		for k, v in pairs(exported) do
			lu.assertEquals(v, type(LibDeflate[k]))
		end
		for k, v in pairs(LibDeflate) do
			lu.assertEquals(type(v), exported[k])
		end
	end
--------------------------------------------------------------
-- Coverage Tests --------------------------------------------
--------------------------------------------------------------
local function AddToCoverageTest(suite, test)
	assert(suite)
	assert(type(suite[test]) == "function")
	CodeCoverage[test] = function(_, ...)
		return suite[test](_G[suite], ...) end
end
local function AddAllToCoverageTest(suite)
	for k, _ in pairs(suite) do
		AddToCoverageTest(suite, k)
	end
end

-- Run "luajit -lluacov tests/Test.lua CodeCoverage" for test coverage test.
CodeCoverage = {}
	AddAllToCoverageTest(TestBasicStrings)
	AddAllToCoverageTest(TestDecompress)
	AddAllToCoverageTest(TestInternals)
	AddAllToCoverageTest(TestPresetDict)
	AddAllToCoverageTest(TestEncode)
	AddAllToCoverageTest(TestErrors)
	AddToCoverageTest(TestMyData, "TestSmallTest")
	AddToCoverageTest(TestThirdPartyBig, "Testptt5")
	AddToCoverageTest(TestThirdPartyBig, "TestGeoProtodata")
	AddToCoverageTest(TestCompressStrategy, "TestIsFixedStrategyInEffect")
	AddToCoverageTest(TestCompressStrategy, "TestIsDynamicStrategyInEffect")
	AddToCoverageTest(TestCompressStrategy, "TestIsHuffmanOnlyStrategyInEffect")

-- Run "lua tests/Test.lua CommandLineCodeCoverage "
-- for test coverage test and CommandLineCodeCoverage
-- DONT run with "luajit -lluaconv"
CommandLineCodeCoverage = {}
	for k, v in pairs(TestCommandLine) do
		CommandLineCodeCoverage[k] = function(_, ...)
			lua_program = "lua -lluacov"
			return TestCommandLine[k](TestCommandLine, ...)
		end
	end

-- Check if decompress will produce any lua error for random string.
-- Expectation is that no Lua error.
-- This test is not run in CI.
DecompressLuaErrorTest = {}
	function DecompressLuaErrorTest:Test()
		math.randomseed(os.time())
		for _=1, 10000 do
			local len = math.random(0, 10000)
			local str = GetRandomString(len)
			local dict = CreateDictionaryWithoutVerify(
				GetRandomString(math.random(1, 32768)))
			local r1, r2
			r1, r2 = LibDeflate:DecompressDeflate(str)
			-- Check the type of return value
			assert((type(r1) == "string" or type(r1) == "nil") and r2 % 1 == 0)
			r1, r2 = LibDeflate:DecompressZlib(str)
			assert((type(r1) == "string" or type(r1) == "nil") and r2 % 1 == 0)
			r1, r2 = LibDeflate:DecompressDeflateWithDict(str, dict)
			assert((type(r1) == "string" or type(r1) == "nil") and r2 % 1 == 0)
			r1, r2 = LibDeflate:DecompressZlibWithDict(str, dict)
			assert((type(r1) == "string" or type(r1) == "nil") and r2 % 1 == 0)
			print("Decompressed one random string without Lua error.")
			print(StringForPrint(StringToHex(str)))
		end
	end

-- Tests for some huge test data.
-- The test data is not in the repository.
-- Run the batch script in tests\dev_scripts\download_huge_data.bat
-- to download.
-- This test is not run in CI.
HugeTests = {}
	function HugeTests:TestCanterburyBible()
		CheckCompressAndDecompressFile("tests/huge_data/bible.txt", "all")
	end
	function HugeTests:TestCanterburyEColi()
		CheckCompressAndDecompressFile("tests/huge_data/E.coli", "all")
	end
	function HugeTests:TestCanterburyWorld129()
		CheckCompressAndDecompressFile("tests/huge_data/world192.txt", "all")
	end
	do
		local silesia_files = {"dickens", "mozilla", "mr", "nci", "ooffice"
				, "osdb", "reymont", "samba", "sao", "webster", "xml", "x-ray"}
		for _, f in pairs(silesia_files) do
			HugeTests["TestSilesia"..f:sub(1, 1):upper()..f:sub(2)] = function()
				CheckCompressAndDecompressFile("tests/huge_data/"..f
				, {0, 1, 2, 3, 4})
			end
		end
	end

for k, v in pairs(_G) do
	if type(k) == "string" and (k:find("^Test") or k:find("^test")) then
		assert(type(v) == "table", "Globals start with Test or test"
			.." must be table: "..k)
		for kk, vv in pairs(v) do
			assert(type(kk) == "string"
				and kk:find("^Test"), "All members in test table"
				.." s key must start with Test: "..tostring(kk))
			assert(type(vv) == "function", "All members in test table"
				.." must be function")
		end
	end
end

--
-- Performance Evaluation, compared with LibCompress
--
local function CheckCompressAndDecompressLibCompress(
	string_or_filename, is_file)

	FullMemoryCollect()
	local LibCompress = require("LibCompress")

	local origin
	if is_file then
		origin = GetFileData(string_or_filename)
	else
		origin = string_or_filename
	end

	FullMemoryCollect()
	local total_memory_before = math.floor(collectgarbage("count")*1024)

	do
		print(
			(">>>>> %s: %s size: %d B (LibCompress)")
			:format(is_file and "File" or "String",
				string_or_filename:sub(1, 40),  origin:len()
			))
		local compress_to_run = {
			{"Compress", origin},
			{"CompressLZW", origin},
			{"CompressHuffman", origin},
		}

		for j, compress_running in ipairs(compress_to_run) do
		-- Compress by raw deflate
			local compress_func_name = compress_running[1]
			local compress_memory_leaked, compress_memory_used
				, compress_time, compress_data =
				MemCheckAndBenchmarkFunc(LibCompress
					, unpack(compress_running))

			local decompress_to_run = {
				{"Decompress", compress_data},
				{"Decompress", compress_data},
				{"Decompress", compress_data},
			}
			lu.assertEquals(#decompress_to_run, #compress_to_run)

			-- Try decompress by LibDeflate
			local decompress_memory_leaked, decompress_memory_used,
				decompress_time, decompress_data =
				MemCheckAndBenchmarkFunc(LibCompress
					, unpack(decompress_to_run[j]))
			AssertLongStringEqual(decompress_data, origin
				, compress_func_name
				.." LibCompress decompress result not match origin string.")

			print(
				("%s:   Size : %d B,Time: %.3f ms, "
					.."Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak?: %d B)\n")
					:format(compress_func_name
					, compress_data:len(), compress_time
					, compress_data:len()/compress_time
					, compress_memory_used
					, compress_memory_used/origin:len()
					, compress_memory_leaked
				),
				("%s:   cRatio: %.2f,Time: %.3f ms"
					..", Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak?: %d B)"):format(
					decompress_to_run[j][1]
					, origin:len()/compress_data:len(), decompress_time
					, decompress_data:len()/decompress_time
					, decompress_memory_used
					, decompress_memory_used/origin:len()
					, decompress_memory_leaked
				)
			)
			print("")
		end
	end

	FullMemoryCollect()
	local total_memory_after = math.floor(collectgarbage("count")*1024)

	local total_memory_difference = total_memory_before - total_memory_after

	if total_memory_difference > 0 then
		local ignore_leak = " (Ignore when the test is for LibCompress)"
		print(
			(">>>>> %s: %s size: %d B\n")
				:format(is_file and "File" or "String"
				, string_or_filename:sub(1, 40), origin:len()),
			("Actual Memory Leak in the test: %d"..ignore_leak.."\n")
				:format(total_memory_difference),
			"\n")
	end
end

local function EvaluatePerformance(filename)
	local interpreter = _G._VERSION
	if _G.jit then
		interpreter = interpreter.."(LuaJIT)"
	end
	print(interpreter)
	print("^^^^^^^^^^^^")
	CheckCompressAndDecompressLibCompress(filename, true)
	CheckCompressAndDecompressFile(filename, "all")
end

PerformanceEvaluation = {}
	function PerformanceEvaluation:TestEvaluateWarlockWeakAuras()
		EvaluatePerformance("tests/data/warlockWeakAuras.txt")
	end
	function PerformanceEvaluation:TestEvaluateTotalRp3Data()
		EvaluatePerformance("tests/data/totalrp3.txt")
	end

local runner = lu.LuaUnit.new()
local exitCode = runner:runSuite()
print("========================================================")
print("LibDeflate", "Version:", LibDeflate._VERSION, "\n")
print("Exported keys:")
for k, v in pairs(LibDeflate) do
	assert(type(k) == "string")
	print(k, type(v))
end
print("--------------------------------------------------------")
if exitCode == 0 then
	print("TEST OK")
else
	print("TEST FAILED")
end

os.exit(exitCode)