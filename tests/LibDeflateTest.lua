-- Commandline tests
local LibDeflate = require("LibDeflate")
local args = rawget(_G, "arg")
-- UnitTests
local lu = require("luaunit")

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
local unpack = unpack or table.unpack
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

local function HalfByteToHex(halfByte)
	assert (halfByte >= 0 and halfByte < 16)
	if halfByte < 10 then
		return string_char(_byte0 + halfByte)
	else
		return string_char(_bytea + halfByte-10)
	end
end

local function StringToHex(str)
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
assert (StringToHex(HexToString("05 e0 81 91 24 cb b2 2c 49 e2 0f 2e 8b 9a 47 56 9f fb fe ec d2 ff 1f"))
	== "05 e0 81 91 24 cb b2 2c 49 e2 0f 2e 8b 9a 47 56 9f fb fe ec d2 ff 1f")

-- Return a string with limited size
local function StringForPrint(str)
	if str:len() < 101 then
		return str
	else
		return str:sub(1, 101)..(" (%d more characters not shown)"):format(str:len()-101)
	end
end

local function OpenFile(fileName, mode)
	local f = io.open(fileName, mode)
	lu.assertNotNil(f, ("Cannot open the file: %s, with mode: %s"):format(fileName, mode))
	return f
end

local function GetFileData(fileName)
	local f = OpenFile(fileName, "rb")
	local str = f:read("*all")
	f:close()
	return str
end

local function GetFileSize(fileName)
	return GetFileData(fileName):len()
end

local function WriteToFile(fileName, data)
	local f = io.open(fileName, "wb")
	lu.assertNotNil(f, ("Cannot open the file: %s, with mode: %s"):format(fileName, "wb"))
	f:write(data)
	f:flush()
	f:close()
end

local function GetLimitedRandomString(strLen)
	local randoms = {}
	for _=1, 7 do
		randoms[#randoms+1] = string.char(math.random(1, 255))
	end
	local tmp = {}
	for _=1, strLen do
		tmp[#tmp+1] = randoms[math.random(1, 7)]
	end
	return table.concat(tmp)
end

local function GetRandomString(strLen)
	local tmp = {}
	for _=1, strLen do
		tmp[#tmp+1] = string_char(math.random(0, 255))
	end
	return table.concat(tmp)
end

-- Repeatedly collect memory garbarge until memory usage no longer changes
local function FullMemoryCollect()
	local memoryUsed = collectgarbage("count")
	local lastMemoryUsed
	local stable_count = 0
	repeat
		lastMemoryUsed = memoryUsed
		collectgarbage("collect")
		memoryUsed = collectgarbage("count")

		if memoryUsed >= lastMemoryUsed then
			stable_count = stable_count + 1
		else
			stable_count = 0
		end
	until stable_count == 10 -- Stop full memory collect until memory usage does not decrease for 10 times.
end

local function RunProgram(program, inputFileName, stdoutFileName)
	local stderrFileName = stdoutFileName..".stderr"
	local status, _, ret = os.execute(program.." "..inputFileName.. "> "..stdoutFileName.." 2> "..stderrFileName)
	local returnedStatus = type(status) == "number" and status or ret or -255 -- lua 5.1 and 5.3 compatibilty
	local stdout = GetFileData(stdoutFileName)
	local stderr = GetFileData(stderrFileName)
	return returnedStatus, stdout, stderr
end

local function AssertLongStringEqual(actual, expected, msg)
	if actual ~= expected then
		lu.assertNotNil(actual, ("%s actual is nil"):format(msg or ""))
		lu.assertNotNil(expected, ("%s expected is nil"):format(msg or ""))
		local diffIndex = -1
		for i=1, expected:len() do
			if string_byte(actual, i, i) ~= string_byte(expected, i, i) then
				diffIndex = i
			end
		end
		local actualMsg = string.format("%s actualLen: %d, expectedLen:%d, first difference at: %d,"
			.." actualByte: %s, expectByte: %s", msg or "", actual:len(), expected:len(), diffIndex,
			tostring(string.byte(actual, diffIndex, diffIndex)), tostring(string.byte(expected, diffIndex, diffIndex)))
		lu.assertTrue(false, actualMsg)
	end
end

local function MemCheckAndBenchmarkFunc(func, ...)
	local memoryBefore
	local memoryRunning
	local memoryAfter
	local startTime
	local elapsedTime
	local ret
	FullMemoryCollect()
	memoryBefore =  math.floor(collectgarbage("count")*1024)
	FullMemoryCollect()
	startTime = os.clock()
	elapsedTime = -1
	local repeatCount = 0
	while elapsedTime < 0.015 do
		ret = {func(...)}
		elapsedTime = os.clock() - startTime
		repeatCount = repeatCount + 1
	end
	memoryRunning = math.floor(collectgarbage("count")*1024)
	FullMemoryCollect()
	memoryAfter = math.floor(collectgarbage("count")*1024)
	local memoryUsed = memoryRunning - memoryBefore
	local memoryLeaked = memoryAfter - memoryBefore

	return memoryLeaked, memoryUsed, elapsedTime*1000/repeatCount, unpack(ret)
end

-- TODO: allow negative start or stop?
local function CheckCompressAndDecompress(stringOrFileName, isFile, levels, start, stop)
	local origin
	if isFile then
		origin = GetFileData(stringOrFileName)
		origin = origin:sub(start or 1, stop or origin:len())
	else
		origin = stringOrFileName:sub(start or 1, stop or stringOrFileName:len())
	end

	FullMemoryCollect()
	local totalMemoryBefore = math.floor(collectgarbage("count")*1024)

	do
		if levels == "all" then
			levels = {1,2,3,4,5,6,7,8}
		else
			levels = levels or {1}
		end

		local compressFileName
		if isFile then
			compressFileName = stringOrFileName..".compress"
		else
			compressFileName = "string.compress"
		end

		local decompressFileName = compressFileName..".decompress"

		local zlibCompressFileName = compressFileName..".zlib"
		local zlibDecompressFileName = zlibCompressFileName..".decompress"

		for _, level in ipairs(levels) do
			-- Compress by raw deflate
			local compressMemoryLeaked, compressMemoryUsed, compressTime,
				compressData, compressBitSize = MemCheckAndBenchmarkFunc(LibDeflate.Compress, LibDeflate
				, origin, level, start, stop)
			lu.assertEquals(math.ceil(compressBitSize/8), compressData:len(),
				"Unexpected compress bit size")
			WriteToFile(compressFileName, compressData)

			-- Try decompress by puff
			local returnedStatus_puff, stdout_puff, stderr_puff = RunProgram("puff -w "
				, compressFileName, decompressFileName)
			lu.assertEquals(returnedStatus_puff, 0, "puff decompression failed with code "..returnedStatus_puff)
			AssertLongStringEqual(stdout_puff, origin, "puff decompress result does not match origin string.")

			-- Try decompress by zdeflate
			local returnedStatus_zdeflate, stdout_zdeflate, stderr_zdeflate = RunProgram("zdeflate -d <", compressFileName
				, decompressFileName)
			lu.assertEquals(returnedStatus_zdeflate, 0, "zdeflate decompression failed with msg "
				..stderr_zdeflate)
			AssertLongStringEqual(stdout_zdeflate, origin, "zdeflate decompress result does not match origin string.")

			-- Try decompress by LibDeflate
			local decompressMemoryLeaked, decompressMemoryUsed, decompressTime,
				decompressData, decompressUnprocessByte = MemCheckAndBenchmarkFunc(LibDeflate.Decompress, LibDeflate
				, compressData)
			lu.assertEquals(decompressUnprocessByte, 0, "Unprocessed bytes after LibDeflate decompression "
					..tostring(decompressUnprocessByte))
			AssertLongStringEqual(decompressData, origin, "LibDeflate decompress result does not match origin string.")

			-- Compress with Zlib header instead of raw Deflate
			local zlibCompressMemoryLeaked, zlibCompressMemoryUsed, zlibCompressTime,
				zlibCompressData, zlibCompressBitSize = MemCheckAndBenchmarkFunc(LibDeflate.CompressZlib, LibDeflate
				, origin, level, start, stop)
			lu.assertEquals(zlibCompressBitSize/8, zlibCompressData:len(), "Unexpected zlib bit size")


			WriteToFile(zlibCompressFileName, zlibCompressData)

			local zlibReturnedStatus_zdeflate, zlibStdout_zdeflate, zlibStderr_zdeflate =
				RunProgram("zdeflate --zlib -d <", zlibCompressFileName, zlibDecompressFileName)
			lu.assertEquals(zlibReturnedStatus_zdeflate, 0, "zdeflate fails to decompress zlib with msg "
				..tostring(zlibStderr_zdeflate))
			AssertLongStringEqual(zlibStdout_zdeflate, origin,
				"zDeflate decompress result does not match origin zlib string.")

			local zlibDecompressMemoryLeaked, zlibDecompressMemoryUsed, zlibDecompressTime,
				zlibDecompressData, zlibDecompressUnprocessByte = MemCheckAndBenchmarkFunc(LibDeflate.DecompressZlib, LibDeflate
				, zlibCompressData)
			lu.assertEquals(zlibDecompressUnprocessByte, 0, "Unprocessed bytes after LibDeflate zlib decompression "
					..tostring(zlibDecompressUnprocessByte))
			AssertLongStringEqual(zlibDecompressData, origin
				, "LibDeflate zlib decompress result does not match origin string.")

			print(
				(">>>>> %s: %s Level: %d size: %d B\n"):format(isFile and "File" or "String",
					stringOrFileName:sub(1, 40), level, origin:len()),
				("CompressDeflate:   Size : %d B,\tTime: %.3f ms, Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak: %d B)\n"):format(
					compressData:len(), compressTime, compressData:len()/compressTime, compressMemoryUsed,
					compressMemoryUsed/origin:len(), compressMemoryLeaked
				),
				("DecompressDeflate: cRatio: %.2f,\tTime: %.3f ms, Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak: %d B)\n"):format(
					origin:len()/compressData:len(), decompressTime, decompressData:len()/decompressTime, decompressMemoryUsed,
					decompressMemoryUsed/origin:len(), decompressMemoryLeaked
				),
				("CompressZlib:      Size : %d B,\tTime: %.3f ms, Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak: %d B)\n"):format(
					zlibCompressData:len(), zlibCompressTime, zlibCompressData:len()/zlibCompressTime, zlibCompressMemoryUsed,
					zlibCompressMemoryUsed/origin:len(), zlibCompressMemoryLeaked
				),
				("DecompressZlib:    cRatio: %.2f,\tTime: %.3f ms, Speed: %.0f KB/s, Memory: %d B,"
					.." Mem/input: %.2f, (memleak: %d B)\n"):format(
					origin:len()/compressData:len(), zlibDecompressTime, zlibDecompressData:len()/zlibDecompressTime
					, zlibDecompressMemoryUsed,zlibDecompressMemoryUsed/origin:len(), zlibDecompressMemoryLeaked
				),
				"\n"
			)
		end

		-- Use all avaiable strategies of zdeflate to compress the data, and see if LibDeflate can decompress it.
		local tmpFileName = "tmp.tmp"
		WriteToFile(tmpFileName, origin)

		local zdeflate_level, zdeflate_strategy
		local strategies = {"--filter", "--huffman", "--rle", "--fix", "--default"}
		local unique_compress = {}
		local uniques_compress_count = 0
		for level=0, 8 do
			zdeflate_level = "-"..level
			for j=1, #strategies do
				zdeflate_strategy = strategies[j]
				local status, stdout, stderr = RunProgram("zdeflate "..zdeflate_level.." "..zdeflate_strategy
					.." < ", tmpFileName, tmpFileName..".out")
				lu.assertEquals(status, 0, ("zdeflate cant compress the file? stderr: %s level: %s, strategy: %s")
					:format(stderr, zdeflate_level, zdeflate_strategy))
				if not unique_compress[stdout] then
					unique_compress[stdout] = true
					uniques_compress_count = uniques_compress_count + 1
					local decompressData = LibDeflate:Decompress(stdout)
					AssertLongStringEqual(decompressData, origin,
						("My decompress fail to decompress at zdeflate level: %s, strategy: %s")
						:format(level, zdeflate_strategy))
				end
			end
		end
		print(
			(">>>>> %s: %s size: %d B\n")
				:format(isFile and "File" or "String", stringOrFileName:sub(1, 40), origin:len()),
			("Full decompress coverage test ok. unique compresses: %d\n")
				:format(uniques_compress_count),
			"\n")
	end

	FullMemoryCollect()
	local totalMemoryAfter = math.floor(collectgarbage("count")*1024)

	local totalMemoryDifference = totalMemoryBefore - totalMemoryAfter

	if totalMemoryDifference > 0 then
		print(
			(">>>>> %s: %s size: %d B\n")
				:format(isFile and "File" or "String", stringOrFileName:sub(1, 40), origin:len()),
			("Actual Memory Leak in the test: %d\n")
				:format(totalMemoryDifference),
			"\n")
		-- ^If above "leak" is very small, it is very likely that it is false positive.
		if not jit and totalMemoryDifference >  64 then
			-- Lua JIT has some problems to garbage collect stuffs, so don't consider as failure.
			lu.assertTrue(false, ("Fail the test because too many actual Memory Leak in the test: %d")
				:format(totalMemoryDifference))
		end
	end

	return 0
end

local function CheckDecompressIncludingError(compress, decompress, start, stop, isZlib)
	start = start or 1
	stop = stop or compress:len()
	local d, decompress_return
	if isZlib then
		d, decompress_return = LibDeflate:DecompressZlib(compress, start, stop)
	else
		d, decompress_return = LibDeflate:Decompress(compress, start, stop)
	end
	if d ~= decompress then
		lu.assertTrue(false, ("My decompress does not match expected result."..
			"expected: %s, actual: %s, Returned status of decompress: %d")
			:format(StringForPrint(StringToHex(d)), StringForPrint(StringToHex(decompress)), decompress_return))
	else
		-- Check my decompress result with "puff"
		local inputFileName = "tmpFile"
		local inputFile = io.open(inputFileName, "wb")
		inputFile:setvbuf("full")
		inputFile:write(compress:sub(start, stop))
		inputFile:flush()
		inputFile:close()
		local returnedStatus_puff, stdout_puff, stderr_puff = RunProgram("puff -w", inputFileName
			, inputFileName..".decompress")
		local returnedStatus_zdeflate, stdout_zdeflate, stderr_zdeflate =
			RunProgram(isZlib and "zdeflate --zlib -d <" or "zdeflate -d <", inputFileName, inputFileName..".decompress")
		if not d then
			if not isZlib then
				if returnedStatus_puff ~= 0 and returnedStatus_zdeflate ~= 0 then
					print((">>>> %q cannot be decompress as expected"):format((StringForPrint(StringToHex(compress)))))
				elseif returnedStatus_puff ~= 0 and returnedStatus_zdeflate == 0 then
					lu.assertTrue(false,
					(">>>> %q puff error but not zdeflate?"):format((StringForPrint(StringToHex(compress)))))
				elseif returnedStatus_puff == 0 and returnedStatus_zdeflate ~= 0 then
					lu.assertTrue(false,
					(">>>> %q zdeflate error but not puff?"):format((StringForPrint(StringToHex(compress)))))
				else
					lu.assertTrue(false,
					(">>>> %q my decompress error, but not puff or zdeflate"):format((StringForPrint(StringToHex(compress)))))
				end
			else
				if returnedStatus_zdeflate ~= 0 then
					print((">>>> %q cannot be zlib decompress as expected"):format(StringForPrint(StringToHex(compress))))
				else
					lu.assertTrue(false,
					(">>>> %q my decompress error, but not zdeflate"):format((StringForPrint(StringToHex(compress)))))
				end
			end

		else
			AssertLongStringEqual(d, stdout_zdeflate)
			if not isZlib then
				AssertLongStringEqual(d, stdout_puff)
			end
			print((">>>> %q is decompressed to %q as expected")
				:format(StringForPrint(StringToHex(compress)), StringForPrint(StringToHex(d))))
		end
	end

end

local function CheckCompressAndDecompressString(str, levels, start, stop)
	return CheckCompressAndDecompress(str, false, levels, start, stop)
end

local function CheckCompressAndDecompressFile(inputFileName, levels, start, stop)
	return CheckCompressAndDecompress(inputFileName, true, levels, start, stop)
end

-- Commandline
if args and #args >= 1 and type(args[0]) == "string" then
	if #args >= 2 and args[1] == "-o" then
	-- For testing purpose, check if the file can be opened by lua
		local input = args[2]
		local inputFile = io.open(input, "rb")
		if not inputFile then
			os.exit(1)
		end
		inputFile.close()
		os.exit(0)
	elseif #args >= 3 and args[1] == "-c" then
	-- For testing purpose, check the if a file can be correctly compress and decompress to origin
		os.exit(CheckCompressAndDecompressFile(args[2], "all", 0, args[3])) -- TODO
	end
end

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

	function TestBasicStrings:testRepeatInTheMiddle()
		CheckCompressAndDecompressString("aaaaaaaaaaaaaaaaaa", "all", nil, nil, nil, 2, 8)
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

	function TestMyData:TestSmallTestInTheMiddle()
		CheckCompressAndDecompressFile("tests/data/smalltest.txt", "all", nil, 10, GetFileSize("tests/data/smalltest.txt")-10)
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
		CheckCompressAndDecompressFile("tests/data/3rdparty/random_chunks", "all")
	end

	function TestThirdPartyMedium:TestGrammerLsp()
		CheckCompressAndDecompressFile("tests/data/3rdparty/grammar.lsp", "all")
	end

	function TestThirdPartyMedium:TestXargs1()
		CheckCompressAndDecompressFile("tests/data/3rdparty/xargs.1", "all")
	end

	function TestThirdPartyMedium:TestRandomOrg10KBin()
		CheckCompressAndDecompressFile("tests/data/3rdparty/random_org_10k.bin", "all")
	end

	function TestThirdPartyMedium:TestCpHtml()
		CheckCompressAndDecompressFile("tests/data/3rdparty/cp.html", "all")
	end

	function TestThirdPartyMedium:TestBadData1Snappy()
		CheckCompressAndDecompressFile("tests/data/3rdparty/baddata1.snappy", "all")
	end

	function TestThirdPartyMedium:TestBadData2Snappy()
		CheckCompressAndDecompressFile("tests/data/3rdparty/baddata2.snappy", "all")
	end

	function TestThirdPartyMedium:TestBadData3Snappy()
		CheckCompressAndDecompressFile("tests/data/3rdparty/baddata3.snappy", "all")
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
		CheckCompressAndDecompressFile("tests/data/3rdparty/backward65536", "all")
	end
	function TestThirdPartyBig:TestHTML()
		CheckCompressAndDecompressFile("tests/data/3rdparty/html", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestPaper100kPdf()
		CheckCompressAndDecompressFile("tests/data/3rdparty/paper-100k.pdf", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestGeoProtodata()
		CheckCompressAndDecompressFile("tests/data/3rdparty/geo.protodata", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestFireworksJpeg()
		CheckCompressAndDecompressFile("tests/data/3rdparty/fireworks.jpeg", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestAsyoulik()
		CheckCompressAndDecompressFile("tests/data/3rdparty/asyoulik.txt", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestCompressedRepeated()
		CheckCompressAndDecompressFile("tests/data/3rdparty/compressed_repeated", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestAlice29()
		CheckCompressAndDecompressFile("tests/data/3rdparty/alice29.txt", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestQuickfox_repeated()
		CheckCompressAndDecompressFile("tests/data/3rdparty/quickfox_repeated", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestKppknGtb()
		CheckCompressAndDecompressFile("tests/data/3rdparty/kppkn.gtb", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestZeros()
		CheckCompressAndDecompressFile("tests/data/3rdparty/zeros", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestMapsdatazrh()
		CheckCompressAndDecompressFile("tests/data/3rdparty/mapsdatazrh", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestHtml_x_4()
		CheckCompressAndDecompressFile("tests/data/3rdparty/html_x_4", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestLcet10()
		CheckCompressAndDecompressFile("tests/data/3rdparty/lcet10.txt", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestPlrabn12()
		CheckCompressAndDecompressFile("tests/data/3rdparty/plrabn12.txt", {1,2,3,4,5})
	end
	function TestThirdPartyBig:TestUrls10K()
		CheckCompressAndDecompressFile("tests/data/3rdparty/urls.10K", {1,2,3,4,5})
	end
	function TestThirdPartyBig:Testptt5()
		CheckCompressAndDecompressFile("tests/data/3rdparty/ptt5", {1,2,3,4})
	end
	function TestThirdPartyBig:TestKennedyXls()
		CheckCompressAndDecompressFile("tests/data/3rdparty/kennedy.xls", {1,2,3,4})
	end

TestWoWData = {}
	function TestWoWData:TestWarlockWeakAuras()
		CheckCompressAndDecompressFile("tests/data/warlockWeakAuras.txt", "all")
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
		CheckDecompressIncludingError("\000\255\255\000\000"..str.."\001\255\255\000\000"..str, str..str)
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
				..string.char(255-size%256)..string.char(255-(size-size%256)/256)..str, str)
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
		CheckDecompressIncludingError("\050\004\000\255\255\000\000"..str.."\001\255\255\000\000"..str, "1"..str..str)
	end
	function TestDecompress:TestIncomplete()
		-- Additonal 1 byte after the end of compression data
		CheckDecompressIncludingError("\001\001\000\254\255\010\000", "\010")
	end
	function TestDecompress:TestInTheMiddle()
		-- Additonal 1 byte before and 1 byte after.
		CheckDecompressIncludingError("\001\001\001\000\254\255\010\001", "\010", 2, 7)
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
		CheckDecompressIncludingError(HexToString("04 80 49 92 24 49 92 24 0f b4 ff ff c3 04"), nil)
	end
	function TestDecompress:TestPuffReturn245()
		CheckDecompressIncludingError(HexToString("0c c0 81 00 00 00 00 00 90 ff 6b 04"), nil)
	end
	function TestDecompress:TestPuffReturn246()
		CheckDecompressIncludingError(HexToString("1a 07"), nil)
		CheckDecompressIncludingError(HexToString("02 7e ff ff"), nil)
		CheckDecompressIncludingError(HexToString("04 c0 81 08 00 00 00 00 20 7f eb 0b 00 00"), nil)
	end
	function TestDecompress:TestPuffReturn247()
		CheckDecompressIncludingError(HexToString("04 00 24 e9 ff 6d"), nil)
	end
	function TestDecompress:TestPuffReturn248()
		CheckDecompressIncludingError(HexToString("04 80 49 92 24 49 92 24 0f b4 ff ff c3 84"), nil)
	end
	function TestDecompress:TestPuffReturn249()
		CheckDecompressIncludingError(HexToString("04 80 49 92 24 49 92 24 71 ff ff 93 11 00"), nil)
	end
	function TestDecompress:TestPuffReturn250()
		CheckDecompressIncludingError(HexToString("04 00 24 e9 ff ff"), nil)
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
		local tmp = {}
		local zeros = table.concat(tmp)
		CheckDecompressIncludingError(HexToString("63 18 68 30 d0 0 0"), ("\000"):rep(257))
		CheckDecompressIncludingError(HexToString("3 00"), "")
		CheckDecompressIncludingError("", nil)
		CheckDecompressIncludingError("", nil, nil, nil, true)
	end
	function TestDecompress:TestZlibCoverWrap()
		CheckDecompressIncludingError(HexToString("77 85"), nil, nil, nil, true) -- Bad zlib header
		CheckDecompressIncludingError(HexToString("70 85"), nil, nil, nil, true) -- Bad zlib header
		CheckDecompressIncludingError(HexToString("88 9c"), nil, nil, nil, true) -- Bad window size
		CheckDecompressIncludingError(HexToString("f8 9c"), nil, nil, nil, true) -- Bad window size
		CheckDecompressIncludingError(HexToString("78 90"), nil, nil, nil, true) -- Bad zlib header check
		CheckDecompressIncludingError(HexToString("78 9c 63 00 00 00 01 00 01"), "\000", nil, nil, true) -- check Adler32
		CheckDecompressIncludingError(HexToString("78 9c 63 00 00 00 01 00"), nil, nil, nil, true) -- Adler32 incomplete
		CheckDecompressIncludingError(HexToString("78 9c 63 00 00 00 01 00 02"), nil, nil, nil, true) -- wrong Adler32
		CheckDecompressIncludingError(HexToString("78 9c 63 0"), nil, nil, nil, true) -- no Adler32
	end
	function TestDecompress:TestZlibCoverInflate()
		CheckDecompressIncludingError(HexToString("0 0 0 0 0"), nil) -- invalid store block length
		CheckDecompressIncludingError(HexToString("3 0"), "", nil) -- Fixed block
		CheckDecompressIncludingError(HexToString("6"), nil) -- Invalid block type
		CheckDecompressIncludingError(HexToString("1 1 0 fe ff 0"), "\000") -- Stored block
		CheckDecompressIncludingError(HexToString("fc 0 0"), nil) -- Too many length or distance symbols
		CheckDecompressIncludingError(HexToString("4 0 fe ff"), nil) -- Invalid code lengths set
		CheckDecompressIncludingError(HexToString("4 0 24 49 0"), nil) -- Invalid bit length repeat
		CheckDecompressIncludingError(HexToString("4 0 24 e9 ff ff"), nil) -- Invalid bit length repeat
		CheckDecompressIncludingError(HexToString("4 0 24 e9 ff 6d"), nil) -- Invalid code: missing end of block
		-- Invalid literal/lengths set
		CheckDecompressIncludingError(HexToString("4 80 49 92 24 49 92 24 71 ff ff 93 11 0"), nil)
		-- Invalid distance set
		CheckDecompressIncludingError(HexToString("4 80 49 92 24 49 92 24 f b4 ff ff c3 84"), nil)
		-- Invalid literal/length code
		CheckDecompressIncludingError(HexToString("4 c0 81 8 0 0 0 0 20 7f eb b 0 0"), nil)
		CheckDecompressIncludingError(HexToString("2 7e ff ff"), nil) -- Invalid distance code
		CheckDecompressIncludingError(HexToString("c c0 81 0 0 0 0 0 90 ff 6b 4 0"), nil) -- Invalid distance too far
		CheckDecompressIncludingError(HexToString("1f 8b 8 0 0 0 0 0 0 0 3 0 0 0 0 1"), nil) -- incorrect data check
		CheckDecompressIncludingError(HexToString("1f 8b 8 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 1"), nil) --incorrect length check
		CheckDecompressIncludingError(HexToString("5 c0 21 d 0 0 0 80 b0 fe 6d 2f 91 6c"), "") -- pull 17
		-- long code
		CheckDecompressIncludingError(HexToString("05 e0 81 91 24 cb b2 2c 49 e2 0f 2e 8b 9a 47 56 9f fb fe ec d2 ff 1f"), "")
		-- extra length
		CheckDecompressIncludingError(HexToString("ed c0 1 1 0 0 0 40 20 ff 57 1b 42 2c 4f"), ("\000"):rep(516))
		-- long distance and extra
		CheckDecompressIncludingError(HexToString("ed cf c1 b1 2c 47 10 c4 30 fa 6f 35 1d 1 82 59 3d fb be 2e 2a fc f c")
			, ("\000"):rep(518))
		-- Window end
		CheckDecompressIncludingError(HexToString("ed c0 81 0 0 0 0 80 a0 fd a9 17 a9 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0")
			, nil)
		-- inflate_fast TYPE return
		CheckDecompressIncludingError(HexToString("2 8 20 80 0 3 0"), "")
		-- Window wrap
		CheckDecompressIncludingError(HexToString("63 18 5 40 c 0"), ("\000"):rep(262))
	end
	function TestDecompress:TestZlibCoverFast()
		-- fast length extra bits
		CheckDecompressIncludingError(
			HexToString("e5 e0 81 ad 6d cb b2 2c c9 01 1e 59 63 ae 7d ee fb 4d fd b5 35 41 68"), nil)
		-- fast distance extra bits
		CheckDecompressIncludingError(
			HexToString("25 fd 81 b5 6d 59 b6 6a 49 ea af 35 6 34 eb 8c b9 f6 b9 1e ef 67 49"), nil)
		CheckDecompressIncludingError(HexToString("3 7e 0 0 0 0 0"), nil) -- Fast invalid distance code
		CheckDecompressIncludingError(HexToString("1b 7 0 0 0 0 0"), nil) -- Fast literal/length code
		-- fast 2nd level codes and too far back
		CheckDecompressIncludingError(
			HexToString("d c7 1 ae eb 38 c 4 41 a0 87 72 de df fb 1f b8 36 b1 38 5d ff ff 0"), nil)
		-- Very common case
		CheckDecompressIncludingError(
			HexToString("63 18 5 8c 10 8 0 0 0 0"), ("\000"):rep(258)..("\000\001"):rep(4))
		-- Continous and wrap aroudn window
		CheckDecompressIncludingError(
			HexToString("63 60 60 18 c9 0 8 18 18 18 26 c0 28 0 29 0 0 0")
			, ("\000"):rep(261)..("\144")..("\000"):rep(6)..("\144\000"))
		-- Copy direct from output
		CheckDecompressIncludingError(HexToString("63 0 3 0 0 0 0 0"), ("\000"):rep(6))
	end

TestInternals = {}
	-- Test from puff
	function TestInternals:TestLoadString()
		local loadStrToTable = LibDeflate.internals.loadStrToTable
		local tmp
		for _=1, 50 do
			local t = {}
			local strLen = math.random(0, 1000)
			local str = GetLimitedRandomString(strLen)
			local uncorruped_data = {}
			for i=1, strLen do
				uncorruped_data[i] = math.random(1, 12345)
				t[i] = uncorruped_data[i]
			end
			local start
			local stop
			if strLen >= 1 then
				start = math.random(1, strLen)
				stop = math.random(1, strLen)
			else
				start = 1
				stop = 0
			end
			if start > stop then
				tmp = start
				start = stop
				stop = tmp
			end
			loadStrToTable(str, t, start, stop)
			for i=1, strLen do
				if i < start or i > stop then
					lu.assertEquals(t[i], uncorruped_data[i], "loadStr corrupts unintended location")
				else
					lu.assertEquals(t[i], string_byte(str, i, i), ("loadStr gives wrong data!, start=%d, stop=%d, i=%d")
						:format(start, stop, i))
				end
			end
		end
	end

	function TestInternals:TestSimpleRandom()
		local compressEmpty = LibDeflate:Compress("")
		lu.assertEquals(LibDeflate:Decompress(compressEmpty), "", "My decompress does not match origin for empty string.")
		for _=1, 50 do
			local tmp
			local strLen = math.random(0, 1000)
			local str = GetLimitedRandomString(strLen)
			local start = (math.random() < 0.5) and (math.random(0, strLen)) or nil
			local stop = (math.random() < 0.5) and (math.random(0, strLen)) or nil
			if start and stop and start > stop then
				tmp = start
				start = stop
				stop = tmp
			end
			local level = (math.random() < 0.5) and (math.random(1, 8)) or nil

			local expected = str:sub(start or 1, stop or str:len())
			local compress = LibDeflate:Compress(str, level, start, stop)
			local _, actual = pcall(function() return LibDeflate:Decompress(compress) end)
			if expected ~= actual then
				local strDumpFile = io.open("fail_random.txt", "wb")
				if (strDumpFile) then
					strDumpFile:write(str)
					print(("Failed test has been dumped to fail_random.txt, with level=%s, start=%s, stop=%s"):
						format(tostring(level), tostring(start), tostring(stop)))
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
		lu.assertEquals(1, LibDeflate:Adler32(""))
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
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefghijkl"), 0x3BC80678)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefghijklm"), 0x42AD06E5)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcefghijklmn"), 0x4A000753)
		lu.assertEquals(LibDeflate:Adler32("1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"), 0x8C40150C)
		local adler32Test = GetFileData("tests/data/adler32Test.txt")
		lu.assertEquals(LibDeflate:Adler32(adler32Test), 0x5D9BAF5D)
		lu.assertEquals(LibDeflate:Adler32(adler32Test, 2), 0x9077AEF9)
		lu.assertEquals(LibDeflate:Adler32(adler32Test, 2, adler32Test:len()-1), 0xE16FAEC4)
		lu.assertEquals(LibDeflate:Adler32(adler32Test, nil, adler32Test:len()-1), 0xAE2FAF28)
		lu.assertEquals(LibDeflate:Adler32(adler32Test, 2, 1), 1)
		local adler32Test2 = GetFileData("tests/data/adler32Test2.txt")
		lu.assertEquals(LibDeflate:Adler32(adler32Test2), 0xD6A07E29)
	end

	function TestInternals:TestLibStub()
		-- Start of LibStub
		local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2
		local LibStub = _G[LIBSTUB_MAJOR]

		if not LibStub or LibStub.minor < LIBSTUB_MINOR then
			LibStub = LibStub or {libs = {}, minors = {} }
			_G[LIBSTUB_MAJOR] = LibStub
			LibStub.minor = LIBSTUB_MINOR
			function LibStub:NewLibrary(major, minor)
				assert(type(major) == "string", "Bad argument #2 to `NewLibrary' (string expected)")
				minor = assert(tonumber(string.match(minor, "%d+")), "Minor version must either be a number or contain a number.")

				local oldminor = self.minors[major]
				if oldminor and oldminor >= minor then return nil end
				self.minors[major], self.libs[major] = minor, self.libs[major] or {}
				return self.libs[major], oldminor
			end
			function LibStub:GetLibrary(major, silent)
				if not self.libs[major] and not silent then
					error(("Cannot find a library instance of %q."):format(tostring(major)), 2)
				end
				return self.libs[major], self.minors[major]
			end
			function LibStub:IterateLibraries() return pairs(self.libs) end
			setmetatable(LibStub, { __call = LibStub.GetLibrary })
		end
		-- End of LibStub
		local MAJOR = "LibDeflate"
		CheckCompressAndDecompressString("aaabbbcccddddddcccbbbaaa", "all")
		LibDeflate = dofile("LibDeflate.lua")
		lu.assertNotNil(LibDeflate, "LibStub does not return LibDeflate")
		lu.assertEquals(LibStub:GetLibrary(MAJOR, true), LibDeflate, "Cant find LibDeflate in LibStub.")
		CheckCompressAndDecompressString("aaabbbcccddddddcccbbbaaa", "all")
		------------------------------------------------------
		FullMemoryCollect()
		local memory1 = math.floor(collectgarbage("collect")*1024)
		local LibDeflateTmp = dofile("LibDeflate.lua")
		lu.assertEquals(LibDeflateTmp, LibDeflate, "LibStub unexpectedly recreates the library.")
		lu.assertNotNil(LibDeflate, "LibStub does not return LibDeflate")
		lu.assertEquals(LibStub:GetLibrary(MAJOR, true), LibDeflate, "Cant find LibDeflate in LibStub.")
		CheckCompressAndDecompressString("aaabbbcccddddddcccbbbaaa", "all")
		FullMemoryCollect()
		local memory2 = math.floor(collectgarbage("collect")*1024)
		if not jit then
			lu.assertTrue((memory2 - memory1 <= 32), ("Too much Memory leak after LibStub without update: %d")
				:format(memory2-memory1))
		end
		----------------------------------------------------
		LibStub.minors[MAJOR] = -1000
		FullMemoryCollect()
		local memory3 = math.floor(collectgarbage("collect")*1024)
		LibDeflateTmp = dofile("LibDeflate.lua")
		CheckCompressAndDecompressString("aaabbbcccddddddcccbbbaaa", "all")
		FullMemoryCollect()
		local memory4 = math.floor(collectgarbage("collect")*1024)
		lu.assertEquals(LibDeflateTmp, LibDeflate, "LibStub unexpectedly recreates the library.")
		lu.assertTrue(LibStub.minors[MAJOR] > -1000, "LibDeflate is not updated.")
		if not jit then
			lu.assertTrue((memory4 - memory3 <= 100), ("Too much Memory leak after LibStub update: %d")
				:format(memory4-memory3))
		end
	end

local function AddToCoverageTest(suite, test)
	assert(suite)
	assert(type(suite[test]) == "function")
	CodeCoverage[test] = function(_, ...) return suite[test](_G[suite], ...) end
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
	AddToCoverageTest(TestThirdPartyBig, "TestUrls10K")
	AddToCoverageTest(TestThirdPartyBig, "Testptt5")
	AddToCoverageTest(TestThirdPartyBig, "TestKennedyXls")

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