#!/bin/bash
# Evaluate performance
# Write result to log. Perserved across runs.
# NOTE: For lua5.1, Luarocks package "luabitop" is required

set -euxo pipefail

log="performance.log"
cd "$(git rev-parse --show-toplevel)"
echo | tee -a "${log}"
echo -------------------------------------------------------------------------------------------------------------------------------------------- | tee -a "${log}"
echo -------------------------------------------------------------------------------------------------------------------------------------------- | tee -a "${log}"
echo | tee -a "${log}"
echo | tee -a "${log}"
date | tee -a "${log}"
git log -n 1 --format=medium | tee -a "${log}"
lua tests/Test.lua PerformanceEvaluation | tee -a "${log}"
luajit tests/Test.lua PerformanceEvaluation | tee -a "${log}"
