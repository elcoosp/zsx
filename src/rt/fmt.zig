//! Native `zsx fmt` — reformat the markup inside `zsx!{ ... }` blocks
//! (master-plan WP 1.6, first slice). Replaces `scripts/zsx-fmt.py`.
//!
//! Contract (identical to the deprecated Python tool):
//! - Zig code outside `zsx!{ }` blocks is preserved byte-for-byte;
//! - inside blocks, every line is stripped and re-indented to
//!   `indent * depth` spaces, where depth follows the structural tokens —
//!   one level per open tag, fragment, `{if}`/`{for}`/`{switch}` body;
//! - close tags, `{/if}`-style closers and fragments sit at the depth of
//!   their container; `{:else}`/`{:case}` stay at body depth;
//! - trailing whitespace disappears; leading/trailing blank lines inside a
//!   block are removed; interior blank lines are kept (as empty lines);
//! - idempotent: `fmt(fmt(x)) == fmt(x)`, because depth is derived from the
//!   CST, never from the file's current indentation;
//! - a block whose `zsx!{` shares a line with other code is left untouched
//!   (there is no unambiguous base indent).
//!
//! The old tool decided depth with regexes over raw lines; this one decides
//! on the CST from `cst.zig` (master-plan WP 1.6): nesting comes from the
//! tree, never from the file's current indentation. Malformed markup (the CST
//! reports diagnostics) falls back to the token scanner so `fmt` can still
//! normalize broken files. Either way the convention holds: decide on
//! tokens/AST, never substring/regex heuristics (finding F11).

const std = @import("std");
const checker = @import("checker.zig");
const cst = @import("cst.zig");
const diag = @import("diag.zig");

const preprocess = checker.preprocess;
const scan = checker.scan;

pub const Options = struct {
    /// Spaces per nesting level (the Python tool hard-coded 4).
    indent: usize = 4,
};

/// Format a whole `.zsx` source. Returns the formatted text; compare with the
/// input to implement `--check`, write it to implement `--write`.
pub fn formatSource(a: std.mem.Allocator, source: []const u8, opts: Options) ![]const u8 {
    const blocks = try preprocess.findBlocks(a, source);
    if (blocks.len == 0) return source;

    var out = std.array_list.Managed(u8).init(a);
    var prev_end: usize = 0;

    for (blocks) |block| {
        try out.appendSlice(source[prev_end..block.start]);
        prev_end = block.end;

        // Base indent = leading spaces on the line that holds `zsx!{`.
        const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..block.start], '\n')) |nl| nl + 1 else 0;
        const line_prefix = source[line_start..block.start];
        const base_indent = countLeadingSpaces(line_prefix);
        if (std.mem.trim(u8, line_prefix, " \t\r").len != 0) {
            // `zsx!{` shares its line with other code — leave the block alone.
            try out.appendSlice(source[block.start..block.end]);
            continue;
        }

        try out.appendSlice("zsx!{");
        if (block.closed) {
            const markup = source[block.start + 5 .. block.end - 1];
            const formatted = try formatMarkup(a, markup, base_indent, opts);
            if (formatted.len != 0) {
                try out.appendSlice("\n");
                try out.appendSlice(formatted);
                try out.appendSlice("\n");
                try out.appendNTimes(' ', base_indent);
            }
        }
        try out.appendSlice("}");
    }
    try out.appendSlice(source[prev_end..]);
    return out.items;
}

fn countLeadingSpaces(s: []const u8) usize {
    var n: usize = 0;
    while (n < s.len and s[n] == ' ') n += 1;
    return n;
}

/// Structural tokens that start on one markup line, plus whether the line is
/// blank. Only open/close/ctrl tokens are tracked — text, expressions and
/// junk never change depth.
const Line = struct {
    raw: []const u8,
    toks: []const scan.Token,
    blank: bool,
};

/// Reindent one block's markup. `base_indent` is the number of spaces before
/// `zsx!{` on its line; the first body level is one deeper than that.
///
/// Valid markup is formatted from the CST (structural depth per line).
/// Malformed markup keeps the old scanner-driven behaviour.
pub fn formatMarkup(a: std.mem.Allocator, markup: []const u8, base_indent: usize, opts: Options) ![]const u8 {
    const idx = diag.LineIndex.build(a, markup) catch return formatMarkupScan(a, markup, base_indent, opts);
    var list = diag.List.init(a);
    const root = cst.parse(a, markup, 0, "<fmt>", idx, &list) catch return formatMarkupScan(a, markup, base_indent, opts);
    if (list.count() != 0) return formatMarkupScan(a, markup, base_indent, opts);
    return formatMarkupCst(a, markup, base_indent, opts, root);
}

/// Nesting depth at a structural byte offset, derived from CST containment.
/// Returns null for text/expression lines and multiline-tag continuations:
/// those are preserved byte-exact, matching the legacy formatter.
fn cstDepthAt(node: cst.Node, base: usize, off: usize, src: []const u8) ?usize {
    switch (node.kind) {
        .block => {
            for (node.children) |c| {
                if (off >= c.span.off and off < c.span.end) return cstDepthAt(c, base + 1, off, src);
            }
            return null;
        },
        .element, .fragment, .control_if, .control_for, .control_switch => {
            if (off == node.span.off) return base;
            if (off < node.span.off or off >= node.span.end) return null;
            // Children own their closer line: recurse first so a nested
            // `</Card>` is attributed to the inner Card.
            for (node.children) |c| {
                if (off < c.span.off or off >= c.span.end) continue;
                if (c.kind == .control_close and off == c.span.off) return base;
                if (cstDepthAt(c, base + 1, off, src)) |d| return d;
            }
            // No child owns it: this node's own closer sits at its depth.
            if (isOwnCloser(node, off, src)) return base;
            return null;
        },
        .branch => return if (off == node.span.off) base else null,
        .text, .expression, .control_close, .error_token => return null,
    }
}

fn isOwnCloser(node: cst.Node, off: usize, src: []const u8) bool {
    const rest = src[off..];
    switch (node.kind) {
        .element, .fragment => {
            if (!std.mem.startsWith(u8, rest, "</")) return false;
            const after = rest[2..];
            const end = std.mem.indexOfScalar(u8, after, '>') orelse return false;
            return std.mem.eql(u8, after[0..end], node.tag);
        },
        .control_if, .control_for, .control_switch => {
            if (!std.mem.startsWith(u8, rest, "{/")) return false;
            const after = rest[2..];
            const end = std.mem.indexOfScalar(u8, after, '}') orelse return false;
            const want = switch (node.kind) {
                .control_if => "if",
                .control_for => "for",
                .control_switch => "switch",
                else => unreachable,
            };
            return std.mem.eql(u8, after[0..end], want);
        },
        else => return false,
    }
}

fn formatMarkupCst(
    a: std.mem.Allocator,
    markup: []const u8,
    base_indent: usize,
    opts: Options,
    root: cst.Node,
) ![]const u8 {
    const base_level = base_indent / opts.indent;
    var lines = std.array_list.Managed(Line).init(a);
    var it = std.mem.splitScalar(u8, markup, '\n');
    var line_start: usize = 0;
    while (it.next()) |raw| {
        try lines.append(.{
            .raw = raw,
            .toks = &.{},
            .blank = std.mem.trim(u8, raw, " \t\r").len == 0,
        });
        line_start += raw.len + 1;
    }

    var emitted = try a.alloc([]const u8, lines.items.len);
    line_start = 0;
    for (lines.items, 0..) |line, li| {
        defer line_start += line.raw.len + 1;
        if (line.blank) {
            emitted[li] = "";
            continue;
        }
        var lead: usize = 0;
        while (lead < line.raw.len and (line.raw[lead] == ' ' or line.raw[lead] == '\t')) lead += 1;
        const off = line_start + lead;
        const depth = cstDepthAt(root, base_level, off, markup) orelse {
            emitted[li] = line.raw;
            continue;
        };

        var buf = std.array_list.Managed(u8).init(a);
        try buf.appendNTimes(' ', depth * opts.indent);
        try buf.appendSlice(std.mem.trim(u8, line.raw, " \t\r"));
        emitted[li] = buf.items;
    }

    var start: usize = 0;
    var end: usize = emitted.len;
    while (start < end and lines.items[start].blank) start += 1;
    while (end > start and lines.items[end - 1].blank) end -= 1;

    var kept = std.array_list.Managed(u8).init(a);
    for (emitted[start..end], 0..) |l, i| {
        if (i != 0) try kept.appendSlice("\n");
        try kept.appendSlice(l);
    }
    return kept.items;
}

fn formatMarkupScan(a: std.mem.Allocator, markup: []const u8, base_indent: usize, opts: Options) ![]const u8 {
    var scanner = scan.Scanner.init(a, markup, 0);
    const toks = try scanner.run();

    const line_count = std.mem.count(u8, markup, "\n") + 1;
    var per_line = try a.alloc(std.array_list.Managed(scan.Token), line_count);
    for (per_line) |*l| l.* = std.array_list.Managed(scan.Token).init(a);
    for (toks) |t| {
        if (t == .text or t == .expression or t == .junk) continue;
        const ln = std.mem.count(u8, markup[0..t.off()], "\n");
        try per_line[ln].append(t);
    }

    var lines = std.array_list.Managed(Line).init(a);
    {
        var it = std.mem.splitScalar(u8, markup, '\n');
        var idx: usize = 0;
        while (it.next()) |raw| : (idx += 1) {
            try lines.append(.{
                .raw = raw,
                .toks = per_line[idx].items,
                .blank = std.mem.trim(u8, raw, " \t\r").len == 0,
            });
        }
    }

    const base_level = base_indent / opts.indent;
    var depth: usize = base_level + 1;

    var emitted = try a.alloc([]const u8, lines.items.len);
    for (lines.items, 0..) |line, li| {
        if (line.blank) {
            emitted[li] = "";
            continue;
        }

        // A continuation line of a multi-line opening tag carries no token
        // start of its own; leave it byte-exact instead of crashing.
        if (line.toks.len == 0) {
            emitted[li] = line.raw;
            continue;
        }

        const first = line.toks[0];
        if (first == .close_tag or first == .ctrl_close) {
            depth = if (depth > base_level + 1) depth - 1 else base_level + 1;
        }

        var buf = std.array_list.Managed(u8).init(a);
        try buf.appendNTimes(' ', depth * opts.indent);
        try buf.appendSlice(std.mem.trim(u8, line.raw, " \t\r"));
        emitted[li] = buf.items;

        switch (first) {
            .ctrl_open => depth += 1,
            .ctrl_mid, .ctrl_close => {},
            .open_tag => |ot| {
                if (ot.tag.len == 0) {
                    depth += 1; // fragment `<>`
                } else if (!ot.self_closing) {
                    depth += openMinusClose(line.toks);
                }
            },
            .close_tag => {},
            else => {},
        }
    }

    // Strip leading/trailing blank lines.
    var start: usize = 0;
    var end: usize = emitted.len;
    while (start < end and lines.items[start].blank) start += 1;
    while (end > start and lines.items[end - 1].blank) end -= 1;

    var kept = std.array_list.Managed(u8).init(a);
    for (emitted[start..end], 0..) |l, i| {
        if (i != 0) try kept.appendSlice("\n");
        try kept.appendSlice(l);
    }
    return kept.items;
}

/// Python-parity line delta for a non-self-closing open tag: count opens not
/// followed by a close on the same line, minus the closes on the line. A
/// paired `<label>x</label>` therefore nets zero.
fn openMinusClose(toks: []const scan.Token) usize {
    var open_count: usize = 0;
    for (toks) |t| {
        if (t != .open_tag) continue;
        const o = t.open_tag;
        if (o.self_closing or o.tag.len == 0) continue;
        var suppressed = false;
        for (toks) |t2| {
            if (t2 != .close_tag) continue;
            if (t2.close_tag.tag.len == 0) continue;
            if (t2.off() > o.off) suppressed = true;
        }
        if (!suppressed) open_count += 1;
    }
    var close_count: usize = 0;
    for (toks) |t| {
        if (t == .close_tag and t.close_tag.tag.len != 0) close_count += 1;
    }
    return if (open_count > close_count) open_count - close_count else 0;
}

// -- tests ---------------------------------------------------------------

const testing = std.testing;

fn fmtEquals(a: std.mem.Allocator, src: []const u8, want: []const u8) !void {
    const got = try formatSource(a, src, .{});
    try testing.expectEqualStrings(want, got);
}

test "fmt: single line block gets canonical body indent" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try fmtEquals(arena.allocator(),
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{<label>x</label>}
        \\}
    ,
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{
        \\        <label>x</label>
        \\    }
        \\}
    );
}

test "fmt: mangled indentation normalizes to 4-space levels" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try fmtEquals(arena.allocator(),
        \\zsx!{
        \\  <column>
        \\      <label>hi</label>
        \\ </column>
        \\}
    ,
        \\zsx!{
        \\    <column>
        \\        <label>hi</label>
        \\    </column>
        \\}
    );
}

test "fmt: control flow indents bodies and keeps mid at body depth" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try fmtEquals(arena.allocator(),
        \\zsx!{
        \\{if ctx.a}
        \\<label>A</label>
        \\{:else if ctx.b}
        \\<label>B</label>
        \\{:else}
        \\<label>C</label>
        \\{/if}
        \\}
    ,
        \\zsx!{
        \\    {if ctx.a}
        \\        <label>A</label>
        \\        {:else if ctx.b}
        \\        <label>B</label>
        \\        {:else}
        \\        <label>C</label>
        \\    {/if}
        \\}
    );
}

test "fmt: paired open+close on one line nets zero depth" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try fmtEquals(arena.allocator(),
        \\zsx!{
        \\<row>
        \\    <label>a</label>
        \\    <label>b</label>
        \\</row>
        \\}
    ,
        \\zsx!{
        \\    <row>
        \\        <label>a</label>
        \\        <label>b</label>
        \\    </row>
        \\}
    );
}

test "fmt: fragments indent like containers" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try fmtEquals(arena.allocator(),
        \\zsx!{
        \\<>
        \\<label>x</label>
        \\</>
        \\}
    ,
        \\zsx!{
        \\    <>
        \\        <label>x</label>
        \\    </>
        \\}
    );
}

test "fmt: blank lines collapse to empty; edges are stripped" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try fmtEquals(arena.allocator(),
        \\zsx!{
        \\
        \\<label>x</label>
        \\
        \\
        \\<label>y</label>
        \\
        \\}
    ,
        \\zsx!{
        \\    <label>x</label>
        \\
        \\
        \\    <label>y</label>
        \\}
    );
}

test "fmt: zig outside blocks is byte-exact, including strings and comments" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const src =
        \\const s = "zsx!{ <label>not touched</label> }";
        \\// zsx!{ <label>still not touched</label> }
        \\fn f() void {
        \\    zsx!{
        \\        <label>ok</label>
        \\    }
        \\}
    ;
    const got = try formatSource(arena.allocator(), src, .{});
    try testing.expectEqualStrings(src, got);
}

test "fmt: block sharing a line with code is untouched" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const src = "const v = zsx!{<label>x</label>};\n";
    const got = try formatSource(arena.allocator(), src, .{});
    try testing.expectEqualStrings(src, got);
}

test "fmt: idempotent on a mangled fixture" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const mangled =
        \\zsx!{
        \\   <column class="gap-2">
        \\  {for ctx.items as item}
        \\        <label>{item}</label>
        \\   {/for}
        \\  </column>
        \\}
    ;
    const once = try formatSource(arena.allocator(), mangled, .{});
    const twice = try formatSource(arena.allocator(), once, .{});
    try testing.expectEqualStrings(once, twice);
    try fmtEquals(arena.allocator(), mangled,
        \\zsx!{
        \\    <column class="gap-2">
        \\        {for ctx.items as item}
        \\            <label>{item}</label>
        \\        {/for}
        \\    </column>
        \\}
    );
}

test "fmt: self-closing tags do not change depth" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try fmtEquals(arena.allocator(),
        \\zsx!{
        \\<row>
        \\<Input buffer={&ctx.name} />
        \\</row>
        \\}
    ,
        \\zsx!{
        \\    <row>
        \\        <Input buffer={&ctx.name} />
        \\    </row>
        \\}
    );
}

test "fmt: multiline control openers stay idempotent" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "<row>{if\nctx.flag}{ctx.value}{/if}{for ctx.items as\nitem}{item}{/for}</row>";
    const once = try formatMarkup(a, src, 0, .{});
    const twice = try formatMarkup(a, once, 0, .{});
    try std.testing.expectEqualStrings(once, twice);
    const third = try formatMarkup(a, twice, 0, .{});
    try std.testing.expectEqualStrings(twice, third);
}
