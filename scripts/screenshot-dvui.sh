#!/usr/bin/env bash
# Capture the DVUI window on macOS using CoreGraphics (CGWindowListCopyWindowInfo)
# and the system `screencapture` tool. No AppleScript, no Python, no window moving.
#
# Why Swift: it ships with macOS and can call CoreGraphics directly. CGWindowListCopyWindowInfo
# is the same API System Events wraps, but it works on SDL3 apps that System Events cannot see.
#
# Requires: Screen Recording permission for Terminal.
# Usage: ./scripts/screenshot-dvui.sh [output.png]

set -uo pipefail

OUT="${1:-/tmp/components-dvui.png}"
BIN="./zig-out/bin/zsx-hello-dvui"

if [ ! -x "$BIN" ]; then
    echo "ERROR: $BIN not found. Run: zig build build-app-dvui" >&2
    exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "ERROR: swift not found. Install with: xcode-select --install" >&2
    exit 1
fi

echo "Launching $BIN"
"$BIN" &
APP_PID=$!

WINDOW_ID=""
for attempt in 1 2 3 4 5; do
    sleep 1
    WINDOW_ID=$(swift -e "
import CoreGraphics
import Foundation
let pid = Int32($APP_PID)
guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
for w in list {
    if let owner = w[kCGWindowOwnerPID as String] as? Int32, owner == pid {
        if let num = w[kCGWindowNumber as String] as? UInt32 {
            print(num)
            exit(0)
        }
    }
}
exit(1)
" 2>/dev/null) || true
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
    echo "If Screen Recording is missing:" >&2
    echo "  System Settings → Privacy & Security → Screen Recording → Terminal" >&2
    exit 1
fi

echo "Capturing window $WINDOW_ID → $OUT"
# -l <id>: only that window. -o: no shadow. -x: no sound.
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
    echo "WARN: very small file — likely empty" >&2
    exit 1
fi

# Sanity: capture is the window, not the desktop
case "$DIMS" in
    1920x*|2560x*|2880x*|3840x*)
        echo "WARN: dims $DIMS look like full screen, not window" >&2
        exit 1
        ;;
esac
