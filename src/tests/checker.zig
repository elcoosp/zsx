//! Checker rule tests (M1). Written failing-first: the rule set was
//! implemented only after these assertions existed. Each case pins one
//! diagnostic code, its severity and the cited position, so messages can be
//! reworded later without loosening the contract.

const std = @import("std");
const diag = @import("../rt/diag.zig");
const checker = @import("../rt/checker.zig");

fn check(a: std.mem.Allocator, markup: []const u8) !diag.List {
    var list = diag.List.init(a);
    const idx = try diag.LineIndex.build(a, markup);
    try checker.checkMarkup(a, markup, 0, idx, "test.zsx", .{}, &list);
    return list;
}

/// File-level helper: full `.zsx` source, exactly what `zsx check` sees.
fn checkFile(a: std.mem.Allocator, src: []const u8) !diag.List {
    var list = diag.List.init(a);
    try checker.checkSource(a, src, "test.zsx", .{}, &list);
    return list;
}

fn expectOneError(a: std.mem.Allocator, src: []const u8, code: diag.Code, line: usize) !void {
    var list = try check(a, src);
    try std.testing.expectEqual(@as(usize, 1), list.errorCount());
    const d = list.items.items[0];
    try std.testing.expectEqual(code, d.code);
    try std.testing.expectEqual(diag.Severity.err, d.severity);
    try std.testing.expectEqual(line, d.line);
}

test "checker: clean view produces no diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var list = try checkFile(a,
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{
        \\        <column padding={8} class="gap-2">
        \\            {if ctx.show}
        \\                <button class="bg-blue-500 text-white" on_click={ctx.save()}>Save</button>
        \\            {:else}
        \\                <label class="text-gray-500">No actions</label>
        \\            {/if}
        \\            {for ctx.items as item}
        \\                <label>{item}</label>
        \\            {/for}
        \\        </column>
        \\    }
        \\}
    );
    try std.testing.expectEqual(@as(usize, 0), list.count());
}

test "checker: mismatched closing tag cites open line (ZSX0002)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try expectOneError(arena.allocator(),
        \\<column>
        \\  <label>hi</label>
        \\</row>
    , .tag_mismatch, 3);
}

test "checker: unclosed tag (ZSX0003)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try expectOneError(arena.allocator(),
        \\<column>
        \\  <label>hi</label>
    , .unclosed_tag, 1);
}

test "checker: stray close tag (ZSX0001)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try expectOneError(arena.allocator(), "</column>", .stray_close_tag, 1);
}

test "checker: recovery — structure after a junk token still validates" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var list = try check(a,
        \\<column>
        \\  < label>junk
        \\  <row>
        \\    <label>x</label>
        \\  </row>
        \\</column>
    );
    // The stray '<' is one junk error; column/row still balance because the
    // scanner recovered instead of aborting like the fail-fast parser.
    try std.testing.expectEqual(@as(usize, 1), list.errorCount());
    try std.testing.expectEqual(diag.Code.junk_syntax, list.items.items[0].code);
    try std.testing.expectEqual(@as(usize, 2), list.items.items[0].line);
}

test "checker: control flow mismatch (ZSX0005)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try expectOneError(arena.allocator(),
        \\{if ctx.a}
        \\{/for}
    , .ctrl_mismatch, 2);
}

test "checker: unclosed control flow (ZSX0006)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try expectOneError(arena.allocator(),
        \\<column>
        \\  {for ctx.items as item}
        \\    <label>{item}</label>
        \\</column>
    , .unclosed_ctrl, 2);
}

test "checker: stray control close (ZSX0004)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try expectOneError(arena.allocator(), "{/if}", .stray_ctrl_close, 1);
}

test "checker: {:else} outside a body (ZSX0007)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try expectOneError(arena.allocator(),
        \\{for ctx.items as item}
        \\{:else}
        \\{/for}
    , .misplaced_else, 2);
}

test "checker: {:case} inside {if} is rejected (ZSX0008)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try expectOneError(arena.allocator(),
        \\{if ctx.a}
        \\{:case "x"}
        \\{/if}
    , .misplaced_case, 2);
}

test "checker: {:else if} inside {if} is accepted" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var list = try check(arena.allocator(),
        \\{if ctx.a}
        \\{:else if ctx.b}
        \\{/if}
    );
    try std.testing.expectEqual(@as(usize, 0), list.count());
}

test "checker: {:case} inside {switch} is accepted" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var list = try check(arena.allocator(),
        \\{switch ctx.s}
        \\{:case "ok"}
        \\{:else}
        \\{/switch}
    );
    try std.testing.expectEqual(@as(usize, 0), list.count());
}

test "checker: unknown class is a warning, not an error (ZSX0009)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var list = try check(a,
        \\<label class="text-sm made-up-class">x</label>
    );
    try std.testing.expectEqual(@as(usize, 0), list.errorCount());
    try std.testing.expectEqual(@as(usize, 1), list.warningCount());
    try std.testing.expectEqual(diag.Code.unknown_class, list.items.items[0].code);
    try std.testing.expectEqual(@as(usize, 1), list.items.items[0].line);
}

test "checker: every token of a class string is checked" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var list = try check(a,
        \\<label class="bogus-one bogus-two">x</label>
    );
    try std.testing.expectEqual(@as(usize, 2), list.warningCount());
}

test "checker: known classes stay silent" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var list = try check(arena.allocator(),
        \\<label class="text-sm bg-blue-500 rounded-lg gap-2">x</label>
    );
    try std.testing.expectEqual(@as(usize, 0), list.count());
}

test "checker: --no-class-check disables ZSX0009" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var list = diag.List.init(a);
    const idx = try diag.LineIndex.build(a, "<label class=\"made-up-class\">x</label>");
    try checker.checkMarkup(a, "<label class=\"made-up-class\">x</label>", 0, idx, "test.zsx", .{ .check_classes = false }, &list);
    try std.testing.expectEqual(@as(usize, 0), list.count());
}

test "checker: legacy alias warns (ZSX0010)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var list = try check(a,
        \\{if ctx.a}
        \\{endif}
    );
    try std.testing.expectEqual(@as(usize, 0), list.errorCount());
    try std.testing.expectEqual(@as(usize, 1), list.warningCount());
    try std.testing.expectEqual(diag.Code.legacy_alias, list.items.items[0].code);
}

test "checker: unterminated block is an error (ZSX0011)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var list = try checkFile(a,
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{
        \\        <column>
    );
    try std.testing.expectEqual(@as(usize, 1), list.errorCount());
    try std.testing.expectEqual(diag.Code.unterminated_block, list.items.items[0].code);
    try std.testing.expectEqual(@as(usize, 2), list.items.items[0].line);
}

test "checker: junk markup is an error with the scanner's message (ZSX0012)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try expectOneError(arena.allocator(),
        \\< label>x
    , .junk_syntax, 1);
}

test "checker: fragments balance" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var list = try check(arena.allocator(),
        \\<>
        \\  <label>x</label>
        \\</>
    );
    try std.testing.expectEqual(@as(usize, 0), list.count());
}

test "checker: fragment never closed (ZSX0003)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try expectOneError(arena.allocator(),
        \\<>
        \\  <label>x</label>
    , .unclosed_tag, 1);
}

test "checker: string with braces in Zig part does not start a block" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var list = try checkFile(arena.allocator(),
        \\const s = "zsx!{ not a block";
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{
        \\        <label>ok</label>
        \\    }
        \\}
    );
    try std.testing.expectEqual(@as(usize, 0), list.count());
}

// -- corpus --------------------------------------------------------------
//
// Every committed view must come back clean. This is the same gate CI runs
// (`zig build zsx -Dcmd=check`), pinned as a unit test so a rule change that
// starts flagging the corpus cannot land silently.

const corpus = [_][]const u8{
    @embedFile("../views/demo.zsx"),
    @embedFile("../views/component_demo.zsx"),
    @embedFile("../views/else_if_demo.zsx"),
    @embedFile("../views/fragment_demo.zsx"),
    @embedFile("../views/onclick_demo.zsx"),
    @embedFile("../views/path_demo.zsx"),
    @embedFile("../views/playground.zsx"),
    @embedFile("../views/switch_demo.zsx"),
};

test "checker: corpus views are clean" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const names = [_][]const u8{ "demo", "component_demo", "else_if_demo", "fragment_demo", "onclick_demo", "path_demo", "playground", "switch_demo" };
    for (corpus, names) |src, name| {
        var list = diag.List.init(a);
        try checker.checkSource(a, src, name, .{}, &list);
        if (list.count() != 0) {
            std.debug.print("checker corpus: {s} produced {d} diagnostic(s):\n", .{ name, list.count() });
            for (list.items.items) |d| {
                std.debug.print("  {s}\n", .{try d.renderHeader(a)});
            }
            return error.TestUnexpected;
        }
    }
}
