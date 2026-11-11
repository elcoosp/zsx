//! `examples/render` — consumes the M1 code-frame renderer as a library.
//!
//! `examples/checker` shows the validation seam (`zsx.checker.checkSource`);
//! this example shows the presentation seam: build a `zsx.render.Renderer`
//! once per source, then turn each structured diagnostic into the annotated
//! snippet a developer reads — header, optional `  help:` line, source lines
//! with a caret span. The same API backs `zsx check` output (see
//! `src/cli.zig`) and is what an editor plugin or CI annotator would embed.
//!
//! Run:
//!
//!     zig build run    # from this directory
//!     zig build test   # the smoke tests below

const std = @import("std");
const zsx = @import("zsx");

const broken_source =
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
/// every rendered header, exactly as in `zsx check` output.
fn check(a: std.mem.Allocator, src_name: []const u8, source: []const u8) !zsx.diag.List {
    var list = zsx.diag.List.init(a);
    try zsx.checker.checkSource(a, source, src_name, .{}, &list);
    return list;
}

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;

    var list = try check(a, "views/bad.zsx", broken_source);
    if (!list.hasErrors()) {
        std.debug.print("render-demo: expected errors for the broken view\n", .{});
        return error.MissingDiagnostics;
    }

    // One Renderer per file: the O(n) line index is built once and reused for
    // every diagnostic of that file.
    const r = try zsx.render.Renderer.init(a, broken_source);
    for (list.items.items) |d| {
        try say(io, try r.render(d, .{}));
        try say(io, "\n");
    }
    const summary = try std.fmt.allocPrint(
        a,
        "views/bad.zsx: {d} error(s), {d} warning(s) — each one framed against the source\n",
        .{ list.errorCount(), list.warningCount() },
    );
    try say(io, summary);
}

fn say(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
}

test "render demo: every diagnostic renders a file citation, a ZSX code and a caret" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var list = try check(a, "views/bad.zsx", broken_source);
    // <column> and <row> never closed (ZSX0003 x2), made-up-class warning
    // (ZSX0009); the {if}/{/if} pair is balanced.
    try std.testing.expectEqual(@as(usize, 2), list.errorCount());
    try std.testing.expectEqual(@as(usize, 1), list.warningCount());

    const r = try zsx.render.Renderer.init(a, broken_source);
    for (list.items.items) |d| {
        const out = try r.render(d, .{});
        try std.testing.expect(std.mem.indexOf(u8, out, "views/bad.zsx") != null);
        try std.testing.expect(std.mem.indexOf(u8, out, "[ZSX") != null);
        try std.testing.expect(std.mem.indexOf(u8, out, "^") != null);
    }
}

test "render demo: the unknown-class warning cites its class attribute" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const list = try check(a, "views/bad.zsx", broken_source);
    const r = try zsx.render.Renderer.init(a, broken_source);
    const first = try r.render(list.items.items[0], .{});
    try std.testing.expect(std.mem.startsWith(
        u8,
        first,
        "views/bad.zsx:3:17: warning[ZSX0009]: unknown class 'made-up-class'",
    ));
    // The caret covers the whole class attribute value on line 3.
    try std.testing.expect(std.mem.indexOf(u8, first, "made-up-class") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "^^^^^^^^^^^^^^^^^^^^^^^^^^^") != null);
}
