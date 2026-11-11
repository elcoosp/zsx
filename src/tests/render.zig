//! Code-frame renderer tests (M1). Written failing-first, like the checker
//! and fmt suites: each test pins one piece of the rendered output contract —
//! header, help line, gutter, caret placement, context window, clamping.
//! The exact bytes matter: editor plugins and tests assert on them, and the
//! CLI forwards them verbatim to stderr.

const std = @import("std");
const diag = @import("../rt/diag.zig");
const checker = @import("../rt/checker.zig");
const render = @import("../rt/render.zig");

const testing = std.testing;

fn renderer(a: std.mem.Allocator, src: []const u8) !render.Renderer {
    return render.Renderer.init(a, src);
}

test "render: frame shows span line, gutter and caret (ZSX0001)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "<column>\n  <label>hi</label>\n</row>\n";
    var r = try renderer(a, src);
    const d = Diagnostic{
        .code = .stray_close_tag,
        .severity = .err,
        .message = "</row> with no open tag",
        .file = "test.zsx",
        .line = 3,
        .col = 1,
        .offset = 29,
        .len = 6,
    };
    const frame = try r.renderFrame(d, .{});
    try testing.expectEqualStrings(
        \\2 |   <label>hi</label>
        \\3 | </row>
        \\  | ^^^^^^
    , frame);
}

test "render: render composes header, help and frame" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "<column>\n</row>\n";
    var r = try renderer(a, src);
    const d = Diagnostic{
        .code = .stray_close_tag,
        .severity = .err,
        .message = "</row> with no open tag",
        .help = "remove it or open a matching tag",
        .file = "test.zsx",
        .line = 2,
        .col = 1,
        .offset = 9,
        .len = 6,
    };
    const out = try r.render(d, .{});
    try testing.expectEqualStrings(
        \\test.zsx:2:1: error[ZSX0001]: </row> with no open tag
        \\  help: remove it or open a matching tag
        \\1 | <column>
        \\2 | </row>
        \\  | ^^^^^^
    , out);
}

test "render: zero-length span renders a single caret" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "<column>\n</column>\n";
    var r = try renderer(a, src);
    const d = Diagnostic{
        .code = .unclosed_tag,
        .severity = .err,
        .message = "<column> never closed",
        .file = "t.zsx",
        .line = 1,
        .col = 1,
        .offset = 0,
        .len = 0,
    };
    const frame = try r.renderFrame(d, .{});
    try testing.expectEqualStrings(
        \\1 | <column>
        \\  | ^
        \\2 | </column>
    , frame);
}

test "render: context option widens and shrinks the window" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "a\nb\nc\nd\ne\nf\ng\n";
    var r = try renderer(a, src);
    const d = Diagnostic{
        .code = .stray_ctrl_close,
        .severity = .err,
        .message = "boom",
        .file = "t.zsx",
        .line = 4,
        .col = 1,
        .offset = 6,
        .len = 1,
    };
    try testing.expectEqualStrings(
        \\3 | c
        \\4 | d
        \\  | ^
        \\5 | e
    , try r.renderFrame(d, .{}));
    try testing.expectEqualStrings(
        \\4 | d
        \\  | ^
    , try r.renderFrame(d, .{ .context = 0 }));
    try testing.expectEqualStrings(
        \\1 | a
        \\2 | b
        \\3 | c
        \\4 | d
        \\  | ^
        \\5 | e
        \\6 | f
        \\7 | g
    , try r.renderFrame(d, .{ .context = 3 }));
}

test "render: gutter grows with the largest shown line number" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 12 lines so the gutter needs two digits.
    var src: []const u8 = "";
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        src = try std.fmt.allocPrint(a, "{s}line{d}\n", .{ src, i + 1 });
    }
    var r = try renderer(a, src);
    const d = Diagnostic{
        .code = .stray_close_tag,
        .severity = .err,
        .message = "meh",
        .file = "t.zsx",
        .line = 11,
        .col = 1,
        .offset = 61,
        .len = 2,
    };
    const frame = try r.renderFrame(d, .{});
    try testing.expectEqualStrings(
        \\10 | line10
        \\11 | line11
        \\   | ^^
        \\12 | line12
    , frame);
}

test "render: span is clamped to the end of its line" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Span claims 100 bytes but the line has 9.
    const src = "<column>\n</row>\n";
    var r = try renderer(a, src);
    const d = Diagnostic{
        .code = .stray_close_tag,
        .severity = .err,
        .message = "meh",
        .file = "t.zsx",
        .line = 2,
        .col = 1,
        .offset = 9,
        .len = 100,
    };
    const frame = try r.renderFrame(d, .{});
    try testing.expectEqualStrings(
        \\1 | <column>
        \\2 | </row>
        \\  | ^^^^^^
    , frame);
}

test "render: offset past end of source is clamped, no panic" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var r = try renderer(a, "<column>\n");
    const d = Diagnostic{
        .code = .unclosed_tag,
        .severity = .err,
        .message = "meh",
        .file = "t.zsx",
        .line = 99,
        .col = 99,
        .offset = 9999,
        .len = 0,
    };
    const frame = try r.renderFrame(d, .{});
    // Clamped to the last real line; caret at end of its content.
    try testing.expectEqualStrings(
        \\1 | <column>
        \\  |         ^
    , frame);
}

test "render: end-to-end — checker diagnostics render with frames" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src =
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{
        \\<column>
        \\  {if ctx.show}
        \\    <row>
        \\      <label>x</label>
        \\  {/for}
        \\</column>
        \\    }
        \\}
    ;
    var list = diag.List.init(a);
    try checker.checkSource(a, src, "views/bad.zsx", .{}, &list);
    try testing.expect(list.hasErrors());

    var r = try renderer(a, src);
    var rendered_any_frame = false;
    for (list.items.items) |d| {
        const out = try r.render(d, .{});
        // Every rendered diagnostic cites the file, a ZSX code and a caret row.
        try testing.expect(std.mem.indexOf(u8, out, "views/bad.zsx") != null);
        try testing.expect(std.mem.indexOf(u8, out, "[ZSX") != null);
        try testing.expect(std.mem.indexOf(u8, out, "^") != null);
        rendered_any_frame = true;
    }
    try testing.expect(rendered_any_frame);
}

test "render: warning severity renders as warning[ZSX00xx]" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var r = try renderer(a, "<label class=\"made-up\">x</label>\n");
    const d = Diagnostic{
        .code = .unknown_class,
        .severity = .warning,
        .message = "unknown class 'made-up' (will error at build)",
        .file = "t.zsx",
        .line = 1,
        .col = 15,
        .offset = 14,
        .len = 12,
    };
    const out = try r.render(d, .{});
    try testing.expect(std.mem.startsWith(u8, out, "t.zsx:1:15: warning[ZSX0009]: "));
    try testing.expect(std.mem.indexOf(u8, out, "^^^^^^^^^^^^") != null);
}

// Local re-export so the fixture literal above stays honest about the type
// being rendered (diag.Diagnostic, exactly what checkSource produces).
const Diagnostic = diag.Diagnostic;
