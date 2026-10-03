# Code Linting

Provide deterministic tools to detect code mistakes. Make them run quickly.
Make them runnable locally.

## Overview

Assume code will not be correct the first time it's written. Invest in
tooling that can be run in the same local development environment. Make sure it
runs quickly. Make sure it covers the critical areas and gives meaningful
feedback/hints.

Use a combination of existing linting libraries along with custom checks. Speed
to run them is critical - slow linters will be ignored and eventually
discarded.

When possible use a tiered approach - have fast to execute checks that can
detect potential problems. Only if it flags specific issues, then run the
slower but more accurate tooling. For example, use static analysis (grep) to
find potential issues, then use a syntax parser (AST walking) to confirm the
flagged issues.

## Implementation

A suggested implementation is to use `ex_check` library, which provides `mix
check` as the single command to run. It is built to integrate with common
Elixir community linters like the built-in `mix format`, the popular library
like `mix credo`, as well as our own custom checks written in `priv/checks`.

The last tier is the most interesting, custom linter checks written in Rust
using the tiered approach pattern above. In addition to the `rust` based
custom checks, you can also add custom `credo` rules where appropriate.

**Key files**

- [Custom checks written in Rust](priv/checks/README.md)
- [ExCheck config](.check.exs)
- [Credo config](.credo.exs)
