local io = io
local print = print
local os = os

dofile("tests\\TestHeader.lua")

local function PerformanceTests()

	function UTest.SmallTestFile()
		CheckFile("tests\\data\\smalltest.txt", 100, 9)
	end
	
	function UTest.ItemStringsFile()
		CheckFile("tests\\data\\ItemStrings.txt", 100, 9)
	end
	
	function UTest.ReconnectData()
		CheckFile("tests\\data\\ReconnectData.txt", 100, 9)
	end
end

PerformanceTests()
