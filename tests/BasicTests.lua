local io = io
local print = print
local os = os

dofile("tests\\TestHeader.lua")

local function BasicTests()

	function UTest.TestEmpty()
		CheckStr("")
		CheckStr("abcdefgh")
		CheckStr("aaaaaaaaaaaaaaaaaa")
		CheckStr("ab")
	end
	
	function UTest.ItemStringsFile()
		CheckFile("tests\\data\\ItemStrings.txt")
	end

	---- Test begins
	function UTest.SmallTestFile()
		CheckFile("tests\\data\\smalltest.txt")
	end


end

BasicTests()
