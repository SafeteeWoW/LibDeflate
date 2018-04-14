local io = io
local print = print
local os = os

dofile("tests\\TestHeader.lua")

local function BasicTests()

	function UTest.Empty()
		CheckStr("")
	end
	
	function UTest.AllLiterals()
		CheckStr("abcdefgh")
		CheckStr("ab")
	end
	
	function UTest.ShortRepeat()
		CheckStr("aaaaaaaaaaaaaaaaaa")
	end
	
	function UTest.ItemStringsFile()
		CheckFile("tests\\data\\ItemStrings.txt")
	end

	---- Test begins
	function UTest.SmallTestFile()
		CheckFile("tests\\data\\smalltest.txt")
	end

	---- Test begins
	function UTest.ReconnectData()
		CheckFile("tests\\data\\reconnectData.txt")
	end
	
	function UTest.LongRepeat()
		local repeated = {}
		for i=1, 300000 do
			repeated[i] = "a"
		end
		CheckStr(table.concat(repeated))
	end

end

BasicTests()
