package = "LibDeflate"
version = "0.9.0-4"
source = {
   url = "git+https://github.com/safeteeWow/LibDeflate.git",
   tag = "0.9.0-beta4",
}
description = {
   detailed = [[Pure Lua compressor and decompressor with high compression ratio using DEFLATE/zlib format.]],
   homepage = "https://github.com/safeteeWow/LibDeflate",
   license = "GPL-3",
}
dependencies = {
   "lua >= 5.1, < 5.4"
}
build = {
   type = "builtin",
   modules = {
      LibDeflate = "LibDeflate.lua",
   },
   copy_directories = {
      "docs",
      "examples",
   }
}