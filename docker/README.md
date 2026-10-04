# Docker

One single-stage image, used everywhere. It holds the app, the build
environment that produced it, and the scripts that rebuild it in place. A
container built from it can follow a git branch and rebuild itself on every
commit, which is what makes it useful for prototypes and demos. See
[the Prototypes pattern](../docs/patterns/prototypes.md).

## What the single stage buys

| | typical multi-stage image | this one |
|---|---|---|
| Build tools at runtime | stripped | kept (mix, hex, rebar, git, compiler) |
| Rebuild in place | no | yes, `/app/bin/rebuild.sh` |
| PID 1 | the release | `tini`, then `start-wrapper.sh`, then the release |
| Releases on disk | one | `/app/releases/<n>`, with `/app/current` pointing at the live one |

## Running locally

```sh
bin/docker start   # build the image and run the container
bin/docker shell   # open a shell in the running container
bin/docker stop    # stop it
bin/docker build   # build only
```

Then open `http://localhost:4000`.

On the first `start`, `bin/docker` writes `docker/local.env` (gitignored)
with a fresh `SECRET_KEY_BASE` and `PHX_HOST=localhost`, so the container is
browsable on localhost with no other setup. Delete the file to regenerate it.

The image and container are named after the `app` in `mix.exs`, so the
script needs no edits in another project.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `SECRET_KEY_BASE` | none, required | Signs cookies. `bin/docker` generates one. |
| `PHX_HOST` | `example.com` | The endpoint host. LiveView rejects browser connections from any other host, so a local container sets `localhost`. |
| `PORT` | `4000` | Host and container port. |
| `DATABASE_PATH` | `/app/data/app.db` | Where the SQLite database lives, set in the `Dockerfile`. Mount a volume at `/app/data` to keep it across containers. An app on Postgres sets `DATABASE_URL` instead. |
| `GIT_REPO_URL`, `GIT_BRANCH` | unset | Watch this branch and rebuild on new commits. Both are needed. |
| `GIT_TOKEN` | unset | A GitHub token, for a private repository. |
| `GIT_POLL_INTERVAL` | `5` | Seconds between fetches. |
| `GIT_REPO_SUBDIR` | unset | The app's path inside a monorepo. |

`PORT` and the `GIT_*` variables are read from your shell by `bin/docker` and
passed through when set.

## Database

The app runs pending migrations when it starts: a generated Phoenix app
supervises `Ecto.Migrator` in `application.ex` and only skips it outside a
release. On the first boot that creates the database file and its tables. A
rebuilt release that adds a migration runs it on its first start. Nothing
seeds data and nothing drops the database.

## Layout inside the container

```
/app/current                symlink to the live release under /app/releases/<n>
/app/bin/start-wrapper.sh   PID 1's child: server loop, health check, rollback
/app/bin/healthcheck.sh     smoke test run after every server start
/app/bin/rebuild.sh         build a new release and point /app/current at it
/app/bin/git-poll.sh        watch a branch and rebuild on new commits
/app/data/                  the database
```

The rest of `/app` is the source tree the image was built from, plus `deps`
and `_build`, which is what makes a rebuild possible.

## Lifecycle

1. `tini` (PID 1) runs `start-wrapper.sh`.
2. The wrapper starts `git-poll.sh` when `GIT_REPO_URL` and `GIT_BRANCH` are
   set.
3. It starts `/app/current/bin/server`. The app runs its migrations as it
   boots. The wrapper runs `healthcheck.sh`.
4. A crash or failing health check counts as a failure. After 3 failures in
   a row for the same release, the wrapper rolls back to the previous
   numbered release.
5. `rebuild.sh` builds `/app/releases/<n+1>`, points `/app/current` at it
   and sends SIGUSR1 to the wrapper, which restarts only the server child.
   The 3 newest releases are kept.

## Rebuilding inside the container

```sh
bin/docker shell
# edit code under /app, then:
/app/bin/rebuild.sh
```

## Watching a branch

Set `GIT_REPO_URL` and `GIT_BRANCH`, plus `GIT_TOKEN` for a private
repository, and the container fetches that branch every few seconds. When
the tip moves, it writes the changed files to `/app` and runs `rebuild.sh`.

```sh
GIT_REPO_URL=https://github.com/org/repo \
GIT_BRANCH=your-feature-branch \
GIT_TOKEN=github_pat_xxxxx \
bin/docker start
```

Check out and pull that branch locally first. The image is built from your
working tree, but the poller takes the branch's tip at container start as its
baseline and only rewrites files that change after it. A working tree that
differs from the branch would leave the container running a mix of both.
`bin/docker start` warns when that is the case.

### Generating a GIT_TOKEN

A fine-grained personal access token scoped to the one repository is enough.
The poller only reads repository contents.

1. GitHub, profile avatar, **Settings**
2. **Developer settings** (bottom of the left sidebar)
3. **Personal access tokens**, **Fine-grained tokens**, **Generate new token**
4. Fill in:
   - Token name: for example `git-poll`
   - Expiration: 30 or 90 days
   - Resource owner: the organization that owns the repository
   - Repository access: **Only select repositories**, then the one repository
   - Permissions, Repository permissions, **Contents: Read-only** and nothing else
5. **Generate token** and copy the value

The token is embedded as `https://x-access-token:<token>@github.com/...`,
the standard way to authenticate HTTPS git operations with a GitHub token.
