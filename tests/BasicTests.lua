local io = io
local print = print
local os = os

dofile("tests\\TestHeader.lua")

local function BasicTests()

	function UTest.TestEmpty()
    CheckStr("")
    CheckStr("abcdefgh")
	end
	---- Test begins
	function UTest.SmallTestFile()
		--CheckFile("tests\\data\\smalltest.txt")
	end
end

BasicTests()
