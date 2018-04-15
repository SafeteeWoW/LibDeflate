local io = io
local print = print
local os = os

dofile("tests\\TestHeader.lua")

assert(not jit, "Don't run this in JIT.")

local function PerformanceTests()

	function UTest.SmallTestFile()
		CheckFile("tests\\data\\smalltest.txt", 100, 1,2,3,4,5,6,7,8,9)
	end
	
	function UTest.ItemStringsFile()
		CheckFile("tests\\data\\ItemStrings.txt", 100, 1,2,3,4,5,6,7,8,9)
	end
	
	function UTest.ReconnectData()
		CheckFile("tests\\data\\ReconnectData.txt", 100, 1,2,3,4,5,6,7,8,9)
	end
	
	function UTest.Kennedy()
		CheckFile("tests\\data\\Cantrbry\\Kennedy.xls", 1, 1,2,3,4,5,6,7,8,9)
	end
end

PerformanceTests()
