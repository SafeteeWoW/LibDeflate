local io = io
local print = print
local os = os

dofile("tests\\TestHeader.lua")

local function BasicTests()

	function TestEmpty()
		CheckStr("")
		CheckStr("abcdefgh")
		CheckStr("aaaaaaaaaaaaaaaaaa")
		CheckStr("ab")
	end
	
	function ItemStringsFile()
		CheckFile("tests\\data\\ItemStrings.txt")
	end

	---- Test begins
	function UTest.SmallTestFile()
		CheckFile("tests\\data\\smalltest.txt")
	end

	---- Test begins
	function ReconnectData()
		CheckFile("tests\\data\\reconnectData.txt")
	end
	
	function RepeatedStr()
		local repeated = {}
		for i=1, 300000 do
			repeated[i] = "a"
		end
		CheckStr(table.concat(repeated))
	end

end

BasicTests()
