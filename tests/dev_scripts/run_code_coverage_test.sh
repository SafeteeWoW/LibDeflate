#!/bin/bash
# Run code coverage tests and generate report

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
rm -f luacov.stats.out
rm -f luacov.report.out
luajit tests/Test.lua CommandLineCodeCoverage --verbose
luajit -lluacov tests/Test.lua CodeCoverage --verbose
luacov
