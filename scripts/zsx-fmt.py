#!/usr/bin/env python3
"""zsx-fmt — DEPRECATED: use `zsx fmt` (M1 replaces this Python tool).

zsx-fmt — reformat the markup inside `zsx!{ ... }` blocks.

Usage:
    scripts/zsx-fmt.py [--check] [--write] [files...]

Behavior:
- Zig code outside `zsx!{ }` blocks is preserved byte-for-byte.
- Inside blocks, indentation is normalized to 4 spaces per nesting level.
- Opening tags `<tag>`, self-closing `<tag />`, closing `</tag>` adjust depth.
- Control-flow `{if}`, `{for}`, `{switch}`, `{:case}`, `{:else}` indent their
  bodies by +1.
- Idempotent: running twice produces the same output.

Exit:
    0 — all files already formatted (or all formatted with --write)
    1 — at least one file needs formatting (--check mode)
    2 — parse / IO error
"""

import sys
import os
import re

INDENT = 4

# Patterns
OPEN_Zsx = re.compile(r'zsx!\{')
CLOSE_TAG = re.compile(r'^\s*</\w+')
SELF_CLOSING = re.compile(r'<[^>]+/>\s*$')
OPEN_TAG = re.compile(r'<[A-Za-z][A-Za-z0-9_.-]*[^>]*[^/\s]>')
CTRL_OPEN = re.compile(r'^\{(if|for|switch)\b')
CTRL_MID = re.compile(r'^\{(:else|:case)\b')
CTRL_CLOSE = re.compile(r'^\{(/(if|for|switch)|endif|endfor|endswitch|endcase)\b')
FRAGMENT_CLOSE = re.compile(r'^\s*</>')


def find_block_bounds(src):
    """Return list of (start, end) offsets for each zsx!{ ... } block.
    start = offset of 'z' in 'zsx!{'
    end = offset just after the matching '}'
    Skips strings, chars, comments."""
    blocks = []
    pos = 0
    n = len(src)
    while pos < n:
        c = src[pos]
        if c == '"':
            pos = _skip_string(src, pos)
            continue
        if c == "'":
            pos = _skip_char(src, pos)
            continue
        if c == '/' and pos + 1 < n and src[pos+1] == '/':
            while pos < n and src[pos] != '\n':
                pos += 1
            continue
        if c == '/' and pos + 1 < n and src[pos+1] == '*':
            end = src.find('*/', pos + 2)
            pos = end + 2 if end > 0 else n
            continue
        if c == 'z' and src[pos:pos+5] == 'zsx!{':
            brace_open = pos + 4  # position of '{'
            close = _find_matching_brace(src, brace_open)
            if close < 0:
                raise ValueError(f"unmatched zsx!{{ at offset {pos}")
            blocks.append((pos, close + 1))
            pos = close + 1
            continue
        pos += 1
    return blocks


def _skip_string(src, start):
    p = start + 1
    n = len(src)
    while p < n:
        if src[p] == '\\':
            p += 2
            continue
        if src[p] == '"':
            return p + 1
        p += 1
    return n


def _skip_char(src, start):
    p = start + 1
    n = len(src)
    while p < n:
        if src[p] == '\\':
            p += 2
            continue
        if src[p] == "'":
            return p + 1
        p += 1
    return n


def _find_matching_brace(src, open_pos):
    """open_pos points at '{'. Returns offset of matching '}' or -1."""
    depth = 0
    p = open_pos
    n = len(src)
    while p < n:
        c = src[p]
        if c == '"':
            p = _skip_string(src, p)
            continue
        if c == "'":
            p = _skip_char(src, p)
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return p
        p += 1
    return -1


def format_markup(markup, base_indent):
    """Reindent the markup body. `base_indent` is the indent of the
    `zsx!{` line (number of spaces before 'zsx')."""
    lines = markup.split('\n')
    out = []
    depth = base_indent // INDENT + 1  # body starts one level deeper
    first_nonempty_seen = False

    for raw in lines:
        stripped = raw.strip()
        if not stripped:
            out.append('')
            continue

        # Adjust depth for this line
        if CTRL_CLOSE.match(stripped) or FRAGMENT_CLOSE.match(stripped) or CLOSE_TAG.match(stripped):
            depth = max(base_indent // INDENT + 1, depth - 1)

        out.append(' ' * (depth * INDENT) + stripped)

        # Adjust depth for next line
        if CTRL_OPEN.match(stripped):
            depth += 1
        elif CTRL_MID.match(stripped):
            # e.g. {:else} closes prior {if} body, opens new body
            pass
        elif CTRL_CLOSE.match(stripped):
            pass  # already decremented
        elif stripped.startswith('<>'):
            depth += 1
        elif FRAGMENT_CLOSE.match(stripped):
            pass  # already decremented
        elif SELF_CLOSING.search(stripped):
            pass  # no depth change
        elif OPEN_TAG.search(stripped) and not stripped.rstrip().endswith('/>'):
            # Don't count open tags whose close is on same line (rare in .zsx)
            open_count = len(re.findall(r'<[A-Za-z][^>]*[^/\s]>(?!.*</)', stripped))
            close_count = len(re.findall(r'</[A-Za-z][^>]*>', stripped))
            depth += max(0, open_count - close_count)

        first_nonempty_seen = True

    # Strip leading / trailing empty lines
    while out and out[0] == '':
        out.pop(0)
    while out and out[-1] == '':
        out.pop()

    return '\n'.join(out)


def format_file(src):
    """Format a full .zsx source. Returns formatted source."""
    blocks = find_block_bounds(src)
    if not blocks:
        return src

    result = []
    prev_end = 0

    for (start, end) in blocks:
        # Copy everything up to the block
        result.append(src[prev_end:start])

        # Determine the indent of the line containing `zsx!{`
        line_start = src.rfind('\n', 0, start) + 1
        line_prefix = src[line_start:start]
        base_indent = len(line_prefix) - len(line_prefix.lstrip(' '))
        if line_prefix.strip() != '':
            # Something else on the same line as zsx!{ — leave alone
            result.append(src[start:end])
            prev_end = end
            continue

        # Extract the markup between `{` and matching `}`
        brace_open = start + 4
        brace_close = end - 1
        markup = src[brace_open + 1:brace_close]

        formatted = format_markup(markup, base_indent)
        result.append('zsx!{')
        if formatted:
            result.append('\n')
            result.append(formatted)
            result.append('\n' + ' ' * base_indent)
        result.append('}')
        prev_end = end

    result.append(src[prev_end:])
    return ''.join(result)


def main():
    args = sys.argv[1:]
    check_mode = '--check' in args
    write_mode = '--write' in args
    files = [a for a in args if not a.startswith('--')]

    if not files:
        files = []
        for root, _, filenames in os.walk('.'):
            if '/.git' in root or '/.zig-cache' in root:
                continue
            for fn in filenames:
                if fn.endswith('.zsx'):
                    files.append(os.path.join(root, fn))
        files.sort()

    if not files:
        print('zsx-fmt: no .zsx files found')
        return 0

    needs_format = []
    for f in files:
        try:
            with open(f) as fh:
                src = fh.read()
            formatted = format_file(src)
            if formatted != src:
                needs_format.append(f)
                if write_mode:
                    with open(f, 'w') as fh:
                        fh.write(formatted)
        except Exception as e:
            print(f'zsx-fmt: {f}: {e}', file=sys.stderr)
            return 2

    if check_mode:
        if needs_format:
            for f in needs_format:
                print(f'would format: {f}')
            return 1
        print('all formatted')
        return 0

    if write_mode:
        if needs_format:
            for f in needs_format:
                print(f'formatted: {f}')
        else:
            print('all formatted')
        return 0

    # Default = dry run: show which would change
    if needs_format:
        for f in needs_format:
            print(f'would format: {f}')
        print(f'\n{len(needs_format)} file(s) need formatting. Run with --write to apply.')
        return 0
    print('all formatted')
    return 0


if __name__ == '__main__':
    sys.exit(main())
