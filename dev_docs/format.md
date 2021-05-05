# Code Formatting

All hand written code in this repo should be formatted by an auto
formatter before committed to the repository.
Code formatting is checked in CI.

## Code Style in General

1. Follow the style of the auto formatter. If it has a bug, exclude the buggy line from formatting.
2. Always use LF line ending.
3. 2 space indentation, except for Python, which uses PEP8 style.
4. 120 colomn width, except for Python, which uses PEP8 style.
5. Data for compression test should not be auto formatted.

## Auto Formatter tool version and installation

For linux environment, see github workflow [check_format.yml](../.github/workflows/check_format.yml).
If you are using Mac or Windows, try to install similar tools.

## Helper scripts

[format_all.sh](../tools/format_all.sh) is a helper script to auto format everything in this repository.

## If you cannot setup the formatter

Do not bother it. Just minimize format only changes in your pull request.
Someone else will fix it.
