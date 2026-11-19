//! M0.4 reproducer tests for findings F1, F2, F3, F4, F5, F6.
//!
//! These tests pin the *fixed* behaviour so a regression flips them back to red.
//! Each test names the finding and links the master plan
//! (`docs/ZSX_MASTER_PLAN.md` §2.2). Do not "loosen" these without an ADR.
//!
//! Status: F1, F2, F3, F4, F5 and F6 are FIXED. F5's two
//! quirks were closed earlier (shared string-aware brace matcher); F1/F2/F3 by
//! the hash-based ID scheme and the unified scope-aware control-flow lowering;
//! F4 by token-level `std` detection in `preprocess`.

const std = @import("std");
const parser = @import("../rt/parser.zig");
const codegen = @import("../rt/codegen.zig");
const preprocess = @import("../rt/preprocess.zig");

fn render(a: std.mem.Allocator, src: []const u8) !codegen.BlockOutput {
    const root = try parser.parse(a, src, "repro.zsx");
    return codegen.emitBlock(a, root, "repro.zsx", 0);
}

test "F1 fixed: stable IDs are hash-based, order-independent and non-overflowing" {
    // `file_index` no longer participates; only the stable source key and the
    // structural path do. 10 000 distinct blocks cannot overflow a u64.
    var block: usize = 0;
    while (block < 10_000) : (block += 1) {
        _ = codegen.stableNodeId("src/views/repro.zsx", block, 0);
    }

    // Same inputs → same IDs (no dependence on build-list order).
    const id = codegen.stableNodeId("src/views/repro.zsx", 3, 7);
    try std.testing.expectEqual(id, codegen.stableNodeId("src/views/repro.zsx", 3, 7));
    // Different sources → different IDs.
    try std.testing.expect(id != codegen.stableNodeId("src/views/other.zsx", 3, 7));

    // Generated code references the stable hash rather than a file stride.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = try render(arena.allocator(), "<label>hi</label>");
    try std.testing.expect(std.mem.indexOf(u8, out.code, "@truncate") != null);
}

test "F2 fixed: nested loops inside a slot get distinct idx names" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const out = try render(a,
        \\<Card>
        \\  <Slot name="body">
        \\    {for rows as row}
        \\      {for row.cells as cell}
        \\        <label>{cell}</label>
        \\      {/for}
        \\    {/for}
        \\  </Slot>
        \\</Card>
    );

    // One shared lowering: the second loop is `idx_1`, not a colliding `idx_0`.
    try std.testing.expect(std.mem.indexOf(u8, out.preamble, "idx_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.preamble, "idx_1") != null);
}

test "F3 fixed: slot body captures surrounding loop locals" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const out = try render(a,
        \\<column>
        \\  {for items as item}
        \\    <Card>
        \\      <Slot name="body">
        \\        <label>{item}</label>
        \\      </Slot>
        \\    </Card>
        \\  {/for}
        \\</column>
    );

    // The body becomes a capture struct built at the call site (with the
    // factory hoisted) instead of a `fn(ui, c, ctx)` that cannot see `item`.
    const all = try std.fmt.allocPrint(a, "{s}{s}", .{ out.preamble, out.code });
    try std.testing.expect(std.mem.indexOf(u8, all, "ZsxBody_") != null);
    try std.testing.expect(std.mem.indexOf(u8, all, "@TypeOf(item)") != null);
    try std.testing.expect(std.mem.indexOf(u8, all, ".item = item") != null);
    try std.testing.expect(std.mem.indexOf(u8, all, "const item = self.item;") != null);
    // The body is not hoisted as an uncaptured render function.
    try std.testing.expect(std.mem.indexOf(u8, out.preamble, "render_Card_body") == null);
}

test "reproducer F5 fixed: newline between attributes parses" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Was: error.ZsxParseError (the attribute separator only accepted ' ').
    // The parser now skips any whitespace between attributes, matching the
    // tolerant scanner in scan.zig.
    const el = try parser.parse(a, "<column\n  class=\"gap-2\"></column>", "repro.zsx");
    try std.testing.expectEqual(@as(usize, 1), el.attributes.len);
    try std.testing.expectEqualStrings("column", el.tag);
}

test "reproducer F5 fixed: brace matching is string-aware" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const el = try parser.parse(a, "<label>{\"}\"}</label>", "repro.zsx");
    // Was: the first '}' inside the string ended the expression, splitting it
    // into a broken expression plus junk text. The expression child is now
    // exactly the string literal.
    try std.testing.expectEqual(@as(usize, 1), el.children.len);
    switch (el.children[0]) {
        .expression => |e| try std.testing.expectEqualStrings("\"}\"", e),
        else => return error.TestUnexpected,
    }
}

test "F6 fixed: zsx!{ inside a Zig multiline string is not a block" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "pub fn view() void {\n" ++
        "    const doc =\n" ++
        "        \\\\fake zsx!{ <label>fake</label> }\n" ++
        "    ;\n" ++
        "    zsx!{ <label>real</label> }\n" ++
        "}\n";
    const blocks = try preprocess.findBlocks(a, src);
    try std.testing.expectEqual(@as(usize, 1), blocks.len);
    try std.testing.expectEqualStrings("zsx!{ <label>real</label> }", src[blocks[0].start..blocks[0].end]);

    const out = try preprocess.preprocess(a, src, "repro.zsx", 0);
    try std.testing.expect(std.mem.indexOf(u8, out, "<label>fake</label>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<label>real</label>") == null);
}

test "F4 fixed: std import detection is token-based, not substring" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const text_only =
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{
        \\        <label>std.out is not an import</label>
        \\    }
        \\}
        \\
    ;
    const out = try preprocess.preprocess(a, text_only, "repro.zsx", 0);
    try std.testing.expect(std.mem.indexOf(u8, out, "const std = @import") == null);

    const uses_std =
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{
        \\        <button on:click={std.debug.print("x", .{})}>x</button>
        \\    }
        \\}
        \\
    ;
    const out2 = try preprocess.preprocess(a, uses_std, "repro.zsx", 0);
    try std.testing.expect(std.mem.indexOf(u8, out2, "const std = @import") != null);
}

test "RFC-0001: whitespace inside control-flow braces is ignored" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const out = try render(a,
        \\<>
        \\  { if true }
        \\    <label>yes</label>
        \\  { /if }
        \\</>
    );
    // Same lowering as `{if true}`; the raw expression is trimmed before
    // classification, matching the tolerant scanner.
    try std.testing.expect(std.mem.indexOf(u8, out.code, "if (true)") != null);
}
