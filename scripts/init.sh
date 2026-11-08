#!/usr/bin/env bash
# scripts/init.sh — create a new ZSX project from the local clone.
#
# Usage:
#   scripts/init.sh <project-dir> [project-name]
#
# Creates a working project that depends on zsx via .path (default — points
# at the current clone). Set ZSX_URL + ZSX_HASH to use a published package:
#
#   ZSX_URL="git+https://github.com/elcoosp/zsx#v0.1.0" \
#   ZSX_HASH="zsx-0.1.0-AAAA..." \
#   scripts/init.sh ~/code/my-app my_app
#
# The script:
#   1. Copies examples/consumer/ as the template
#   2. Rewrites build.zig.zon (name, fingerprint, dependency)
#   3. Renames the binary to the project name
#   4. Personalizes the home view heading
#   5. Computes the fingerprint (fast — Zig fails before compiling)
#   6. Verifies `zig build` succeeds
#   7. Runs `git init` + first commit

set -euo pipefail

DEST="${1:?usage: $0 <project-dir> [project-name]}"
NAME="${2:-$(basename "$DEST" | tr '-' '_' | tr 'A-Z' 'a-z')}"

if ! [[ "$NAME" =~ ^[a-z][a-z0-9_]*$ ]]; then
    echo "error: project name must match [a-z][a-z0-9_]*, got: $NAME" >&2
    exit 1
fi

if [ -e "$DEST" ]; then
    echo "error: destination already exists: $DEST" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZSX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$ZSX_ROOT/examples/consumer"

if [ ! -d "$TEMPLATE" ]; then
    echo "error: template not found at $TEMPLATE" >&2
    echo "       (scripts/init.sh expects to live inside the zsx repo)" >&2
    exit 1
fi

if [ -n "${ZSX_URL:-}" ]; then
    if [ -z "${ZSX_HASH:-}" ]; then
        echo "error: ZSX_URL set but ZSX_HASH missing" >&2
        echo "       run 'zig fetch --save \"$ZSX_URL\"' in a scratch project" >&2
        echo "       and copy the hash it writes to build.zig.zon" >&2
        exit 1
    fi
    DEP_LINES=".url = \"$ZSX_URL\",
            .hash = \"$ZSX_HASH\","
    echo "using ZSX_URL = $ZSX_URL"
else
    # .path must be relative to the new project's build root. On macOS /tmp is
    # a symlink to /private/tmp, so os.path.relpath() on the symlink path yields
    # a wrong "../" count. Realpath both sides first.
    REL_PATH=$(python3 - "$DEST" "$ZSX_ROOT" << 'PYEOF2'
import os, sys
dest_arg, zsx_arg = sys.argv[1], sys.argv[2]
dest_real = os.path.realpath(dest_arg)   # resolves /tmp -> /private/tmp etc.
zsx_real = os.path.realpath(zsx_arg)
print(os.path.relpath(zsx_real, dest_real))
PYEOF2
)
    DEP_LINES=".path = \"$REL_PATH\","
    echo "using local zsx at $ZSX_ROOT (relative: $REL_PATH)"
fi

echo "creating project at $DEST (package: $NAME)"
mkdir -p "$DEST"

cp -R "$TEMPLATE/src" "$DEST/"
cp "$TEMPLATE/build.zig" "$DEST/"
cp "$TEMPLATE/.gitignore" "$DEST/" 2>/dev/null || true

rm -rf "$DEST/.zig-cache" "$DEST/zig-out" "$DEST/todos.json"

cat > "$DEST/build.zig.zon" << ZON
.{
    .name = .$NAME,
    .version = "0.1.0",
    .fingerprint = 0x0,
    .minimum_zig_version = "0.17.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    .dependencies = .{
        .zsx = .{
            $DEP_LINES
        },
    },
}
ZON

sed -i.bak "s/\.name = \"consumer-demo\"/.name = \"$NAME\"/" "$DEST/build.zig"
rm -f "$DEST/build.zig.bak"

if [ -f "$DEST/src/views/home.zsx" ]; then
    sed -i.bak "0,/>Home</s//>$NAME</" "$DEST/src/views/home.zsx"
    rm -f "$DEST/src/views/home.zsx.bak"
fi

echo "computing fingerprint..."
FP_OUT=$(cd "$DEST" && zig build 2>&1 || true)
FP=$(echo "$FP_OUT" | grep -oE 'use this value: 0x[0-9a-f]+' | head -1 | sed 's/use this value: //' || true)

if [ -z "$FP" ]; then
    echo "warn: could not auto-detect fingerprint" >&2
    echo "       run 'zig build' once and paste the suggested value" >&2
    echo "       into build.zig.zon's .fingerprint field" >&2
else
    sed -i.bak "s/\.fingerprint = 0x[0-9a-f]*/.fingerprint = $FP/" "$DEST/build.zig.zon"
    rm -f "$DEST/build.zig.zon.bak"
    echo "fingerprint: $FP"
fi

echo "verifying build..."
if (cd "$DEST" && zig build > /tmp/zsx-init-build.log 2>&1); then
    echo "ok: zig build succeeds"
else
    echo "warn: initial build failed — see /tmp/zsx-init-build.log" >&2
    tail -15 /tmp/zsx-init-build.log >&2
fi

if command -v git > /dev/null 2>&1; then
    (cd "$DEST" && git init -q && git add -A && git commit -q -m "Initial commit from zsx init" 2>/dev/null) || true
    echo "git: initialized"
fi

echo ""
echo "done. next:"
echo "  cd $DEST"
echo "  zig build run      # run the demo (prints widget counts to stdout)"
echo "  edit src/views/home.zsx"
