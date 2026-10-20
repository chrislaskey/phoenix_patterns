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

- [The library that builds and runs the checks](https://github.com/chrislaskey/app_checks)
- [Its Mix task](https://github.com/chrislaskey/app_checks/blob/main/lib/mix/tasks/app_checks.ex)
- [Guide for writing checks in Rust](../guides/writing-checks-in-rust.md)
- [ExCheck config](../../.check.exs)
- [Credo config](../../.credo.exs)
- [Custom checks config](../../.app_checks.exs)
- [CI workflow that runs the same command](../../.github/workflows/protected-check.yml)

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

The checks are run by the Mix task of the `app_checks` library, so it looks
and behaves like every other tool. `mix app_checks` builds and runs the
checks that `.app_checks.exs` enables, the built-in ones and the project's
own in `priv/checks`. Paths narrow a run to what is under them:

```sh
mix app_checks
mix app_checks lib/my_app_web/components/layouts.ex
mix app_checks --scope changed   # only the files and lines the branch changed
mix app_checks --verbose         # print every stage, not only the result
```

**Note**: `.app_checks.exs` lists the checks that run, in the shape of
`.credo.exs`. For each one it says whether a violation is an `error` that
fails the run or a `warning` that only prints, and whether the check looks
at `all` files or only at what the branch `changed`. The second lets a new
or stricter check land in a large codebase without first fixing every
file, since a problem that was already there on a line the branch did not
touch is not reported.

### The same command in CI

CI runs `mix check` too, in `.github/workflows/protected-check.yml`, so a
run that passes on a laptop passes in CI and the other way round. The
workflow sets up Elixir and Rust from `.tool-versions`, caches `deps`,
`_build` and the Rust build, and runs the one command. The `protected-`
prefix is explained in the [Code Review](code-review.md) pattern.

## Adopting this pattern

1. Add `credo`, `ex_check` and `app_checks` to `deps` in `mix.exs`, all with
   `only: [:dev, :test], runtime: false`, and add
   `preferred_envs: [check: :test]` to `cli/0` so tests run in the right
   environment.
2. Run `mix app_checks.install`, which writes `.app_checks.exs`, lists the
   task in `.check.exs` and pins Rust in `.tool-versions`. Then copy
   `.credo.exs`, and the paths of each check from the `.app_checks.exs`
   here.
3. Put the project's own checks in `priv/checks`, see the
   [guide](../guides/writing-checks-in-rust.md).
4. Remove the generated `precommit` alias and point `AGENTS.md` at
   `mix check` instead, so there is one command.
5. Run `mix check`. A freshly generated application needs two small fixes
   before it is clean: run `mix gettext.extract` so the `.pot` files exist,
   and fix the handful of Credo findings in the generated code.
6. Copy `.github/workflows/protected-check.yml` and pin `erlang`, `elixir`
   and `rust` in `.tool-versions`, which both the workflow and `asdf` read.
