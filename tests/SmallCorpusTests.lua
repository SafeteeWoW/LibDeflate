local io = io
local print = print
local os = os

dofile("tests\\TestHeader.lua")

local function SmallCorpusTests()
	function UTest.Brotli()
		local files = {"10x10y", "64x", "backward65536", "compressed_file", "compressed_repeated", "empty"
			, "mapsdatazrh", "monkey", "plrabn12.txt", "quickfox", "quickfox_repeated", "random_chunks", "random_org_10k.bin"
			, "ukkonooa", "x", "xyzzy", "zeros"}
		for _, file in ipairs(files) do
			CheckFile("tests\\data\\Brotli\\"..file)
		end
	end
	
	function UTest.Calgary()
		local files = {"bib", "pic", "geo", "book1", "book2", "geo", "news", "obj1", "obj2", "paper1", "paper2", "pic", "progc", "progl", "progp", "trans"}
		for _, file in ipairs(files) do
			CheckFile("tests\\data\\calgary\\"..file)
		end
	end

	function UTest.Cantrbry()
		local files = {"alice29.txt", "asyoulik.txt", "cp.html", "fields.c", "grammar.lsp", "kennedy.xls", "lcet10.txt", "plrabn12.txt", "ptt5", "sum", "xargs.1"}
		for _, file in ipairs(files) do
			CheckFile("tests\\data\\Cantrbry\\"..file)
		end
	end

	function UTest.Snappy()
		local files = {"alice29.txt", "asyoulik.txt", "baddata1.snappy", "baddata2.snappy", "baddata3.snappy", "fireworks.jpeg"
			, "geo.protodata", "html", "html_x_4", "kppkn.gtb", "lcet10.txt", "paper-100k.pdf", "plrabn12.txt", "urls.10K"}
		for _, file in ipairs(files) do
			CheckFile("tests\\data\\Snappy\\"..file)
		end
	end
	
end

SmallCorpusTests()
UTest.summary()
