-- Commandline tests
local Lib = require("LibDeflate")
local args = rawget(_G, "arg")
-- UnitTests
local lu = require("luaunit")

local string_byte = string.byte
math.randomseed(os.time())
-- Repeatedly collect memory garbarge until memory usage no longer changes
local function FullMemoryCollect()
	local memoryUsed = collectgarbage("count")
	local lastMemoryUsed
	repeat
		lastMemoryUsed = memoryUsed
		collectgarbage("collect")
		memoryUsed = collectgarbage("count")
	until memoryUsed >= lastMemoryUsed
	collectgarbage("collect")
	collectgarbage("collect")
end

local function RunProgram(program, inputFileName, stdoutFileName)
	local stderrFileName = stdoutFileName..".stderr"
	os.execute("rm -f "..stdoutFileName)
	os.execute("rm -f "..stderrFileName)
	local status, _, ret = os.execute(program.." "..inputFileName.. "> "..stdoutFileName.." 2> "..stderrFileName)
	local returnedStatus = type(status) == "number" and status or ret or -255
	local stdout = ""
	local stderr = ""
	local file
	file = io.open(stdoutFileName, "rb")
	if file then
		stdout = file:read("*all")
		file:close()
	end
	file = io.open(stderrFileName, "rb")
	if file then
		stderr = file:read("*all")
		file:close()
	end
	return returnedStatus, stdout, stderr
end


local function CheckStr(str, levels, minRunTime, inputFileName, outputFileName)

	FullMemoryCollect()
	local totalMemoryBefore = math.floor(collectgarbage("count")*1024)

	do
		minRunTime = minRunTime or 0
		if levels == "all" then
			levels = {1,2,3,4,5,6,7,8}
		else
			levels = levels or {1}
		end

		local compressedFileName = outputFileName or "tests/data/tmp.deflate"

		for _, level in ipairs(levels) do
			-- Check memory usage and leaking
			print((">> %s %s, Level: %d, Size: %s"):format((inputFileName and "File:" or "Str:")
				,(inputFileName or str):sub(1, 40), level, str:len()))
			local memoryBefore
			local memoryRunning
			local memoryAfter
			collectgarbage("stop")
			FullMemoryCollect()
			memoryBefore =  math.floor(collectgarbage("count")*1024)
			FullMemoryCollect()
			Lib:Compress(str, level)
			memoryRunning = math.floor(collectgarbage("count")*1024)
			FullMemoryCollect()
			memoryAfter = math.floor(collectgarbage("count")*1024)
			collectgarbage("restart")
			local memoryUsed = memoryRunning - memoryBefore
			local memoryLeaked = memoryAfter - memoryBefore

			local compressed = ""

			local startTime = os.clock()
			local elapsed = -1
			local repeated = 0
			while elapsed < minRunTime do
				compressed = Lib:Compress(str, level)
				elapsed = (os.clock()-startTime)
				repeated = repeated + 1
			end
			elapsed = elapsed/repeated
			local outputFile = io.open(compressedFileName, "wb")
			lu.assertNotNil(outputFile, "Fail to write to "..compressedFileName)
			outputFile:write(compressed)
			outputFile:close()

			local decompressedFileName = compressedFileName..".decompressed"

			local returnedStatus_puff, stdout_puff = RunProgram("puff -w ", compressedFileName, decompressedFileName)
			lu.assertEquals(returnedStatus_puff, 0, "puff decompression failed with code "..returnedStatus_puff)

			local returnedStatus_zdeflate, stdout_zdeflate = RunProgram("zdeflate -d <", compressedFileName
				, decompressedFileName)
			lu.assertEquals(returnedStatus_zdeflate, 0, "zdeflate decompression failed with code "..returnedStatus_zdeflate)

			if str ~= stdout_puff then
				lu.assertEquals(str:len(), stdout_puff:len(), ("level: %d, string size does not match actual size: %d"
					..", after Lib compress and puff decompress: %d")
						:format(level, str:len(), stdout:len()))
				for i=1, str:len() do
					lu.assertEquals(string_byte(str, i, i), string_byte(stdout_puff, i, i), ("Level: %d, First diff at: %d")
						:format(level, i))
				end
				return 1
			else
				print("Compress then puff decompress OK")
			end

			if str ~= stdout_zdeflate then
				lu.assertEquals(str:len(), stdout_zdeflate:len(), ("level: %d, string size does not match actual size: %d"
					..", after Lib compress and zdeflate decompress: %d")
						:format(level, str:len(), stdout:len()))
				for i=1, str:len() do
					lu.assertEquals(string_byte(str, i, i), string_byte(stdout_zdeflate, i, i), ("Level: %d, First diff at: %d")
						:format(level, i))
				end
				return 1
			else
				print("Compress then zDeflate decompress OK")
			end

			local dStartTime = os.clock()
			local dRepeated = 0
			local decompressed
			local dElapsed = -1
			while dElapsed < minRunTime/3 do
				decompressed = Lib:Decompress(compressed)
				dRepeated = dRepeated + 1
				dElapsed = os.clock() - dStartTime
			end
			dElapsed = dElapsed/dRepeated

			lu.assertEquals(decompressed, str, "My decompression does not match origin string")
			if decompressed ~= str then
				print("Compress then my decompress FAILED")
				return 1
			else
				print("Compress then my decompress OK")
			end

			print(("Level: %d, Before: %d, After: %d, Ratio:%.2f, Compress Time: %.3fms, Decompress Time: %.3fms, "..
				"Speed: %.2f KB/s, Decompress Speed: %.2f KB/s, Memory: %d bytes"..
				", Memory/input: %.3f, Possible Memory Leaked: %d bytes"
				..", Run repeated by: %d times"):
				format(level, str:len(), compressed:len(), str:len()/compressed:len()
					, elapsed*1000, dElapsed*1000, str:len()/elapsed/1000, str:len()/dElapsed/1000
					, memoryUsed, memoryUsed/str:len(), memoryLeaked, repeated))
			print("-------------------------------------")
		end
	end

	FullMemoryCollect()
	local totalMemoryAfter = math.floor(collectgarbage("count")*1024)

	local totalMemoryDifference = totalMemoryBefore - totalMemoryAfter

	if totalMemoryDifference > 0 then
		print(("Actual Memory Leak in the test: %d"):format(totalMemoryDifference))
	end
	if not jit then -- Lua JIT has some problems to garbage collect stuffs, so don't consider as failure.
		lu.assertTrue((totalMemoryDifference<=0), ("Actual Memory Leak in the test: %d"):format(totalMemoryDifference))
		if totalMemoryDifference > 0 then
			return 2
		end
	end

	-- Use all avaiable strategies of zdeflate to compress the data, and see if LibDeflate can decompress it.
	local level, strategy
	local strategies = {"--filter", "--huffman", "--rle", "--fix", "--default"}
	local tmpFileName = "tmp.tmp"
	local tmpFile = io.open(tmpFileName, "wb")
	tmpFile:write(str)
	tmpFile:close()
	print((">> %s %s, Size: %s"):format((inputFileName and "File:" or "Str:")
		,(inputFileName or str):sub(1, 40), str:len()))
	local unique_compress = {}
	local uniques_compress_count = 0
	for i=0, 8 do
		level = "-"..i
		for j=1, #strategies do
			strategy = strategies[j]
			local status, stdout, stderr = RunProgram("zdeflate "..level.." "..strategy.." < ", tmpFileName, tmpFileName..".out")
			lu.assertEquals(status, 0, ("zdeflate cant compress the file? stderr: %s level: %s, strategy: %s")
				:format(stderr, level, strategy))
			if status ~= 0 then
				return 3
			end
			if not unique_compress[stdout] then
				unique_compress[stdout] = true
				uniques_compress_count = uniques_compress_count + 1
				local decomp = Lib:Decompress(stdout)
				if str ~= decomp then
					print(("My decompress fail to decompress at zdeflate level: %s, strategy: %s")
						:format(stderr, level, strategy))
					lu.assertTrue(false, ("My decompress fail to decompress at zdeflate level: %s, strategy: %s")
						:format(stderr, level, strategy))
					return 4
				end
			end
		end
	end
	print(("Full decompress coverage test ok. unique compresses: %d"):format(uniques_compress_count))
	print("-------------------------------------")

	return 0
end

local function CheckDecompressIncludingError(compressed, decompressed)
	local d, status = Lib:Decompress(compressed)
	if d ~= decompressed then
		lu.assertTrue(false, ("My decompressed does not match expected result."..
			"expected: %s, actual: %s, Returned status of decompress: %d"):format(decompressed, d, status))
	else
		-- Check my decompress result with "puff"
		local inputFileName = "tmpFile"
		local inputFile = io.open(inputFileName, "wb")
		inputFile:setvbuf("full")
		inputFile:write(compressed)
		inputFile:flush()
		inputFile:close()
		local returnedStatus_puff, stdout_puff = RunProgram("puff -w", inputFileName, inputFileName..".decompressed")
		local returnedStatus_zdeflate, stdout_zdeflate = RunProgram("zdeflate -d <", inputFileName
			, inputFileName..".decompressed")
		if status ~= 0 then
			if returnedStatus_puff ~= 0 and returnedStatus_zdeflate ~= 0 then
				print((">>>> %q cannot be decompress as expected"):format(compressed:sub(1, 15)))
			elseif returnedStatus_puff ~= 0 and returnedStatus_zdeflate == 0 then
				lu.assertTrue(false, "Puff error but not zdeflate?")
			elseif returnedStatus_puff == 0 and returnedStatus_zdeflate ~= 0 then
				lu.assertTrue(false, "zDeflate error but not puff?")
			else
				lu.assertTrue(false, "My decompressed returns error, but not puff and zdeflate.")
			end

		else
			if d == stdout_puff and d == stdout_zdeflate then
				print((">>>> %q is decompressed successfully"):format(compressed:sub(1, 15)))
			else
				lu.assertTrue(false, "My decompress result does not match puff or zdeflate.")
			end
		end
	end

end

local function CheckFile(inputFileName, levels, minRunTime, outputFileName)
	local inputFile = io.open(inputFileName, "rb")
	lu.assertNotNil(inputFile, "Input file "..inputFileName.." does not exist")
	local inputFileContent = inputFile:read("*all")
	inputFile:close()
	return CheckStr(inputFileContent, levels, minRunTime, inputFileName, outputFileName or inputFileName..".deflate")
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
	-- For testing purpose, check the if a file can be correctly compressed and decompressed to origin
		os.exit(CheckFile(args[2], "all", 0, args[3]))
	end
end

TestMin1Strings = {}
	function TestMin1Strings:testEmpty()
		CheckStr("", "all")
	end
	function TestMin1Strings:testAllLiterals1()
		CheckStr("ab", "all")
	end
	function TestMin1Strings:testAllLiterals2()
		CheckStr("abcdefgh", "all")
	end
	function TestMin1Strings:testAllLiterals3()
		local t = {}
		for i=0, 255 do
			t[#t+1] = string.char(i)
		end
		local str = table.concat(t)
		CheckStr(str, "all")
	end

	function TestMin1Strings:testRepeat()
		CheckStr("aaaaaaaaaaaaaaaaaa", "all")
	end
	function TestMin1Strings:testLongRepeat()
		local repeated = {}
		for i=1, 100000 do
			repeated[i] = "c"
		end
		CheckStr(table.concat(repeated), "all")
	end

TestMin2MyData = {}
	function TestMin2MyData:TestItemStrings()
		CheckFile("tests/data/itemStrings.txt", "all")
	end

	function TestMin2MyData:TestSmallTest()
		CheckFile("tests/data/smalltest.txt", {4}, 4)
	end

	function TestMin2MyData:TestReconnectData()
		CheckFile("tests/data/reconnectData.txt", "all")
	end

TestMin3ThirdPartySmall = {}
	function TestMin3ThirdPartySmall:TestEmpty()
		CheckFile("tests/data/3rdparty/empty", "all")
	end

	function TestMin3ThirdPartySmall:TestX()
		CheckFile("tests/data/3rdparty/x", "all")
	end

	function TestMin3ThirdPartySmall:TestXYZZY()
		CheckFile("tests/data/3rdparty/xyzzy", "all")
	end

Test4ThirdPartyMedium = {}
	function Test4ThirdPartyMedium:Test10x10y()
		CheckFile("tests/data/3rdparty/10x10y", "all")
	end

	function Test4ThirdPartyMedium:TestQuickFox()
		CheckFile("tests/data/3rdparty/quickfox", "all")
	end

	function Test4ThirdPartyMedium:Test64x()
		CheckFile("tests/data/3rdparty/64x", "all")
	end

	function Test4ThirdPartyMedium:TestUkkonoona()
		CheckFile("tests/data/3rdparty/ukkonooa", "all")
	end

	function Test4ThirdPartyMedium:TestMonkey()
		CheckFile("tests/data/3rdparty/monkey", "all")
	end

	function Test4ThirdPartyMedium:TestRandomChunks()
		CheckFile("tests/data/3rdparty/random_chunks", "all")
	end

	function Test4ThirdPartyMedium:TestGrammerLsp()
		CheckFile("tests/data/3rdparty/grammar.lsp", "all")
	end

	function Test4ThirdPartyMedium:TestXargs1()
		CheckFile("tests/data/3rdparty/xargs.1", "all")
	end

	function Test4ThirdPartyMedium:TestRandomOrg10KBin()
		CheckFile("tests/data/3rdparty/random_org_10k.bin", "all")
	end

	function Test4ThirdPartyMedium:TestCpHtml()
		CheckFile("tests/data/3rdparty/cp.html", "all")
	end

	function Test4ThirdPartyMedium:TestBadData1Snappy()
		CheckFile("tests/data/3rdparty/baddata1.snappy", "all")
	end

	function Test4ThirdPartyMedium:TestBadData2Snappy()
		CheckFile("tests/data/3rdparty/baddata2.snappy", "all")
	end

	function Test4ThirdPartyMedium:TestBadData3Snappy()
		CheckFile("tests/data/3rdparty/baddata3.snappy", "all")
	end

	function Test4ThirdPartyMedium:TestSum()
		CheckFile("tests/data/3rdparty/sum", "all")
	end

	function Test4ThirdPartyMedium:TestCompressedFile()
		CheckFile("tests/data/3rdparty/compressed_file", "all")
	end

Test5_64K = {}
	function Test5_64K:Test64KFile()
		CheckFile("tests/data/64k.txt", "all")
	end
	function Test5_64K:Test64KFilePlus1()
		CheckFile("tests/data/64kplus1.txt", "all")
	end
	function Test5_64K:Test64KFilePlus2()
		CheckFile("tests/data/64kplus2.txt", "all")
	end
	function Test5_64K:Test64KFilePlus3()
		CheckFile("tests/data/64kplus3.txt", "all")
	end
	function Test5_64K:Test64KFilePlus4()
		CheckFile("tests/data/64kplus4.txt", "all")
	end
	function Test5_64K:Test64KFileMinus1()
		CheckFile("tests/data/64kminus1.txt", "all")
	end
	function Test5_64K:Test64KRepeated()
		local repeated = {}
		for i=1, 65536 do
			repeated[i] = "c"
		end
		CheckStr(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedPlus1()
		local repeated = {}
		for i=1, 65536+1 do
			repeated[i] = "c"
		end
		CheckStr(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedPlus2()
		local repeated = {}
		for i=1, 65536+2 do
			repeated[i] = "c"
		end
		CheckStr(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedPlus3()
		local repeated = {}
		for i=1, 65536+3 do
			repeated[i] = "c"
		end
		CheckStr(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedPlus4()
		local repeated = {}
		for i=1, 65536+4 do
			repeated[i] = "c"
		end
		CheckStr(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedMinus1()
		local repeated = {}
		for i=1, 65536-1 do
			repeated[i] = "c"
		end
		CheckStr(table.concat(repeated), "all")
	end
	function Test5_64K:Test64KRepeatedMinus2()
		local repeated = {}
		for i=1, 65536-2 do
			repeated[i] = "c"
		end
		CheckStr(table.concat(repeated), "all")
	end

-- > 64K
Test6ThirdPartyBig = {}
	function Test6ThirdPartyBig:TestBackward65536()
		CheckFile("tests/data/3rdparty/backward65536", "all")
	end
	function Test6ThirdPartyBig:TestHTML()
		CheckFile("tests/data/3rdparty/html", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestPaper100kPdf()
		CheckFile("tests/data/3rdparty/paper-100k.pdf", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestGeoProtodata()
		CheckFile("tests/data/3rdparty/geo.protodata", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestFireworksJpeg()
		CheckFile("tests/data/3rdparty/fireworks.jpeg", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestAsyoulik()
		CheckFile("tests/data/3rdparty/asyoulik.txt", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestCompressedRepeated()
		CheckFile("tests/data/3rdparty/compressed_repeated", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestAlice29()
		CheckFile("tests/data/3rdparty/alice29.txt", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestQuickfox_repeated()
		CheckFile("tests/data/3rdparty/quickfox_repeated", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestKppknGtb()
		CheckFile("tests/data/3rdparty/kppkn.gtb", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestZeros()
		CheckFile("tests/data/3rdparty/zeros", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestMapsdatazrh()
		CheckFile("tests/data/3rdparty/mapsdatazrh", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestHtml_x_4()
		CheckFile("tests/data/3rdparty/html_x_4", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestLcet10()
		CheckFile("tests/data/3rdparty/lcet10.txt", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestPlrabn12()
		CheckFile("tests/data/3rdparty/plrabn12.txt", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:Testptt5()
		CheckFile("tests/data/3rdparty/ptt5", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestUrls10K()
		CheckFile("tests/data/3rdparty/urls.10K", {1,2,3,4,5})
	end
	function Test6ThirdPartyBig:TestKennedyXls()
		CheckFile("tests/data/3rdparty/kennedy.xls", {1,2,3,4,5})
	end

Test7WoWData = {}
	function Test7WoWData:TestWarlockWeakAuras()
		CheckFile("tests/data/warlockWeakAuras.txt", {1,2,3,4,5,6,7,8,9})
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
	function TestMin8Decompress:TestError1()
		-- Additonal byte
		CheckDecompressIncludingError("\001\001\000\254\255\010\000", nil)
	end

local runner = lu.LuaUnit.new()
os.exit( runner:runSuite())
