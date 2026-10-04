# Prototypes

Make it easy and fast to generate prototypes in the same application. Do not merge them.

## Overview

Prototypes are enormously helpful and there are many tools to build them outside
of the app code itself. While these work, in practice the distance from in-app
code causes a variety of friction points:

- Demo environments make assumptions about in-app code. This can lead to
solutions that require large changes rather than hooking into existing patterns
with minimal additional code in both UI, backend, and data layers.
- UI/UX drift and false approximations of existing UI. This leads to
implementation confusion - is the button padding wider because it's a conscious
choice and part of the requirements? Or is it just a generation mistake while
simulating the existing UI?
- Simulated backends and data layers. Most prototypes only go as deep as the UX flow
and simulate backends and data layers. Does this reuse existing patterns or
implement new ones?
- Prototype graveyards. After prototypes are built, they often hang around
in the third-party tool. Which of these are complete, which are still outstanding?

This pattern is about moving prototypes to be done in-app. An in-app prototype
can match all of the functionality of third-party tools while also solving:

- UI/UX alignment. Using real component library vs. a mock one in prototypes.
- Gap identification. Clearly shows what is reusable, and what still needs to
be built before the prototype is turned into production code.

Add in Docker and automatic code watching, and now these in-app prototypes can also provide:

- Demoable environments that can be viewed by others
- Multi-user collaborative real-time development (using code watchers/automatic rebuild tooling in Docker)
- Easy automation for code review (screenshots, videos)

Additional points:

- Do not allow prototypes to be merged. Have CI checks prevent this. Instead
make them easily deployable. Can be validated against, even bringing in the
prototype code into the PR while it's being built. But when it's delivered,
only the feature exists and not the prototype.

## Implementation

A prototype is a branch. One Docker image runs it and follows it: push a
commit and the running container rebuilds itself.

The image is a single stage, so the tools that built the app stay in it:
`mix`, `git` and the compiler. That is what makes a rebuild inside the
container possible. The same image serves a local container, a shared demo
and production, so a prototype runs exactly what production runs.

```sh
bin/docker start                      # build the image, run it on localhost:4000
GIT_REPO_URL=https://github.com/org/repo GIT_BRANCH=my-prototype bin/docker start
```

With the two `GIT_*` variables set the container watches the branch:

1. Every 5 seconds it fetches the branch tip.
2. When the tip moved, it writes the files that changed since the container
   started onto `/app`. The image was built from a working tree, so there is
   no checkout to update; the files are written one by one.
3. It builds a new release into `/app/releases/<n+1>` and points the
   `/app/current` symlink at it.
4. It restarts only the server. The container, and the shell anyone has open
   in it, keep running.
5. A release that crashes or fails its health check three times in a row is
   rolled back to the previous one. The branch stays broken until the next
   push, but the demo stays up.

Everyone looking at the demo sees the new commit as soon as the rebuild
finishes, which is what makes a prototype a shared, live thing instead of a
screenshot. The
app runs pending migrations as it boots, as every generated Phoenix app does
in a release, so a prototype that adds a table works without a step by hand.
Nothing seeds data.

The watching is opt-in. Without the `GIT_*` variables the container is a
plain release that can be rebuilt by hand from a shell inside it. See
[docker/README.md](../../docker/README.md) for the variables, the layout
inside the container and how to create a token for a private repository.

**Key files**

- [How the container works, and watching a branch](../../docker/README.md)
- [Dockerfile](../../Dockerfile)
- [Local wrapper: build, start, shell, stop](../../bin/docker)
- [Server loop, health check and rollback](../../docker/start-wrapper.sh)
- [Rebuild in place](../../docker/rebuild.sh)
- [Watch a branch](../../docker/git-poll.sh)
- [Health check](../../docker/healthcheck.sh)
- [Migrations run on boot](../../lib/example/application.ex)

## Adopting this pattern

1. Run `mix phx.gen.release --docker` if the project has no release files
   yet. It writes `lib/<app>/release.ex`, `rel/overlays/bin/server` and
   `rel/overlays/bin/migrate`, a `Dockerfile` and a `.dockerignore`.
2. Replace the generated `Dockerfile` with this one. Set `DATABASE_PATH` for
   SQLite as here, or remove it and pass `DATABASE_URL` for Postgres. Check
   the Elixir and Erlang versions at the top against `.tool-versions`.
3. Copy `docker/` and `bin/docker`. Nothing in them is named after the
   application: `bin/docker` reads the app name from `mix.exs`.
4. Check that `application.ex` supervises `Ecto.Migrator`, as a generated
   Phoenix 1.8 app does. An older app adds it, or calls `bin/migrate` from
   `rel/overlays/bin/server` before starting, so the database is created on
   first boot and migrations run on every start.
5. Add `/docker/*.env` to `.gitignore` and `.dockerignore`, so the generated
   local secrets are never committed or built into the image.
6. Run `bin/docker start` and open `http://localhost:4000`. Then start it
   again with `GIT_REPO_URL` and `GIT_BRANCH` set, push a commit to that
   branch, and watch the container log rebuild.
