# Writing checks in Rust

A check is a rule the repository must follow. The checks run in a small
Rust program that ships with the [`app_checks`](https://github.com/chrislaskey/app_checks) library,
a dependency of this project. Four checks are built in. The project's
own checks live in `priv/checks/`, one file each, and are compiled in with
the built-in ones. The program runs each enabled check, prints what it
finds, and exits with an error code if anything is wrong.

A check is a small function that finds facts: these files, these lines,
break this rule. Everything else is decided by `.app_checks.exs` and the
command line: which checks run, which files each looks at, and what a
violation means.

Rust is used so the whole run finishes in well under a second on a normal
codebase, and prints as it goes on a huge one. A slow check gets ignored,
then deleted.

## How a run works

1. The task reads `.app_checks.exs` and picks the named config, `default`
   unless the command line says otherwise.
2. The program gathers the state of the code once, from git, so no check
   has to: every file in the project, and every file the branch changed
   since it left the base ref, with the line numbers it changed. Commits,
   staged and unstaged edits and untracked files all count.
3. Each enabled check runs in turn with its config and that state, and
   returns violations: a file, a line where there is one, and a message.
4. Each violation prints with the check's level. `error` fails the run,
   `warning` does not.

A check about files does its work in two passes. **The fast pass** is a
cheap test, such as a substring search, over the files the check looks at.
It must never miss a real problem, so when it is not sure it keeps the
file. **The slow pass** runs only on the files the fast pass kept. It does
the careful work, such as parsing, and returns the violations. Files run
in parallel, and a check over all files prints each violation as soon as
it is found, so you can start fixing the first one while the rest of the
run continues.

Here is a run on a branch that changed the layout module, where a doc
string mentions `<button>` on line 24 and a template uses one on line 134,
and a page template uses a raw `<input>`:

```
lib/example_web/components/layouts.ex:134: <button> is a raw tag, use <.button> from ExampleWeb.CoreComponents [core_component_tags, error]
lib/example_web/controllers/page_html/home.html.heex:12: <input> is a raw tag, use <.input> from ExampleWeb.CoreComponents [core_component_tags, error]
lib/example_web/components/layouts.ex: ask an architect to review this change [architect_review, warning]
4 check(s), 2 error(s), 1 warning(s)
```

Each line is `file:line: message [check, level]`. A violation about a
whole file has no line. Line 24 is not reported: the slow pass reads only
the `~H` templates in an `.ex` file, so the mention in the doc string is
not a violation. The last line is a summary. The exit code is `1` if any
violation was an error and `0` otherwise.

## Build and run

You need Rust. The version is pinned in `.tool-versions`, so `asdf install`
sets it up.

```sh
mix app_checks
```

The task builds the program into `_build` first, then runs it. The first
build takes a little while. After that, when nothing changed, cargo finishes
at once, so a run costs about as much as the checks themselves.

```sh
mix app_checks lib test               # only what is under these paths
mix app_checks --base feature/parent  # compare the branch with another ref
mix app_checks --config-name review   # run another named config
mix app_checks --check no_io_inspect  # one check, from the active config
mix app_checks --scope changed        # every check on changed files only
mix app_checks --verbose              # print every stage, not only the result
```

`--base` is for a branch that builds on another unmerged branch. The
comparison starts where the branch left the base, so commits that landed
on the base afterwards do not count. Git is only read. Nothing is fetched
or changed.

`mix check` runs the same task alongside the formatter, Credo and the
tests, see `.check.exs`.

## Configuration

`.app_checks.exs` in the project root, a map in the shape of `.credo.exs`.
The one here is a complete example with every built-in check. In short:

```elixir
%{
  custom_checks: "priv/checks",
  configs: [
    %{
      name: "default",
      base_ref: "origin/main",
      checks: [
        enabled: [
          {:core_component_tags, config: [paths: ["lib/example_web/components/core_components.ex"]]},
          {:no_io_inspect, level: :warning, scope: :changed},
          {:separate_pr, config: [groups: [agents: ["AGENTS.md"]]]}
        ],
        disabled: [:human_review]
      ]
    }
  ]
}
```

A check runs only when it is listed under `enabled`. An atom alone runs
with the defaults, `level: :error` and `scope: :all`. A tuple sets either
of those, and `config:` holds the check's own keys. `disabled` lists the
checks the project knows about and chose not to run; a check in neither
list does not run either, and the summary counts it, so a new file in
`priv/checks` is not silently ignored.

`scope: :changed` limits a check to the files the branch changed, and
reports only the lines it changed, so a problem that was already there on
a line the branch left alone is not reported. This is how a new or
stricter check lands in a large codebase without a sweep through every
file first. On the default branch nothing is changed, so such a check
checks nothing there, and a change elsewhere that creates a violation on
an untouched line is only seen by a check over `all` files.

## Adding a check

Every check is one file in `priv/checks/`. Every `.rs` file in that
directory is a check: the library's build script lists the directory at
compile time and compiles the files in with the built-in checks, so adding
a check is adding a file. A file named like a built-in check stops the
build.

A check implements the `Check` trait from the library's `check` module and
exports itself as `CHECK`. Two functions to write:

- `name` returns the file name without `.rs`, which is how the config
  refers to the check and what is shown next to each violation. A
  generated test fails the build when the two differ.
- `run` is given the `State`, every file and every change, and the check's
  `Config`, and returns `Violation`s, or an error message when the config
  cannot be used.

Here is a complete check that forbids `IO.inspect`:

```rust
use crate::check::{fast, slow, Check, Config, Files, State, Violation};

pub struct NoIoInspect;

pub const CHECK: &dyn Check = &NoIoInspect;

impl Check for NoIoInspect {
    fn name(&self) -> &'static str {
        "no_io_inspect"
    }

    fn run(&self, state: &State, config: &Config) -> Result<Vec<Violation>, String> {
        let files = state.files(config.scope()).with_extension(&["ex", "exs"]);
        let suspects = fast(config, files, |file| file.contents().contains("IO.inspect"));
        let violations = slow(config, suspects, |file| {
            file.contents()
                .lines()
                .enumerate()
                .filter(|(_, line)| line.contains("IO.inspect") && !line.trim_start().starts_with('#'))
                .map(|(index, _)| Violation::at(index + 1, "remove the IO.inspect call"))
                .collect()
        });
        Ok(state.in_scope(config.scope(), violations))
    }
}
```

The four lines of `run` are the shape every check about files follows,
with a helper for each step:

1. **Pick the files.** `state.files(config.scope())` is every file, or the
   files the branch changed, as the config says. `with_extension` keeps
   the ones the check applies to.
2. **The fast pass.** `fast` keeps the files the closure says yes to, in
   parallel.
3. **The slow pass.** `slow` runs the closure on each kept file, in
   parallel, and collects the violations. `Violation::at(line, message)`
   is on a line of the file in hand; `slow` fills in the path.
4. **Keep what is in scope.** `state.in_scope` drops violations on lines
   the branch did not change when the scope is `changed`, and does
   nothing otherwise.

The check calls each helper itself, so nothing happens to its files or
violations that it did not ask for. Read a file with `file.contents()`.
Files are read from disk the first time any check asks and shared after
that. `file.line_of(offset)` is the line of a byte offset.

Save the file as `priv/checks/no_io_inspect.rs`, add `:no_io_inspect` to
`enabled` in `.app_checks.exs`, and run `mix app_checks`.

## A check about the branch

A check about which paths changed, rather than about the contents of a
file, reads `state.changed()`: every path the branch changed, deleted
files included, each with the lines it changed. It returns
`Violation::file(path, message)` for a violation about a whole file, or
`Violation::run(message)` for one about the whole run. Such a check reads
the branch whatever its scope is, and should say so in its docs.

Here is a complete check that fails when a branch adds a file ending in
`.env`:

```rust
use crate::check::{Check, Config, State, Violation};

pub struct NoEnvFiles;

pub const CHECK: &dyn Check = &NoEnvFiles;

impl Check for NoEnvFiles {
    fn name(&self) -> &'static str {
        "no_env_files"
    }

    fn run(&self, state: &State, _config: &Config) -> Result<Vec<Violation>, String> {
        Ok(state
            .changed()
            .iter()
            .filter(|file| file.path.extension().is_some_and(|ext| ext == "env"))
            .map(|file| Violation::file(&file.path, "secrets do not belong in git, add the file to .gitignore"))
            .collect())
    }
}
```

The built-in [`separate_pr.rs`](https://github.com/chrislaskey/app_checks/blob/main/priv/checks/src/checks/separate_pr.rs)
is a larger worked example that uses config keys.

## Config keys

A check that needs configuration declares the keys it accepts and reads
them from `Config`:

```rust
fn config_keys(&self) -> &'static [&'static str] {
    &["paths", "groups.*"]
}
```

A key ending in `.*` accepts any one more segment, so `groups.*` accepts
`groups.agents`. The runner refuses any other key before any check runs.
`config.one(key)` is the last value, `config.many(key)` every value, and
`config.under(prefix)` every key below `prefix.` with the prefix removed,
which is how `groups.agents` and `groups.lint_config` become named groups.

In `.app_checks.exs` the keys are the `config:` keyword list of the check.
The Mix task flattens it: a list gives the key once per element and a
nested keyword list adds a segment.

```elixir
{:separate_pr, config: [groups: [agents: ["AGENTS.md"], lint_config: [".credo.exs", ".check.exs"]]]}
```

becomes `--set separate_pr.groups.agents=AGENTS.md`,
`--set separate_pr.groups.lint_config=.credo.exs` and
`--set separate_pr.groups.lint_config=.check.exs`.

A check that does expensive work from its config, such as reading a module
or building a regular expression, does it in `prepare`, which the runner
calls once for every enabled check before anything runs or prints. The
built-in [`core_component_tags.rs`](https://github.com/chrislaskey/app_checks/blob/main/priv/checks/src/checks/core_component_tags.rs)
reads the components modules there, builds one regular expression from their
function names, and keeps both in a `OnceLock`. An `Err` from `prepare` or
`run` stops the run with exit code `2`. `glob_set(key, patterns)` builds a
path matcher and refuses an empty list or a bad pattern.

## Testing a check

Each check file ends with its own tests. The helpers in `check::testing`
keep them short:

- `state()` builds a `State` file by file: `.file(path, contents)` for a
  file the branch did not touch, `.changed(path, contents, &[lines])` for
  one it changed on those lines, `.added(path, contents)` for a new one,
  `.deleted(path)`, then `.build()`.
- `config(check, &[(key, value)])` is a config for the check with those
  keys, as an error over all files. `scoped(check, scope, keys)` sets the
  scope.
- `run(check, state, config)` prepares and runs the check and returns each
  violation as `path:line: message`, in path and line order.
- `error(check, state, config)` is the message when preparing or running
  fails.

Here are tests for the `IO.inspect` check above:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::check::testing::{config, run, scoped, state};
    use crate::check::Scope;

    #[test]
    fn skips_comments() {
        let state = state().file("a.ex", "# IO.inspect\nIO.inspect(x)\n").build();
        assert_eq!(
            run(&NoIoInspect, &state, &config(&NoIoInspect, &[])),
            vec!["a.ex:2: remove the IO.inspect call"]
        );
    }

    #[test]
    fn the_changed_scope_skips_old_lines() {
        let state = state().changed("a.ex", "IO.inspect(x)\nIO.inspect(y)\n", &[2]).build();
        assert_eq!(
            run(&NoIoInspect, &state, &scoped(&NoIoInspect, Scope::Changed, &[])),
            vec!["a.ex:2: remove the IO.inspect call"]
        );
    }
}
```

And one for the `.env` check:

```rust
#[test]
fn fails_on_env_files_only() {
    let state = state().added("env/dev.env", "").changed("config/dev.exs", "", &[1]).build();
    assert_eq!(
        run(&NoEnvFiles, &state, &config(&NoEnvFiles, &[])),
        vec!["env/dev.env: secrets do not belong in git, add the file to .gitignore"]
    );
}
```

Run them, together with the tests of the built-in checks, with:

```sh
mix app_checks.test
```

## Writing a good check

- **The fast pass must not miss anything.** It is fine for it to
  over-report. It is not fine for it to stay quiet on a real problem,
  because the slow pass only looks at files the fast pass kept.
- **The slow pass may rescan the whole file.** It does not need to know
  what the fast pass found.
- **Write the message as an instruction.** Say what to use instead, as in
  `use <.p> from CoreComponents`. The reader may be a person or a tool
  fixing the code without any other context.
- **Skip files early.** Filter by extension before reading anything. A
  file is only read from disk when a check asks for its contents.
- **Do the expensive work once**, in `prepare`, not inside the closures,
  which run on every file. One expression that matches every tag at once
  is one pass over each file however many tags there are.
- **Refuse bad config loudly.** Return an error for a value you cannot
  use, naming the key, rather than falling back to a default. A check that
  quietly checks nothing is worse than no check.
- **Leave the meaning to the config.** A check returns facts. Whether a
  fact fails the run is `level`, and whether old code counts is `scope`.
  The same check can be an error in one project and a warning on changed
  lines in another, without a line of Rust changing.

## Where things live

| Path | What it is |
|---|---|
| `priv/checks/` | This project's own checks, one `.rs` file each. |
| `.app_checks.exs` | The named configs: which checks run, what a violation means, which files each looks at, and each check's own keys. |
| `.check.exs` | Lists the Mix task as a tool so `mix check` runs it with everything else. |
| [`app_checks`](https://github.com/chrislaskey/app_checks) | The library, in its own repository. Its README covers installing it in a project. |
| [`priv/checks/src/main.rs`](https://github.com/chrislaskey/app_checks/blob/main/priv/checks/src/main.rs) | The runner. Parses the flags, prepares the enabled checks, gathers the state from git, runs each check, prints its violations, then the summary, and sets the exit code. |
| [`priv/checks/src/check.rs`](https://github.com/chrislaskey/app_checks/blob/main/priv/checks/src/check.rs) | The `Check` trait, the `State`, `File`, `Config` and `Violation` types, the `fast`, `slow` and `glob_set` helpers, and the `testing` helpers. |
| [`priv/checks/src/checks/core_component_tags.rs`](https://github.com/chrislaskey/app_checks/blob/main/priv/checks/src/checks/core_component_tags.rs) | A built-in check about files, with config and `prepare`. |
| [`priv/checks/src/checks/separate_pr.rs`](https://github.com/chrislaskey/app_checks/blob/main/priv/checks/src/checks/separate_pr.rs) | A built-in check about the branch. See the [Code Review](../patterns/code-review.md) pattern. |
