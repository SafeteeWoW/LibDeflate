Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# PATH that contains lua and luarocks
$ENV:PATH = "C:\usr\local\bin;${ENV:PATH}"

# PATH that contains reference compressor
$ENV:PATH = "${ENV:GITHUB_WORKSPACE}/tests;${ENV:PATH}"

cmd /C "C:\usr\local\luarocks\luarocks path > %TEMP%/luarocks_env.cmd & call %TEMP%/luarocks_env.cmd & set > %TEMP%/setenv_lua.txt"

Get-Content ${ENV:TEMP}/setenv_lua.txt | ForEach-Object {
  $line = $_
  $key,$value = $line -split '=',2
  Set-Item "ENV:$key" $value
}

if ((Test-Path -LiteralPath variable:\LASTEXITCODE)) {
  exit $LASTEXITCODE
}
