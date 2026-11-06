#!/usr/bin/env bash
# Capture the DVUI window on macOS. Uses CGWindowListCopyWindowInfo to find
# the window by PID (SDL3 apps don't reliably register with System Events).
# This script NEVER moves, activates, or resizes any window.
# Requires: Screen Recording permission for Terminal.
# Usage: ./scripts/screenshot-dvui.sh [output.png]

set -uo pipefail

OUT="${1:-/tmp/components-dvui.png}"
BIN="./zig-out/bin/zsx-hello-dvui"

if [ ! -x "$BIN" ]; then
    echo "ERROR: $BIN not found. Run: zig build build-app-dvui" >&2
    exit 1
fi

echo "Launching $BIN"
"$BIN" &
APP_PID=$!

WINDOW_ID=""
for attempt in 1 2 3 4 5; do
    sleep 1
    WINDOW_ID=$(/usr/bin/python3 <<PYEOF 2>/dev/null || true
import Quartz, sys
pid = $APP_PID
wins = Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)
for w in wins:
    if w.get('kCGWindowOwnerPID') == pid:
        n = w.get('kCGWindowNumber')
        if n is not None:
            print(n)
            sys.exit(0)
sys.exit(1)
PYEOF
)
    if [ -n "$WINDOW_ID" ]; then
        echo "  window id found on attempt $attempt: $WINDOW_ID"
        break
    fi
    echo "  attempt $attempt: window not yet visible"
done

if [ -z "$WINDOW_ID" ]; then
    echo "ERROR: window not found after 5s for PID $APP_PID" >&2
    kill -9 $APP_PID 2>/dev/null || true
    echo "" >&2
    echo "If Screen Recording permission is missing:" >&2
    echo "  System Settings → Privacy & Security → Screen Recording → Terminal" >&2
    exit 1
fi

echo "Capturing window $WINDOW_ID → $OUT"
if ! screencapture -x -o -l "$WINDOW_ID" "$OUT" 2>&1; then
    echo "ERROR: screencapture failed" >&2
    kill -9 $APP_PID 2>/dev/null || true
    exit 1
fi

kill -9 $APP_PID 2>/dev/null || true
sleep 0.3

if [ ! -f "$OUT" ]; then
    echo "ERROR: $OUT not created" >&2
    exit 1
fi

SIZE=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT" 2>/dev/null)
DIMS=$(sips -g pixelWidth -g pixelHeight "$OUT" 2>/dev/null | awk '/pixel/{print $2}' | paste -sd'x' -)
echo "Wrote $OUT ($SIZE bytes, ${DIMS:-unknown dims})"

if [ "$SIZE" -lt 3000 ]; then
    echo "WARN: file very small — likely empty" >&2
    exit 1
fi
