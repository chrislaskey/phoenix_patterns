#!/bin/sh
# rebuild.sh: build a new release from the code in /app and switch to it.
#
# Run it inside the container after changing code under /app, or let
# git-poll.sh run it after a new commit. It compiles the app and assets,
# builds /app/releases/<n+1>, points /app/current at it, and sends SIGUSR1 to
# start-wrapper.sh, which restarts only the server child. The container keeps
# running. The server is down for the moment between the old process
# stopping and the new one starting.
#
# Usage, inside the container:
#   /app/bin/rebuild.sh

set -e

# mix must build in the environment the image was built with, even when a
# deployment overrides MIX_ENV for the running app.
export MIX_ENV=prod

APP_DIR="/app"
RELEASES_DIR="$APP_DIR/releases"
CURRENT_LINK="$APP_DIR/current"
WRAPPER_PID_FILE="/tmp/wrapper.pid"

# Releases kept on disk after a rebuild, the newest ones.
KEEP=3

# ---------------------------------------------------------------------------
# Step 1: the next release number
# ---------------------------------------------------------------------------

LAST_VERSION=0
for dir in "$RELEASES_DIR"/*/; do
  name=$(basename "$dir")
  if echo "$name" | grep -qE '^[0-9]+$'; then
    if [ "$name" -gt "$LAST_VERSION" ]; then
      LAST_VERSION="$name"
    fi
  fi
done

NEXT_VERSION=$((LAST_VERSION + 1))
NEXT_RELEASE_DIR="$RELEASES_DIR/$NEXT_VERSION"

echo "[rebuild] Building release version $NEXT_VERSION into $NEXT_RELEASE_DIR..."

# ---------------------------------------------------------------------------
# Step 2: compile the app and assets, build the release
# ---------------------------------------------------------------------------

cd "$APP_DIR"

# Compile before the assets: app.css imports the colocated CSS the compiler
# writes.
echo "[rebuild] Compiling application..."
mix compile

echo "[rebuild] Compiling assets..."
mix assets.deploy

echo "[rebuild] Building release..."
mix release --overwrite --path "$NEXT_RELEASE_DIR"

echo "[rebuild] Release built successfully."

# ---------------------------------------------------------------------------
# Step 3: point /app/current at the new release
# ---------------------------------------------------------------------------

echo "[rebuild] Swapping symlink: $CURRENT_LINK -> $NEXT_RELEASE_DIR"

# ln -sfn replaces the symlink target in one step.
ln -sfn "$NEXT_RELEASE_DIR" "$CURRENT_LINK"

echo "[rebuild] Symlink updated."

# ---------------------------------------------------------------------------
# Step 4: tell the wrapper to restart the server child
# ---------------------------------------------------------------------------

if [ ! -f "$WRAPPER_PID_FILE" ]; then
  echo "[rebuild] ERROR: Wrapper PID file not found at $WRAPPER_PID_FILE."
  echo "[rebuild] Is start-wrapper.sh running? Start the container normally and try again."
  exit 1
fi

WRAPPER_PID=$(cat "$WRAPPER_PID_FILE")

echo "[rebuild] Sending SIGUSR1 to wrapper (pid $WRAPPER_PID) to restart server..."
kill -USR1 "$WRAPPER_PID"

echo "[rebuild] Done. The server will restart momentarily."
echo "[rebuild] To roll back, run: ln -sfn $RELEASES_DIR/$LAST_VERSION $CURRENT_LINK && kill -USR1 $WRAPPER_PID"

# ---------------------------------------------------------------------------
# Step 5: remove old releases, keeping the newest KEEP
# ---------------------------------------------------------------------------

# Numbered release directories, oldest first. sort -n orders by value, so 2
# comes before 10.
SORTED=""
for dir in "$RELEASES_DIR"/*/; do
  name=$(basename "$dir")
  if echo "$name" | grep -qE '^[0-9]+$'; then
    SORTED="$SORTED $name"
  fi
done
SORTED=$(echo "$SORTED" | tr ' ' '\n' | grep -v '^$' | sort -n)

# Count only lines that hold a number, so an empty list counts as 0 and not 1.
TOTAL=$(echo "$SORTED" | grep -c '^[0-9]' || true)

if [ "$TOTAL" -gt "$KEEP" ]; then
  DELETE_COUNT=$((TOTAL - KEEP))
  TO_DELETE=$(echo "$SORTED" | head -n "$DELETE_COUNT")
  for version in $TO_DELETE; do
    echo "[rebuild] Removing old release: $RELEASES_DIR/$version"
    # ${name:?} stops the script if either variable is empty, so this can
    # never remove anything but a numbered release directory.
    rm -rf "${RELEASES_DIR:?}/${version:?}"
  done
fi
