local io = io
local print = print
local os = os

dofile("tests\\TestHeader.lua")

local function LargeCorpusTests()
	function UTest.Silesia()
		local files = {"osdb", "dickens", "mozilla", "mr", "nci", "ooffice", "reymont", "samba", "sao", "webster", "xml", "x-ray"}
		for _, file in ipairs(files) do
			CheckFile("tests\\data\\Silesia\\"..file)
		end
	end


end

LargeCorpusTests()
