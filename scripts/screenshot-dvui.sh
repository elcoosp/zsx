#!/usr/bin/env bash
# Capture the DVUI binary's window using macOS screencapture.
# Requires: Screen Recording permission for Terminal
#           Accessibility permission for Terminal (for window positioning via AppleScript)
#
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

# Give the app time to open its window
sleep 2

echo "Positioning window at 100,100 (700x500)"
osascript >/dev/null 2>&1 << APPLESCRIPT || echo "WARN: AppleScript positioning failed (may need Accessibility permission)"
tell application "System Events"
    set procs to (name of every process whose background only is false)
    repeat with p in procs
        try
            tell process p
                set winCount to count of windows
                if winCount > 0 then
                    set position of window 1 to {100, 100}
                    set size of window 1 to {700, 500}
                    set frontmost to true
                end if
            end tell
        end try
    end repeat
end tell
APPLESCRIPT

sleep 1

echo "Capturing region 100,100 700x500 → $OUT"
if ! screencapture -x -R 100,100,700,500 "$OUT" 2>&1; then
    echo "ERROR: screencapture failed" >&2
    echo ""
    echo "Grant permission: System Settings → Privacy & Security → Screen Recording"
    echo "  → Enable for Terminal (or the app you run this from)"
    echo "Then re-run this script."
    kill -9 "$APP_PID" 2>/dev/null || true
    exit 1
fi

# Cleanup
kill -9 "$APP_PID" 2>/dev/null || true

if [ -f "$OUT" ]; then
    SIZE=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT" 2>/dev/null)
    echo "Wrote $OUT ($SIZE bytes)"
    if [ "$SIZE" -lt 3000 ]; then
        echo "WARN: file is small ($SIZE bytes) — likely still empty or capture failed"
        exit 1
    fi
    open "$OUT" 2>/dev/null || true
else
    echo "ERROR: $OUT not created" >&2
    exit 1
fi
