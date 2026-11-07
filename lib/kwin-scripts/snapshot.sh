#!/bin/bash
# kdoitall snapshot — thin client that calls the long-lived snapshot daemon.
#
# The daemon (daemon.py) registers org.kdoitall.Snapshot on the session
# bus and exposes a TakeSnapshot(int) -> string method. We probe for the
# daemon via qdbus; if it isn't running, we spawn it (detached from this
# process) and wait briefly for the bus name to appear before issuing the
# call.
#
# Calls are serialized via flock so a single bash client cannot have two
# TakeSnapshot calls in flight at once (the daemon would reject the second
# with "daemon busy" — the lock guarantees we never observe that case).
#
# Usage: snapshot.sh [timeout_seconds]
#   default timeout: 5
# Output: JSON payload on stdout
# Exit:   0 success; non-zero on failure / timeout / daemon spawn failure

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON="${SCRIPT_DIR}/daemon.py"
JS_FILE="${SCRIPT_DIR}/snapshot.js"

QDBUS="${QDBUS_BIN:-qdbus-qt6}"
TIMEOUT_SECS="${1:-5}"
TIMEOUT_MS=$(( TIMEOUT_SECS * 1000 ))

LOCK_FILE="/tmp/kdoitall-snapshot.lock"

exec 200>"$LOCK_FILE"
flock -x 200

# Probe for an already-running daemon
if ! "$QDBUS" org.kdoitall.Snapshot &>/dev/null; then
    # Spawn one. We deliberately detach via nohup so the daemon outlives
    # this script (and any kdoitall invocation that triggered it). The
    # `200>&-` is critical: without it, the daemon inherits fd 200 (our
    # flock target) and holds the lock for its entire lifetime, blocking
    # every subsequent snapshot.sh call.
    nohup python3 "$DAEMON" "$JS_FILE" >/dev/null 2>&1 </dev/null 200>&- &
    disown 2>/dev/null || true

    # Wait up to 2s for the bus name to register
    SERVICE_READY=false
    for _ in $(seq 1 40); do
        if "$QDBUS" org.kdoitall.Snapshot &>/dev/null; then
            SERVICE_READY=true
            break
        fi
        sleep 0.05
    done

    if [[ "$SERVICE_READY" != true ]]; then
        echo "snapshot.sh: daemon failed to register bus name" >&2
        exit 1
    fi
fi

# Issue the call. qdbus blocks until the daemon sends its async reply.
PAYLOAD=$("$QDBUS" org.kdoitall.Snapshot /Snapshot \
    org.kdoitall.Snapshot.TakeSnapshot "$TIMEOUT_MS" 2>&1)
RC=$?

if [[ $RC -ne 0 ]]; then
    echo "snapshot.sh: TakeSnapshot failed: $PAYLOAD" >&2
    exit 1
fi

printf '%s\n' "$PAYLOAD"
