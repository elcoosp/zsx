//! `examples/lossless` — consumes the lossless front-end as a library.
//!
//! `examples/consumer` shows the codegen path (`zsx.addViews`) and
//! `examples/checker` shows the validation seam (`zsx.checker.checkSource`).
//! This example shows the lossless seam (spikes S1 + S2): partition a `.zsx`
//! source into typed, byte-exact segments and re-emit the file byte-for-byte.
//! It is the guarantee editor tooling, formatters and the future CST parser
//! build on: rewrite markup spans while every byte outside them survives.
//!
//! Run:
//!
//!     zig build run    # from this directory
//!     zig build test   # the two smoke tests below

const std = @import("std");
const zsx = @import("zsx");

const sample_source =
    \\const std = @import("std");
    \\
    \\// A comment mentioning zsx!{ <label>fake</label> } must not fool the scanner.
    \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
    \\    const brace = '}';
    \\    zsx!{
    \\        <column class="gap-2">
    \\            {if ctx.show}<label>{ctx.name}</label>{:else}<row></row>{/if}
    \\        </column>
    \\    }
    \\}
;

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;

    const doc = try zsx.lossless.Document.init(a, sample_source);

    // S1: the file is a typed partition of segments.
    try say(io, "segment outline of sample.zsx:\n");
    for (doc.segs) |seg| {
        const text = sample_source[seg.off..seg.end];
        const head = text[0..@min(text.len, 28)];
        const line = try std.fmt.allocPrint(
            a,
            "  {s:<14} bytes {d:>3}..{d:<3} |{s}|{s}\n",
            .{ @tagName(seg.kind), seg.off, seg.end, head, if (text.len > 28) "…" else "" },
        );
        try say(io, line);
    }

    const counts = try std.fmt.allocPrint(
        a,
        "{d} segment(s), {d} zsx block(s)\n",
        .{ doc.segs.len, doc.blockCount() },
    );
    try say(io, counts);
    try say(io, "  - the fake zsx!{ inside the comment is a line_comment, not a block\n");
    try say(io, "  - the '}' char literal and the {if} braces live inside the block, intact\n");
    for (doc.blocks) |blk| {
        const line = try std.fmt.allocPrint(
            a,
            "  block markup: {s}\n",
            .{doc.markup(blk)},
        );
        try say(io, line);
    }

    // S2: re-emitting the segments reproduces the source byte-for-byte.
    const rendered = try doc.render(a);
    if (!std.mem.eql(u8, rendered, sample_source)) {
        std.debug.print("lossless-demo: render did not reproduce the source\n", .{});
        return error.RoundTripMismatch;
    }
    try say(io, "round-trip: render(doc) == source, byte-for-byte\n");
}

fn say(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
}

test "lossless demo: round-trip is byte-exact" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const doc = try zsx.lossless.Document.init(arena.allocator(), sample_source);
    const rendered = try doc.render(arena.allocator());
    try std.testing.expectEqualStrings(sample_source, rendered);
}

test "lossless demo: comment opener is not a block, real block is found" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const doc = try zsx.lossless.Document.init(arena.allocator(), sample_source);
    try std.testing.expectEqual(@as(usize, 1), doc.blockCount());
    try std.testing.expect(doc.blocks[0].closed);
    try std.testing.expect(std.mem.indexOf(u8, doc.markup(doc.blocks[0]), "{if ctx.show}") != null);
}
