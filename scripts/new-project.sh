#!/usr/bin/env bash
# Fork ZSX into a fresh project.
# Usage: new-project.sh <destination> <project-name>
set -euo pipefail

DEST="${1:-}"
NAME="${2:-}"

if [ -z "$DEST" ] || [ -z "$NAME" ]; then
    echo "usage: $0 <destination> <project-name>" >&2
    exit 1
fi
if ! echo "$NAME" | grep -qE '^[a-z][a-z0-9_]*$'; then
    echo "ERROR: name must match [a-z][a-z0-9_]*" >&2
    exit 1
fi
if [ -e "$DEST" ]; then
    echo "ERROR: $DEST already exists" >&2
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
echo "Copying $SCRIPT_DIR -> $DEST"
mkdir -p "$DEST"
rsync -a \
    --exclude='.git' \
    --exclude='.zig-cache' \
    --exclude='zig-out' \
    --exclude='zig-pkg' \
    --exclude='scripts/new-project.sh' \
    --exclude='TEMPLATE.md' \
    "$SCRIPT_DIR"/ "$DEST"/

cd "$DEST"

echo "Renaming package to $NAME"
python3 - "$NAME" << 'PY'
import re, sys
name = sys.argv[1]
p = 'build.zig.zon'
c = open(p).read()
c = re.sub(r'\.name\s*=\s*\.\w+', f'.name = .{name}', c, count=1)
c = re.sub(r'\.fingerprint\s*=\s*0x[0-9a-fA-F]+,?\n', '', c)
open(p, 'w').write(c)
PY

echo "Generating fingerprint"
TMPF=$(mktemp)
zig build --help > "$TMPF" 2>&1 || true
FP=$(grep -oE 'suggested value: 0x[0-9a-fA-F]+' "$TMPF" | head -1 | sed 's/suggested value: //')
rm -f "$TMPF"

if [ -z "$FP" ]; then
    echo "WARN: no fingerprint captured — run zig build once to get one"
else
    echo "Fingerprint: $FP"
    python3 - "$FP" << 'PY'
import re, sys
fp = sys.argv[1]
p = 'build.zig.zon'
c = open(p).read()
c = re.sub(
    r'(\.version\s*=\s*"[^"]*",)',
    rf'\1\n    .fingerprint = {fp},',
    c,
    count=1,
)
open(p, 'w').write(c)
PY
fi

echo "Initializing git"
git init -q
git add -A
git commit -q -m "Initial commit from zsx template"

echo ""
echo "Project created at $DEST (package name: $NAME)"
echo "  cd $DEST"
echo "  zig build test"
echo "  zig build build-app"
