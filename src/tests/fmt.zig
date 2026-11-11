//! Native formatter corpus tests (M2). The committed views are canonical
//! output of the deprecated Python formatter; the native formatter must
//! reproduce them byte-for-byte (`fmt(x) == x`). If a rule change starts
//! reformatting the corpus, this suite fails before CI's `zsx fmt --check`
//! does, with the offending file named.

const std = @import("std");
const fmt = @import("../rt/fmt.zig");

const corpus = [_]struct { name: []const u8, src: []const u8 }{
    .{ .name = "demo", .src = @embedFile("../views/demo.zsx") },
    .{ .name = "component_demo", .src = @embedFile("../views/component_demo.zsx") },
    .{ .name = "shadcn_demo", .src = @embedFile("../views/shadcn_demo.zsx") },
    .{ .name = "shadcn_lib_demo", .src = @embedFile("../views/shadcn_lib_demo.zsx") },
    .{ .name = "onclick_demo", .src = @embedFile("../views/onclick_demo.zsx") },
    .{ .name = "struct_loop_demo", .src = @embedFile("../views/struct_loop_demo.zsx") },
    .{ .name = "card_if_demo", .src = @embedFile("../views/card_if_demo.zsx") },
    .{ .name = "else_if_demo", .src = @embedFile("../views/else_if_demo.zsx") },
    .{ .name = "fragment_demo", .src = @embedFile("../views/fragment_demo.zsx") },
    .{ .name = "class_override_demo", .src = @embedFile("../views/class_override_demo.zsx") },
    .{ .name = "nested_card_demo", .src = @embedFile("../views/nested_card_demo.zsx") },
    .{ .name = "dashboard", .src = @embedFile("../views/dashboard.zsx") },
    .{ .name = "input_demo", .src = @embedFile("../views/input_demo.zsx") },
    .{ .name = "playground", .src = @embedFile("../views/playground.zsx") },
    .{ .name = "component_lib_demo", .src = @embedFile("../views/component_lib_demo.zsx") },
    .{ .name = "extended_styles_demo", .src = @embedFile("../views/extended_styles_demo.zsx") },
    .{ .name = "path_demo", .src = @embedFile("../views/path_demo.zsx") },
    .{ .name = "switch_demo", .src = @embedFile("../views/switch_demo.zsx") },
    .{ .name = "slots_demo", .src = @embedFile("../views/slots_demo.zsx") },
    .{ .name = "components_demo", .src = @embedFile("../views/components_demo.zsx") },
};

test "fmt: committed corpus is already canonical (byte-for-byte)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (corpus) |c| {
        const got = try fmt.formatSource(a, c.src, .{});
        if (!std.mem.eql(u8, got, c.src)) {
            std.debug.print("fmt corpus: {s} would change\n", .{c.name});
            const n = @min(got.len, c.src.len);
            var i: usize = 0;
            while (i < n and got[i] == c.src[i]) i += 1;
            const line = std.mem.count(u8, c.src[0..i], "\n") + 1;
            std.debug.print("fmt corpus: first difference at line {d}\n", .{line});
            return error.TestUnexpected;
        }
    }
}

test "fmt: corpus is idempotent" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (corpus) |c| {
        const once = try fmt.formatSource(a, c.src, .{});
        const twice = try fmt.formatSource(a, once, .{});
        try std.testing.expectEqualStrings(once, twice);
    }
}
