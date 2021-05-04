#!/bin/bash
# Test against random files in disk.
# Not in CI. Act as a fuzzing test.

set -euxo pipefail

cd "$(git rev-parse --show-toplevel)"
python tests/dev_scripts/test_from_random_files_in_disk.py /
