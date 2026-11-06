#!/usr/bin/env bash
# Capture DVUI binary window. Requires Screen Recording + Accessibility for Terminal.
set -uo pipefail

OUT="${1:-/tmp/components-dvui.png}"
BIN="./zig-out/bin/zsx-hello-dvui"
WINDOW_TITLE="ZSX Component Library"

if [ ! -x "$BIN" ]; then
    echo "ERROR: $BIN not found. Run: zig build build-app-dvui" >&2
    exit 1
fi

echo "Launching $BIN"
"$BIN" &
APP_PID=$!

sleep 2

echo "Positioning window at 100,100"
osascript >/dev/null 2>&1 << APPLESCRIPT || echo "WARN: positioning failed"
tell application "System Events"
    repeat with p in (every process whose background only is false)
        try
            tell p
                if (count of windows) > 0 then
                    if name of window 1 contains "Component" or name of p contains "zsx" then
                        set position of window 1 to {100, 100}
                        set frontmost to true
                    end if
                end if
            end tell
        end try
    end repeat
end tell
APPLESCRIPT

sleep 1

# Query exact window bounds (includes title bar)
BOUNDS=$(osascript <<'AS' 2>/dev/null
tell application "System Events"
    repeat with p in (every process whose background only is false)
        try
            tell p
                if (count of windows) > 0 then
                    if name of window 1 contains "Component" or name of p contains "zsx" then
                        set pos to position of window 1
                        set sz to size of window 1
                        return ((item 1 of pos) as string) & "," & ((item 2 of pos) as string) & "," & ((item 1 of sz) as string) & "," & ((item 2 of sz) as string)
                    end if
                end if
            end tell
        end try
    end repeat
end tell
return ""
AS
)

if [ -n "$BOUNDS" ]; then
    echo "Window bounds: $BOUNDS"
    CAPTURE_REGION="$BOUNDS"
else
    echo "WARN: bounds query failed, using fallback 100,100,720,560"
    CAPTURE_REGION="100,100,720,560"
fi

echo "Capturing region $CAPTURE_REGION → $OUT"
if ! screencapture -x -R "$CAPTURE_REGION" "$OUT" 2>&1; then
    echo "ERROR: screencapture failed" >&2
    kill -9 "$APP_PID" 2>/dev/null || true
    echo ""
    echo "Grant permission: System Settings → Privacy & Security → Screen Recording"
    echo "  → Enable for Terminal"
    exit 1
fi

kill -9 "$APP_PID" 2>/dev/null || true

if [ -f "$OUT" ]; then
    SIZE=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT" 2>/dev/null)
    echo "Wrote $OUT ($SIZE bytes)"
    if [ "$SIZE" -lt 3000 ]; then
        echo "WARN: file too small ($SIZE bytes) — empty?"
        exit 1
    fi
else
    echo "ERROR: $OUT not created" >&2
    exit 1
fi
