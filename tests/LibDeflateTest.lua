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
local string_byte = string.byte
local unpack = unpack or table.unpack
math.randomseed(0) -- I don't like true random tests that I cant 100% reproduce.

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

local function GetRandomString(strLen)
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

local function CheckDecompressIncludingError(compress, decompress, start, stop)
	start = start or 1
	stop = stop or compress:len()
	local d, decompress_return = LibDeflate:Decompress(compress, start, stop)
	if d ~= decompress then
		lu.assertTrue(false, ("My decompress does not match expected result."..
			"expected: %s, actual: %s, Returned status of decompress: %d"):format(decompress, d, decompress_return))
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
		local returnedStatus_zdeflate, stdout_zdeflate, stderr_zdeflate = RunProgram("zdeflate -d <", inputFileName
			, inputFileName..".decompress")
		if not d then
			if returnedStatus_puff ~= 0 and returnedStatus_zdeflate ~= 0 then
				print((">>>> %q cannot be decompress as expected"):format(compress:sub(1, 15)))
			elseif returnedStatus_puff ~= 0 and returnedStatus_zdeflate == 0 then
				lu.assertTrue(false, "Puff error but not zdeflate?")
			elseif returnedStatus_puff == 0 and returnedStatus_zdeflate ~= 0 then
				lu.assertTrue(false, "zDeflate error but not puff?")
			else
				lu.assertTrue(false, "My decompress returns error, but not puff and zdeflate.")
			end

		else
			if d == stdout_puff and d == stdout_zdeflate then
				print((">>>> %q is decompress successfully"):format(compress:sub(1, 15)))
			else
				lu.assertTrue(false, "My decompress result does not match puff or zdeflate.")
			end
			if decompress_return ~= 0 then
				-- decompress_return is the number of unprocessed bytes in the data.
				-- Some byte not processed, compare with puff and zdeflate
				lu.assertEquals(("%d"):format(decompress_return), stderr_puff, "My decompress unprocessed bytes not match puff")
				lu.assertEquals(("%d"):format(decompress_return), stderr_zdeflate,
				 "My decompress unprocessed bytes not match zdeflate")
			end
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

TestMin1Strings = {}
	function TestMin1Strings:testEmpty()
		CheckCompressAndDecompressString("", "all")
	end
	function TestMin1Strings:testAllLiterals1()
		CheckCompressAndDecompressString("ab", "all")
	end
	function TestMin1Strings:testAllLiterals2()
		CheckCompressAndDecompressString("abcdefgh", "all")
	end
	function TestMin1Strings:testAllLiterals3()
		local t = {}
		for i=0, 255 do
			t[#t+1] = string.char(i)
		end
		local str = table.concat(t)
		CheckCompressAndDecompressString(str, "all")
	end

	function TestMin1Strings:testRepeat()
		CheckCompressAndDecompressString("aaaaaaaaaaaaaaaaaa", "all")
	end

	function TestMin1Strings:testRepeatInTheMiddle()
		CheckCompressAndDecompressString("aaaaaaaaaaaaaaaaaa", "all", nil, nil, nil, 2, 8)
	end

	function TestMin1Strings:testLongRepeat()
		local repeated = {}
		for i=1, 100000 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end

TestMin2MyData = {}
	function TestMin2MyData:TestItemStrings()
		CheckCompressAndDecompressFile("tests/data/itemStrings.txt", "all")
	end

	function TestMin2MyData:TestSmallTest()
		CheckCompressAndDecompressFile("tests/data/smalltest.txt", "all")
	end

	function TestMin2MyData:TestSmallTestInTheMiddle()
		CheckCompressAndDecompressFile("tests/data/smalltest.txt", "all", nil, 10, GetFileSize("tests/data/smalltest.txt")-10)
	end

	function TestMin2MyData:TestReconnectData()
		CheckCompressAndDecompressFile("tests/data/reconnectData.txt", "all")
	end

TestMin3ThirdPartySmall = {}
	function TestMin3ThirdPartySmall:TestEmpty()
		CheckCompressAndDecompressFile("tests/data/3rdparty/empty", "all")
	end

	function TestMin3ThirdPartySmall:TestX()
		CheckCompressAndDecompressFile("tests/data/3rdparty/x", "all")
	end

	function TestMin3ThirdPartySmall:TestXYZZY()
		CheckCompressAndDecompressFile("tests/data/3rdparty/xyzzy", "all")
	end

Test4ThirdPartyMedium = {}
	function Test4ThirdPartyMedium:Test10x10y()
		CheckCompressAndDecompressFile("tests/data/3rdparty/10x10y", "all")
	end

	function Test4ThirdPartyMedium:TestQuickFox()
		CheckCompressAndDecompressFile("tests/data/3rdparty/quickfox", "all")
	end

	function Test4ThirdPartyMedium:Test64x()
		CheckCompressAndDecompressFile("tests/data/3rdparty/64x", "all")
	end

	function Test4ThirdPartyMedium:TestUkkonoona()
		CheckCompressAndDecompressFile("tests/data/3rdparty/ukkonooa", "all")
	end

	function Test4ThirdPartyMedium:TestMonkey()
		CheckCompressAndDecompressFile("tests/data/3rdparty/monkey", "all")
	end

	function Test4ThirdPartyMedium:TestRandomChunks()
		CheckCompressAndDecompressFile("tests/data/3rdparty/random_chunks", "all")
	end

	function Test4ThirdPartyMedium:TestGrammerLsp()
		CheckCompressAndDecompressFile("tests/data/3rdparty/grammar.lsp", "all")
	end

	function Test4ThirdPartyMedium:TestXargs1()
		CheckCompressAndDecompressFile("tests/data/3rdparty/xargs.1", "all")
	end

	function Test4ThirdPartyMedium:TestRandomOrg10KBin()
		CheckCompressAndDecompressFile("tests/data/3rdparty/random_org_10k.bin", "all")
	end

	function Test4ThirdPartyMedium:TestCpHtml()
		CheckCompressAndDecompressFile("tests/data/3rdparty/cp.html", "all")
	end

	function Test4ThirdPartyMedium:TestBadData1Snappy()
		CheckCompressAndDecompressFile("tests/data/3rdparty/baddata1.snappy", "all")
	end

	function Test4ThirdPartyMedium:TestBadData2Snappy()
		CheckCompressAndDecompressFile("tests/data/3rdparty/baddata2.snappy", "all")
	end

	function Test4ThirdPartyMedium:TestBadData3Snappy()
		CheckCompressAndDecompressFile("tests/data/3rdparty/baddata3.snappy", "all")
	end

	function Test4ThirdPartyMedium:TestSum()
		CheckCompressAndDecompressFile("tests/data/3rdparty/sum", "all")
	end

Test5_64K = {}
	function Test5_64K:Test64KFile()
		CheckCompressAndDecompressFile("tests/data/64k.txt", "all")
	end
	function Test5_64K:Test64KFilePlus1()
		CheckCompressAndDecompressFile("tests/data/64kplus1.txt", "all")
	end
	function Test5_64K:Test64KFilePlus2()
		CheckCompressAndDecompressFile("tests/data/64kplus2.txt", "all")
	end
	function Test5_64K:Test64KFilePlus3()
		CheckCompressAndDecompressFile("tests/data/64kplus3.txt", "all")
	end
	function Test5_64K:Test64KFilePlus4()
		CheckCompressAndDecompressFile("tests/data/64kplus4.txt", "all")
	end
	function Test5_64K:Test64KFileMinus1()
		CheckCompressAndDecompressFile("tests/data/64kminus1.txt", "all")
	end
	function Test5_64K:Test64KRepeated()
		local repeated = {}
		for i=1, 65536 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedPlus1()
		local repeated = {}
		for i=1, 65536+1 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedPlus2()
		local repeated = {}
		for i=1, 65536+2 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedPlus3()
		local repeated = {}
		for i=1, 65536+3 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedPlus4()
		local repeated = {}
		for i=1, 65536+4 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedMinus1()
		local repeated = {}
		for i=1, 65536-1 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedMinus2()
		local repeated = {}
		for i=1, 65536-2 do
			repeated[i] = "c"
		end
		CheckCompressAndDecompressString(table.concat(repeated), "all")
	end

-- > 64K
Test6ThirdPartyBig = {}
	function Test6ThirdPartyBig:TestBackward65536()
		CheckCompressAndDecompressFile("tests/data/3rdparty/backward65536", "all")
	end
	function Test6ThirdPartyBig:TestHTML()
		CheckCompressAndDecompressFile("tests/data/3rdparty/html", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestPaper100kPdf()
		CheckCompressAndDecompressFile("tests/data/3rdparty/paper-100k.pdf", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestGeoProtodata()
		CheckCompressAndDecompressFile("tests/data/3rdparty/geo.protodata", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestFireworksJpeg()
		CheckCompressAndDecompressFile("tests/data/3rdparty/fireworks.jpeg", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestAsyoulik()
		CheckCompressAndDecompressFile("tests/data/3rdparty/asyoulik.txt", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestCompressedRepeated()
		CheckCompressAndDecompressFile("tests/data/3rdparty/compressed_repeated", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestAlice29()
		CheckCompressAndDecompressFile("tests/data/3rdparty/alice29.txt", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestQuickfox_repeated()
		CheckCompressAndDecompressFile("tests/data/3rdparty/quickfox_repeated", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestKppknGtb()
		CheckCompressAndDecompressFile("tests/data/3rdparty/kppkn.gtb", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestZeros()
		CheckCompressAndDecompressFile("tests/data/3rdparty/zeros", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestMapsdatazrh()
		CheckCompressAndDecompressFile("tests/data/3rdparty/mapsdatazrh", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestHtml_x_4()
		CheckCompressAndDecompressFile("tests/data/3rdparty/html_x_4", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestLcet10()
		CheckCompressAndDecompressFile("tests/data/3rdparty/lcet10.txt", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestPlrabn12()
		CheckCompressAndDecompressFile("tests/data/3rdparty/plrabn12.txt", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:Testptt5()
		CheckCompressAndDecompressFile("tests/data/3rdparty/ptt5", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestUrls10K()
		CheckCompressAndDecompressFile("tests/data/3rdparty/urls.10K", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestKennedyXls()
		CheckCompressAndDecompressFile("tests/data/3rdparty/kennedy.xls", {1,2,3,4,5})
	end

Test7WoWData = {}
	function Test7WoWData:TestWarlockWeakAuras()
		CheckCompressAndDecompressFile("tests/data/warlockWeakAuras.txt", "all")
	end

TestMin8Decompress = {}
	-- Test from puff
	function TestMin8Decompress:TestStoreEmpty()
		CheckDecompressIncludingError("\001\000\000\255\255", "")
	end
	function TestMin8Decompress:TestStore1()
		CheckDecompressIncludingError("\001\001\000\254\255\010", "\010")
	end
	function TestMin8Decompress:TestStore2()
		local t = {}
		for i=1, 65535 do
			t[i] = "a"
		end
		local str = table.concat(t)
		CheckDecompressIncludingError("\001\255\255\000\000"..str, str)
	end
	function TestMin8Decompress:TestStore3()
		local t = {}
		for i=1, 65535 do
			t[i] = "a"
		end
		local str = table.concat(t)
		CheckDecompressIncludingError("\000\255\255\000\000"..str.."\001\255\255\000\000"..str, str..str)
	end
	function TestMin8Decompress:TestStore4()
		-- 0101 00fe ff31
		CheckDecompressIncludingError("\001\001\000\254\255\049", "1")
	end
	function TestMin8Decompress:TestStore5()
		local size = 0x5555
		local str = GetRandomString(size)
		CheckDecompressIncludingError("\001\085\085\170\170"..str, str)
	end

	function TestMin8Decompress:TestStoreRandom()
		for i = 1, 20 do
			local size = math.random(1, 65535)
			local str = GetRandomString(size)
			CheckDecompressIncludingError("\001"..string.char(size%256)
				..string.char((size-size%256)/256)
				..string.char(255-size%256)..string.char(255-(size-size%256)/256)..str, str)
		end
	end
	function TestMin8Decompress:TestFix1()
		CheckDecompressIncludingError("\003\000", "")
	end
	function TestMin8Decompress:TestFix2()
		CheckDecompressIncludingError("\051\004\000", "1")
	end
	function TestMin8Decompress:TestFixThenStore1()
		local t = {}
		for i=1, 65535 do
			t[i] = "a"
		end
		local str = table.concat(t)
		CheckDecompressIncludingError("\050\004\000\255\255\000\000"..str.."\001\255\255\000\000"..str, "1"..str..str)
	end
	function TestMin8Decompress:TestIncomplete()
		-- Additonal 1 byte after the end of compression data
		CheckDecompressIncludingError("\001\001\000\254\255\010\000", "\010")
	end
	function TestMin8Decompress:TestInTheMiddle()
		-- Additonal 1 byte before and 1 byte after.
		CheckDecompressIncludingError("\001\001\001\000\254\255\010\001", "\010", 2, 7)
	end

TestMin9Internals = {}
	-- Test from puff
	function TestMin9Internals:TestLoadString()
		local loadStrToTable = LibDeflate.internals.loadStrToTable
		local tmp
		for _=1, 1000 do
			local t = {}
			local strLen = math.random(0, 1000)
			local str = GetRandomString(strLen)
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

	function TestMin9Internals:TestSimpleRandom()
		local compressEmpty = LibDeflate:Compress("")
		lu.assertEquals(LibDeflate:Decompress(compressEmpty), "", "My decompress does not match origin for empty string.")
		for _=1, 3000 do
			local tmp
			local strLen = math.random(0, 1000)
			local str = GetRandomString(strLen)
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

	function TestMin9Internals:TestAdler32()
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
local runner = lu.LuaUnit.new()
os.exit( runner:runSuite())