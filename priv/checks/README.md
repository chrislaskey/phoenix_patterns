# Custom checks in rust

Custom source code checks, written in Rust. Each check runs in two passes:

1. **Fast**: a cheap scan of every file. Findings print as soon as each file
   finishes. A finding is either `confirmed` or `potential`. Fast must never
   miss a real problem, so when unsure it returns `potential`.
2. **Slow**: a thorough scan of only the files that had a `potential` finding.
   Prints the findings it confirms.

The run exits `1` if anything was confirmed, `0` otherwise.

## Config

`.app_checks.exs` follows the same shape as `.check.exs` and `.credo.exs`:
one Elixir file in the project root, named after the command that reads it.
Every key is optional and these are the defaults:

```elixir
[
  paths: ["lib"],
  paths_to_ignore: ["_build", "deps", "node_modules"],
  disabled_checks: []
]
```

The Mix task reads the file and turns it into command line arguments. The
Rust program knows nothing about the file, so it needs no changes when the
config grows.

Every file in `priv/checks/src/checks` is a check. Dropping a new file in is
enough to include it, and `disabled_checks` lists the ones to skip by file
name, as in `[:raw_html_tags]`. Disabling a check that does not exist is an
error, so a typo cannot quietly disable nothing.

## Build and run

From the repository root:

```sh
cargo build --release --manifest-path priv/checks/Cargo.toml
./priv/checks/target/release/checks            # scans lib/
./priv/checks/target/release/checks lib test   # or any files and directories
```

Or in one step: `cargo run --release --manifest-path priv/checks/Cargo.toml -- lib`.

Two options, each repeatable:

```sh
./priv/checks/target/release/checks --ignore deps --ignore _build lib   # skip directories with these names
./priv/checks/target/release/checks --disable raw_html_tags lib         # skip a check
```

Day to day, run through Mix instead. `mix app.checks` builds first, reads
`.app_checks.exs` in the project root for the paths to scan, the directory
names to ignore and the checks to disable, and then runs with those:

```sh
mix app.checks
mix app.checks lib test
```

This is also how `mix check` runs them, see `.check.exs`.

## Test

```sh
cargo test --manifest-path priv/checks/Cargo.toml
```

## Output

One line per finding:

```
lib/example_web/controllers/page_html/home.html.heex:59: <p> is a raw tag, use <.p> from CoreComponents [raw_html_tags, confirmed]
lib/example_web/controllers/page_html/home.html.heex:10: <p may be a raw tag [raw_html_tags, potential]
```

A `potential` line means the slow pass will look at that file. If nothing
follows for it, the slow pass cleared it.

## Adding a check

Create `src/checks/my_check.rs`. Every `.rs` file in that directory is a
check, found by `build.rs` at compile time, so there is no list to edit.

1. Define a struct that implements `Check` (see `src/check.rs`). `fast`
   returns `Finding::confirmed` or `Finding::potential`; `slow` returns only
   `Finding::confirmed`. `name` must return the file name without `.rs`, here
   `"my_check"`, which is how `disabled_checks` refers to it. A generated
   test fails the build if it does not.
2. Export it: `pub const CHECK: &dyn Check = &MyCheck;`
3. Add a `#[cfg(test)] mod tests` at the bottom of the file. The helpers in
   `check::testing` build a file from a snippet (`source`), pick out line
   numbers by confidence (`lines`), and run both passes the way the runner
   does (`run`).

`src/checks/raw_html_tags.rs` is a worked example.

## Additional links

See the [Guide for writing checks in rust](../../docs/guides/writing-checks-in-rust.md)
