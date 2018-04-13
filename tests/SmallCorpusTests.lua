local io = io
local print = print
local os = os

dofile("tests\\TestHeader.lua")

local function SmallCorpusTests()
	function UTest.CalgaryCorpus()
	  local files = {"bib", "pic", "geo", "book1", "book2", "geo", "news", "obj1", "obj2", "paper1", "paper2", "pic", "progc", "progl", "progp", "trans"}
	  for _, file in ipairs(files) do
	   CheckFile("tests\\data\\calgary\\"..file)
	  end
	end
end

SmallCorpusTests()
