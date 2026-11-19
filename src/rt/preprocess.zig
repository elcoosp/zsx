const std = @import("std");
const cst = @import("cst.zig");
const diag = @import("diag.zig");
const codegen = @import("codegen.zig");
const lossless = @import("lossless.zig");

/// Preprocesses a `.zsx` source file: hoists preambles (render_* helpers), expands
/// every `zsx!{ ... }` block into the emitted body, passes everything else through
/// verbatim, strips the indent in front of each block (the emitted body supplies
/// its own), and prepends `const std = @import("std");` if any body references
/// `std.`.
///
/// Block detection is delegated to the lossless front-end (`lossless.Document`)
/// so strings, chars and comments are scanned by exactly one implementation —
/// this file no longer carries its own skip helpers (master-plan finding F11).
pub fn preprocess(a: std.mem.Allocator, source: []const u8, src_name: []const u8, file_index: usize) ![]const u8 {
    // Kept for API compatibility; widget identity is derived from `src_name`
    // (stable across build-list reordering), not the file index (F1).
    _ = file_index;
    const doc = try lossless.Document.init(a, source);
    var out = std.array_list.Managed(u8).init(a);
    var preamble_acc = std.array_list.Managed(u8).init(a);
    var needs_std = false;
    var block_idx: usize = 0;
    // `cursor` mirrors the byte the pass-through loop has consumed so far. It
    // can run past a segment's start when a block emitted below swallows the
    // optional `;` that directly follows its closing `}`.
    var cursor: usize = 0;

    for (doc.segs) |seg| {
        if (seg.end <= cursor) continue;
        if (seg.kind != .zsx_block) {
            try out.appendSlice(source[@max(seg.off, cursor)..seg.end]);
            cursor = seg.end;
            continue;
        }
        const blk = doc.blocks[block_idx];
        block_idx += 1;
        cursor = blk.end;
        // Mirror the historic scanner: an optional `;` right after the block
        // is consumed, not passed through.
        if (cursor < source.len and source[cursor] == ';') cursor += 1;
        if (!blk.closed) return error.ZsxParseError;

        // One parser: the tolerant CST with recovery, lowered to the AST
        // codegen consumes. `gen` has already rendered diagnostics from its
        // checker pass, so a dummy index avoids rebuilding line data here.
        const markup = doc.markup(blk);
        var block_diags = diag.List.init(a);
        const root = try cst.parse(a, markup, blk.markup_off, src_name, .{ .starts = &.{} }, &block_diags);
        if (block_diags.hasErrors()) return error.ZsxParseError;
        const el = cst.lowerBlock(a, root) catch return error.ZsxParseError;

        const split = try codegen.emitBlock(a, el, src_name, block_idx - 1);
        if (try mentionsStd(a, split.code)) needs_std = true;
        try preamble_acc.appendSlice(split.preamble);

        // Strip the leading indent from `out` — the emitted body starts at the
        // right indent on its own (level=1 in emitBlock).
        var lead: usize = 0;
        while (lead < out.items.len and out.items[out.items.len - 1 - lead] == ' ') lead += 1;
        out.shrinkRetainingCapacity(out.items.len - lead);

        try out.appendSlice(split.code);
    }

    // Hoist preamble above the pass-through body, prepend `std` import if needed.
    var final = std.array_list.Managed(u8).init(a);
    if (needs_std and !try importsStd(a, out.items)) try final.appendSlice("const std = @import(\"std\");\n\n");
    try final.appendSlice(preamble_acc.items);
    try final.appendSlice(out.items);
    return try final.toOwnedSlice();
}

/// Token-level check: does the generated code reference the `std` namespace
/// (identifier `std` followed by `.`)? Comments and string literals are skipped
/// by the tokenizer, so a label containing `"std."` does not pull in an import
/// (WP 2.9, closes the last substring heuristic).
fn mentionsStd(a: std.mem.Allocator, code: []const u8) !bool {
    // Fast negative filter; the positive answer is always confirmed on tokens.
    if (std.mem.indexOf(u8, code, "std") == null) return false;
    const z = try a.dupeSentinel(u8, code, 0);
    defer a.free(z);
    var tok = std.zig.Tokenizer.init(z);
    var prev_std = false;
    while (true) {
        const t = tok.next();
        if (t.tag == .eof) return false;
        if (prev_std and t.tag == .period) return true;
        prev_std = t.tag == .identifier and std.mem.eql(u8, code[t.loc.start..t.loc.end], "std");
    }
}

/// Token-level check for an existing `@import("std")` in pass-through source.
fn importsStd(a: std.mem.Allocator, code: []const u8) !bool {
    if (std.mem.indexOf(u8, code, "@import") == null) return false;
    const z = try a.dupeSentinel(u8, code, 0);
    defer a.free(z);
    var tok = std.zig.Tokenizer.init(z);
    var prev_import = false;
    while (true) {
        const t = tok.next();
        if (t.tag == .eof) return false;
        if (prev_import and t.tag == .string_literal) return std.mem.eql(u8, code[t.loc.start..t.loc.end], "\"std\"");
        prev_import = t.tag == .builtin and std.mem.eql(u8, code[t.loc.start..t.loc.end], "@import");
    }
}

/// Byte range of one `zsx!{ ... }` block: `start` is the offset of the `z`
/// in `zsx!{`, `end` is one past the matching `}`.
pub const Block = struct {
    start: usize,
    end: usize,
    /// False when end-of-source was reached before the closing `}`; callers
    /// should report `error.unterminated_block` and skip the body.
    closed: bool,
};

/// Find every `zsx!{ ... }` block in a `.zsx` source. Shared front-end for
/// tooling (checker, native formatter): strings, chars, line and block
/// comments are skipped first, so a `zsx!{` inside a doc comment is never
/// matched. Thin adapter over the lossless front-end (`lossless.Document`) —
/// the scanner itself lives in `src/rt/lossless.zig` so the preprocessor,
/// checker and formatter share one block finder instead of drifting copies
/// (master-plan finding F11).
pub fn findBlocks(a: std.mem.Allocator, source: []const u8) ![]Block {
    const doc = try lossless.Document.init(a, source);
    var blocks = std.array_list.Managed(Block).init(a);
    for (doc.blocks) |blk| {
        try blocks.append(.{ .start = blk.start, .end = blk.end, .closed = blk.closed });
    }
    return try blocks.toOwnedSlice();
}
