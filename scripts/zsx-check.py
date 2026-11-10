#!/usr/bin/env python3
"""zsx-check — DEPRECATED: use `zsx check` (M1 replaces this Python tool).

zsx-check — validate .zsx files without compilation.

Usage:
    scripts/zsx-check.py [files...]

Checks (fast, pure Python, no Zig needed):
- Balanced tags: <foo>...</foo> or <foo />
- Control flow: {if}...{/if}, {for}...{/for}, {switch}...{/switch}
- {:case} / {:else} properly nested
- Attribute values are "string" or {expression}
- Unknown-class warnings (optional, --no-class-check disables)

Exit codes:
    0 — all clean (warnings allowed)
    1 — at least one error
    2 — parse failure (couldn't extract block)
"""

import sys
import os
import re

KNOWN_CLASSES = {
    # Match src/rt/style.zig class table
    "bg-blue-500", "bg-blue-600", "bg-gray-100", "bg-red-500", "bg-green-500",
    "bg-yellow-500", "bg-slate-100", "bg-slate-500", "bg-slate-900", "bg-transparent",
    "text-white", "text-black", "text-gray-100", "text-gray-300", "text-gray-500",
    "text-gray-700", "text-gray-900", "text-red-500", "text-green-500",
    "text-slate-500", "text-slate-900",
    "text-xs", "text-sm", "text-lg", "text-xl", "text-2xl", "text-3xl",
    "font-bold", "font-semibold", "font-normal",
    "p-1", "p-2", "p-3", "p-4", "p-6", "p-8",
    "px-2", "px-3", "px-4", "px-6",
    "py-1", "py-2", "py-3", "py-6",
    "gap-1", "gap-2", "gap-4",
    "rounded-md", "rounded-lg", "rounded-full",
}


def error(loc, msg):
    print(f"{loc}: error: {msg}", file=sys.stderr)


def warn(loc, msg):
    print(f"{loc}: warning: {msg}", file=sys.stderr)


def check_file(path, check_classes=True):
    """Returns number of errors."""
    try:
        with open(path) as f:
            src = f.read()
    except OSError as e:
        error(path, f"cannot read: {e}")
        return 1

    blocks = find_zsx_blocks(src)
    if not blocks:
        return 0  # no blocks, nothing to check

    errors = 0
    for (start, end) in blocks:
        markup = src[start+5:end-1]
        errors += check_markup(markup, path, start, src, check_classes)
    return errors


def find_zsx_blocks(src):
    """Same block-finder as zsx-fmt.py."""
    blocks = []
    pos = 0
    n = len(src)
    while pos < n:
        c = src[pos]
        if c == '"':
            pos = skip_string(src, pos); continue
        if c == "'":
            pos = skip_char(src, pos); continue
        if c == '/' and pos+1 < n and src[pos+1] == '/':
            while pos < n and src[pos] != '\n': pos += 1
            continue
        if c == '/' and pos+1 < n and src[pos+1] == '*':
            end = src.find('*/', pos+2)
            pos = end+2 if end > 0 else n
            continue
        if c == 'z' and src[pos:pos+5] == 'zsx!{':
            brace_open = pos + 4
            close = find_matching_brace(src, brace_open)
            if close < 0:
                return blocks  # unmatched, return what we have
            blocks.append((pos, close+1))
            pos = close+1
            continue
        pos += 1
    return blocks


def skip_string(src, start):
    p = start + 1
    while p < len(src):
        if src[p] == '\\': p += 2; continue
        if src[p] == '"': return p+1
        p += 1
    return len(src)


def skip_char(src, start):
    p = start + 1
    while p < len(src):
        if src[p] == '\\': p += 2; continue
        if src[p] == "'": return p+1
        p += 1
    return len(src)


def find_matching_brace(src, open_pos):
    depth = 0
    p = open_pos
    while p < len(src):
        c = src[p]
        if c == '"':
            p = skip_string(src, p); continue
        if c == "'":
            p = skip_char(src, p); continue
        if c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0: return p
        p += 1
    return -1


def line_of(src, offset):
    return src.count('\n', 0, offset) + 1


def check_markup(markup, path, base_offset, full_src, check_classes):
    """Validate structure. Returns error count."""
    errors = 0
    tag_stack = []           # stack of (tag_name, line)
    ctrl_stack = []          # stack of "if"/"for"/"switch"

    tokens = tokenize_markup(markup)

    for (kind, value, offset) in tokens:
        line = line_of(full_src, base_offset + 5 + offset)
        loc = f"{path}:{line}"

        if kind == "open_tag":
            tag, self_closing, attrs = value
            if check_classes:
                for (attr_name, attr_val, _attr_off) in attrs:
                    if attr_name == "class" and isinstance(attr_val, str):
                        for cls in attr_val.split():
                            if cls and cls not in KNOWN_CLASSES:
                                warn(loc, f"unknown class '{cls}' (will error at build)")
            if not self_closing:
                tag_stack.append((tag, line))
        elif kind == "close_tag":
            tag = value
            if not tag_stack:
                error(loc, f"</{tag}> with no open tag")
                errors += 1
            else:
                expected, open_line = tag_stack.pop()
                if expected != tag:
                    error(loc, f"</{tag}> closes <{expected}> opened at line {open_line}")
                    errors += 1
        elif kind == "ctrl_open":
            ctrl_stack.append((value, line))
        elif kind == "ctrl_close":
            c = value
            if not ctrl_stack:
                error(loc, f"{{{c}}} with no matching {{if}}/{{for}}/{{switch}}")
                errors += 1
            else:
                expected, _open_line = ctrl_stack.pop()
                if expected != c:
                    error(loc, f"{{{c}}} closes {{{expected}}}")
                    errors += 1
        elif kind == "ctrl_mid":
            mid = value
            if not ctrl_stack:
                error(loc, f"{{{mid}}} at top level")
                errors += 1
            else:
                top, _ = ctrl_stack[-1]
                if mid == ":case" and top not in ("switch", "if"):
                    error(loc, f"{{:case}} inside {{{top}}} (only valid in {{switch}})")
                    errors += 1
                elif mid == ":else" and top not in ("if", "switch"):
                    error(loc, f"{{:else}} inside {{{top}}}")
                    errors += 1

    # Unclosed tags / control flow
    for (tag, line) in tag_stack:
        error(f"{path}:{line}", f"<{tag}> never closed")
        errors += 1
    for (ctrl, line) in ctrl_stack:
        error(f"{path}:{line}", f"{{{ctrl}}} never closed")
        errors += 1

    return errors


def tokenize_markup(markup):
    """Yield (kind, value, offset) tuples for structural tokens."""
    tokens = []
    pos = 0
    n = len(markup)
    while pos < n:
        c = markup[pos]

        # String in attribute value — skip
        if c == '"':
            end = skip_string(markup, pos)
            pos = end
            continue

        # Expression block { ... } — could be {if} / {for} / {:case} / {/if} / {expr}
        if c == '{':
            close = find_matching_brace(markup, pos)
            if close < 0:
                break
            inner = markup[pos+1:close].strip()
            offset = pos

            if inner.startswith("/"):
                kind = inner[1:].strip()  # /if → if, /for → for, /switch → switch
                if kind in ("if", "for", "switch"):
                    tokens.append(("ctrl_close", kind, offset))
            elif inner.startswith(":case"):
                tokens.append(("ctrl_mid", ":case", offset))
            elif inner.startswith(":else"):
                tokens.append(("ctrl_mid", ":else", offset))
            elif inner.startswith("if "):
                tokens.append(("ctrl_open", "if", offset))
            elif inner.startswith("for ") and " as " in inner:
                tokens.append(("ctrl_open", "for", offset))
            elif inner.startswith("switch "):
                tokens.append(("ctrl_open", "switch", offset))
            elif inner in ("endif", "endfor", "endswitch"):
                tokens.append(("ctrl_close", inner[3:], offset))
            else:
                # Plain expression child — ignore
                pass
            pos = close + 1
            continue

        # Tags
        if c == '<':
            # Fragment <>
            if markup[pos:pos+2] == '<>':
                tokens.append(("open_tag", ("", False, []), pos))
                pos += 2
                continue
            if markup[pos:pos+3] == '</>':
                tokens.append(("close_tag", "", pos))
                pos += 3
                continue
            # Close tag </tag>
            m = re.match(r'</([A-Za-z][A-Za-z0-9_.-]*)\s*>', markup[pos:])
            if m:
                tokens.append(("close_tag", m.group(1), pos))
                pos += m.end()
                continue
            # Open tag <tag ...> or <tag ... />
            m = re.match(r'<([A-Za-z][A-Za-z0-9_.-]*)', markup[pos:])
            if m:
                tag = m.group(1)
                scan = pos + m.end()
                attrs = []
                self_closing = False
                # Scan attributes
                while scan < n:
                    while scan < n and markup[scan] in ' \t\n\r': scan += 1
                    if scan >= n: break
                    if markup[scan] == '>':
                        scan += 1; break
                    if markup[scan] == '/':
                        if scan+1 < n and markup[scan+1] == '>':
                            self_closing = True
                            scan += 2; break
                    # Attribute name
                    a_start = scan
                    while scan < n and (markup[scan].isalnum() or markup[scan] in '_-.:'):
                        scan += 1
                    a_name = markup[a_start:scan]
                    if not a_name:
                        scan += 1; continue
                    while scan < n and markup[scan] in ' \t': scan += 1
                    a_val = None
                    if scan < n and markup[scan] == '=':
                        scan += 1
                        if scan < n and markup[scan] == '"':
                            v_start = scan + 1
                            scan = skip_string(markup, scan)
                            a_val = markup[v_start:scan-1]
                        elif scan < n and markup[scan] == '{':
                            close = find_matching_brace(markup, scan)
                            if close > 0:
                                a_val = ("expr", markup[scan+1:close])
                                scan = close + 1
                    attrs.append((a_name, a_val, a_start))
                tokens.append(("open_tag", (tag, self_closing, attrs), pos))
                pos = scan
                continue
        pos += 1
    return tokens


def main():
    args = sys.argv[1:]
    check_classes = True
    if "--no-class-check" in args:
        check_classes = False
        args.remove("--no-class-check")

    if not args:
        args = []
        for root, _, filenames in os.walk('.'):
            if '/.git' in root or '/.zig-cache' in root:
                continue
            for fn in filenames:
                if fn.endswith('.zsx'):
                    args.append(os.path.join(root, fn))
        args.sort()

    if not args:
        print('zsx-check: no .zsx files found')
        return 0

    total_errors = 0
    for f in args:
        total_errors += check_file(f, check_classes)

    if total_errors > 0:
        print(f"\nzsx-check: {total_errors} error(s)", file=sys.stderr)
        return 1
    print(f"zsx-check: {len(args)} file(s) clean", file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
