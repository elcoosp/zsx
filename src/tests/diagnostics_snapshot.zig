//! Diagnostic snapshot suite (M1 WP 1.8).
//!
//! Every diagnostic code in the contract is rendered four times (context
//! 0..3) against a small source, then compared with
//! `spec/diagnostics/snapshots.txt`. To update deliberately, delete the
//! snapshot file and run `zig build test`; inspect the diff before
//! committing. The point is to pin header, help, gutter, caret and
//! context-window quality, not merely to freeze output.

const std = @import("std");
const diag = @import("../rt/diag.zig");
const checker = @import("../rt/checker.zig");
const render = @import("../rt/render.zig");

const Case = struct {
    name: []const u8,
    src: []const u8,
    code: diag.Code,
};

const cases = [_]Case{
    .{ .name = "stray-close-tag", .src = "zsx!{\n<column>\n</row>\n</column>\n}", .code = .stray_close_tag },
    .{ .name = "tag-mismatch", .src = "zsx!{\n<row>\n</column>\n}", .code = .tag_mismatch },
    .{ .name = "unclosed-tag", .src = "zsx!{\n<column>\n<label>x</label>\n}", .code = .unclosed_tag },
    .{ .name = "stray-ctrl-close", .src = "zsx!{\n<column>\n{/if}\n</column>\n}", .code = .stray_ctrl_close },
    .{ .name = "ctrl-mismatch", .src = "zsx!{\n<column>\n{if ctx.a}\n<label>x</label>\n{/for}\n</column>\n}", .code = .ctrl_mismatch },
    .{ .name = "unclosed-ctrl", .src = "zsx!{\n<column>\n{if ctx.a}\n<label>x</label>\n</column>\n}", .code = .unclosed_ctrl },
    .{ .name = "misplaced-else", .src = "zsx!{\n<column>\n{:else}\n<label>x</label>\n</column>\n}", .code = .misplaced_else },
    .{ .name = "misplaced-case", .src = "zsx!{\n<column>\n{if ctx.a}\n{:case 1}\n{/if}\n</column>\n}", .code = .misplaced_case },
    .{ .name = "unknown-class", .src = "zsx!{\n<column class=\"not-a-zsx-class\">\n<label>x</label>\n</column>\n}", .code = .unknown_class },
    .{ .name = "legacy-alias", .src = "zsx!{\n<column>\n{if ctx.a}\n<label>x</label>\n{endif}\n</column>\n}", .code = .legacy_alias },
    .{ .name = "unterminated-block", .src = "zsx!{\n<label>x</label>\n", .code = .unterminated_block },
    .{ .name = "junk-syntax", .src = "zsx!{\n<column>\n< label>x</label>\n</column>\n}", .code = .junk_syntax },
    .{ .name = "unknown-prop", .src = "zsx!{\n<Button varient=\"primary\">x</Button>\n}", .code = .unknown_prop },
    .{ .name = "multiple-roots", .src = "zsx!{\n<label>a</label>\n<label>b</label>\n}", .code = .multiple_roots },
    .{ .name = "stray-top-level", .src = "zsx!{\ntext\n<label>x</label>\n}", .code = .stray_top_level },
    .{ .name = "missing-root", .src = "zsx!{\n   \n}", .code = .missing_root },
    .{ .name = "unused-binding", .src = "zsx!{\n<column>\n{for ctx.items as item}\n<label>x</label>\n{/for}\n</column>\n}", .code = .unused_binding },
    .{ .name = "empty-for-body", .src = "zsx!{\n<column>\n{for ctx.items as _it}\n{/for}\n</column>\n}", .code = .empty_for_body },
    .{ .name = "text-in-layout-container", .src = "zsx!{\n<column>\nstray\n</column>\n}", .code = .text_in_layout_container },
};

const contexts = [_]usize{ 0, 1, 2, 3 };

fn read(a: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
}

fn build(a: std.mem.Allocator) ![]u8 {
    var out = std.array_list.Managed(u8).init(a);
    for (cases) |c| {
        var list = diag.List.init(a);
        try checker.checkSource(a, c.src, "snap.zsx", .{}, &list);
        var found = false;
        for (list.items.items) |d| if (d.code == c.code) {
            found = true;
        };
        if (!found) {
            std.debug.print("diagnostics snapshot: {s} did not emit ZSX{d:0>4}\n", .{ c.name, c.code.number() });
            return error.TestUnexpected;
        }
        var r = try render.Renderer.init(a, c.src);
        for (contexts) |ctx| {
            try out.appendSlice(try std.fmt.allocPrint(a, "=== {s} context={d} ===\n", .{ c.name, ctx }));
            for (list.items.items) |d| {
                try out.appendSlice(try r.render(d, .{ .context = ctx }));
                try out.append('\n');
            }
        }
    }
    return out.toOwnedSlice();
}

test "diagnostic snapshots: every code renders with stable frames" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const actual = try build(a);
    const path = "spec/diagnostics/snapshots.txt";
    const expected = read(a, path) catch |e| switch (e) {
        error.FileNotFound => {
            try std.Io.Dir.cwd().createDirPath(std.testing.io, "spec/diagnostics");
            const f = try std.Io.Dir.cwd().createFile(std.testing.io, path, .{ .truncate = true });
            defer f.close(std.testing.io);
            try f.writeStreamingAll(std.testing.io, actual);
            return;
        },
        else => return e,
    };
    try std.testing.expectEqualStrings(expected, actual);
}
