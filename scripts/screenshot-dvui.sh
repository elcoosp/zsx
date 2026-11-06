#!/usr/bin/env bash
# Capture the DVUI window by ID. No repositioning of any window.
# Requires: Screen Recording for Terminal.
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

# Give the app time to create its window
sleep 2

# Ask System Events for the window id of exactly this process (by unix id)
WINDOW_ID=$(osascript <<APPLESCRIPT 2>/dev/null
tell application "System Events"
    try
        set p to first process whose unix id is $APP_PID
        set w to first window of p
        return id of w as text
    on error
        return ""
    end try
end tell
APPLESCRIPT
)

if [ -z "$WINDOW_ID" ]; then
    echo "ERROR: window id not found for PID $APP_PID" >&2
    kill -9 $APP_PID 2>/dev/null || true
    echo "Check: System Settings → Privacy & Security → Screen Recording → Terminal" >&2
    exit 1
fi

echo "Window id: $WINDOW_ID"
echo "Capturing window → $OUT"

# -l <id> captures only that window. -o omits the shadow.
if ! screencapture -x -o -l "$WINDOW_ID" "$OUT" 2>&1; then
    echo "ERROR: screencapture failed" >&2
    kill -9 $APP_PID 2>/dev/null || true
    exit 1
fi

kill -9 $APP_PID 2>/dev/null || true

if [ -f "$OUT" ]; then
    SIZE=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT" 2>/dev/null)
    echo "Wrote $OUT ($SIZE bytes)"
    if [ "$SIZE" -lt 3000 ]; then
        echo "WARN: file is small ($SIZE bytes) — likely empty"
        exit 1
    fi
else
    echo "ERROR: $OUT not created" >&2
    exit 1
fi
