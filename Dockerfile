# One image for local containers, previews, demos and production. It is a
# single stage, so the tools that built the app (mix, hex, rebar, git, the C
# compiler) stay in the image and the app can be rebuilt in place:
# /app/bin/rebuild.sh compiles a new release and swaps it in without
# restarting the container. See docker/README.md.
#
# Base image tags: https://hub.docker.com/r/hexpm/elixir/tags
# Keep the versions in step with .tool-versions.

ARG ELIXIR_VERSION=1.19.4
ARG OTP_VERSION=28.1.1
ARG DEBIAN_VERSION=trixie-20260610-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE}

# Build and runtime packages in one layer. curl is for healthcheck.sh. tini is
# a small init that forwards signals and reaps finished child processes, see
# https://github.com/krallin/tini
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates openssl locales tini \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Hex, rebar and the home directory live under /app, so the unprivileged user
# that runs the container can also run mix for in-container rebuilds.
ENV HOME=/app
ENV MIX_HOME=/app/.mix
ENV HEX_HOME=/app/.hex

RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Installs the tailwind and esbuild binaries, which rebuild.sh needs too.
RUN mix assets.setup

COPY priv priv
COPY lib lib

RUN mix compile

COPY assets assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel

# The first release is /app/releases/1 and /app/current points at it. The
# server is always started through /app/current, so rebuild.sh can build
# /app/releases/2 and swap the symlink. Each release directory is a full
# release, so a bad one can be rolled back by pointing the symlink back.
RUN mix release --path /app/releases/1 \
  && ln -s /app/releases/1 /app/current

# The scripts that run the container, see docker/README.md.
COPY docker/start-wrapper.sh docker/rebuild.sh docker/healthcheck.sh docker/git-poll.sh /app/bin/
RUN chmod +x /app/bin/*.sh

# The app stores its SQLite database here. Mount a volume at /app/data to
# keep it across containers. An app on Postgres sets DATABASE_URL instead.
ENV DATABASE_PATH=/app/data/app.db
RUN mkdir -p /app/data

# The runtime user owns /app so it can fetch dependencies, compile, write a
# new release and write the database.
RUN chown -R nobody /app

USER nobody

# tini is PID 1. start-wrapper.sh is its child and runs the server in a loop,
# so the container stays up across rebuilds and restarts.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/app/bin/start-wrapper.sh"]
