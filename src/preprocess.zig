//! ZSX pre-processor: expands `zsx!{ <markup> }` blocks inline.
//!
//! Under the new format a `.zsx` file is ordinary Zig that contains one or
//! more `zsx!{ ... }` blocks. `preprocess` returns a `.zig` source string
//! where every block is replaced by the emitter's output for the single
//! root element inside it. Surrounding Zig is preserved verbatim.
//!
//! Contract for the enclosing scope:
//!   - Parameters must be named `ui`, `c`, `ctx` (any types).
//!   - `ctx` must expose the methods/fields the markup references.
//!   - Do not `_ = ui;` / `_ = c;` / `_ = ctx;` at the same scope as a
//!     block that references them (Zig rejects pointless discards).
//!
//! The block itself is wrapped by the emitter (`column`/`row` open `{ ... }`
//! so `var b_0` stays local). Leaf emitters produce single statements. An
//! optional trailing `;` after the block close is consumed.

const std = @import("std");
const ast = @import("ast.zig");
const zsx_parser = @import("parser.zig");
const codegen = @import("codegen.zig");

pub const BLOCK_STRIDE: usize = 10_000;

pub fn preprocess(comptime source: []const u8, comptime file_index: usize) []const u8 {
    @setEvalBranchQuota(2_000_000);
    var out: []const u8 = "";
    var pos: usize = 0;
    var block_idx: usize = 0;

    while (pos < source.len) {
        const c = source[pos];
        if (c == '"') {
            const end = skipStringLit(source, pos);
            out = out ++ source[pos..end];
            pos = end;
            continue;
        }
        if (c == '\'') {
            const end = skipCharLit(source, pos);
            out = out ++ source[pos..end];
            pos = end;
            continue;
        }
        if (c == '/' and pos + 1 < source.len and source[pos + 1] == '/') {
            const end = skipLineComment(source, pos);
            out = out ++ source[pos..end];
            pos = end;
            continue;
        }
        if (c == '/' and pos + 1 < source.len and source[pos + 1] == '*') {
            const end = skipBlockComment(source, pos);
            out = out ++ source[pos..end];
            pos = end;
            continue;
        }
        if (c == 'z' and startsWith(source, pos, "zsx!{")) {
            const blk = parseBlock(source, pos);
            const block_file_index = file_index * BLOCK_STRIDE + block_idx;
            const result = codegen.emitElement(blk.el, 1, 0, 0, block_file_index);
            out = out ++ result.preamble;
            out = out ++ result.code;
            pos = blk.end;
            block_idx += 1;
            continue;
        }
        const chunk_start = pos;
        pos += 1;
        while (pos < source.len and !isSpecial(source[pos])) pos += 1;
        out = out ++ source[chunk_start..pos];
    }
    return out;
}

const Block = struct {
    el: ast.Element,
    end: usize,
};

fn parseBlock(comptime source: []const u8, comptime start: usize) Block {
    var pos = start + 5;
    while (pos < source.len and isWs(source[pos])) pos += 1;
    const el = zsx_parser.parseElement(source, &pos);
    while (pos < source.len and isWs(source[pos])) pos += 1;
    if (pos >= source.len or source[pos] != '}') {
        @compileError("zsx: expected '}' to close zsx!{ block");
    }
    pos += 1;
    if (pos < source.len and source[pos] == ';') pos += 1;
    return .{ .el = el, .end = pos };
}

fn skipStringLit(comptime source: []const u8, comptime start: usize) usize {
    var pos = start + 1;
    while (pos < source.len) {
        if (source[pos] == '\\' and pos + 1 < source.len) {
            pos += 2;
            continue;
        }
        if (source[pos] == '"') return pos + 1;
        pos += 1;
    }
    return source.len;
}

fn skipCharLit(comptime source: []const u8, comptime start: usize) usize {
    var pos = start + 1;
    while (pos < source.len) {
        if (source[pos] == '\\' and pos + 1 < source.len) {
            pos += 2;
            continue;
        }
        if (source[pos] == '\'') return pos + 1;
        pos += 1;
    }
    return source.len;
}

fn skipLineComment(comptime source: []const u8, comptime start: usize) usize {
    var pos = start;
    while (pos < source.len and source[pos] != '\n') pos += 1;
    return pos;
}

fn skipBlockComment(comptime source: []const u8, comptime start: usize) usize {
    var pos = start + 2;
    while (pos + 1 < source.len) {
        if (source[pos] == '*' and source[pos + 1] == '/') return pos + 2;
        pos += 1;
    }
    return source.len;
}

fn startsWith(comptime source: []const u8, comptime pos: usize, comptime prefix: []const u8) bool {
    if (pos + prefix.len > source.len) return false;
    inline for (prefix, 0..) |ch, i| {
        if (source[pos + i] != ch) return false;
    }
    return true;
}

fn isSpecial(c: u8) bool {
    return c == '"' or c == '\'' or c == '/' or c == 'z';
}

fn isWs(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

test "preprocess empty source" {
    try std.testing.expectEqualStrings("", comptime preprocess("", 0));
}

test "preprocess no-block source is identity" {
    const s = "const x = 1;\n";
    try std.testing.expectEqualStrings(s, comptime preprocess(s, 0));
}

test "preprocess single block emits column code" {
    const src = "zsx!{<column/>}";
    const out = comptime preprocess(src, 0);
    try std.testing.expect(std.mem.indexOf(u8, out, "ui.column(c, ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "zsx!{") == null);
}

test "preprocess preserves surrounding zig verbatim" {
    const src = "const pre = 1;\nzsx!{<label>Hi</label>}\nconst post = 2;\n";
    const out = comptime preprocess(src, 0);
    try std.testing.expect(std.mem.startsWith(u8, out, "const pre = 1;\n"));
    try std.testing.expect(std.mem.endsWith(u8, out, "\nconst post = 2;\n"));
    try std.testing.expect(std.mem.indexOf(u8, out, "ui.text(c, \"Hi\"") != null);
}

test "preprocess consumes trailing semicolon" {
    const src = "zsx!{<column/>};";
    const out = comptime preprocess(src, 0);
    try std.testing.expect(std.mem.indexOf(u8, out, "};") == null);
}

test "preprocess two blocks use distinct ids" {
    const src = "zsx!{<label>a</label>}\nzsx!{<label>b</label>}\n";
    const out = comptime preprocess(src, 0);
    try std.testing.expect(std.mem.indexOf(u8, out, ".id_extra = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, ".id_extra = 10000000000000") != null);
}

test "preprocess block at nonzero file index uses that base" {
    const src = "zsx!{<label>x</label>}";
    const out = comptime preprocess(src, 3);
    // block_file_index = 3 * 10000 + 0 = 30000, base_id = 30000 * 1e13 = 3e17
    try std.testing.expect(std.mem.indexOf(u8, out, ".id_extra = 300000000000000000") != null);
}

test "preprocess ignores marker in string literal" {
    const src = "const s = \"zsx!{\";\n";
    const out = comptime preprocess(src, 0);
    try std.testing.expectEqualStrings(src, out);
}

test "preprocess ignores marker in line comment" {
    const src = "// zsx!{ not a block\nconst x = 1;\n";
    const out = comptime preprocess(src, 0);
    try std.testing.expectEqualStrings(src, out);
}

test "preprocess ignores marker in block comment" {
    const src = "/* zsx!{ not a block */\nconst x = 1;\n";
    const out = comptime preprocess(src, 0);
    try std.testing.expectEqualStrings(src, out);
}

test "preprocess handles escaped quote in string literal" {
    const src = "const s = \"a\\\"zsx!{\";\n";
    const out = comptime preprocess(src, 0);
    try std.testing.expectEqualStrings(src, out);
}
