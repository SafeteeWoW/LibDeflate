local lu = require("luaunit")
local Lib = require("LibDeflate")


math.randomseed(os.time())
function CheckStr(str, levels, minRunTime, inputFileName)
	minRunTime = minRunTime or (inputFileName and 1 or 0)
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
		print((">> %s %s, Level: %d, Size: %s"):format((inputFileName and "File:" or "Str:"),(inputFileName or str):sub(1, 40), level, str:len()))
		local startTime = os.clock()
		local elapsed = -1
		local compressed = ""
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

		lu.assertEquals(str, testFileContent, "File content does not match decompressed file")
		print(("Level: %d, Before: %d, After: %d, Ratio:%.2f, TimePerRun: %.2f ms, Speed: %.2f KB/s, Repeated: %d"):
			format(level, str:len(), compressed:len(), str:len()/compressed:len(), elapsed/repeated*1000, str:len()/elapsed/1000, repeated))
		print("-------------------------------------")
	end
end

function CheckFile(inputFileName, levels, minRunTime)
	local inputFile = io.open(inputFileName, "rb")
	lu.assertNotNil(inputFile, "Input file "..inputFileName.." does not exist")
	local inputFileContent = inputFile:read("*all")
	local inputFileLen = inputFileContent:len()
	inputFile:close()
	CheckStr(inputFileContent, levels, minRunTime, inputFileName)
end

Test1Strings = {}
	function Test1Strings:testEmpty()
		CheckStr("", "all")
	end
	function Test1Strings:testAllLiterals()
		CheckStr("abcdefgh", "all")
		CheckStr("ab", "all")
	end
	function Test1Strings:testRepeat()
		CheckStr("aaaaaaaaaaaaaaaaaa", "all")
	end
	function Test1Strings:testLongRepeat()
		local repeated = {}
		for i=1, 150000 do
			repeated[i] = "c"
		end
		CheckStr(table.concat(repeated), "all")
	end

Test2MyData = {}
	function Test2MyData:TestItemStrings()
		CheckFile("tests/data/itemStrings.txt", "all")
	end

	function Test2MyData:TestSmallTest()
		CheckFile("tests/data/smalltest.txt", "all")
	end

	function Test2MyData:TestReconnectData()
		CheckFile("tests/data/reconnectData.txt", "all")
	end

Test3ThirdPartySmall = {}
	function Test3ThirdPartySmall:TestEmpty()
		CheckFile("tests/data/3rdparty/empty", "all")
	end

	function Test3ThirdPartySmall:TestX()
		CheckFile("tests/data/3rdparty/x", "all")
	end

	function Test3ThirdPartySmall:TestXYZZY()
		CheckFile("tests/data/3rdparty/xyzzy", "all")
	end


lu.LuaUnit.verbosity = 2
local runner = lu.LuaUnit.new()
runner:setOutputType("tap")
os.exit( runner:runSuite())