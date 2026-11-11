//! M0.4 — reproducer tests for findings F1, F2, F3, F5.
//!
//! These tests pin the *current, buggy* behaviour so M1/M2 has a green → red →
//! green story: when the fix lands, the assertion flips (the test is updated)
//! and the finding is closed. Each test names the finding and links the master
//! plan (`docs/ZSX_MASTER_PLAN.md` §2.2). Do not "loosen" these without an ADR.
//!
//! F5 status: FIXED. Both quirks (newline between attributes, string-blind
//! brace matching) were closed in the fail-fast parser by sharing the
//! string-aware matcher from `scan.zig`; the two F5 tests below now assert
//! the *fixed* behaviour. F1, F2 and F3 remain pinned as bugs.

const std = @import("std");
const parser = @import("../rt/parser.zig");
const codegen = @import("../rt/codegen.zig");

fn render(a: std.mem.Allocator, src: []const u8) !codegen.BlockOutput {
    const root = try parser.parse(a, src, "repro.zsx");
    return codegen.emitBlock(a, root, 0, 0);
}

test "reproducer F1: widget IDs overflow at ~185 .zsx files" {
    // codegen.zig: real = (file_index * BLOCK_STRIDE + block) * FILE_STRIDE + base
    const last_safe = @as(usize, 184) * codegen.BLOCK_STRIDE;
    _ = try std.math.mul(usize, last_safe, codegen.FILE_STRIDE);

    const overflow_at = @as(usize, 185) * codegen.BLOCK_STRIDE;
    try std.testing.expectError(
        error.Overflow,
        std.math.mul(usize, overflow_at, codegen.FILE_STRIDE),
    );
}

test "reproducer F2: nested loops inside a slot reuse idx_0" {
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

    try std.testing.expect(std.mem.indexOf(u8, out.preamble, "idx_0") != null);
    // Bug: emitContentChildren hard-codes idx_0, so the second loop never
    // produces idx_1 and the two loops collide on identity.
    try std.testing.expect(std.mem.indexOf(u8, out.preamble, "idx_1") == null);
}

test "reproducer F3: slot body cannot capture loop locals" {
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

    // Bug: hoisted helpers only receive (ui, c, ctx); `item` is referenced in
    // the body but is not a parameter. This would fail to compile.
    try std.testing.expect(std.mem.indexOf(u8, out.preamble, "render_Card_body") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.preamble, "item") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.preamble, "item: ") == null);
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
