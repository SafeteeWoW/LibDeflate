files['.luacheckrc'].global = false
self = false
files['tests/LibDeflateTest.lua'].ignore = {"241", -- 	Local variable is mutated but never accessed.
											}
stds.wow = {
   read_globals = {"bit", "bit32", "LibStub", "wipe"}
}
std="max+wow"
