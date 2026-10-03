# Custom checks in rust

Custom source code checks, written in Rust. Each check runs in two passes:

1. **Fast**: a cheap scan of every file. Findings print as soon as each file
   finishes. A finding is either `confirmed` or `potential`. Fast must never
   miss a real problem, so when unsure it returns `potential`.
2. **Slow**: a thorough scan of only the files that had a `potential` finding.
   Prints the findings it confirms.

The run exits `1` if anything was confirmed, `0` otherwise.

## Build and run

From the repository root:

```sh
cargo build --release --manifest-path priv/checks/Cargo.toml
./priv/checks/target/release/checks            # scans lib/
./priv/checks/target/release/checks lib test   # or any files and directories
```

Or in one step: `cargo run --release --manifest-path priv/checks/Cargo.toml -- lib`.

Directories named `_build`, `deps`, or `node_modules` are skipped unless you
name one directly.

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

1. Create `src/checks/my_check.rs` with a struct that implements `Check`
   (see `src/check.rs`). `fast` returns `Finding::confirmed` or
   `Finding::potential`; `slow` returns only `Finding::confirmed`.
2. In `src/checks/mod.rs`, add `mod my_check;` and push `Box::new(my_check::MyCheck)`
   onto the list in `all()`.
3. Add a `#[cfg(test)] mod tests` at the bottom of the file. The helpers in
   `check::testing` build a file from a snippet (`source`), pick out line
   numbers by confidence (`lines`), and run both passes the way the runner
   does (`run`).

`src/checks/raw_html_tags.rs` is a worked example.

## Additional links

See the [Guide for writing checks in rust](docs/guides/writing-checks-in-rust.md)
