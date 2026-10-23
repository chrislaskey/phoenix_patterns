# Standalone binary

The app can be built into one executable file per platform with
[Burrito](https://github.com/burrito-elixir/burrito). The file holds the
compiled app, the Erlang runtime, the CSS and JS, and the native code for
SQLite and bcrypt. It runs on macOS or Linux with nothing else installed:
no Erlang, no Elixir, no Homebrew packages.

The main use is a desktop app, written in Swift, Rust or similar, that ships
the binary inside its bundle and starts it as a background server on
`localhost`. Regular deployments keep using the Docker image.

## Building

Burrito needs Zig 0.16.0 exactly (pinned in `.tool-versions`, install with
`asdf install`) and `xz` (`brew install xz`).

```sh
export MIX_ENV=prod
mix deps.get --only prod
mix assets.setup
mix assets.deploy
mix release app_standalone
mix phx.digest.clean --all   # remove the digested files assets.deploy wrote
```

This writes one file per target to `burrito_out/`:

| File                               | Size  | Runs on                       |
| ---------------------------------- | ----- | ----------------------------- |
| `app_standalone_macos_silicon`     | 12 MB | macOS, Apple Silicon          |
| `app_standalone_macos_intel`       | 14 MB | macOS, Intel                  |
| `app_standalone_linux`             | 21 MB | Linux x86_64, any libc        |
| `app_standalone_linux_arm`         | 20 MB | Linux arm64, any libc         |

All four build from one Mac. To build a single target, set
`BURRITO_TARGET=linux_arm`. Burrito 1.6.0 only takes one target here, not a
comma separated list as its README says.

`mix release` with no name still builds the regular `app` release for the
Docker image, and does not need Zig.

## Running

```sh
DATABASE_PATH=~/data/app.db \
SECRET_KEY_BASE=$(mix phx.gen.secret) \
PORT=4000 \
./burrito_out/app_standalone_macos_silicon --no-halt
```

- **Always pass `--no-halt`, and no other arguments.** See known issues below.
- The variables can also go in a `.env` file in the directory the binary is
  started from. `config/runtime.exs` reads it with Dotenvy.
- When running from the binary, `config/runtime.exs` turns the server on,
  listens on `127.0.0.1` only, and builds `http://localhost:PORT` URLs.
  `PHX_SERVER` is not needed.
- Migrations run on every start.

The first start unpacks the payload, about 55 MB on macOS and 90 MB on
Linux, into:

- macOS: `~/Library/Application Support/.burrito/app_standalone_erts-16.1.1_0.1.0`
- Linux: `~/.local/share/.burrito/app_standalone_erts-16.1.1_0.1.0`

Later starts skip unpacking and are ready in about 3 seconds.
`./app_standalone_... maintenance uninstall` deletes the unpacked copy.

## Starting it from a desktop app

1. Start the binary with `--no-halt`, and pass settings as environment
   variables, not a `.env` file. An app opened from the macOS Finder starts
   its child processes in `/`, so a `.env` in the working directory is never
   found.
   - `DATABASE_PATH`: in the desktop app's own data directory, not in the
     unpacked payload, which is deleted on uninstall.
   - `SECRET_KEY_BASE`: generate it once and store it, for example in the
     macOS Keychain. A new one on every launch logs the user out each time.
   - `PORT`: ask the OS for a free port (bind to port 0, read the port, close
     the socket) and pass that, so a second copy or another app on 4000
     can't block startup.
   - `ERL_CRASH_DUMP`: a path in the desktop app's log directory. By default
     the dump goes to the working directory, which is `/` from the Finder
     and can't be written.
2. Start it in its own process group, set `EXIT_ON_STDIN_CLOSE=1`, and keep a
   pipe open to the binary's standard input. When the desktop app quits or
   crashes, the operating system closes the pipe and `App.StdinWatcher`
   stops the server. Without this, a crash leaves the server running in the
   background, holding its port.
3. Wait for the port to accept connections before loading
   `http://localhost:PORT` in the web view. Stop waiting as soon as the
   process exits, and give up after a deadline, so a server that fails to
   start shows an error instead of a spinner.
4. Send the server's output to the desktop app's log. An app opened from
   the Finder has nowhere to print it.
5. To stop the server on purpose, close the pipe, or send `SIGTERM` to the
   BEAM process (the binary's child), then kill the process group after a
   few seconds. Sending `SIGTERM` only to the binary's own process ID stops
   the outer wrapper and leaves the server running.

## What Burrito adds over a regular release

A regular `mix release` already includes the Erlang runtime, so Erlang and
Elixir don't need to be installed. It falls short in three ways:

| | Regular release | Burrito binary |
| --- | --- | --- |
| Shape | A directory of about 35 MB with start scripts | One file |
| Platforms | Only the OS and CPU it was built on | Builds macOS and Linux, Intel and ARM, from one machine |
| System libraries | Uses the build machine's. On a Mac with Erlang from asdf, `crypto` needs Homebrew's `openssl@3`, so it fails on a Mac without it | macOS: OpenSSL is built in, needs only system libraries. Linux: brings its own libc, so it runs on Debian (glibc) and Alpine (musl) alike |
| Native code | Built once for the build machine | SQLite and bcrypt rebuilt for each target with Zig |

To skip Burrito, build a regular release on each target machine, or in a
container per Linux target, with an Erlang built against static OpenSSL,
and ship the directory inside the desktop app's bundle. That gives up the
single file and building everything from one machine.

## Tested

Each check started the binary with a fresh database and confirmed that
migrations ran, the home page returned 200, the digested CSS and JS were
served, and a login form POST worked, which reads the database and runs
bcrypt.

| Binary | Where | Result |
| --- | --- | --- |
| `macos_silicon` | macOS 26, Apple Silicon | Pass |
| `macos_intel` | Same Mac, under Rosetta | Pass |
| `linux_arm` | `debian:trixie-slim`, no Erlang | Pass |
| `linux_arm` | `alpine:3.22` (musl), no Erlang | Pass |
| `linux` | `debian:trixie-slim` x86_64, emulated | Pass |

Also checked: settings from a `.env` file alone, the server stopping when
the process holding its standard input was killed with `SIGKILL`, and a
graceful stop on `SIGTERM` to the server process.

## Known issues

Burrito calls itself experimental. As of October 2026, none of these fixes
are merged:

- **The server exits right after it starts** unless `--no-halt` is passed
  ([#229](https://github.com/burrito-elixir/burrito/issues/229), fix in
  [PR #230](https://github.com/burrito-elixir/burrito/pull/230)). Burrito
  1.6.0 hands the app's arguments to Elixir's command line, which treats
  them as a script to run and then halts. `--no-halt` keeps it running. Any
  other argument is read as a script path. Once #230 is merged, `--no-halt`
  becomes an ordinary app argument and is ignored.
- **Burrito 1.5.0 does not build on macOS 26.** Its Zig 0.15.2 can't link
  against the macOS 26 SDK (reported in #229), which is why this uses 1.6.0
  and Zig 0.16.0.
- **The release starts in interactive mode instead of embedded mode**
  ([#233](https://github.com/burrito-elixir/burrito/issues/233), fix in
  [PR #236](https://github.com/burrito-elixir/burrito/pull/236)). Modules
  load the first time they are used, so `function_exported?/3` can return
  `false` for a module that hasn't been used yet. No effect seen in this app.
- **A rebuilt binary can run old code.** The unpack directory is named after
  the app version and Erlang version only. If a directory with that name
  already exists, the binary uses it as is. Bump `version` in `mix.exs` for
  every build that ships, and run `maintenance uninstall` between local test
  builds.
- **Different apps built from this project share one unpack directory.**
  The directory is named after the release, and every copy of this project
  calls it `app_standalone`. Two products on one machine at the same
  version would run each other's code. Rename the release after the product
  in `mix.exs` before shipping.
- **macOS Intel and Apple Silicon binaries share one unpack directory.**
  Running both on one Mac, for example under Rosetta, makes the second one
  load the first one's native code and fail.
- **Linux needs a `/tmp` that allows running programs.** The wrapper writes
  its libc loader to `/tmp/libc-musl-<hash>` on every start.
- **`SIGTERM` to the wrapper does not reach the server.** See the desktop
  app steps above.
- **`database is locked` errors on the very first start.** Database
  connections race the migration that creates the file. They retry, and the
  server starts normally.
- **The release cookie is visible in `ps` output.** The app is not
  clustered, so it isn't used.

## Still to do

- Sign and notarize the macOS binaries. Gatekeeper blocks an unsigned
  binary that was downloaded.
- Try the steps above from a real desktop app. They follow
  [ex_tauri](https://github.com/filipecabaco/ex_tauri), which embeds
  Burrito binaries in Tauri apps, but closing standard input as the stop
  signal is untested outside a shell script.
- Restart the server when it exits while the window is still open.
- Pin a fork with PRs #230 and #236 applied if they stay unmerged.
- Bump `version` automatically when building the binary.
