-- Run this tests at the folder where LibDeflate.lua located.
-- lua tests/LibDeflateTest.lua
-- Don't run two tests at the same time.

local LibDeflate = require("LibDeflate")
-- UnitTests
local lu = require("luaunit")

local assert = assert
local loadstring = loadstring or load
local math = math
local string = string
local table = table
local collectgarbage = collectgarbage
local os = os
local type = type
local io = io
local ipairs = ipairs
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

local _byte0 = string_byte("0", 1)
local _byte9 = string_byte("9", 1)
local _byteA = string_byte("A", 1)
local _byteF = string_byte("F", 1)
local _bytea = string_byte("a", 1)
local _bytef = string_byte("f", 1)
local function HexToString(str)
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

local function HalfByteToHex(half_byte)
	assert (half_byte >= 0 and half_byte < 16)
	if half_byte < 10 then
		return string_char(_byte0 + half_byte)
	else
		return string_char(_bytea + half_byte-10)
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

local function GetFileSize(filename)
	return GetFileData(filename):len()
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
local function GetRandomStringComplete(strlen)
	assert(strlen >= 256)
	local taken = {}
	local tmp = {}
	for i=0, 255 do
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
	for _=1, strlen-256 do
		table_insert(tmp, math.random(1, #tmp+1)
			, string_char(math.random(0, 255)))
	end
	return table_concat(tmp)
end
assert(GetRandomStringComplete(256):len() == 256)
assert(GetRandomStringComplete(500):len() == 500)
do
	local taken = {}
	local str = GetRandomStringComplete(256)
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

local function MemCheckAndBenchmarkFunc(func, ...)
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
		ret = {func(...)}
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

local dictionary32768 = GetFileData("tests/dictionary32768.txt")
dictionary32768 = LibDeflate:CreateDictionary(dictionary32768)

local function CheckCompressAndDecompress(string_or_filename, is_file, levels)
	-- Init cache table in these functions
	-- , to help memory leak check in the following codes.
	LibDeflate:EncodeForWoWAddonChannel("")
	LibDeflate:EncodeForWoWChatChannel("")

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
			levels = {1,2,3,4,5,6,7,8}
		else
			levels = levels or {1}
		end

		local compress_filename
		if is_file then
			compress_filename = string_or_filename..".compress"
		else
			compress_filename = "tests/string.compress"
		end

		local decompress_filename = compress_filename..".decompress"

		local zlib_compress_filename = compress_filename..".zlib"
		local zlib_decompress_filename = zlib_compress_filename..".decompress"
		local dict_compress_filename = compress_filename..".dict"
		local dict_decompress_filename = compress_filename..".dict.decompress"

		for _, level in ipairs(levels) do
			-- Compress by raw deflate
			local compress_memory_leaked, compress_memory_used, compress_time,
				compress_data, compress_bitlen =
				MemCheckAndBenchmarkFunc(LibDeflate.Compress, LibDeflate
				, origin, level)
			lu.assertEquals(math.ceil(compress_bitlen/8), compress_data:len(),
				"Unexpected compress bit size")
			WriteToFile(compress_filename, compress_data)

			-- Test encoding
			local compress_data_WoW_addon_encoded =
				LibDeflate:EncodeForWoWAddonChannel(compress_data)
			AssertLongStringEqual(
				LibDeflate:DecodeForWoWAddonChannel(
					compress_data_WoW_addon_encoded), compress_data,
					"EncodeForAddonChannel fails")

			local compress_data_data_WoW_chat_encoded =
				LibDeflate:EncodeForWoWChatChannel(compress_data)
			AssertLongStringEqual(
				LibDeflate:DecodeForWoWChatChannel(
					compress_data_data_WoW_chat_encoded), compress_data,
					"EncodeForChatChannel fails")

			-- Try decompress by puff
			local returnedStatus_puff, stdout_puff, stderr_puff = 
				RunProgram("puff -w ", compress_filename, decompress_filename)
			lu.assertEquals(returnedStatus_puff, 0
				, "puff decompression failed with code "..returnedStatus_puff)
			AssertLongStringEqual(stdout_puff, origin
				, "puff decompress result does not match origin string.")

			-- Try decompress by zdeflate
			local returnedStatus_zdeflate, stdout_zdeflate, stderr_zdeflate =
				RunProgram("zdeflate -d <", compress_filename
					, decompress_filename)
			lu.assertEquals(returnedStatus_zdeflate, 0
				, "zdeflate decompression failed with msg "..stderr_zdeflate)
			AssertLongStringEqual(stdout_zdeflate, origin
				, "zdeflate decompress result does not match origin string.")

			-- Try decompress by LibDeflate
			local decompress_memory_leaked, decompress_memory_used,
				decompress_time, decompress_data,
				decompress_unprocess_byte =
				MemCheckAndBenchmarkFunc(LibDeflate.Decompress, LibDeflate
				, compress_data)
			lu.assertEquals(decompress_unprocess_byte, 0
				, "Unprocessed bytes after LibDeflate decompression "
					..tostring(decompress_unprocess_byte))
			AssertLongStringEqual(decompress_data, origin
				, "LibDeflate decompress result does not match origin string.")

			-- Compress with Zlib header instead of raw Deflate
			local zlib_compress_memory_leaked, zlib_compress_memory_used
				, zlib_compress_time, zlib_compress_data, zlib_compress_bitlen =
				MemCheckAndBenchmarkFunc(LibDeflate.CompressZlib, LibDeflate
				, origin, level)
			lu.assertEquals(zlib_compress_bitlen/8, zlib_compress_data:len()
				, "Unexpected zlib bit size")

			WriteToFile(zlib_compress_filename, zlib_compress_data)

			local zlib_returned_status_zdeflate, zlibStdout_zdeflate
				, zlibStderr_zdeflate =
				RunProgram("zdeflate --zlib -d <", zlib_compress_filename
				, zlib_decompress_filename)
			lu.assertEquals(zlib_returned_status_zdeflate, 0
				, "zdeflate fails to decompress zlib with msg "
				..tostring(zlibStderr_zdeflate))
			AssertLongStringEqual(zlibStdout_zdeflate, origin,
				"zDeflate decompress result does not match origin zlib string.")

			local zlibDecompressMemoryLeaked, zlibDecompressMemoryUsed
				, zlibDecompressTime, zlibDecompressData
				, zlibDecompressUnprocessByte =
				MemCheckAndBenchmarkFunc(LibDeflate.DecompressZlib, LibDeflate
				, zlib_compress_data)
			lu.assertEquals(zlibDecompressUnprocessByte, 0
				, "Unprocessed bytes after LibDeflate zlib decompression "
					..tostring(zlibDecompressUnprocessByte))
			AssertLongStringEqual(zlibDecompressData, origin
				, "LibDeflate zlib decompress result does not"..
				" match origin string.")


			local dict_compress_memory_leaked, dict_compress_memory_used
				, dict_compress_time,
				dict_compress_data, dictCompressBitlen =
				MemCheckAndBenchmarkFunc(LibDeflate.CompressDeflate, LibDeflate
				, origin, level, dictionary32768)
			WriteToFile(dict_compress_filename, dict_compress_data)
			lu.assertEquals(math.ceil(dictCompressBitlen/8)
				, dict_compress_data:len(),
				"Unexpected compress bit size")
			local dict_returned_status_zdeflate, dict_stdout_zdeflate
				, dictStderr_zdeflate =
				RunProgram("zdeflate -d --dict tests/dictionary32768.txt <"
				, dict_compress_filename, dict_decompress_filename)
			lu.assertEquals(dict_returned_status_zdeflate, 0
				, "zdeflate fails to decompress with dict with msg "
				..tostring(dictStderr_zdeflate))
			AssertLongStringEqual(dict_stdout_zdeflate, origin,
				"zdeflate decompress with dictionary result does not "
				.."match origin string.")
			local dict_decompress_memory_leaked, dict_decompress_memory_used
				, dict_decompress_time, dict_decompress_data
				, dict_decompress_unprocess_byte =
				MemCheckAndBenchmarkFunc(LibDeflate.DecompressDeflate
				, LibDeflate, dict_compress_data, dictionary32768)
			lu.assertEquals(dict_decompress_unprocess_byte, 0
			, "Unprocessed bytes after LibDeflate zlib decompression "
					..tostring(dict_decompress_unprocess_byte))
			AssertLongStringEqual(dict_decompress_data, origin,
				"my decompress with dictionary result does not "
				.."match origin string.")

			print(
				(">>>>> %s: %s Level: %d size: %d B\n")
				:format(is_file and "File" or "String",
					string_or_filename:sub(1, 40), level, origin:len()),
				("CompressDeflate:   Size : %d B,\tTime: %.3f ms, "
					.."Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak: %d B)\n"):format(
					compress_data:len(), compress_time
					, compress_data:len()/compress_time, compress_memory_used
					, compress_memory_used/origin:len(), compress_memory_leaked
				),
				("CompDeflateDict:   Size : %d B,\tTime: %.3f ms, "
					.."Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak: %d B)\n"):format(
					dict_compress_data:len(), dict_compress_time
					, dict_compress_data:len()/dict_compress_time
					, dict_compress_memory_used
					, dict_compress_memory_used/origin:len()
					, dict_compress_memory_leaked
				),
				("DecompressDeflate: cRatio: %.2f,\tTime: %.3f ms"
					..", Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak: %d B)\n"):format(
					origin:len()/compress_data:len(), decompress_time
					, decompress_data:len()/decompress_time
					, decompress_memory_used
					, decompress_memory_used/origin:len()
					, decompress_memory_leaked
				),
				("DeCompDeflateDict: cRatio : %.2f,\tTime: %.3f ms"
					..", Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak: %d B)\n"):format(
					origin:len()/dict_compress_data:len()
					, dict_decompress_time
					, dict_decompress_data:len()/dict_decompress_time
					, dict_decompress_memory_used
					, dict_decompress_memory_used/origin:len()
					, dict_decompress_memory_leaked
				),
				("CompressZlib:      Size : %d B,\tTime: %.3f ms"
					..", Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak: %d B)\n"):format(
					zlib_compress_data:len(), zlib_compress_time
					, zlib_compress_data:len()/zlib_compress_time
					, zlib_compress_memory_used
					,zlib_compress_memory_used/origin:len()
					, zlib_compress_memory_leaked
				),
				("DecompressZlib:    cRatio: %.2f,\tTime: %.3f ms"
					..", Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak: %d B)\n"):format(
					origin:len()/compress_data:len(), zlibDecompressTime
					, zlibDecompressData:len()/zlibDecompressTime
					, zlibDecompressMemoryUsed
					, zlibDecompressMemoryUsed/origin:len()
					, zlibDecompressMemoryLeaked
				),
				"\n"
			)
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
					local decompressData = LibDeflate:Decompress(stdout)
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
		print(
			(">>>>> %s: %s size: %d B\n")
				:format(is_file and "File" or "String"
				, string_or_filename:sub(1, 40), origin:len()),
			("Actual Memory Leak in the test: %d\n")
				:format(total_memory_difference),
			"\n")
		-- ^If above "leak" is very small
		-- , it is very likely that it is false positive.
		if not jit and total_memory_difference > 64 then
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

local function CheckDecompressIncludingError(compress, decompress, is_zlib)
	assert (is_zlib == true or is_zlib == nil)
	local d, decompress_return
	if is_zlib then
		d, decompress_return = LibDeflate:DecompressZlib(compress)
	else
		d, decompress_return = LibDeflate:DecompressDeflate(compress)
	end
	if d ~= decompress then
		lu.assertTrue(false, ("My decompress does not match expected result."
			.."expected: %s, actual: %s, Returned status of decompress: %d")
			:format(StringForPrint(StringToHex(d))
			, StringForPrint(StringToHex(decompress)), decompress_return))
	else
		-- Check my decompress result with "puff"
		local input_filename = "tests/tmpFile"
		local inputFile = io.open(input_filename, "wb")
		inputFile:setvbuf("full")
		inputFile:write(compress)
		inputFile:flush()
		inputFile:close()
		local returned_status_puff, stdout_puff, stderr_puff =
			RunProgram("puff -w", input_filename
			, input_filename..".decompress")
		local returnedStatus_zdeflate, stdout_zdeflate, stderr_zdeflate =
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

local function CheckCompressAndDecompressString(str, levels)
	return CheckCompressAndDecompress(str, false, levels)
end

local function CheckCompressAndDecompressFile(inputFileName, levels)
	return CheckCompressAndDecompress(inputFileName, true, levels)
end

-- Commandline
local arg = _G.arg
if arg and #arg >= 1 and type(arg[0]) == "string" then
	if #arg >= 2 and arg[1] == "-o" then
	-- For testing purpose, check if the file can be opened by lua
		local input = arg[2]
		local inputFile = io.open(input, "rb")
		if not inputFile then
			os.exit(1)
		end
		inputFile.close()
		os.exit(0)
	elseif #arg >= 3 and arg[1] == "-c" then
	-- For testing purpose
	-- , check the if a file can be correctly compress and decompress to origin
		os.exit(CheckCompressAndDecompressFile(arg[2], "all", 0, arg[3]))-- TODO
	end
end

-------------------------------------------------------------------------
-- LibCompress encode code to help verity encode code in LibDeflate -----
-------------------------------------------------------------------------
local LibCompress = {}
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

	function LibCompress:GetEncodeTable(reservedChars, escapeChars, mapChars)
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
	function LibCompress:GetAddonEncodeTable(reservedChars
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
	function LibCompress:GetChatEncodeTable(reservedChars
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

local _libcompress_addon_encode_table = LibCompress:GetAddonEncodeTable()
local _libcompress_chat_encode_table = LibCompress:GetChatEncodeTable()

-- Check if LibDeflate's encoding works properly
local function CheckEncodeAndDecode(str, reserved_chars, escape_chars
	, map_chars)
	if reserved_chars then
		local encode_decode_table_libcompress =
			LibCompress:GetEncodeTable(reserved_chars
			, escape_chars, map_chars)
		local encode_decode_table, message =
			LibDeflate:GetEncodeDecodeTable(reserved_chars
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
		_libcompress_addon_encode_table:Encode(str)
	AssertLongStringEqual(encoded_addon, encoded_addon_libcompress
		, "Encoded addon channel result does not match libcompress")
	AssertLongStringEqual(LibDeflate:DecodeForWoWAddonChannel(encoded_addon)
		, str, "Encoded for addon channel str cant be decoded to origin")

	local encoded_chat = LibDeflate:EncodeForWoWChatChannel(str)
	local encoded_chat_libcompress = _libcompress_chat_encode_table:Encode(str)
	AssertLongStringEqual(encoded_chat, encoded_chat_libcompress
		, "Encoded chat channel result does not match libcompress")
	AssertLongStringEqual(LibDeflate:DecodeForWoWChatChannel(encoded_chat), str
		, "Encoded for chat channel str cant be decoded to origin")
end

--------------------------------------------------------------
-- Actual Tests Start ----------------------------------------
--------------------------------------------------------------
TestBasicStrings = {}
	function TestBasicStrings:testEmpty()
		CheckCompressAndDecompressString("", "all")
	end
	function TestBasicStrings:testAllLiterals1()
		CheckCompressAndDecompressString("ab", "all")
	end
	function TestBasicStrings:testAllLiterals2()
		CheckCompressAndDecompressString("abcdefgh", "all")
	end
	function TestBasicStrings:testAllLiterals3()
		local t = {}
		for i=0, 255 do
			t[#t+1] = string.char(i)
		end
		local str = table.concat(t)
		CheckCompressAndDecompressString(str, "all")
	end

	function TestBasicStrings:testRepeat()
		CheckCompressAndDecompressString("aaaaaaaaaaaaaaaaaa", "all")
	end

	function TestBasicStrings:testLongRepeat()
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
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestPaper100kPdf()
		CheckCompressAndDecompressFile("tests/data/3rdparty/paper-100k.pdf"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestGeoProtodata()
		CheckCompressAndDecompressFile("tests/data/3rdparty/geo.protodata"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestFireworksJpeg()
		CheckCompressAndDecompressFile("tests/data/3rdparty/fireworks.jpeg"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestAsyoulik()
		CheckCompressAndDecompressFile("tests/data/3rdparty/asyoulik.txt"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestCompressedRepeated()
		CheckCompressAndDecompressFile(
			"tests/data/3rdparty/compressed_repeated", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestAlice29()
		CheckCompressAndDecompressFile("tests/data/3rdparty/alice29.txt"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestQuickfox_repeated()
		CheckCompressAndDecompressFile("tests/data/3rdparty/quickfox_repeated"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestKppknGtb()
		CheckCompressAndDecompressFile("tests/data/3rdparty/kppkn.gtb"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestZeros()
		CheckCompressAndDecompressFile("tests/data/3rdparty/zeros"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestMapsdatazrh()
		CheckCompressAndDecompressFile("tests/data/3rdparty/mapsdatazrh"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestHtml_x_4()
		CheckCompressAndDecompressFile("tests/data/3rdparty/html_x_4"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestLcet10()
		CheckCompressAndDecompressFile("tests/data/3rdparty/lcet10.txt"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestPlrabn12()
		CheckCompressAndDecompressFile("tests/data/3rdparty/plrabn12.txt"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestUrls10K()
		CheckCompressAndDecompressFile("tests/data/3rdparty/urls.10K"
			, {1,2,3,4,5})
	end
	function TestThirdPartyBig:Testptt5()
		CheckCompressAndDecompressFile("tests/data/3rdparty/ptt5"
			, {1,2,3,4})
	end
	function TestThirdPartyBig:TestKennedyXls()
		CheckCompressAndDecompressFile("tests/data/3rdparty/kennedy.xls"
			, {1,2,3,4})
	end

TestWoWData = {}
	function TestWoWData:TestWarlockWeakAuras()
		CheckCompressAndDecompressFile("tests/data/warlockWeakAuras.txt"
			, "all")
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
		CheckDecompressIncludingError(
			HexToString("4 0 24 e9 ff 6d"), nil) -- Invalid code: missing end of block
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
		local compress_empty = LibDeflate:Compress("")
		lu.assertEquals(LibDeflate:Decompress(compress_empty)
			, "", "My decompress does not match origin for empty string.")
		for _=1, 50 do
			local tmp
			local strlen = math.random(0, 1000)
			local str = GetLimitedRandomString(strlen)
			local level = (math.random() < 0.5) and (math.random(1, 8)) or nil
			local expected = str
			local compress = LibDeflate:Compress(str, level)
			local _, actual = pcall(function() return LibDeflate
				:Decompress(compress) end)
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
		if not jit then
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
		if not jit then
			lu.assertTrue((memory4 - memory3 <= 100)
				, ("Too much Memory leak after LibStub update: %d")
				:format(memory4-memory3))
		end
	end

TestPresetDict = {}
	function TestPresetDict:TestBasic()
		--[[
		local dict = {}
		for i=8468, 0, -1 do
			dict[#dict+1] = tostring(i)
		end
		dict = table.concat(dict).."00"
		print(dict:len())
		--]]
		local dict = [[ilvl::::::::110:::1517:3336:3528:3337]]
		local fileData = GetFileData("tests/data/itemStrings.txt")
		local dictionary = LibDeflate:CreateDictionary(dict)
		print("dictLen", dict:len())
		for i=1, dict:len() do
			assert(dictionary.string_table[i] == string_byte(dict, i, i))
		end
		for i=1, dict:len()-2 do
			local hash = string_byte(dict, i, i)*65536
				+ string_byte(dict, i+1, i+1)*256
				+ string_byte(dict, i+2, i+2)
			assert(dictionary.hash_tables[hash])
		end
		assert(dictionary.strlen == dict:len())
		assert(dictionary)

		local compress = LibDeflate:Compress(fileData, 7, dictionary)
		print(compress:len())

		local decompressed = LibDeflate:Decompress(compress, dictionary)
		print(fileData:len(), decompressed:len())
		AssertLongStringEqual(fileData, decompressed)
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
			local str = GetRandomStringComplete(math.random(256, 1000))
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
			local str = GetRandomStringComplete(1000)
			CheckEncodeAndDecode(str, reservedChars, escapedChars)
		end
	end
	function TestEncode:TestRandomComplete1()
		for _ = 0, 200 do
			local tmp = GetRandomStringComplete(256)
			local reserved = tmp:sub(1, 10)
			local escaped = tmp:sub(11, 11)
			local mapped = tmp:sub(12, 12+math.random(0, 9))
			local str = GetRandomStringComplete(math.random(256, 1000))
			CheckEncodeAndDecode(str, reserved, escaped, mapped)
		end
	end

	function TestEncode:TestRandomComplete2()
		for _ = 0, 200 do
			local tmp = GetRandomStringComplete(256)
			local reserved = tmp:sub(1, 10)
			local escaped = tmp:sub(11, 11)
			local str = GetRandomStringComplete(math.random(256, 1000))
			CheckEncodeAndDecode(str, reserved, escaped)
		end
	end

	function TestEncode:TestRandomComplete3()
		for _ = 0, 200 do
			local tmp = GetRandomStringComplete(256)
			local reserved = tmp:sub(1, 130) -- Over half chractrs escaped
			local escaped = tmp:sub(131, 132) -- Two escape char needed.
			local mapped = tmp:sub(133, 133+math.random(0, 20))
			local str = GetRandomStringComplete(math.random(256, 1000))
			CheckEncodeAndDecode(str, reserved, escaped, mapped)
		end
	end

	function TestEncode:TestRandomComplete4()
		for _ = 0, 200 do
			local tmp = GetRandomStringComplete(256)
			local reserved = tmp:sub(1, 130) -- Over half chractrs escaped
			local escaped = tmp:sub(131, 132) -- Two escape char needed.
			local str = GetRandomStringComplete(math.random(256, 1000))
			CheckEncodeAndDecode(str, reserved, escaped)
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
CodeCoverage = {}
	AddAllToCoverageTest(TestBasicStrings)
	AddAllToCoverageTest(TestMyData)
	AddAllToCoverageTest(TestWoWData)
	AddAllToCoverageTest(TestDecompress)
	AddAllToCoverageTest(TestInternals)
	AddAllToCoverageTest(TestEncode)
	AddToCoverageTest(TestThirdPartyBig, "TestUrls10K")
	AddToCoverageTest(TestThirdPartyBig, "Testptt5")
	AddToCoverageTest(TestThirdPartyBig, "TestKennedyXls")
	AddToCoverageTest(TestThirdPartyBig, "TestGeoProtodata")
	AddToCoverageTest(TestThirdPartyBig, "TestPaper100kPdf")
	AddToCoverageTest(TestThirdPartyBig, "TestMapsdatazrh")

-- Check if decompress can give any lua error for random string.
DecompressInfinite = {}
	function DecompressInfinite:Test()
		math.randomseed(os.time())
		for _=1, 100000 do
			local len = math.random(0, 10000)
			local str = GetRandomString(len)
			LibDeflate:Decompress(str)
			LibDeflate:DecompressZlib(str)
			print(StringForPrint(StringToHex(str)))
		end
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