# Code linting

All hand Lua code should be linted in this repository,
exclude third-party code.
Linting is checked in CI.

## Tool version and installation

Please use [lua_cov.yml](../.github/workflows/lua_lint.yml) as the reference.
We use luacheck as the linter.
There should be not lint warnings in LibDeflate code.

You can install luacheck by Luarocks:
`luarocks install luacheck`

## Helper script

[lint_lua_code.sh](../tools/lint_lua_code.sh) can be used to lint lua code.
