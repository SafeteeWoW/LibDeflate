-- The test data is not in the repository.
-- Download this in Silesia: http://sun.aei.polsl.pl/~sdeor/index.php?page=silesia
-- And put the file under tests\data\Silesia

local io = io
local print = print
local os = os

assert(jit, "Dont attempt to run this without Lua Just in Time.")
dofile("tests\\TestHeader.lua")

local function LargeCorpusTests()
	function UTest.Silesia()
		local files = {"osdb", "dickens", "mozilla", "mr", "nci", "ooffice", "reymont", "samba", "sao", "webster", "xml", "x-ray"}
		for _, file in ipairs(files) do
			CheckFile("tests\\data\\Silesia\\"..file, 1, 1, 2, 3, 4, 5, 6)
		end
	end


end

LargeCorpusTests()
UTest.summary()