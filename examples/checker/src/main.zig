//! `examples/checker` — consumes ZSX's tooling front-end as a library.
//!
//! `examples/consumer` shows the codegen path (`zsx.addViews`); this example
//! shows the M1 validation seam: call `zsx.checker.checkSource` directly on a
//! `.zsx` source and inspect the structured diagnostics — no process spawn,
//! no Python, no compilation. The same API backs `zsx check` (see
//! `src/cli.zig`) and is what a future editor plugin or LSP would embed.
//!
//! Run:
//!
//!     zig build run    # from this directory
//!     zig build test   # the two smoke tests below

const std = @import("std");
const zsx = @import("zsx");

const good_source =
    \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
    \\    zsx!{
    \\        <column padding={8} class="gap-2">
    \\            {if ctx.show}
    \\                <button class="bg-blue-500 text-white" on_click={ctx.save()}>Save</button>
    \\            {:else}
    \\                <label class="text-gray-500">No actions</label>
    \\            {/if}
    \\            {for ctx.items as item}
    \\                <shadcn.Badge color="green">{item}</shadcn.Badge>
    \\            {/for}
    \\        </column>
    \\    }
    \\}
;

const bad_source =
    \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
    \\    zsx!{
    \\        <column class="gap-2 made-up-class">
    \\            {if ctx.show}
    \\                <row>
    \\                    <label>x</label>
    \\            {/if}
    \\    }
    \\}
;

/// Check one source and return the diagnostic list. `src_name` shows up in
/// every rendered diagnostic, exactly as in `zsx check` output.
fn check(a: std.mem.Allocator, src_name: []const u8, source: []const u8) !zsx.diag.List {
    var list = zsx.diag.List.init(a);
    try zsx.checker.checkSource(a, source, src_name, .{}, &list);
    return list;
}

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;

    var clean_list = try check(a, "good.zsx", good_source);
    if (clean_list.count() != 0) {
        std.debug.print("checker-demo: expected 0 diagnostics for the clean view, got {d}\n", .{clean_list.count()});
        return error.UnexpectedDiagnostics;
    }
    try say(io, "good.zsx: 0 diagnostics (clean)\n");

    var bad_list = try check(a, "bad.zsx", bad_source);
    if (!bad_list.hasErrors()) {
        std.debug.print("checker-demo: expected errors for the broken view\n", .{});
        return error.MissingDiagnostics;
    }
    for (bad_list.items.items) |d| {
        const line = try d.renderHeader(a);
        try say(io, line);
        try say(io, "\n");
    }
    const summary = try std.fmt.allocPrint(
        a,
        "bad.zsx: {d} error(s), {d} warning(s) — structural problems found before any compile\n",
        .{ bad_list.errorCount(), bad_list.warningCount() },
    );
    try say(io, summary);
}

fn say(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
}

test "checker demo: clean source has no diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var list = try check(arena.allocator(), "good.zsx", good_source);
    try std.testing.expectEqual(@as(usize, 0), list.count());
}

test "checker demo: broken source yields two unclosed tags plus a class warning" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var list = try check(arena.allocator(), "bad.zsx", bad_source);
    // <column> and <row> never closed (ZSX0003 x2), made-up-class warning
    // (ZSX0009). The {if} in this fixture is balanced, so control flow is
    // silent — coverage for that lives in src/tests/checker.zig.
    try std.testing.expectEqual(@as(usize, 2), list.errorCount());
    try std.testing.expectEqual(@as(usize, 1), list.warningCount());
    try std.testing.expectEqual(zsx.diag.Code.unknown_class, list.items.items[0].code);
    try std.testing.expectEqual(zsx.diag.Code.unclosed_tag, list.items.items[1].code);
}
