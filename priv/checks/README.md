# Custom checks in rust

Custom checks, written in Rust. There are two kinds, named after what they
are given:

- A **source check** is given one source file. It runs in two passes. The
  **fast** pass is a cheap scan of every file, printing findings as each file
  finishes. It must never miss a real problem, so when unsure it returns a
  `potential` finding instead of a `confirmed` one. The **slow** pass is a
  thorough scan of only the files that had a `potential` finding, and prints
  what it confirms.
- A **branch check** is given the branch: every path it changed compared
  with a base branch. It runs once. Git is only read, never fetched.

The run exits `1` if anything was confirmed, `0` otherwise, and `2` when the
arguments, the settings or git are wrong.

## Config

`.app_checks.exs` follows the same shape as `.check.exs` and `.credo.exs`:
one Elixir file in the project root, named after the command that reads it.
The first four keys are the runner's, every one optional, with these
defaults:

```elixir
[
  paths: ["lib"],
  paths_to_ignore: ["_build", "deps", "node_modules"],
  disabled_checks: [],
  base: "origin/main"
]
```

Every other key names a check and holds its settings as a keyword list. See
`.app_checks.exs` for the `review_tier` settings as an example.

The Mix task reads the file and turns it into command line arguments. The
Rust program knows nothing about the file, so it needs no changes when the
config grows.

Every file in `priv/checks/src/checks` is a check. Dropping a new file in is
enough to include it, and `disabled_checks` lists the ones to skip by file
name, as in `[:raw_html_tags]`. Disabling a check that does not exist is an
error, so a typo cannot quietly disable nothing. The same goes for a setting
a check does not accept.

## Build and run

From the repository root:

```sh
cargo build --release --manifest-path priv/checks/Cargo.toml
./priv/checks/target/release/checks            # scans lib/
./priv/checks/target/release/checks lib test   # or any files and directories
```

Or in one step: `cargo run --release --manifest-path priv/checks/Cargo.toml -- lib`.

Four options. All but `--base` can be repeated:

```sh
./priv/checks/target/release/checks --base origin/develop lib             # what branch checks compare with
./priv/checks/target/release/checks --ignore deps --ignore _build lib     # skip directories with these names
./priv/checks/target/release/checks --disable raw_html_tags lib           # skip a check
./priv/checks/target/release/checks --set review_tier.low='docs/**' lib   # one setting for one check
```

Day to day, run through Mix instead. `mix app.checks` builds first, reads
`.app_checks.exs` and runs with those arguments:

```sh
mix app.checks
mix app.checks lib test
mix app.checks --base feature/parent-branch   # for a branch built on another branch
```

This is also how `mix check` runs them, see `.check.exs`.

## Test

```sh
cargo test --manifest-path priv/checks/Cargo.toml
```

## Output

One line per finding. Source checks give a file and a line:

```
lib/example_web/controllers/page_html/home.html.heex:59: <p> is a raw tag, use <.p> from CoreComponents [raw_html_tags, confirmed]
lib/example_web/controllers/page_html/home.html.heex:10: <p may be a raw tag [raw_html_tags, potential]
```

A `potential` line means the slow pass will look at that file. If nothing
follows for it, the slow pass cleared it.

Branch checks give a file with no line, or no file at all, and may print
`info` lines that never fail the run:

```
lib/example/orders.ex: standard [review_tier, info]
review tier: standard, 1 file(s) changed against origin/main [review_tier, info]
```

## Adding a check

Create `src/checks/my_check.rs`. Every `.rs` file in that directory is a
check, found by `build.rs` at compile time, so there is no list to edit.

1. Define a struct that implements `SourceCheck` or `BranchCheck` (see
   `src/check.rs`). `name` must return the file name without `.rs`, here
   `"my_check"`, which is how `disabled_checks` and `--set` refer to it. A
   generated test fails the build if it does not.
2. Export it: `pub const CHECK: Kind = Kind::Source(&MyCheck);` or
   `Kind::Branch(&MyCheck)`.
3. Add a `#[cfg(test)] mod tests` at the bottom of the file. The helpers in
   `check::testing` build a file from a snippet (`source`), a branch from a
   list of paths (`branch`), settings from pairs (`settings`), pick out line
   numbers or messages by confidence (`lines`, `messages`), and run both
   passes of a source check the way the runner does (`run`).

`src/checks/raw_html_tags.rs` is a worked source check and
`src/checks/review_tier.rs` a worked branch check with settings.

## Additional links

See the [Guide for writing checks in rust](../../docs/guides/writing-checks-in-rust.md)
