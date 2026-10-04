#!/bin/sh
# git-poll.sh: watch a branch and rebuild the app when it changes
#
# start-wrapper.sh runs this in the background. Every GIT_POLL_INTERVAL
# seconds it fetches the branch. When the tip moved, it writes the files that
# changed since the container started onto /app and runs rebuild.sh, which
# builds a new release and swaps it in.
#
# Environment variables:
#   GIT_REPO_URL       Repository HTTPS URL. Required for polling to start.
#   GIT_BRANCH         Branch to watch. Required for polling to start.
#   GIT_POLL_INTERVAL  Seconds between polls (default: 5).
#   GIT_TOKEN          GitHub access token for a private repository. A
#                      fine-grained token with Contents: read is enough.
#   GIT_REPO_SUBDIR    Path of the app inside the repository, for a
#                      monorepo. Unset when the app is the repository root.
#
# Without GIT_REPO_URL and GIT_BRANCH the script exits at once and the
# container runs as if it did not exist.
#
# The image was built from a working tree, not a clone, so there is no .git
# directory. The script creates an empty repository in /app and fetches the
# branch tip, which becomes the baseline. From then on it tracks the set of
# paths that changed since the baseline and writes each one as it is in the
# latest commit, or removes it when the commit deleted it. That keeps every
# file the image was built from and still handles a later commit that
# reverts an earlier one. Nothing is checked out, rebased or reset.

# mix must build in the environment the image was built with, even when a
# deployment overrides MIX_ENV for the running app.
export MIX_ENV=prod

APP_DIR="/app"
REBUILD_SCRIPT="$APP_DIR/bin/rebuild.sh"
REBUILD_LOCK="/tmp/git-poll-rebuild.lock"
RECONCILE_PATHS_FILE="/tmp/git-poll-reconcile-paths.txt"
GIT_POLL_INTERVAL="${GIT_POLL_INTERVAL:-5}"
GIT_REPO_SUBDIR="${GIT_REPO_SUBDIR:-}"

# ---------------------------------------------------------------------------
# Exit early when not configured
# ---------------------------------------------------------------------------

if [ -z "${GIT_REPO_URL:-}" ] || [ -z "${GIT_BRANCH:-}" ]; then
  echo "[git-poll] GIT_REPO_URL or GIT_BRANCH not set. Polling disabled."
  exit 0
fi

# ---------------------------------------------------------------------------
# The remote URL, with the token embedded for a private repository. This is
# the standard way to authenticate HTTPS git operations with a GitHub token.
# ---------------------------------------------------------------------------

if [ -n "${GIT_TOKEN:-}" ]; then
  REMOTE_URL=$(echo "$GIT_REPO_URL" | sed "s|https://|https://x-access-token:${GIT_TOKEN}@|")
  echo "[git-poll] Using authenticated URL (token provided)."
else
  REMOTE_URL="$GIT_REPO_URL"
  echo "[git-poll] Using public URL (no token)."
fi

# ---------------------------------------------------------------------------
# An empty repository in /app, with the branch tip as the baseline
# ---------------------------------------------------------------------------

cd "$APP_DIR"

if [ ! -d ".git" ]; then
  echo "[git-poll] Initializing git repository in $APP_DIR..."
  git init -q
  git remote add origin "$REMOTE_URL"
else
  git remote set-url origin "$REMOTE_URL"
fi

git config advice.detachedHead false 2>/dev/null || true

echo "[git-poll] Fetching latest commit on branch '$GIT_BRANCH'..."
if ! git fetch --depth=1 origin "$GIT_BRANCH" 2>&1; then
  echo "[git-poll] ERROR: Initial fetch failed."
  echo "[git-poll] Check that GIT_REPO_URL, GIT_BRANCH, and GIT_TOKEN (if private) are correct."
  exit 1
fi

CURRENT_SHA=$(git rev-parse FETCH_HEAD)
echo "[git-poll] Baseline commit: ${CURRENT_SHA} on ${GIT_BRANCH}"
echo "[git-poll] Polling every ${GIT_POLL_INTERVAL}s for new commits..."
rm -f "$RECONCILE_PATHS_FILE"

# The subdirectory without leading or trailing slashes.
REMOTE_PATH_PREFIX=$(echo "$GIT_REPO_SUBDIR" | sed 's#^/*##; s#/*$##')

if [ -n "$REMOTE_PATH_PREFIX" ]; then
  echo "[git-poll] Using repo subdir prefix: '${REMOTE_PATH_PREFIX}/'"
else
  echo "[git-poll] Repo root matches /app (no path prefix)."
fi

# ---------------------------------------------------------------------------
# Mapping repository paths to paths under /app
# ---------------------------------------------------------------------------

to_local_path() {
  REMOTE_PATH="$1"

  if [ -z "$REMOTE_PATH_PREFIX" ]; then
    printf "%s\n" "$REMOTE_PATH"
    return 0
  fi

  case "$REMOTE_PATH" in
    "$REMOTE_PATH_PREFIX"/*)
      printf "%s\n" "${REMOTE_PATH#"$REMOTE_PATH_PREFIX"/}"
      ;;
    *)
      # Outside the app's subdirectory, ignore it.
      printf "%s\n" ""
      ;;
  esac
  return 0
}

# Adds the paths that changed between two commits to the tracked set.
append_changed_paths() {
  FROM_SHA="$1"
  TO_SHA="$2"
  CHANGED_LIST="/tmp/git-poll-changed-paths.$$"
  MERGED_LIST="/tmp/git-poll-merged-paths.$$"

  # --no-renames lists a rename as a delete and an add, which keeps the
  # reconcile step simple.
  if ! git diff --name-only --no-renames "$FROM_SHA" "$TO_SHA" > "$CHANGED_LIST"; then
    echo "[git-poll] ERROR: Failed to diff ${FROM_SHA}..${TO_SHA}."
    rm -f "$CHANGED_LIST"
    return 1
  fi

  if [ ! -s "$CHANGED_LIST" ]; then
    rm -f "$CHANGED_LIST"
    return 0
  fi

  FILTERED_LIST="/tmp/git-poll-filtered-paths.$$"
  : > "$FILTERED_LIST"

  while IFS= read -r REMOTE_PATH; do
    [ -z "$REMOTE_PATH" ] && continue
    LOCAL_PATH=$(to_local_path "$REMOTE_PATH")
    [ -z "$LOCAL_PATH" ] && continue
    printf "%s\n" "$LOCAL_PATH" >> "$FILTERED_LIST"
  done < "$CHANGED_LIST"

  if [ ! -s "$FILTERED_LIST" ]; then
    rm -f "$CHANGED_LIST" "$FILTERED_LIST"
    return 0
  fi

  if [ -f "$RECONCILE_PATHS_FILE" ]; then
    cat "$RECONCILE_PATHS_FILE" "$FILTERED_LIST" | sed '/^$/d' | sort -u > "$MERGED_LIST"
    mv "$MERGED_LIST" "$RECONCILE_PATHS_FILE"
  else
    mv "$FILTERED_LIST" "$RECONCILE_PATHS_FILE"
    FILTERED_LIST=""
  fi

  rm -f "$CHANGED_LIST" "$FILTERED_LIST"
  return 0
}

# Writes every tracked path as it is in the given commit, or removes it.
reconcile_tracked_paths() {
  TO_SHA="$1"

  if [ ! -f "$RECONCILE_PATHS_FILE" ] || [ ! -s "$RECONCILE_PATHS_FILE" ]; then
    echo "[git-poll] No changed paths to reconcile."
    return 0
  fi

  PATH_COUNT=$(wc -l < "$RECONCILE_PATHS_FILE" | tr -d ' ')
  echo "[git-poll] Reconciling ${PATH_COUNT} cumulative changed path(s)..."

  FAILED=0
  while IFS= read -r PATHNAME; do
    [ -z "$PATHNAME" ] && continue

    REMOTE_PATH="$PATHNAME"
    if [ -n "$REMOTE_PATH_PREFIX" ]; then
      REMOTE_PATH="$REMOTE_PATH_PREFIX/$PATHNAME"
    fi

    # The path exists in the commit: write that version to disk.
    if git cat-file -e "${TO_SHA}:${REMOTE_PATH}" 2>/dev/null; then
      OBJ_TYPE=$(git cat-file -t "${TO_SHA}:${REMOTE_PATH}" 2>/dev/null || true)
      MODE=$(git ls-tree "$TO_SHA" -- "$REMOTE_PATH" | awk 'NR==1 {print $1}')

      mkdir -p "$(dirname "$PATHNAME")"

      if [ "$OBJ_TYPE" = "blob" ] && [ "$MODE" = "120000" ]; then
        # A symlink: the blob holds the target path.
        TARGET=$(git show "${TO_SHA}:${REMOTE_PATH}")
        rm -f "$PATHNAME"
        if ! ln -s "$TARGET" "$PATHNAME"; then
          echo "[git-poll] ERROR: Failed to write symlink: ${PATHNAME}"
          FAILED=1
          break
        fi
      elif [ "$OBJ_TYPE" = "blob" ]; then
        if ! git show "${TO_SHA}:${REMOTE_PATH}" > "$PATHNAME"; then
          echo "[git-poll] ERROR: Failed to write file: ${PATHNAME}"
          FAILED=1
          break
        fi
        if [ "$MODE" = "100755" ]; then
          chmod 755 "$PATHNAME" 2>/dev/null || true
        else
          chmod 644 "$PATHNAME" 2>/dev/null || true
        fi
      else
        echo "[git-poll] WARN: Unsupported object type '${OBJ_TYPE}' for ${REMOTE_PATH}; skipping."
        FAILED=1
        break
      fi
      continue
    fi

    # The commit deleted the path: remove the local file if present.
    rm -f "$PATHNAME" 2>/dev/null || true
  done < "$RECONCILE_PATHS_FILE"

  [ "$FAILED" -eq 0 ]
}

reconcile_changed_paths() {
  FROM_SHA="$1"
  TO_SHA="$2"

  if ! append_changed_paths "$FROM_SHA" "$TO_SHA"; then
    return 1
  fi

  if ! reconcile_tracked_paths "$TO_SHA"; then
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Poll loop
# ---------------------------------------------------------------------------

while true; do
  sleep "$GIT_POLL_INTERVAL"

  if ! git fetch --depth=1 origin "$GIT_BRANCH" 2>/dev/null; then
    echo "[git-poll] Fetch failed (network issue?). Will retry next cycle."
    continue
  fi

  LATEST_SHA=$(git rev-parse FETCH_HEAD)

  if [ "$LATEST_SHA" = "$CURRENT_SHA" ]; then
    continue
  fi

  echo "[git-poll] =========================================="
  echo "[git-poll] New commit detected on '$GIT_BRANCH'"
  echo "[git-poll]   was: ${CURRENT_SHA}"
  echo "[git-poll]   now: ${LATEST_SHA}"
  echo "[git-poll] =========================================="

  # A rebuild is already running.
  if [ -f "$REBUILD_LOCK" ]; then
    echo "[git-poll] Rebuild already in progress (lock file exists). Skipping this cycle."
    continue
  fi

  echo "$$" > "$REBUILD_LOCK"

  if ! reconcile_changed_paths "$CURRENT_SHA" "$LATEST_SHA"; then
    echo "[git-poll] ERROR: File reconciliation failed."
    rm -f "$REBUILD_LOCK"
    continue
  fi

  # In case mix.exs or mix.lock changed. Fast when nothing did.
  echo "[git-poll] Running mix deps.get..."
  if ! mix deps.get; then
    echo "[git-poll] WARNING: mix deps.get failed. Attempting rebuild anyway."
  fi

  echo "[git-poll] Running rebuild..."
  if "$REBUILD_SCRIPT"; then
    echo "[git-poll] Rebuild succeeded for ${LATEST_SHA}."
  else
    echo "[git-poll] Rebuild FAILED for ${LATEST_SHA}."
    echo "[git-poll] start-wrapper.sh rolls back a release that does not start."
    echo "[git-poll] Push a fix to trigger another rebuild."
  fi

  CURRENT_SHA="$LATEST_SHA"
  rm -f "$REBUILD_LOCK"
done
