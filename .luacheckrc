files['.luacheckrc'].global = false
self = false
files['tests/LibDeflateTest.lua'].global = false

stds.wow = {
   read_globals = {"bit", "bit32", "LibStub", "wipe"}
}
std="max+wow"
