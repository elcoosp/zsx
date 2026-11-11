//! M1 lossless front-end tests (master-plan spikes S1 + S2).
//!
//! The lossless front-end (`src/rt/lossless.zig`) partitions a `.zsx` file
//! into typed, byte-exact segments: Zig text, string and char literals,
//! line/block comments and `zsx!{ }` blocks. Two properties matter:
//!
//! 1. **S2 (lossless emission):** `Document.render` reproduces the source
//!    byte-for-byte. This is the guarantee the future CST parser and
//!    RFC-0001 grammar v1 build on — tooling can rewrite markup spans while
//!    every byte outside them survives untouched.
//! 2. **S1 (Zig-side parsing):** `zsx!{` detection shares one scanner with
//!    strings, chars and comments, so a block opener inside a literal or
//!    comment is never mistaken for a block. `preprocess.findBlocks` is
//!    re-expressed on top of this scanner (one front-end, not two drifting
//!    copies — master-plan finding F11).
//!
//! Fixtures include every committed view under `src/views/` so the
//! round-trip property is checked against real corpus, not only synthetic
//! edge cases.

const std = @import("std");
const lossless = @import("../rt/lossless.zig");
const preprocess = @import("../rt/preprocess.zig");

/// Every committed view, paired with its `@embedFile` source. Keep in sync
/// with the `zsx_files` list in `build.zig`.
const views = [_]struct { name: []const u8, src: []const u8 }{
    .{ .name = "demo.zsx", .src = @embedFile("../views/demo.zsx") },
    .{ .name = "component_demo.zsx", .src = @embedFile("../views/component_demo.zsx") },
    .{ .name = "shadcn_demo.zsx", .src = @embedFile("../views/shadcn_demo.zsx") },
    .{ .name = "shadcn_lib_demo.zsx", .src = @embedFile("../views/shadcn_lib_demo.zsx") },
    .{ .name = "onclick_demo.zsx", .src = @embedFile("../views/onclick_demo.zsx") },
    .{ .name = "struct_loop_demo.zsx", .src = @embedFile("../views/struct_loop_demo.zsx") },
    .{ .name = "card_if_demo.zsx", .src = @embedFile("../views/card_if_demo.zsx") },
    .{ .name = "else_if_demo.zsx", .src = @embedFile("../views/else_if_demo.zsx") },
    .{ .name = "fragment_demo.zsx", .src = @embedFile("../views/fragment_demo.zsx") },
    .{ .name = "class_override_demo.zsx", .src = @embedFile("../views/class_override_demo.zsx") },
    .{ .name = "nested_card_demo.zsx", .src = @embedFile("../views/nested_card_demo.zsx") },
    .{ .name = "dashboard.zsx", .src = @embedFile("../views/dashboard.zsx") },
    .{ .name = "input_demo.zsx", .src = @embedFile("../views/input_demo.zsx") },
    .{ .name = "playground.zsx", .src = @embedFile("../views/playground.zsx") },
    .{ .name = "component_lib_demo.zsx", .src = @embedFile("../views/component_lib_demo.zsx") },
    .{ .name = "extended_styles_demo.zsx", .src = @embedFile("../views/extended_styles_demo.zsx") },
    .{ .name = "path_demo.zsx", .src = @embedFile("../views/path_demo.zsx") },
    .{ .name = "switch_demo.zsx", .src = @embedFile("../views/switch_demo.zsx") },
    .{ .name = "slots_demo.zsx", .src = @embedFile("../views/slots_demo.zsx") },
    .{ .name = "components_demo.zsx", .src = @embedFile("../views/components_demo.zsx") },
};

test "lossless: render round-trips synthetic edge cases byte-for-byte" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fixtures = [_][]const u8{
        // No blocks at all: pure Zig passes through as one zig_text segment.
        "const std = @import(\"std\");\npub fn view() void {}\n",
        // One block with nested braces, strings and control flow.
        "pub fn view(ui: anytype, c: anytype, ctx: anytype) void {\n" ++
            "    zsx!{\n" ++
            "        <column class=\"gap-2\">\n" ++
            "            {if ctx.show}<label>{ctx.name}</label>{:else}<row></row>{/if}\n" ++
            "            {for ctx.items as item}<input buffer={&item.value} />{/for}\n" ++
            "        </column>\n" ++
            "    }\n" ++
            "}\n",
        // A block opener inside a string literal is not a block.
        "const s = \"zsx!{ <label>not markup</label> }\";\n",
        // A block opener inside comments is not a block.
        "// zsx!{ <label>nope</label> }\n/* zsx!{ <row></row> } */\n",
        // Braces inside string and char literals never confuse the scanner.
        "const c = '}'; const s = \"}{\";\nzsx!{ <label>{\"}\"}</label> }\n",
        // Unterminated block: closed=false, tail still renders exactly.
        "pub fn f() void { zsx!{\n    <label>oops\n",
        // A quote inside a block comment must not open a string.
        "/* \" */ const s = \"after\";\nzsx!{ <row></row> }\n",
        // Empty and single-byte sources.
        "",
        ";",
    };

    for (fixtures, 0..) |src, i| {
        const doc = try lossless.Document.init(a, src);
        const out = try doc.render(a);
        std.testing.expectEqualStrings(src, out) catch |e| {
            std.debug.print("lossless: fixture {d} round-trip mismatch\n", .{i});
            return e;
        };
    }
}

test "lossless: segments partition the source exactly" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fixtures = [_][]const u8{
        "const x = 1;\nzsx!{ <label>hi</label> }\nconst y = 2;\n",
        "const s = \"zsx!{ fake }\";\nzsx!{ <row></row> }\n// zsx!{ fake }\n",
        "zsx!{ <label>a</label> };\nzsx!{ <label>b</label> }",
    };
    for (fixtures) |src| {
        const doc = try lossless.Document.init(a, src);
        try std.testing.expect(doc.segs.len > 0);
        try std.testing.expectEqual(@as(usize, 0), doc.segs[0].off);
        var covered: usize = 0;
        for (doc.segs, 0..) |seg, i| {
            // Contiguous, ordered, non-overlapping coverage of [0, src.len).
            try std.testing.expectEqual(covered, seg.off);
            try std.testing.expect(seg.end > seg.off);
            covered = seg.end;
            if (i + 1 == doc.segs.len) try std.testing.expectEqual(src.len, seg.end);
        }
    }
}

test "lossless: classifies segments (strings, comments, blocks)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src =
        \\const s = "zsx!{ fake }";
        \\// zsx!{ line-comment fake }
        \\/* zsx!{ block-comment fake } */
        \\const ch = '}';
        \\zsx!{ <label>real</label> }
    ;
    const doc = try lossless.Document.init(a, src);

    var strings: usize = 0;
    var line_comments: usize = 0;
    var block_comments: usize = 0;
    var char_literals: usize = 0;
    var blocks: usize = 0;
    for (doc.segs) |seg| switch (seg.kind) {
        .string => strings += 1,
        .line_comment => line_comments += 1,
        .block_comment => block_comments += 1,
        .char_literal => char_literals += 1,
        .zsx_block => blocks += 1,
        .zig_text => {},
    };
    try std.testing.expectEqual(@as(usize, 1), strings);
    try std.testing.expectEqual(@as(usize, 1), line_comments);
    try std.testing.expectEqual(@as(usize, 1), block_comments);
    try std.testing.expectEqual(@as(usize, 1), char_literals);
    try std.testing.expectEqual(@as(usize, 1), blocks);

    // The one real block spans exactly the `zsx!{ … }` run.
    const blk = doc.blocks[0];
    try std.testing.expect(blk.closed);
    try std.testing.expectEqualStrings("zsx!{ <label>real</label> }", src[blk.start..blk.end]);
    try std.testing.expectEqualStrings(" <label>real</label> ", doc.markup(blk));
}

test "lossless: unterminated block keeps tail, closed=false" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "pub fn f() void { zsx!{\n    <label>oops\n";
    const doc = try lossless.Document.init(a, src);
    try std.testing.expectEqual(@as(usize, 1), doc.blocks.len);
    const blk = doc.blocks[0];
    try std.testing.expect(!blk.closed);
    try std.testing.expectEqual(src.len, blk.end);
    // Markup runs from just after `zsx!{` to end of source (no closing
    // brace to exclude).
    try std.testing.expectEqualStrings("\n    <label>oops\n", doc.markup(blk));
    // And the whole source still round-trips.
    try std.testing.expectEqualStrings(src, try doc.render(a));
}

test "lossless: round-trips every committed view byte-for-byte" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    for (views) |v| {
        const doc = try lossless.Document.init(a, v.src);
        const out = try doc.render(a);
        std.testing.expectEqualStrings(v.src, out) catch |e| {
            std.debug.print("lossless: view {s} round-trip mismatch\n", .{v.name});
            return e;
        };
        try std.testing.expect(v.src.len > 0);
    }
}

test "lossless: block detection matches preprocess.findBlocks on every view" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    for (views) |v| {
        const doc = try lossless.Document.init(a, v.src);
        const legacy = try preprocess.findBlocks(a, v.src);
        try std.testing.expectEqual(legacy.len, doc.blocks.len);
        for (legacy, doc.blocks) |lb, nb| {
            try std.testing.expectEqual(lb.start, nb.start);
            try std.testing.expectEqual(lb.end, nb.end);
            try std.testing.expectEqual(lb.closed, nb.closed);
        }
    }
}

test "lossless: markup agrees with the checker's slice convention" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // checker.zig reads markup as source[block.start + 5 .. block.end - 1]
    // for closed blocks; Document.markup must produce the same bytes.
    const src = "zsx!{\n  <column class=\"p-4\"><label>x</label></column>\n}\n";
    const doc = try lossless.Document.init(a, src);
    try std.testing.expectEqual(@as(usize, 1), doc.blocks.len);
    const blk = doc.blocks[0];
    try std.testing.expectEqualStrings(src[blk.start + 5 .. blk.end - 1], doc.markup(blk));
}

test "lossless: multiple blocks and trailing semicolons" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "zsx!{ <label>a</label> };\nzsx!{ <label>b</label> };\n";
    const doc = try lossless.Document.init(a, src);
    try std.testing.expectEqual(@as(usize, 2), doc.blocks.len);
    try std.testing.expectEqualStrings(" <label>a</label> ", doc.markup(doc.blocks[0]));
    try std.testing.expectEqualStrings(" <label>b</label> ", doc.markup(doc.blocks[1]));
    try std.testing.expectEqualStrings(src, try doc.render(a));
}

test "lossless: render allocates fresh bytes, not an alias" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "zsx!{ <row></row> }";
    const doc = try lossless.Document.init(a, src);
    const out = try doc.render(a);
    try std.testing.expectEqualStrings(src, out);
    // Mutating the copy must not touch the source (render re-assembles
    // segment slices into new storage).
    @constCast(out)[0] = 'Z';
    try std.testing.expectEqual(@as(u8, 'z'), src[0]);
}
