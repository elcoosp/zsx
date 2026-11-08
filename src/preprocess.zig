//! ZSX pre-processor: expands `zsx!{ <markup> }` blocks inline.
//!
//! A `.zsx` file is ordinary Zig that contains one or more `zsx!{ ... }`
//! blocks. `preprocess` returns a `.zig` source string where every block is
//! replaced by the emitter's output for the single root element inside it.
//! Surrounding Zig is preserved verbatim.
//!
//! Two post-processing steps are applied per block:
//!   1. Preamble hoisting. When a block contains component children
//!      (`<Card>...</Card>`), the emitter returns a `preamble` with helper
//!      functions like `inline fn render_Card_N(...)`. These are collected
//!      and prepended at module scope, since Zig forbids nested fn decls.
//!   2. Indent shift. The emitter always starts at `makeIndent(1)=4sp`. We
//!      dedent by `(block_source_column - 4)` so the block's `{` lines up
//!      with the `zsx!{` in the source.
//!
//! Contract for the enclosing scope:
//!   - Parameters must be named `ui`, `c`, `ctx` (any types).
//!   - `ctx` must expose the methods/fields the markup references.
//!   - Do not `_ = ui;` / `_ = c;` / `_ = ctx;` if the block uses them.
//!
//! `src_name` is used only for error messages: parser failures produce
//! `<src_name>:<line>:<col>: <msg>` so users can jump directly to the bad
//! markup in their `.zsx` file.

const std = @import("std");
const ast = @import("ast.zig");
const zsx_parser = @import("parser.zig");
const codegen = @import("codegen.zig");

pub const BLOCK_STRIDE: usize = 10_000;

pub fn preprocess(
    comptime source: []const u8,
    comptime src_name: []const u8,
    comptime file_index: usize,
) []const u8 {
    @setEvalBranchQuota(2_000_000);
    var out: []const u8 = "";
    var preamble_acc: []const u8 = "";
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
            const blk = parseBlock(source, src_name, pos);
            const block_file_index = file_index * BLOCK_STRIDE + block_idx;
            const result = codegen.emitElement(blk.el, 1, 0, 0, block_file_index);
            preamble_acc = preamble_acc ++ result.preamble;
            var lead: usize = 0;
            while (lead < out.len and out[out.len - 1 - lead] == ' ') lead += 1;
            out = out[0 .. out.len - lead];
            const delta: isize = @as(isize, @intCast(lead)) - 4;
            out = out ++ shiftLines(result.code, delta);
            pos = blk.end;
            block_idx += 1;
            continue;
        }
        const chunk_start = pos;
        pos += 1;
        while (pos < source.len and !isSpecial(source[pos])) pos += 1;
        out = out ++ source[chunk_start..pos];
    }
    const body = preamble_acc ++ out;
    const needs_std = std.mem.indexOf(u8, body, "std.") != null;
    const has_std = std.mem.indexOf(u8, body, "@import(\"std\")") != null;
    if (needs_std and !has_std) {
        return "const std = @import(\"std\");\n\n" ++ body;
    }
    return body;
}

const Block = struct {
    el: ast.Element,
    end: usize,
};

fn parseBlock(comptime source: []const u8, comptime src_name: []const u8, comptime start: usize) Block {
    var pos = start + 5;
    while (pos < source.len and isWs(source[pos])) pos += 1;
    const el = zsx_parser.parseElement(source, src_name, &pos);
    while (pos < source.len and isWs(source[pos])) pos += 1;
    if (pos >= source.len or source[pos] != '}') {
        @compileError(src_name ++ ": zsx: expected '}' to close zsx!{ block");
    }
    pos += 1;
    if (pos < source.len and source[pos] == ';') pos += 1;
    return .{ .el = el, .end = pos };
}

fn shiftLines(comptime code: []const u8, comptime delta: isize) []const u8 {
    @setEvalBranchQuota(1_000_000);
    if (delta == 0) return code;
    const d: usize = @intCast(if (delta > 0) delta else -delta);
    const add = delta > 0;
    var out: []const u8 = "";
    var pos: usize = 0;
    while (pos < code.len) {
        if (add) {
            for (0..d) |_| out = out ++ " ";
        } else {
            var strip: usize = 0;
            while (strip < d and pos + strip < code.len and code[pos + strip] == ' ') strip += 1;
            pos += strip;
        }
        const nl = std.mem.indexOfScalarPos(u8, code, pos, '\n') orelse code.len;
        out = out ++ code[pos..nl];
        if (nl < code.len) {
            out = out ++ "\n";
            pos = nl + 1;
        } else {
            pos = nl;
        }
    }
    return out;
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
    try std.testing.expectEqualStrings("", comptime preprocess("", "test.zsx", 0));
}

test "preprocess no-block source is identity" {
    const s = "const x = 1;\n";
    try std.testing.expectEqualStrings(s, comptime preprocess(s, "test.zsx", 0));
}

test "preprocess single block emits column code" {
    const src = "zsx!{<column/>}";
    const out = comptime preprocess(src, "test.zsx", 0);
    try std.testing.expect(std.mem.indexOf(u8, out, "ui.column(c, ") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "zsx!{") == null);
}

test "preprocess preserves surrounding zig verbatim" {
    const src = "const pre = 1;\nzsx!{<label>Hi</label>}\nconst post = 2;\n";
    const out = comptime preprocess(src, "test.zsx", 0);
    try std.testing.expect(std.mem.startsWith(u8, out, "const pre = 1;\n"));
    try std.testing.expect(std.mem.endsWith(u8, out, "\nconst post = 2;\n"));
    try std.testing.expect(std.mem.indexOf(u8, out, "ui.text(c, \"Hi\"") != null);
}

test "preprocess consumes trailing semicolon" {
    const src = "zsx!{<column/>};";
    const out = comptime preprocess(src, "test.zsx", 0);
    try std.testing.expect(std.mem.indexOf(u8, out, "};") == null);
}

test "preprocess two blocks use distinct ids" {
    const src = "zsx!{<label>a</label>}\nzsx!{<label>b</label>}\n";
    const out = comptime preprocess(src, "test.zsx", 0);
    try std.testing.expect(std.mem.indexOf(u8, out, ".id_extra = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, ".id_extra = 10000000000000") != null);
}

test "preprocess block at nonzero file index uses that base" {
    const src = "zsx!{<label>x</label>}";
    const out = comptime preprocess(src, "test.zsx", 3);
    try std.testing.expect(std.mem.indexOf(u8, out, ".id_extra = 300000000000000000") != null);
}

test "preprocess ignores marker in string literal" {
    const src = "const s = \"zsx!{\";\n";
    const out = comptime preprocess(src, "test.zsx", 0);
    try std.testing.expectEqualStrings(src, out);
}

test "preprocess ignores marker in line comment" {
    const src = "// zsx!{ not a block\nconst x = 1;\n";
    const out = comptime preprocess(src, "test.zsx", 0);
    try std.testing.expectEqualStrings(src, out);
}

test "preprocess ignores marker in block comment" {
    const src = "/* zsx!{ not a block */\nconst x = 1;\n";
    const out = comptime preprocess(src, "test.zsx", 0);
    try std.testing.expectEqualStrings(src, out);
}

test "preprocess handles escaped quote in string literal" {
    const src = "const s = \"a\\\"zsx!{\";\n";
    const out = comptime preprocess(src, "test.zsx", 0);
    try std.testing.expectEqualStrings(src, out);
}

test "preprocess hoists component preamble to top" {
    const src = "pub fn view(ui: anytype, c: anytype, ctx: anytype) void {\n    zsx!{<Card><label>Title</label><label>Sub</label></Card>}\n}\n";
    const out = comptime preprocess(src, "test.zsx", 0);
    const view_idx = std.mem.indexOf(u8, out, "pub fn view") orelse unreachable;
    const render_idx = std.mem.indexOf(u8, out, "inline fn render_Card_") orelse unreachable;
    try std.testing.expect(render_idx < view_idx);
}

test "preprocess shifts block to match source column" {
    const src = "    zsx!{<label>x</label>}\n";
    const out = comptime preprocess(src, "test.zsx", 0);
    try std.testing.expect(std.mem.startsWith(u8, out, "    ui.text(c, "));
}

test "preprocess block at col 0 starts at col 0" {
    const src = "zsx!{<column><label>x</label></column>}\n";
    const out = comptime preprocess(src, "test.zsx", 0);
    try std.testing.expect(std.mem.startsWith(u8, out, "{\n"));
}
