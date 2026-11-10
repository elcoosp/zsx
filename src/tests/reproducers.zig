//! M0.4 — reproducer tests for findings F1, F2, F3, F5.
//!
//! These tests pin the *current, buggy* behaviour so M1/M2 has a green → red →
//! green story: when the fix lands, the assertion flips (the test is updated)
//! and the finding is closed. Each test names the finding and links the master
//! plan (`docs/ZSX_MASTER_PLAN.md` §2.2). Do not "loosen" these without an ADR.

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

test "reproducer F5: newline between attributes is a parse error" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try std.testing.expectError(
        error.ZsxParseError,
        parser.parse(arena.allocator(), "<column\n  class=\"gap-2\"></column>", "repro.zsx"),
    );
}

test "reproducer F5: brace matching ignores string literals" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parser.parse(arena.allocator(), "<label>{\"}\"}</label>", "repro.zsx");
    // Bug: the first '}' inside the string ends the expression. The AST is
    // wrong even though parsing "succeeds".
    try std.testing.expectEqual(@as(usize, 2), el.children.len);
    switch (el.children[0]) {
        .expression => |e| try std.testing.expect(!std.mem.eql(u8, e, "\"}\"")),
        else => return error.TestUnexpected,
    }
}
