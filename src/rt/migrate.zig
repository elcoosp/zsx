//! `zsx migrate` codemod: rewrite pre-0.3 markup to the current syntax
//! (master-plan WP 2.11).
//!
//! Only transformations the current compiler actually supports are applied:
//!
//! * event attributes `on_click=` → `on:click=` (also `change`, `input`,
//!   `submit`, `key`, `focus`, `blur`, `hover`, `drag`), and
//! * legacy control-flow closers `{endif}` / `{endfor}` / `{endswitch}` →
//!   `{/if}` / `{/for}` / `{/switch}`.
//!
//! `<label>` → `<text>` is intentionally *not* rewritten yet: `<text>` is not
//! an intrinsic tag in this compiler, so the codemod would produce views that
//! no longer build. It lands with the rename in RFC-0001.
//!
//! Edits are located with the tolerant scanner (token offsets, never
//! substrings) and applied to the original bytes, so the Zig side and all
//! untouched markup stay byte-exact.

const std = @import("std");
const scan = @import("scan.zig");
const lossless = @import("lossless.zig");

const Edit = struct { off: usize, len: usize, text: []const u8 };

const event_suffixes = [_][]const u8{ "click", "change", "input", "submit", "key", "focus", "blur", "hover", "drag" };

fn isLegacyEvent(name: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, name, "on_")) return null;
    const suffix = name[3..];
    for (event_suffixes) |ev| {
        if (std.mem.eql(u8, ev, suffix)) return suffix;
    }
    return null;
}

/// Rewrite `source`. Returns the original slice when nothing matched (no
/// allocation), otherwise a new buffer owned by `a`.
pub fn migrate(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    const doc = try lossless.Document.init(a, source);
    var edits = std.array_list.Managed(Edit).init(a);

    for (doc.blocks) |blk| {
        if (!blk.closed) continue;
        var scanner = scan.Scanner.init(a, doc.markup(blk), blk.markup_off);
        const toks = try scanner.run();
        for (toks) |t| switch (t) {
            .open_tag => |ot| for (ot.attrs) |attr| {
                const suffix = isLegacyEvent(attr.name) orelse continue;
                const text = try std.fmt.allocPrint(a, "on:{s}", .{suffix});
                try edits.append(.{ .off = attr.off, .len = attr.name.len, .text = text });
            },
            .ctrl_close => |cc| if (cc.legacy) {
                const text = try std.fmt.allocPrint(a, "{{/{s}}}", .{scan.ctrlName(cc.kind)});
                try edits.append(.{ .off = cc.off, .len = cc.end - cc.off, .text = text });
            },
            else => {},
        };
    }

    if (edits.items.len == 0) return source;

    std.mem.sort(Edit, edits.items, {}, struct {
        fn lt(_: void, x: Edit, y: Edit) bool {
            return x.off < y.off;
        }
    }.lt);

    var out = std.array_list.Managed(u8).init(a);
    var cursor: usize = 0;
    for (edits.items) |e| {
        if (e.off < cursor) continue; // never overlap; defensive
        try out.appendSlice(source[cursor..e.off]);
        try out.appendSlice(e.text);
        cursor = e.off + e.len;
    }
    try out.appendSlice(source[cursor..]);
    return out.toOwnedSlice();
}

test "migrate: rewrites event attributes and legacy closers" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src =
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    const keep = 1;
        \\    zsx!{
        \\        <Button on_click={ctx.save()}>Save</Button>
        \\        {if ctx.ok}
        \\            <label>x</label>
        \\        {endif}
        \\        {for ctx.items as item}
        \\            <label>{item}</label>
        \\        {endfor}
        \\    }
        \\    _ = keep;
        \\}
        \\
    ;
    const out = try migrate(a, src);
    try std.testing.expect(std.mem.indexOf(u8, out, "on:click") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "on_click") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "{/if}") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "{/for}") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "{endif}") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "const keep = 1;") != null);
}

test "migrate: idempotent and leaves current syntax alone" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src =
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{
        \\        <Button on:click={ctx.save()} on:change={ctx.swap()}>Save</Button>
        \\    }
        \\}
        \\
    ;
    const once = try migrate(a, src);
    try std.testing.expectEqualStrings(src, once);
}

test "migrate: unrelated on_ props are not treated as events" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src =
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{
        \\        <Widget on_ready={ctx.ready()}>x</Widget>
        \\    }
        \\}
        \\
    ;
    const out = try migrate(a, src);
    try std.testing.expectEqualStrings(src, out);
}
