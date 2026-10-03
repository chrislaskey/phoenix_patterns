# Writing checks in Rust

A check is a rule about the source code, such as "templates must not use a
raw `<p>` tag". The checks live in `priv/checks/`, a small Rust program. It reads
every source file once, runs each check against each file, prints what it
finds, and exits with an error code if anything is wrong.

Rust is used so the whole run finishes in well under a second, even on a large
codebase. A slow check gets ignored, then deleted.

## How a run works

Each check has two parts: a fast pass and a slow pass.

1. **The fast pass** runs on every file. It is a cheap scan, such as a
   substring search. It must never miss a real problem, so when it is not sure
   it reports the line as `potential` rather than staying quiet. When it is
   sure, it reports the line as `confirmed`.
2. **The slow pass** runs only on the files where the fast pass reported
   something `potential`. It does the careful work, such as parsing, and
   reports only what it can confirm.

Findings print as soon as each file finishes, so you can start fixing the first
one while the rest of the run continues. Files run in parallel.

Here is a run against the example app, trimmed to one potential finding per
kind:

```
lib/example_web/controllers/page_html/home.html.heex:10: <p may be a raw tag [raw_html_tags, potential]
lib/example_web/controllers/page_html/home.html.heex:50: <h may be a raw tag [raw_html_tags, potential]
lib/example_web/controllers/page_html/home.html.heex:59: <p> is a raw tag, use <.p> from CoreComponents [raw_html_tags, confirmed]
lib/example_web/controllers/page_html/home.html.heex:62: <p> is a raw tag, use <.p> from CoreComponents [raw_html_tags, confirmed]
lib/example_web/components/layouts/root.html.heex:2: <h may be a raw tag [raw_html_tags, potential]
lib/example_web/controllers/page_html/home.html.heex:50: <h1> is a raw tag, use <.h1> from CoreComponents [raw_html_tags, confirmed]
1 check(s) over 17 file(s), 2 slow pass(es), 3 confirmed finding(s)
```

Each line is `file:line: message [check name, confidence]`.

Read it like this. Line 10 holds `<path`, which the fast pass could not tell
apart from `<p`, so it reported it as potential. Lines 59 and 62 hold
`<p class=`, which the fast pass could confirm on its own. Line 50 holds `<h1`, reported as
potential by the fast pass and then confirmed by the slow pass. Line 2 of the
layout holds `<html`. The slow pass looked at it and said nothing, which means
it was cleared.

The last line is a summary. The exit code is `1` if any finding was confirmed
and `0` otherwise. Potential findings that the slow pass cleared do not fail
the run.

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

There are two options, and each can be given more than once. `--ignore NAME`
skips every directory called `NAME`, however deep, so
`checks --ignore deps --ignore _build .` is safe. A directory named directly
as a path is still scanned. `--disable NAME` skips the check called `NAME`.
Naming a check that does not exist is an error, so a typo cannot quietly
disable nothing.

Day to day, run the checks through Mix instead. `mix app.checks` builds the
program first, then fills in those options from `.app_checks.exs` in the
project root and passes any paths through:

```sh
mix app.checks
mix app.checks lib test
```

Every key in the file is optional. These are the defaults:

```elixir
[
  paths: ["lib"],
  paths_to_ignore: ["_build", "deps", "node_modules"],
  disabled_checks: []
]
```

Paths on the command line replace `paths` for that run. `disabled_checks`
names checks by file name, so `[:raw_html_tags]` turns off
`src/checks/raw_html_tags.rs`.

`mix check` runs the same task alongside the formatter, Credo and the tests,
see `.check.exs`. The task is in `lib/mix/tasks/app.checks.ex`.

## Adding a check

Every check is one file in `priv/checks/src/checks/`. Every `.rs` file in that
directory is a check: `build.rs` lists the directory at compile time and
generates the `checks` module from it, so adding a check is adding a file.
Each file implements the `Check` trait from `priv/checks/src/check.rs`, which
has three functions, and exports the result as `CHECK`:

- `name` returns a short label shown next to each finding. It must be the
  file name without `.rs`, because that is also how `disabled_checks` refers
  to the check. A generated test fails the build when the two differ.
- `fast` takes a file and returns findings. Use `Finding::confirmed` when sure
  and `Finding::potential` when not.
- `slow` takes a file and returns only `Finding::confirmed` findings.

Here is a complete check that forbids `IO.inspect` in `lib/`:

```rust
use crate::check::{Check, Finding, SourceFile};

pub struct NoIoInspect;

pub const CHECK: &dyn Check = &NoIoInspect;

impl Check for NoIoInspect {
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

## Testing a check

Each check file ends with its own tests. Three helpers in `check::testing`
keep them short:

- `source(path, contents)` builds a file from a snippet. Only the extension of
  the path matters.
- `lines(findings, confidence)` returns the line numbers of the findings with
  that confidence.
- `run(check, path, contents)` runs the fast pass, then the slow pass if
  anything was potential, and returns the line numbers that end up confirmed.
  This is what a real run would report for that file.

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
- **Skip files early.** If a check only applies to templates, return an empty
  list for everything else before doing any work. See `is_template` in
  `priv/checks/src/checks/raw_html_tags.rs`.

## Where things live

| Path | What it is |
|---|---|
| `priv/checks/Cargo.toml` | The Rust project. Two dependencies: `rayon` for running files in parallel, `walkdir` for finding files. |
| `priv/checks/src/main.rs` | The runner. Parses `--ignore` and `--disable`, collects files, runs the fast pass, then the slow pass, then prints the summary and sets the exit code. |
| `priv/checks/src/check.rs` | The `Check` trait, the `Finding` and `SourceFile` types every check uses, and the `testing` helpers. |
| `priv/checks/build.rs` | Runs at compile time. Lists `src/checks/`, generates the `checks` module with `all()`, and a test that each check's `name` matches its file name. |
| `priv/checks/src/checks/raw_html_tags.rs` | A worked example check. |
| `priv/checks/README.md` | The short version of this guide, kept next to the code. |
| `lib/mix/tasks/app.checks.ex` | The Mix task. Builds the program with cargo, runs it, and fails when a finding is confirmed. |
| `.check.exs` | Lists the Mix task as a tool so `mix check` runs it with everything else. |
| `.app_checks.exs` | Paths to scan, directory names to ignore, and checks to disable. Optional. |
