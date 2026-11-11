//! Lossless front-end for `.zsx` files — master-plan spikes S1 + S2.
//!
//! S1 (Zig-side parsing): a `.zsx` file is a superset of Zig, but
//! `std.zig.Ast` cannot parse the `zsx!{ … }` blocks yet, so this module
//! provides the placeholder scanner until RFC-0001 makes `.zsx` valid Zig:
//! one string-, char- and comment-aware pass that partitions the whole file
//! into typed, byte-exact segments (`zig_text`, `string`, `char_literal`,
//! `line_comment`, `block_comment`, `zsx_block`).
//!
//! S2 (line-preserving emission): `Document.render` re-assembles those
//! segments and reproduces the input byte-for-byte. That is the guarantee
//! the future CST parser builds on: tooling can rewrite markup spans while
//! every byte outside them survives untouched, and no formatter or checker
//! has to re-derive "what was Zig here" again.
//!
//! This is also where master-plan finding F11 ("three parsers") shrinks by
//! one: `preprocess.zig` used to carry two private Zig-side scanners (its
//! inline loop plus `findBlocks`) with their own string/char/comment skip
//! helpers. Both now consume `Document`, so block detection has exactly one
//! implementation, shared by the preprocessor, the checker and the formatter.
//!
//! Conventions (matching `scan.zig` and `diag.zig`):
//!
//! - segments are zero-copy slices; all offsets are absolute file offsets,
//!   so `diag.LineIndex` built on the same source points at the same bytes;
//! - scanning never fails on unterminated content: a string that never
//!   closes runs to end of source, a block without its `}` keeps
//!   `closed == false` (callers decide how to report it);
//! - the only errors are allocation failures from the caller's allocator;
//! - token precedence is fixed: string → char → line comment → block
//!   comment → `zsx!{` — a block opener inside a literal or comment is
//!   never mistaken for a block.
//!
//! Example:
//!
//!     const doc = try zsx.lossless.Document.init(arena, source);
//!     for (doc.blocks) |blk| {
//!         std.debug.print("block markup: {s}\n", .{doc.markup(blk)});
//!     }
//!     try std.testing.expectEqualStrings(source, try doc.render(arena));

const std = @import("std");

/// What a byte range of the source is. `zig_text` is everything outside
/// literals, comments and blocks (identifiers, keywords, punctuation, the
/// whitespace between them).
pub const Kind = enum {
    /// Pass-through Zig source (also covers unterminated junk bytes).
    zig_text,
    /// A `"…"` string literal, including both quotes; unterminated strings
    /// run to end of source.
    string,
    /// A `'…'` char literal, including both quotes; unterminated literals
    /// run to end of source.
    char_literal,
    /// A `// …` line comment, excluding the trailing newline.
    line_comment,
    /// A `/* … */` block comment, including both delimiters; unterminated
    /// comments run to end of source.
    block_comment,
    /// A `zsx!{ … }` markup block, including the opener and the closing
    /// brace (see `Block` for the markup span inside).
    zsx_block,
};

/// One contiguous, typed byte range. Segments are ordered, non-overlapping
/// and exactly cover `[0, src.len)` — concatenating their slices reproduces
/// the source.
pub const Segment = struct {
    kind: Kind,
    /// Absolute file offset of the first byte (matches `diag.LineIndex`).
    off: usize,
    /// One past the last byte.
    end: usize,
};

/// A `zsx!{ … }` block found by the scanner. `start`/`end` mirror
/// `preprocess.Block` (with `closed` replacing its sentinel semantics) so
/// tooling can switch between the two without translation.
pub const Block = struct {
    /// Offset of the `z` in `zsx!{`.
    start: usize,
    /// One past the closing `}` — or end of source when unterminated.
    end: usize,
    /// Offset of the first byte after `zsx!{` (the markup body start,
    /// leading whitespace included — matches the checker's slice convention
    /// `source[block.start + 5 .. block.end - 1]` for closed blocks).
    markup_off: usize,
    /// One past the last markup byte: `end - 1` for closed blocks (inside
    /// the closing `}`), end of source when unterminated.
    markup_end: usize,
    /// False when end-of-source was reached before the closing `}`; callers
    /// should report `error.unterminated_block` and skip the body.
    closed: bool,
};

/// A fully segmented `.zsx` source. Build once per file with `init`, then
/// query segments/blocks or `render` the lossless reconstruction.
pub const Document = struct {
    /// The scanned source (segments' offsets point into it).
    src: []const u8,
    /// Ordered segment list covering the whole source.
    segs: []const Segment,
    /// The `zsx!{ … }` blocks, in source order. Always non-empty when at
    /// least one real block opener exists outside literals and comments.
    blocks: []const Block,

    /// Segment `src` (S1): one pass, string/char/comment-aware. Uses the
    /// caller's allocator (an arena) for the segment and block lists only —
    /// all content slices stay zero-copy views into `src`.
    pub fn init(a: std.mem.Allocator, src: []const u8) !Document {
        var segs = std.array_list.Managed(Segment).init(a);
        var blocks = std.array_list.Managed(Block).init(a);
        var run_start: usize = 0; // start of the pending zig_text run
        var i: usize = 0;

        while (i < src.len) {
            const c = src[i];
            if (c == '"') {
                const end = skipString(src, i);
                try pushZigText(&segs, run_start, i);
                try segs.append(.{ .kind = .string, .off = i, .end = end });
                i = end;
                run_start = end;
                continue;
            }
            if (c == '\'') {
                const end = skipChar(src, i);
                try pushZigText(&segs, run_start, i);
                try segs.append(.{ .kind = .char_literal, .off = i, .end = end });
                i = end;
                run_start = end;
                continue;
            }
            if (c == '/' and i + 1 < src.len and src[i + 1] == '/') {
                const end = skipLineComment(src, i);
                try pushZigText(&segs, run_start, i);
                try segs.append(.{ .kind = .line_comment, .off = i, .end = end });
                i = end;
                run_start = end;
                continue;
            }
            if (c == '/' and i + 1 < src.len and src[i + 1] == '*') {
                const end = skipBlockComment(src, i);
                try pushZigText(&segs, run_start, i);
                try segs.append(.{ .kind = .block_comment, .off = i, .end = end });
                i = end;
                run_start = end;
                continue;
            }
            if (c == 'z' and startsWith(src, i, "zsx!{")) {
                const blk = scanBlock(src, i);
                try pushZigText(&segs, run_start, i);
                try segs.append(.{ .kind = .zsx_block, .off = blk.start, .end = blk.end });
                try blocks.append(blk);
                i = blk.end;
                run_start = blk.end;
                continue;
            }
            i += 1;
        }
        try pushZigText(&segs, run_start, src.len);

        return .{
            .src = src,
            .segs = try segs.toOwnedSlice(),
            .blocks = try blocks.toOwnedSlice(),
        };
    }

    /// Re-emit the source (S2): concatenating the segment slices reproduces
    /// `src` byte-for-byte. The result is freshly allocated storage, not an
    /// alias of `src`, so callers may pass it to byte-mutating post-passes.
    pub fn render(self: *const Document, a: std.mem.Allocator) ![]const u8 {
        var out = std.array_list.Managed(u8).init(a);
        try out.ensureTotalCapacity(self.src.len);
        for (self.segs) |seg| {
            try out.appendSlice(self.src[seg.off..seg.end]);
        }
        return try out.toOwnedSlice();
    }

    /// The markup body of a block: the bytes between `zsx!{` and the
    /// closing `}` (both excluded), matching the slice the structural
    /// checker validates. For unterminated blocks the body runs to end of
    /// source.
    pub fn markup(self: *const Document, blk: Block) []const u8 {
        return self.src[blk.markup_off..blk.markup_end];
    }

    /// Convenience: number of blocks (length of `blocks`).
    pub fn blockCount(self: *const Document) usize {
        return self.blocks.len;
    }
};

fn pushZigText(segs: *std.array_list.Managed(Segment), start: usize, end: usize) !void {
    if (end > start) try segs.append(.{ .kind = .zig_text, .off = start, .end = end });
}

/// Extent of one `zsx!{ … }` block starting at `start`. The inner scan is
/// string- and char-aware (a `'}'` inside `{"}"}` never closes the block —
/// the same matcher the fail-fast parser uses since F5) and brace-depth
/// counted; an unterminated block ends at end of source with `closed=false`.
fn scanBlock(src: []const u8, start: usize) Block {
    var depth: usize = 1; // the '{' of "zsx!{"
    var p: usize = start + 5;
    var closed = false;
    while (p < src.len) {
        const d = src[p];
        if (d == '"') {
            p = skipString(src, p);
            continue;
        }
        if (d == '\'') {
            p = skipChar(src, p);
            continue;
        }
        if (d == '{') depth += 1;
        if (d == '}') {
            depth -= 1;
            if (depth == 0) {
                closed = true;
                break;
            }
        }
        p += 1;
    }
    if (closed) {
        return .{
            .start = start,
            .end = p + 1,
            .markup_off = start + 5,
            .markup_end = p,
            .closed = true,
        };
    }
    return .{
        .start = start,
        .end = src.len,
        .markup_off = start + 5,
        .markup_end = src.len,
        .closed = false,
    };
}

fn startsWith(src: []const u8, pos: usize, prefix: []const u8) bool {
    if (pos + prefix.len > src.len) return false;
    return std.mem.eql(u8, src[pos..][0..prefix.len], prefix);
}

/// Index just past the `"…"` string starting at the `"` at `src[start]`; the
/// end of `src` if the string never closes. `\` escapes are honoured.
fn skipString(src: []const u8, start: usize) usize {
    var p = start + 1;
    while (p < src.len) : (p += 1) {
        if (src[p] == '\\' and p + 1 < src.len) {
            p += 2;
            continue;
        }
        if (src[p] == '"') return p + 1;
    }
    return p;
}

/// Index just past the `'…'` char literal starting at the `'` at
/// `src[start]`; the end of `src` if the literal never closes.
fn skipChar(src: []const u8, start: usize) usize {
    var p = start + 1;
    while (p < src.len) : (p += 1) {
        if (src[p] == '\\' and p + 1 < src.len) {
            p += 2;
            continue;
        }
        if (src[p] == '\'') return p + 1;
    }
    return p;
}

/// Index of the newline ending the `// …` comment at `src[start]` (the
/// comment excludes the newline); end of `src` for a last-line comment.
fn skipLineComment(src: []const u8, start: usize) usize {
    var p = start;
    while (p < src.len and src[p] != '\n') : (p += 1) {}
    return p;
}

/// Index just past the `/* … */` comment starting at `src[start]`; the end
/// of `src` if the comment never closes.
fn skipBlockComment(src: []const u8, start: usize) usize {
    var p = start + 2;
    while (p + 1 < src.len) : (p += 1) {
        if (src[p] == '*' and src[p + 1] == '/') return p + 2;
    }
    return src.len;
}

// -- tests ---------------------------------------------------------------

const testing = std.testing;
const ArenaAllocator = std.heap.ArenaAllocator;
const page_allocator = std.heap.page_allocator;

test "lossless: empty source produces zero segments" {
    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();
    const doc = try Document.init(arena.allocator(), "");
    try testing.expectEqual(@as(usize, 0), doc.segs.len);
    try testing.expectEqualStrings("", try doc.render(arena.allocator()));
}

test "lossless: block in string is a string segment, not a block" {
    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "const s = \"zsx!{ <label>x</label> }\";";
    const doc = try Document.init(a, src);
    try testing.expectEqual(@as(usize, 0), doc.blockCount());
    var strings: usize = 0;
    for (doc.segs) |seg| {
        if (seg.kind == .string) strings += 1;
    }
    try testing.expectEqual(@as(usize, 1), strings);
}

test "lossless: unterminated string runs to end of source" {
    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "const s = \"never closed";
    const doc = try Document.init(a, src);
    const last = doc.segs[doc.segs.len - 1];
    try testing.expectEqual(Kind.string, last.kind);
    try testing.expectEqual(src.len, last.end);
    try testing.expectEqualStrings(src, try doc.render(a));
}

test "lossless: markup excludes the closing brace" {
    var arena = ArenaAllocator.init(page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "zsx!{ <row><label>x</label></row> }";
    const doc = try Document.init(a, src);
    try testing.expectEqual(@as(usize, 1), doc.blockCount());
    try testing.expectEqualStrings(" <row><label>x</label></row> ", doc.markup(doc.blocks[0]));
}
