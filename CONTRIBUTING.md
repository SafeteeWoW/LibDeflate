# Contributing to this repository

## Pure Lua Requirement

This library **MUST** work in pure Lua environment, without depending any other Lua packages.

There can be dependency requirement in order to test this library, but the library itself should not have any mandatory dependency.

Optional dependency is allowed, but the existence of it must be checked, such as LibStub.

## CI

All CI running as Github workflow should be passing.

See comments in the config files in [.github/workflows](.github/workflows) for detail.

## Testing

Test code for your features are required. 100% Code coverage is recommended.

Read [tests/README.md](tests/README.md) for detail.

## Format

All hand written code in this repo should be formatted by an auto
formatter before committed to the repository.
There should be no format-only changes in the Pull Request.

Read [dev_docs/format.md](dev_docs/format.md) for detail.

## Linting

Lua code of LibDeflate should not have lint warnings.

Read [dev_docs/lint.md](dev_docs/lint.md) for detail.

## IDE

Share my IDE setup as a reference.

Read [dev_docs/ide.md](dev_docs/ide.md) for detail.
