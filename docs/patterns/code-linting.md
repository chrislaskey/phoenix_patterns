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

- [Custom checks written in Rust](../../priv/checks/README.md)
- [Mix task that builds and runs them](../../lib/mix/tasks/app.checks.ex)
- [Test for the Mix task](../../test/mix/tasks/app.checks_test.exs)
- [ExCheck config](../../.check.exs)
- [Credo config](../../.credo.exs)
- [Custom checks config](../../.app_checks.exs)

### One command

Use the `mix check` as the one command to run all linters. It runs every tool
in parallel and prints one report at the end:

```
 ✓ compiler success in 0:00
 ✓ formatter success in 0:00
 ✓ unused_deps success in 0:00
 ✓ hex_audit success in 0:01
 ✓ credo success in 0:00
 ✓ ex_unit success in 0:01
 ✓ gettext success in 0:01
 ✓ app_checks success in 0:01
```

**Note:** `mix check --fix` also runs the fixers, such as `mix format`.

**Note:** `mix check --retry` can be used to rerun just the failures.

### The custom checks as a Mix task

The custom checks in `priv/checks` are wrapped in a Mix task so it looks and
behaves like every other tool. `mix app.checks` builds and runs all the checks
for the app. Custom paths can be passed in as an argument:

```sh
mix app.checks
mix app.checks lib/my_app_web/components/layouts.ex
```

**Note**: an `.app_checks.exs` file can be used to configure the custom app checks.

## Adopting this pattern

1. Add `credo` and `ex_check` to `deps` in `mix.exs`, both with
   `only: [:dev, :test], runtime: false`, and add
   `preferred_envs: [check: :test]` to `cli/0` so tests run in the right
   environment.
2. Copy `.check.exs`, `.credo.exs` and `.app_checks.exs`.
3. Copy `priv/checks`, `lib/mix/tasks/app.checks.ex` and its test. Nothing
   in them is named after the application, so no edits are needed.
4. Remove the generated `precommit` alias and point `AGENTS.md` at
   `mix check` instead, so there is one command.
5. Run `mix check`. A freshly generated application needs two small fixes
   before it is clean: run `mix gettext.extract` so the `.pot` files exist,
   and fix the handful of Credo findings in the generated code.
