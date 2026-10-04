#!/bin/sh
# start-wrapper.sh: run the release server in a loop, check its health, and
# roll back a release that keeps failing.
#
# tini (PID 1) runs this script. The server is always started from the
# /app/current symlink, so a new release is deployed by pointing the symlink
# at it and restarting only the server child. The container keeps running.
#
# Failure and rollback:
#   healthcheck.sh runs after every server start. A failure is a server
#   process that exits on its own, or a health check that does not pass.
#   After FAILURE_THRESHOLD failures in a row for the same release, the
#   wrapper points /app/current at the previous numbered release and starts
#   it. With no previous release it keeps retrying the current one.
#
# Signals, forwarded by tini:
#   SIGTERM  stop the server and exit, which stops the container.
#   SIGUSR1  restart the server child only. rebuild.sh sends this after it
#            has pointed /app/current at the release it just built.
#
# Git polling starts when GIT_REPO_URL and GIT_BRANCH are set, see
# git-poll.sh.

set -e

WRAPPER_PID_FILE="/tmp/wrapper.pid"
SERVER_PID_FILE="/tmp/server.pid"
HEALTHCHECK_RESULT_FILE="/tmp/healthcheck.result"
RELEASES_DIR="/app/releases"
CURRENT_LINK="/app/current"
HEALTHCHECK="/app/bin/healthcheck.sh"
GIT_POLL_SCRIPT="/app/bin/git-poll.sh"
GIT_POLL_PID=""

# Failures in a row before rolling back to the previous release.
FAILURE_THRESHOLD=3

echo $$ > "$WRAPPER_PID_FILE"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

current_release_version() {
  # The name of the directory /app/current points at, a number.
  basename "$(readlink "$CURRENT_LINK")"
}

previous_release_version() {
  # The highest numbered release older than the current one, or nothing.
  current=$(current_release_version)
  prev=0
  for dir in "$RELEASES_DIR"/*/; do
    name=$(basename "$dir")
    if echo "$name" | grep -qE '^[0-9]+$'; then
      if [ "$name" -lt "$current" ] && [ "$name" -gt "$prev" ]; then
        prev="$name"
      fi
    fi
  done
  [ "$prev" -gt 0 ] && echo "$prev" || echo ""
}

stop_server() {
  if [ -f "$SERVER_PID_FILE" ]; then
    SERVER_PID=$(cat "$SERVER_PID_FILE")
    echo "[wrapper] Stopping server (pid $SERVER_PID)..."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    rm -f "$SERVER_PID_FILE"
  fi
}

rollback() {
  prev=$(previous_release_version)
  if [ -z "$prev" ]; then
    echo "[wrapper] ROLLBACK SKIPPED: no previous release found. Retrying current release."
    return 1
  fi
  echo "[wrapper] *** ROLLING BACK to release $prev ***"
  ln -sfn "$RELEASES_DIR/$prev" "$CURRENT_LINK"
  echo "[wrapper] Symlink updated: $CURRENT_LINK -> $RELEASES_DIR/$prev"
  return 0
}

stop_git_poll() {
  if [ -n "$GIT_POLL_PID" ]; then
    echo "[wrapper] Stopping git-poll (pid $GIT_POLL_PID)..."
    kill "$GIT_POLL_PID" 2>/dev/null || true
    wait "$GIT_POLL_PID" 2>/dev/null || true
    GIT_POLL_PID=""
  fi
}

# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

cleanup() {
  echo "[wrapper] Shutdown signal received."
  stop_git_poll
  stop_server
  echo "[wrapper] Exiting."
  exit 0
}

# rebuild.sh sends SIGUSR1 after pointing /app/current at a new release. The
# failure counter starts over so the new release gets a clean slate. The
# main loop then starts a new server child.
restart_server() {
  echo "[wrapper] Restart signal received (new release)."
  stop_server
  CONSECUTIVE_FAILURES=0
  TRACKED_VERSION=$(current_release_version)
  echo "[wrapper] Failure counter reset for release $TRACKED_VERSION."
}

trap cleanup TERM INT
trap restart_server USR1

# ---------------------------------------------------------------------------
# Git polling, when a branch to watch is configured
# ---------------------------------------------------------------------------

if [ -n "${GIT_REPO_URL:-}" ] && [ -n "${GIT_BRANCH:-}" ]; then
  echo "[wrapper] Git polling configured: branch '$GIT_BRANCH' from $GIT_REPO_URL"
  "$GIT_POLL_SCRIPT" &
  GIT_POLL_PID=$!
  echo "[wrapper] git-poll started (pid $GIT_POLL_PID)."
else
  echo "[wrapper] Git polling not configured (set GIT_REPO_URL and GIT_BRANCH to enable)."
fi

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

CONSECUTIVE_FAILURES=0
TRACKED_VERSION=$(current_release_version)

echo "[wrapper] Starting. Current release: $TRACKED_VERSION (failure threshold: $FAILURE_THRESHOLD)"

while true; do
  RELEASE_BIN="$CURRENT_LINK/bin/server"
  LOOP_VERSION=$(current_release_version)

  # The symlink changed outside this script, for example a rollback by hand.
  # The newly active release gets a fresh failure counter.
  if [ "$LOOP_VERSION" != "$TRACKED_VERSION" ]; then
    echo "[wrapper] Release changed to $LOOP_VERSION. Resetting failure counter."
    CONSECUTIVE_FAILURES=0
    TRACKED_VERSION="$LOOP_VERSION"
  fi

  echo "[wrapper] Starting server (release $TRACKED_VERSION, failure count: $CONSECUTIVE_FAILURES)..."
  "$RELEASE_BIN" &
  SERVER_PID=$!
  echo "$SERVER_PID" > "$SERVER_PID_FILE"
  echo "[wrapper] Server started (pid $SERVER_PID)."

  # The health check runs in the background. When it fails it kills the
  # server, so the wait below returns. Otherwise a running but unhealthy
  # server would block the wrapper forever.
  rm -f "$HEALTHCHECK_RESULT_FILE"
  (
    set +e
    sh "$HEALTHCHECK"
    HC_EXIT=$?
    echo "$HC_EXIT" > "$HEALTHCHECK_RESULT_FILE"
    if [ "$HC_EXIT" -ne 0 ] && [ -f "$SERVER_PID_FILE" ]; then
      echo "[wrapper] Health check failed. Stopping server to trigger restart."
      kill "$(cat "$SERVER_PID_FILE")" 2>/dev/null || true
    fi
  ) &
  HEALTHCHECK_PID=$!

  # Returns when the server exits, when a signal handler stops it, or when
  # the health check kills it.
  wait "$SERVER_PID" || true
  SERVER_EXIT=$?

  # The server may have exited before the health check finished.
  kill "$HEALTHCHECK_PID" 2>/dev/null || true
  wait "$HEALTHCHECK_PID" 2>/dev/null || true

  rm -f "$SERVER_PID_FILE"

  HEALTHCHECK_EXIT=0
  if [ -f "$HEALTHCHECK_RESULT_FILE" ]; then
    HEALTHCHECK_EXIT=$(cat "$HEALTHCHECK_RESULT_FILE")
  else
    # No result: the server crashed before the health check could finish.
    HEALTHCHECK_EXIT=1
  fi

  if [ "$SERVER_EXIT" -ne 0 ] || [ "$HEALTHCHECK_EXIT" -ne 0 ]; then
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    echo "[wrapper] Failure detected (crash=$SERVER_EXIT, healthcheck=$HEALTHCHECK_EXIT). Consecutive failures: $CONSECUTIVE_FAILURES/$FAILURE_THRESHOLD"

    if [ "$CONSECUTIVE_FAILURES" -ge "$FAILURE_THRESHOLD" ]; then
      echo "[wrapper] Failure threshold reached."
      if rollback; then
        CONSECUTIVE_FAILURES=0
        TRACKED_VERSION=$(current_release_version)
        echo "[wrapper] Now running release $TRACKED_VERSION."
      fi
    fi
  else
    if [ "$CONSECUTIVE_FAILURES" -ne 0 ]; then
      echo "[wrapper] Server healthy. Resetting failure counter."
      CONSECUTIVE_FAILURES=0
    fi
  fi

  echo "[wrapper] Restarting in 1s..."
  sleep 1
done
