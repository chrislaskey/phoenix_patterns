# Code Generators

Use deterministic code generation tools whenever possible.

## Overview

One major issue with LLM output is its non-determinism. Instead rely on
deterministic code generators roughly in this order:

- Code generators that work with the abstract syntax tree (AST). Examples: `igniter`
- Code generators that rely on static analysis. Examples: `regex`

When writing SKILL files for LLMs, provide it with a library of deterministic
code generation tools and have it use those, rather than code examples and code
explanations.

## Implementation

Uses the `igniter` library to build a library of generators in
`priv/code_generators`. Each generator is a Mix task, so it runs the same way
as every other tool and its moduledoc shows up in `mix help`. The moduledoc
says when to use the generator, what it writes and what it refuses to do.
`AGENTS.md` points at the folder and lists the tasks, so an engineer or an LLM
finds the generator before writing the code by hand.

Two generators cover the two shapes most generators take:

- **Creating files.** `mix app.gen.live Dashboard /dashboard` writes a
  LiveView and its test, then adds `live "/dashboard", DashboardLive` to the
  browser scope of the router. The LiveView follows the rules in `AGENTS.md`
  that are easy to miss: the `Live` suffix, the template wrapped in
  `<Layouts.app flash={@flash}>`, an id on the root element and a test that
  looks for that id.
- **Changing a file.** `mix app.gen.component card` appends a function
  component to `CoreComponents` with the same shape every time: a doc, a
  `class` attribute, the global attributes and the inner block. Because the
  [Common UI](common-ui.md) check reads that module, a component named after
  an HTML tag is enforced in every template from then on.

Both read the web module from `mix.exs`, so nothing in the folder is named
after the application.

**Key files**

- [The generators and how to add one](../../priv/code_generators/README.md)
- [LiveView generator](../../priv/code_generators/app.gen.live.ex)
- [Component generator](../../priv/code_generators/app.gen.component.ex)
- [Tests for the generators](../../test/code_generators)
- [Igniter config](../../.igniter.exs)
- [The section in AGENTS.md](../../AGENTS.md)

### Why a syntax tree

A generator that edits text has to find the right place with a pattern, and
the pattern breaks when the file is formatted differently or the code moves.
Igniter parses the file, walks the tree to the node it wants, such as the
`scope "/", MyAppWeb do` call that pipes through `:browser`, adds the new
code next to it and writes the file back formatted. The router can be
reordered or commented and the route still lands in the right scope.

### Refuse, do not overwrite

A generator reports a problem and writes nothing when the module or function
it would add already exists. All of its changes are written together or not
at all, so a failed run never leaves a route without its LiveView. The
`--dry-run` flag prints the changes without writing them.

### Tests without files

Igniter builds a project in memory for tests. A test gives
`Igniter.Test.test_project/1` the few files the generator looks at, such as a
router, runs the task with `Igniter.compose_task/3` and asserts on the
created files and patches. No files are written, so the tests are fast and
run with `async: true`.

## Adopting this pattern

1. Add `igniter` to `deps` in `mix.exs` with `only: [:dev, :test]`.
2. Add `priv/code_generators` to `elixirc_paths` for `:dev` and `:test`, to
   `inputs` in `.formatter.exs`, to `included` in `.credo.exs`, and to the
   `high` tier in `.app_checks.exs` from [Code Review](code-review.md).
3. Copy `.igniter.exs`. Without it igniter moves a generated LiveView out of
   the `live/` folder to match its module name.
4. Copy `priv/code_generators` and `test/code_generators`. Nothing in them is
   named after the application, so no edits are needed.
5. Add the "Code generators" section to `AGENTS.md`.
6. Run `mix app.gen.live Dashboard /dashboard --dry-run` to see it work, then
   `mix check`.
