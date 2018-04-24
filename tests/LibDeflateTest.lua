local lu = require("luaunit")
local Lib = require("LibDeflate")

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

local function CheckStr(str, levels, minRunTime, inputFileName)

	FullMemoryCollect()
	local totalMemoryBefore = math.floor(collectgarbage("count")*1024)

	do
		minRunTime = minRunTime or 0
		if levels == "all" then
			levels = {1,2,3,4,5,6,7,8,9}
		else
			levels = levels or {1}
		end

		local compressedFileName
		if inputFileName then
			compressedFileName = inputFileName..".deflate"
		else
			compressedFileName = "tests/data/str.deflate"
		end



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
			os.execute("rm -f "..decompressedFileName)

			-- For lua5.1, "status" stores the returned number of the program. For 5.2/5.3, "ret" stores it.
			local status, _, ret = os.execute("puff -w "..compressedFileName.. "> "..decompressedFileName)
			local returnedStatus = type(status)== "number" and status or ret or -255
			lu.assertEquals(returnedStatus, 0, "puff decompression failed with code "..returnedStatus)

			local testFile = io.open(decompressedFileName, "rb")
			lu.assertNotNil(testFile, "Decompressed file "..decompressedFileName.." does not exist")
			local testFileContent = testFile:read("*all")
			testFile:close()

			if str ~= testFileContent then
				lu.assertEquals(str:len(), testFileContent:len(), ("level: %d, string size does not match actual size: %d"
					..", after compress and decompress: %d")
						:format(level, str:len(), testFileContent:len()))
				for i=1, str:len() do
					lu.assertEquals(string_byte(str, i, i), string_byte(testFileContent, i, i), ("Level: %d, First diff at: %d")
						:format(level, i))
				end
			end

			local dStartTime = os.clock()
			local dRepeated = 0
			local decompressed
			local dElapsed = -1
			while dElapsed < minRunTime/10 do
				decompressed = Lib:Decompress(compressed)
				dRepeated = dRepeated + 1
				dElapsed = os.clock() - dStartTime
			end
			dElapsed = dElapsed/dRepeated

			lu.assertEquals(decompressed, str, "My decompression does not match origin string")
			if decompressed ~= str then
				print("My decompress FAILED")
			else
				print("My decompress OK")
			end

			print(("Level: %d, Before: %d, After: %d, Ratio:%.2f, TimePerRun: %.3fms, Decompress Time: %.3fms, "..
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
	end
end

local function CheckFile(inputFileName, levels, minRunTime)
	local inputFile = io.open(inputFileName, "rb")
	lu.assertNotNil(inputFile, "Input file "..inputFileName.." does not exist")
	local inputFileContent = inputFile:read("*all")
	inputFile:close()
	CheckStr(inputFileContent, levels, minRunTime, inputFileName)
end

TestMin1Strings = {}
	function TestMin1Strings:testEmpty()
		CheckStr("", "all")
	end
	function TestMin1Strings:testAllLiterals()
		CheckStr("abcdefgh", "all")
		CheckStr("ab", "all")
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
		CheckFile("tests/data/smalltest.txt", "all")
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

local runner = lu.LuaUnit.new()
os.exit( runner:runSuite())
