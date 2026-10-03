# Writing checks in Rust

A check is a rule the repository must follow. The checks live in
`priv/checks/`, a small Rust program. It runs each check, prints what it
finds, and exits with an error code if anything is wrong.

There are two kinds of check, named after what they are given:

- A **source check** is given one source file, such as "templates must use
  `<.button>` rather than a raw `<button>`". It reads every source file once
  and runs on each.
- A **branch check** is given the branch: every path it changed compared
  with a base branch, such as "a change to `AGENTS.md` must be the only
  change". It runs once.

Rust is used so the whole run finishes in well under a second, even on a large
codebase. A slow check gets ignored, then deleted.

## How a run works

Branch checks run first, once. Then source checks, in two passes:

1. **The fast pass** runs on every file. It is a cheap scan, such as a
   substring search. It must never miss a real problem, so when it is not sure
   it reports the line as `potential` rather than staying quiet. When it is
   sure, it reports the line as `confirmed`.
2. **The slow pass** runs only on the files where the fast pass reported
   something `potential`. It does the careful work, such as parsing, and
   reports only what it can confirm.

Findings print as soon as each file finishes, so you can start fixing the first
one while the rest of the run continues. Files run in parallel.

Here is a run on a branch that changed the layout module, where a doc string
mentions `<button>` on line 24 and a template uses one on line 134, and a
page template uses a raw `<input>`:

```
lib/example_web/components/layouts.ex: high [review_tier, info]
review tier: high, 1 file(s) changed against origin/main [review_tier, info]
lib/example_web/components/layouts.ex:24: <button> may be a raw tag [core_component_tags, potential]
lib/example_web/components/layouts.ex:134: <button> may be a raw tag [core_component_tags, potential]
lib/example_web/controllers/page_html/home.html.heex:12: <input> is a raw tag, use <.input> from ExampleWeb.CoreComponents [core_component_tags, confirmed]
lib/example_web/components/layouts.ex:134: <button> is a raw tag, use <.button> from ExampleWeb.CoreComponents [core_component_tags, confirmed]
2 check(s) over 18 file(s), 1 slow pass(es), 2 confirmed finding(s)
```

Each line is `file:line: message [check name, confidence]`. A branch check
has no line to give, so its lines are `file: message` or just `message`.

Read it like this. The first two lines are the branch check: the one changed
file is in the `high` tier, so the branch is too. They are `info`, which
never fails the run. The `.heex` file is all template, so its `<input>` is
confirmed by the fast pass on its own. In the `.ex` file the fast pass cannot
tell a template from a doc string, so it reports both mentions of `<button>`
as potential. The slow pass reads only the `~H` templates in that file. It
confirms line 134 and says nothing about line 24, which means it was
cleared.

The last line is a summary. The exit code is `1` if any finding was confirmed
and `0` otherwise. Potential findings that the slow pass cleared do not fail
the run, and neither do `info` findings.

## Build and run

You need Rust. The version is pinned in `.tool-versions`, so `asdf install`
sets it up.

From the repository root:

```sh
cargo build --release --manifest-path priv/checks/Cargo.toml
./priv/checks/target/release/checks
```

With no arguments it scans `lib/`. Pass any files or directories to scan
something else:

```sh
./priv/checks/target/release/checks lib test
./priv/checks/target/release/checks lib/example_web/components/layouts.ex
```

To build and run in one step:

```sh
cargo run --release --manifest-path priv/checks/Cargo.toml -- lib
```

There are four options:

- `--base REF` is what branch checks compare the current branch with,
  `origin/main` when not given. The comparison starts where the branch left
  the base, so commits that landed on the base afterwards do not count. Git
  is only read. Nothing is fetched or changed.
- `--ignore NAME` skips every directory called `NAME`, however deep, so
  `checks --ignore deps --ignore _build .` is safe. A directory named directly
  as a path is still scanned.
- `--disable NAME` skips the check called `NAME`. Naming a check that does
  not exist is an error, so a typo cannot quietly disable nothing.
- `--set CHECK.KEY=VALUE` gives one setting to one check. A check that does
  not exist, or a key the check does not accept, is an error for the same
  reason.

All but `--base` can be given more than once. Paths apply to source checks
only. A branch check always looks at the whole branch.

Day to day, run the checks through Mix instead. `mix app.checks` builds the
program first, then fills in those options from `.app_checks.exs` in the
project root and passes any paths through:

```sh
mix app.checks
mix app.checks lib test
mix app.checks --base feature/parent-branch
```

The last form is for a branch that builds on another unmerged branch.

Every key in the file is optional. These are the defaults:

```elixir
[
  paths: ["lib"],
  paths_to_ignore: ["_build", "deps", "node_modules"],
  disabled_checks: [],
  base: "origin/main"
]
```

Paths on the command line replace `paths` for that run. `disabled_checks`
names checks by file name, so `[:core_component_tags]` turns off
`src/checks/core_component_tags.rs`.

Any other key names a check and holds its settings. See "Settings" below.

`mix check` runs the same task alongside the formatter, Credo and the tests,
see `.check.exs`. The task is in `lib/mix/tasks/app.checks.ex`.

## Adding a source check

Every check is one file in `priv/checks/src/checks/`. Every `.rs` file in that
directory is a check: `build.rs` lists the directory at compile time and
generates the `checks` module from it, so adding a check is adding a file.
Each file exports the check as `CHECK`, wrapped in `Kind::Source` or
`Kind::Branch` from `priv/checks/src/check.rs`.

A source check implements the `SourceCheck` trait, which has three functions
to write:

- `name` returns a short label shown next to each finding. It must be the
  file name without `.rs`, because that is also how `disabled_checks` refers
  to the check. A generated test fails the build when the two differ.
- `fast` takes a file and returns findings. Use `Finding::confirmed` when sure
  and `Finding::potential` when not.
- `slow` takes a file and returns only `Finding::confirmed` findings.

And two more for a check that takes settings, `settings` and `prepare`. See
"Settings" below.

Here is a complete check that forbids `IO.inspect` in `lib/`:

```rust
use crate::check::{Finding, Kind, SourceCheck, SourceFile};

pub struct NoIoInspect;

pub const CHECK: Kind = Kind::Source(&NoIoInspect);

impl SourceCheck for NoIoInspect {
    fn name(&self) -> &'static str {
        "no_io_inspect"
    }

    fn fast(&self, file: &SourceFile) -> Vec<Finding> {
        file.contents
            .match_indices("IO.inspect")
            .map(|(offset, _)| {
                Finding::potential(file.line_of(offset), "IO.inspect may be a leftover debug call")
            })
            .collect()
    }

    fn slow(&self, file: &SourceFile) -> Vec<Finding> {
        file.contents
            .lines()
            .enumerate()
            .filter(|(_, line)| line.contains("IO.inspect") && !line.trim_start().starts_with('#'))
            .map(|(index, _)| Finding::confirmed(index + 1, "remove the IO.inspect call"))
            .collect()
    }
}
```

The fast pass flags every mention, including ones inside comments. The slow
pass drops the commented lines and confirms the rest.

There is nothing to wire in. Save the file as
`priv/checks/src/checks/no_io_inspect.rs`, build, and run. The new check is
now part of every run. To turn it off for a project without deleting it, add
it to `disabled_checks` in `.app_checks.exs`.

## Adding a branch check

A branch check implements the `BranchCheck` trait: `name` as above, and
`run`, which takes the `Branch` and the check's `Settings` and returns
findings, or an error message when the settings cannot be used. The error
stops the run with exit code `2` before anything else runs.

The `Branch` has `base`, the branch it was compared with, and `paths`, every
path the branch changed: commits since it left the base, staged and unstaged
edits, and untracked files that are not ignored. A rename is both paths.

Findings from a branch check name their own file, since there is no current
file. `Finding::about(path, confidence, message)` is about a file and
`Finding::info(message)` is about the whole run. The third confidence,
`Confidence::Info`, prints but never fails the run.

Here is a complete check that fails when a branch adds a file ending in
`.env`:

```rust
use crate::check::{Branch, BranchCheck, Confidence, Finding, Kind, Settings};

pub struct NoEnvFiles;

pub const CHECK: Kind = Kind::Branch(&NoEnvFiles);

impl BranchCheck for NoEnvFiles {
    fn name(&self) -> &'static str {
        "no_env_files"
    }

    fn run(&self, branch: &Branch, _settings: &Settings) -> Result<Vec<Finding>, String> {
        Ok(branch
            .paths
            .iter()
            .filter(|path| path.extension().is_some_and(|ext| ext == "env"))
            .map(|path| {
                Finding::about(path, Confidence::Confirmed, "secrets do not belong in git, add the file to .gitignore")
            })
            .collect())
    }
}
```

`priv/checks/src/checks/review_tier.rs` is a larger worked example that uses
settings.

## Settings

A check that needs configuration declares the keys it accepts and reads them
from `Settings`:

```rust
fn settings(&self) -> &'static [&'static str] {
    &["default", "protected.*", "high", "standard", "low"]
}
```

A key ending in `.*` accepts any one more segment, so `protected.*` accepts
`protected.agents`. The runner refuses any other key before any check runs.

`Settings` keeps every value in the order given, with the check name removed
from the keys. `one(key)` is the last value, so a later `--set` overrides an
earlier one. `many(key)` is every value. `under(prefix)` is every key below
`prefix.` with the prefix removed, which is how `protected.agents` and
`protected.lint_config` become named groups.

A branch check gets its `Settings` in `run`. A source check gets them in
`prepare`, which the runner calls once, before any file is scanned and before
anything prints. The check reads what it needs there and keeps it for the
passes. `priv/checks/src/checks/core_component_tags.rs` reads the components
modules in `prepare`, builds one regular expression from their function
names, and keeps both in a `OnceLock`. An `Err` from `prepare` stops the run with
exit code `2`, the same as from `run`.

In `.app_checks.exs` the settings are a keyword list under the check's name.
The Mix task flattens it: a list gives the key once per element and a nested
keyword list adds a segment.

```elixir
review_tier: [
  default: :high,
  protected: [agents: ["AGENTS.md"]],
  high: ["config/**", "mix.exs"]
]
```

becomes `--set review_tier.default=high`,
`--set review_tier.protected.agents=AGENTS.md`,
`--set review_tier.high=config/**` and `--set review_tier.high=mix.exs`.

## Testing a check

Each check file ends with its own tests. The helpers in `check::testing`
keep them short:

- `source(path, contents)` builds a file from a snippet. Only the extension of
  the path matters.
- `lines(findings, confidence)` returns the line numbers of the findings with
  that confidence.
- `run(check, path, contents)` runs the fast pass, then the slow pass if
  anything was potential, and returns the line numbers that end up confirmed.
  This is what a real run would report for that file.
- `branch(paths)` builds a branch that changed those paths, and
  `settings(pairs)` builds settings from `(key, value)` pairs.
- `messages(findings, confidence)` returns `file: message` strings, for
  findings that have no line.

Here are tests for the `IO.inspect` check above:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::check::Confidence::Potential;
    use crate::check::testing::{lines, run, source};

    #[test]
    fn fast_flags_every_mention() {
        let file = source("a.ex", "# IO.inspect\nIO.inspect(x)\n");
        assert_eq!(lines(&NoIoInspect.fast(&file), Potential), vec![1, 2]);
    }

    #[test]
    fn full_run_skips_comments() {
        assert_eq!(run(&NoIoInspect, "a.ex", "# IO.inspect\nIO.inspect(x)\n"), vec![2]);
    }
}
```

And one for the `.env` check:

```rust
#[test]
fn fails_on_env_files_only() {
    let findings = NoEnvFiles
        .run(&branch(&["env/dev.env", "config/dev.exs"]), &settings(&[]))
        .unwrap();
    assert_eq!(
        messages(&findings, Confirmed),
        vec!["env/dev.env: secrets do not belong in git, add the file to .gitignore"]
    );
}
```

Run them with:

```sh
cargo test --manifest-path priv/checks/Cargo.toml
```

## Writing a good check

- **The fast pass must not miss anything.** It is fine for it to over-report.
  It is not fine for it to stay quiet on a real problem, because the slow pass
  only looks at files the fast pass flagged.
- **Only confirm from the fast pass when it is certain.** A confirmed finding
  fails the run and is never re-checked.
- **The slow pass may rescan the whole file.** It does not need to know what
  the fast pass found. If it reports a line the fast pass already confirmed,
  the runner drops the duplicate.
- **Write the message as an instruction.** Say what to use instead, as in
  `use <.p> from CoreComponents`. The reader may be a person or a tool fixing
  the code without any other context.
- **Skip files early.** If a check only applies to some files, return an
  empty list for the rest before doing any work. See `is_module` in
  `priv/checks/src/checks/core_component_tags.rs`, which compares file names
  before it touches the disk.
- **Do the expensive work once.** A check that reads a module or builds a
  regular expression does it in `prepare`, not in `fast`, which runs on
  every file. One expression that matches every tag at once is one pass
  over each file however many tags there are.
- **Refuse bad settings loudly.** Return an error from `run` for a value you
  cannot use, naming the setting, rather than falling back to a default. A
  check that quietly checks nothing is worse than no check.
- **Use `info` for what people look for on a good day.** The tier of a branch
  is worth printing every time. A problem is `confirmed`.

## Where things live

| Path | What it is |
|---|---|
| `priv/checks/Cargo.toml` | The Rust project. Four dependencies: `rayon` for running files in parallel, `walkdir` for finding files, `globset` for matching paths against patterns, `regex` for matching text. |
| `priv/checks/src/main.rs` | The runner. Parses the options, prepares the source checks, collects the branch from git and the files from disk, runs branch checks, then the fast and slow passes, then prints the summary and sets the exit code. |
| `priv/checks/src/check.rs` | The `SourceCheck` and `BranchCheck` traits, the `Kind` enum, the `Finding`, `SourceFile`, `Branch` and `Settings` types, and the `testing` helpers. |
| `priv/checks/build.rs` | Runs at compile time. Lists `src/checks/`, generates the `checks` module with `all()`, and a test that each check's `name` matches its file name. |
| `priv/checks/src/checks/core_component_tags.rs` | A worked source check with settings and a `prepare` step. See the [Common UI](../patterns/common-ui.md) pattern. |
| `priv/checks/src/checks/review_tier.rs` | A worked branch check with settings. See the [Code Review](../patterns/code-review.md) pattern. |
| `priv/checks/README.md` | The short version of this guide, kept next to the code. |
| `lib/mix/tasks/app.checks.ex` | The Mix task. Builds the program with cargo, turns `.app_checks.exs` into options, runs it, and fails when a finding is confirmed. |
| `.check.exs` | Lists the Mix task as a tool so `mix check` runs it with everything else. |
| `.app_checks.exs` | Paths to scan, directory names to ignore, checks to disable, the base branch, and each check's settings. Optional. |
