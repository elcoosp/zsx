#!/usr/bin/env bash
# Capture the DVUI window by ID. Polls for the window (SDL apps need ~2-3s
# to register with System Events). Never moves or activates any window.
# Requires: Screen Recording + Accessibility permissions for Terminal.
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

# Poll for the window id. SDL apps take a moment to register with System Events.
WINDOW_ID=""
for attempt in 1 2 3 4 5 6 7 8; do
    sleep 1
    WINDOW_ID=$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
    repeat with p in (every process whose background only is false)
        try
            if name of p contains "zsx-hello" then
                tell p
                    if (count of windows) > 0 then
                        return id of window 1 as text
                    end if
                end tell
            end if
        end try
    end repeat
end tell
return ""
APPLESCRIPT
)
    if [ -n "$WINDOW_ID" ]; then
        echo "  window id found on attempt $attempt: $WINDOW_ID"
        break
    fi
    echo "  attempt $attempt: window not yet visible"
done

if [ -z "$WINDOW_ID" ]; then
    echo "ERROR: window not found after 8s for $APP_PID" >&2
    kill -9 $APP_PID 2>/dev/null || true
    echo "" >&2
    echo "Check permissions (both required):" >&2
    echo "  System Settings → Privacy & Security → Screen Recording → Terminal" >&2
    echo "  System Settings → Privacy & Security → Accessibility → Terminal" >&2
    exit 1
fi

echo "Capturing window $WINDOW_ID → $OUT"
# -l: capture only that window. -o: omit shadow. -x: no sound.
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
    echo "WARN: file is very small — likely empty" >&2
    exit 1
fi

# Sanity: full-screen capture would be ~1920x1080 or larger
if echo "$DIMS" | grep -qE '^(1920|2560|2880|3840)x'; then
    echo "WARN: dims $DIMS look like full screen, not window" >&2
    exit 1
fi
