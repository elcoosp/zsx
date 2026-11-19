//! M1 WP 1.5: CST → AST lowering dumps (`spec/ast/*.txt`).
//!
//! Dumps are the reviewable contract between the CST (spans, recovery) and
//! the flat AST codegen consumes. Add a `.zsx`/`.txt` pair and an entry.

const std = @import("std");
const ast = @import("../rt/parser.zig");
const astdump = @import("../rt/astdump.zig");
const cst = @import("../rt/cst.zig");
const diag = @import("../rt/diag.zig");

const Case = struct { name: []const u8 };

const cases = [_]Case{
    .{ .name = "basic" },
    .{ .name = "control" },
    .{ .name = "attrs" },
    .{ .name = "whitespace" },
};

fn read(a: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
}

fn lower(a: std.mem.Allocator, src: []const u8) !ast.Element {
    const idx = try diag.LineIndex.build(a, src);
    var list = diag.List.init(a);
    const root = try cst.parse(a, src, 0, "ast.zsx", idx, &list);
    try std.testing.expectEqual(@as(usize, 0), list.count());
    return cst.lowerBlock(a, root);
}

test "lowered AST dump matches spec/ast goldens" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (cases) |c| {
        const src = try read(a, try std.fmt.allocPrint(a, "spec/ast/{s}.zsx", .{c.name}));
        const expected = try read(a, try std.fmt.allocPrint(a, "spec/ast/{s}.txt", .{c.name}));
        const actual = try astdump.dump(a, try lower(a, src));
        try std.testing.expectEqualStrings(expected, actual);
    }
}

test "lowering rejects non-element roots" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try std.testing.expectError(error.MultipleRoots, lower(a, "<a></a><b></b>"));
    try std.testing.expectError(error.StrayTopLevel, lower(a, "text<b></b>"));
    try std.testing.expectError(error.NoRoot, lower(a, "  \n  "));
}
