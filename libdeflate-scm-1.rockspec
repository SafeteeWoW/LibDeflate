package = "LibDeflate"
version = "scm-1"
source = {
   url = "git+https://github.com/safeteeWow/LibDeflate.git"
}
description = {
   detailed = [[Pure Lua DEFLATE/zlib compressors and decompressors.]],
   homepage = "https://github.com/safeteeWow/LibDeflate",
   license = "GPLv3",
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