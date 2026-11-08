const std = @import("std");
const parser = @import("parser.zig");
const codegen = @import("codegen.zig");

/// Preprocesses a `.zsx` source file: hoists preambles (render_* helpers), expands
/// every `zsx!{ ... }` block into the emitted body, passes everything else through
/// verbatim, strips the indent in front of each block (the emitted body supplies
/// its own), and prepends `const std = @import("std");` if any body references
/// `std.`.
pub fn preprocess(a: std.mem.Allocator, source: []const u8, src_name: []const u8, file_index: usize) ![]const u8 {
    var out = std.array_list.Managed(u8).init(a);
    var preamble_acc = std.array_list.Managed(u8).init(a);
    var pos: usize = 0;
    var block_idx: usize = 0;
    var needs_std = false;

    while (pos < source.len) {
        const c = source[pos];
        if (c == '"') { const end = skipString(source, pos); try out.appendSlice(source[pos..end]); pos = end; continue; }
        if (c == '\'') { const end = skipChar(source, pos); try out.appendSlice(source[pos..end]); pos = end; continue; }
        if (c == '/' and pos + 1 < source.len and source[pos + 1] == '/') { const end = skipLineComment(source, pos); try out.appendSlice(source[pos..end]); pos = end; continue; }
        if (c == '/' and pos + 1 < source.len and source[pos + 1] == '*') { const end = skipBlockComment(source, pos); try out.appendSlice(source[pos..end]); pos = end; continue; }
        if (c == 'z' and startsWith(source, pos, "zsx!{")) {
            var p = pos + 5;
            while (p < source.len and std.ascii.isWhitespace(source[p])) : (p += 1) {}
            var pp = p;
            const el = try parser.parseElement(a, source, src_name, &pp);
            while (pp < source.len and std.ascii.isWhitespace(source[pp])) : (pp += 1) {}
            if (pp >= source.len or source[pp] != '}') return error.ZsxParseError;
            pp += 1;
            if (pp < source.len and source[pp] == ';') pp += 1;

            const split = try codegen.emitBlock(a, el, file_index, block_idx);
            if (std.mem.indexOf(u8, split.code, "std.") != null) needs_std = true;
            try preamble_acc.appendSlice(split.preamble);

            // Strip the leading indent from `out` — the emitted body starts at the
            // right indent on its own (level=1 in emitBlock).
            var lead: usize = 0;
            while (lead < out.items.len and out.items[out.items.len - 1 - lead] == ' ') lead += 1;
            out.shrinkRetainingCapacity(out.items.len - lead);

            try out.appendSlice(split.code);
            pos = pp;
            block_idx += 1;
            continue;
        }
        try out.append(c);
        pos += 1;
    }

    // Hoist preamble above the pass-through body, prepend `std` import if needed.
    var final = std.array_list.Managed(u8).init(a);
    const has_std = std.mem.indexOf(u8, out.items, "@import(\"std\")") != null;
    if (needs_std and !has_std) try final.appendSlice("const std = @import(\"std\");\n\n");
    try final.appendSlice(preamble_acc.items);
    try final.appendSlice(out.items);
    return try final.toOwnedSlice();
}

fn startsWith(src: []const u8, pos: usize, prefix: []const u8) bool {
    if (pos + prefix.len > src.len) return false;
    return std.mem.eql(u8, src[pos..][0..prefix.len], prefix);
}
fn skipString(src: []const u8, start: usize) usize {
    var p = start + 1;
    while (p < src.len) : (p += 1) {
        if (src[p] == '\\' and p + 1 < src.len) { p += 2; continue; }
        if (src[p] == '"') return p + 1;
    }
    return src.len;
}
fn skipChar(src: []const u8, start: usize) usize {
    var p = start + 1;
    while (p < src.len) : (p += 1) {
        if (src[p] == '\\' and p + 1 < src.len) { p += 2; continue; }
        if (src[p] == '\'') return p + 1;
    }
    return src.len;
}
fn skipLineComment(src: []const u8, start: usize) usize {
    var p = start;
    while (p < src.len and src[p] != '\n') : (p += 1) {}
    return p;
}
fn skipBlockComment(src: []const u8, start: usize) usize {
    var p = start + 2;
    while (p + 1 < src.len) : (p += 1) {
        if (src[p] == '*' and src[p + 1] == '/') return p + 2;
    }
    return src.len;
}
