#!/bin/sh
# healthcheck.sh: smoke test for the running server
#
# start-wrapper.sh runs it after every server start. Exit 0 means healthy.
# Anything else counts as a failure, and after FAILURE_THRESHOLD failures in
# a row the wrapper rolls back to the previous release.
#
# Adjust it to the app. Common additions:
#   - Request a page that reads from the database
#   - Check that a background job queue is running
#   - Check that an external service is reachable

PORT="${PORT:-4000}"
URL="http://127.0.0.1:${PORT}/"

# The VM and migrations can take a while to start. Allow this many seconds
# before declaring the server unhealthy.
TIMEOUT=30
ELAPSED=0
INTERVAL=2

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL" 2>/dev/null) || STATUS="000"

  if [ "$STATUS" = "200" ] || [ "$STATUS" = "301" ] || [ "$STATUS" = "302" ]; then
    echo "[healthcheck] OK (HTTP $STATUS from $URL)"
    exit 0
  fi

  echo "[healthcheck] Waiting for server... (HTTP $STATUS, ${ELAPSED}s elapsed)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "[healthcheck] FAILED: no success status within ${TIMEOUT}s (last status: $STATUS)"
exit 1
