//! Tolerant tokenizer for the markup inside a `zsx!{ ... }` block.
//!
//! `src/rt/parser.zig` is fail-fast: the first problem aborts parsing and the
//! caller only gets a bare `error.ZsxParseError`. Tooling needs the opposite
//! contract — recover, tokenize as much as possible, and keep byte offsets so
//! diagnostics can point at the source. This scanner is that seam:
//!
//! - never fails; unparseable input becomes a `junk` token with a message;
//! - every token carries absolute file offsets (`off`/`end`) so `diag.zig`
//!   can build spans without re-deriving positions;
//! - brace matching is string-aware (a `'}'` inside `{"}"}` no longer ends
//!   the expression — reproducer F5);
//! - attribute scanning skips any whitespace, not just spaces (reproducer F5
//!   second case: newline between attributes);
//! - control-flow tokens are classified (`{if}`, `{:else}`, `{:case}`,
//!   `{/if}`, legacy `{endif}`) so the checker and the future native
//!   formatter share one front-end instead of each re-implementing the
//!   grammar with regexes (master-plan finding F11: "three parsers").
//!
//! Tokens are slices of the caller's source (zero-copy). Callers allocate an
//! arena for the token list only.

const std = @import("std");

pub const CtrlKind = enum { if_, for_, switch_ };

/// Human-readable name used in diagnostics ("{if} never closed").
pub fn ctrlName(k: CtrlKind) []const u8 {
    return switch (k) {
        .if_ => "if",
        .for_ => "for",
        .switch_ => "switch",
    };
}

pub const MidKind = enum { else_, case_ };

pub const AttrValue = union(enum) {
    boolean,
    string: []const u8,
    expression: []const u8,
};

pub const Attr = struct {
    name: []const u8,
    value: AttrValue,
    off: usize,
};

pub const OpenTag = struct {
    /// Tag name, `""` for fragments (`<>`).
    tag: []const u8,
    self_closing: bool,
    attrs: []const Attr,
    off: usize,
    end: usize,
};

pub const CloseTag = struct {
    /// Tag name, `""` for fragment closes (`</>`).
    tag: []const u8,
    off: usize,
    end: usize,
};

pub const CtrlOpen = struct { kind: CtrlKind, off: usize, end: usize };
pub const CtrlMid = struct { kind: MidKind, off: usize, end: usize };
pub const CtrlClose = struct {
    kind: CtrlKind,
    /// True for legacy `{endif}`/`{endfor}`/`{endswitch}` aliases.
    legacy: bool,
    off: usize,
    end: usize,
};

pub const Junk = struct {
    msg: []const u8,
    off: usize,
    end: usize,
};

pub const Token = union(enum) {
    open_tag: OpenTag,
    close_tag: CloseTag,
    ctrl_open: CtrlOpen,
    ctrl_mid: CtrlMid,
    ctrl_close: CtrlClose,
    /// `{expr}` child; `raw` includes the braces.
    expression: struct { raw: []const u8, off: usize, end: usize },
    /// Raw text run between structural tokens.
    text: struct { raw: []const u8, off: usize, end: usize },
    /// Unparseable input; scanning continues after it (error recovery).
    junk: Junk,

    pub fn off(self: Token) usize {
        return switch (self) {
            inline else => |t| t.off,
        };
    }

    pub fn end(self: Token) usize {
        return switch (self) {
            inline else => |t| t.end,
        };
    }
};

pub const Scanner = struct {
    a: std.mem.Allocator,
    src: []const u8,
    /// Absolute file offset of `src[0]` (for block scanning inside a file).
    base: usize,
    toks: std.array_list.Managed(Token),

    pub fn init(a: std.mem.Allocator, markup: []const u8, base: usize) Scanner {
        return .{
            .a = a,
            .src = markup,
            .base = base,
            .toks = std.array_list.Managed(Token).init(a),
        };
    }

    /// Tokenize the whole markup; returns the token list.
    pub fn run(self: *Scanner) ![]const Token {
        var i: usize = 0;
        while (i < self.src.len) {
            const c = self.src[i];
            if (c == '<') {
                i = try self.scanTag(i);
            } else if (c == '{') {
                i = try self.scanBrace(i);
            } else {
                i = try self.scanText(i);
            }
        }
        return try self.toks.toOwnedSlice();
    }

    fn abs(self: *const Scanner, i: usize) usize {
        return self.base + i;
    }

    fn append(self: *Scanner, t: Token) !void {
        try self.toks.append(t);
    }

    fn scanText(self: *Scanner, start: usize) !usize {
        var i = start;
        while (i < self.src.len and self.src[i] != '<' and self.src[i] != '{') i += 1;
        try self.append(.{ .text = .{ .raw = self.src[start..i], .off = self.abs(start), .end = self.abs(i) } });
        return i;
    }

    fn scanBrace(self: *Scanner, start: usize) !usize {
        const close = self.matchBrace(start) orelse {
            try self.append(.{ .junk = .{
                .msg = "unterminated expression: no matching '}'",
                .off = self.abs(start),
                .end = self.abs(self.src.len),
            } });
            return self.src.len;
        };
        const inner = std.mem.trim(u8, self.src[start + 1 .. close], " \t\r\n");
        const tok_start = self.abs(start);
        const tok_end = self.abs(close + 1);
        if (inner.len > 0 and inner[0] == '/') {
            const kind_str = std.mem.trim(u8, inner[1..], " \t\r\n");
            if (ctrlKindFromString(kind_str)) |k| {
                try self.append(.{ .ctrl_close = .{ .kind = k, .legacy = false, .off = tok_start, .end = tok_end } });
                return close + 1;
            }
            if (legacyEndFromString(kind_str)) |k| {
                try self.append(.{ .ctrl_close = .{ .kind = k, .legacy = true, .off = tok_start, .end = tok_end } });
                return close + 1;
            }
            // `{/something-else}` — treated as an expression by the old
            // tokenizer; keep the same lenient behaviour.
            try self.append(.{ .expression = .{ .raw = self.src[start .. close + 1], .off = tok_start, .end = tok_end } });
            return close + 1;
        }
        if (std.mem.startsWith(u8, inner, ":case")) {
            try self.append(.{ .ctrl_mid = .{ .kind = .case_, .off = tok_start, .end = tok_end } });
            return close + 1;
        }
        if (std.mem.startsWith(u8, inner, ":else")) {
            try self.append(.{ .ctrl_mid = .{ .kind = .else_, .off = tok_start, .end = tok_end } });
            return close + 1;
        }
        if (std.mem.startsWith(u8, inner, "if ") or std.mem.eql(u8, inner, "if")) {
            try self.append(.{ .ctrl_open = .{ .kind = .if_, .off = tok_start, .end = tok_end } });
            return close + 1;
        }
        if (std.mem.startsWith(u8, inner, "switch ")) {
            try self.append(.{ .ctrl_open = .{ .kind = .switch_, .off = tok_start, .end = tok_end } });
            return close + 1;
        }
        if (std.mem.startsWith(u8, inner, "for ") and std.mem.indexOf(u8, inner, " as ") != null) {
            try self.append(.{ .ctrl_open = .{ .kind = .for_, .off = tok_start, .end = tok_end } });
            return close + 1;
        }
        if (legacyEndFromString(inner)) |k| {
            try self.append(.{ .ctrl_close = .{ .kind = k, .legacy = true, .off = tok_start, .end = tok_end } });
            return close + 1;
        }
        try self.append(.{ .expression = .{ .raw = self.src[start .. close + 1], .off = tok_start, .end = tok_end } });
        return close + 1;
    }

    /// String-aware brace matching from the '{' at `start`.
    fn matchBrace(self: *const Scanner, start: usize) ?usize {
        var depth: usize = 0;
        var i = start;
        while (i < self.src.len) {
            const c = self.src[i];
            if (c == '"') {
                i = self.skipString(i);
                continue;
            }
            if (c == '\'') {
                i = self.skipChar(i);
                continue;
            }
            if (c == '{') depth += 1;
            if (c == '}') {
                depth -= 1;
                if (depth == 0) return i;
            }
            i += 1;
        }
        return null;
    }

    fn skipString(self: *const Scanner, start: usize) usize {
        var i = start + 1;
        while (i < self.src.len) : (i += 1) {
            if (self.src[i] == '\\' and i + 1 < self.src.len) {
                i += 2;
                continue;
            }
            if (self.src[i] == '"') return i + 1;
        }
        return i;
    }

    fn skipChar(self: *const Scanner, start: usize) usize {
        var i = start + 1;
        while (i < self.src.len) : (i += 1) {
            if (self.src[i] == '\\' and i + 1 < self.src.len) {
                i += 2;
                continue;
            }
            if (self.src[i] == '\'') return i + 1;
        }
        return i;
    }

    /// Returns the index just past the tag token.
    fn scanTag(self: *Scanner, start: usize) !usize {
        // Fragment close `</>`
        if (self.startsWithAt(start, "</>")) {
            try self.append(.{ .close_tag = .{ .tag = "", .off = self.abs(start), .end = self.abs(start + 3) } });
            return start + 3;
        }
        // Fragment open `<>`
        if (self.startsWithAt(start, "<>")) {
            try self.append(.{ .open_tag = .{ .tag = "", .self_closing = false, .attrs = &.{}, .off = self.abs(start), .end = self.abs(start + 2) } });
            return start + 2;
        }
        // Closing tag `</tag>`
        if (self.startsWithAt(start, "</")) {
            var i = start + 2;
            const tag_start = i;
            while (i < self.src.len and isTagChar(self.src[i])) i += 1;
            const tag = self.src[tag_start..i];
            while (i < self.src.len and isSpace(self.src[i])) i += 1;
            if (i >= self.src.len or self.src[i] != '>') {
                try self.append(.{ .junk = .{
                    .msg = "unterminated closing tag: expected '>'",
                    .off = self.abs(start),
                    .end = self.abs(@min(i + 1, self.src.len)),
                } });
                return @min(i + 1, self.src.len);
            }
            try self.append(.{ .close_tag = .{ .tag = tag, .off = self.abs(start), .end = self.abs(i + 1) } });
            return i + 1;
        }
        // Opening tag `<tag ...>` / `<tag ... />`
        if (self.src[start] == '<' and start + 1 < self.src.len and isTagChar(self.src[start + 1])) {
            var i = start + 1;
            const tag_start = i;
            while (i < self.src.len and isTagChar(self.src[i])) i += 1;
            const tag = self.src[tag_start..i];

            var attrs = std.array_list.Managed(Attr).init(self.a);
            while (true) {
                while (i < self.src.len and isSpace(self.src[i])) i += 1;
                if (i >= self.src.len) {
                    try self.append(.{ .junk = .{
                        .msg = "unterminated opening tag: expected '>'",
                        .off = self.abs(start),
                        .end = self.abs(self.src.len),
                    } });
                    return self.src.len;
                }
                if (self.src[i] == '>') {
                    try self.append(.{ .open_tag = .{
                        .tag = tag,
                        .self_closing = false,
                        .attrs = try attrs.toOwnedSlice(),
                        .off = self.abs(start),
                        .end = self.abs(i + 1),
                    } });
                    return i + 1;
                }
                if (self.src[i] == '/' and i + 1 < self.src.len and self.src[i + 1] == '>') {
                    try self.append(.{ .open_tag = .{
                        .tag = tag,
                        .self_closing = true,
                        .attrs = try attrs.toOwnedSlice(),
                        .off = self.abs(start),
                        .end = self.abs(i + 2),
                    } });
                    return i + 2;
                }
                const attr_off = i;
                const name_start = i;
                while (i < self.src.len and isAttrNameChar(self.src[i])) i += 1;
                const name = self.src[name_start..i];
                if (name.len == 0) {
                    // Stray character inside a tag: skip it and keep going so
                    // one typo does not hide every later diagnostic.
                    try self.append(.{ .junk = .{
                        .msg = "unexpected character inside opening tag",
                        .off = self.abs(i),
                        .end = self.abs(i + 1),
                    } });
                    i += 1;
                    continue;
                }
                var value: AttrValue = .boolean;
                if (i < self.src.len and self.src[i] == '=') {
                    i += 1;
                    if (i < self.src.len and self.src[i] == '"') {
                        const v_start = i + 1;
                        var j = v_start;
                        while (j < self.src.len and self.src[j] != '"') j += 1;
                        if (j >= self.src.len) {
                            try self.append(.{ .junk = .{
                                .msg = "unterminated string attribute",
                                .off = self.abs(i),
                                .end = self.abs(self.src.len),
                            } });
                            return self.src.len;
                        }
                        value = .{ .string = self.src[v_start..j] };
                        i = j + 1;
                    } else if (i < self.src.len and self.src[i] == '{') {
                        const close = self.matchBrace(i) orelse {
                            try self.append(.{ .junk = .{
                                .msg = "unterminated expression attribute: no matching '}'",
                                .off = self.abs(i),
                                .end = self.abs(self.src.len),
                            } });
                            return self.src.len;
                        };
                        value = .{ .expression = self.src[i + 1 .. close] };
                        i = close + 1;
                    }
                    // Anything else after `=` is tolerated as a boolean
                    // attribute so scanning can continue.
                }
                try attrs.append(.{ .name = name, .value = value, .off = self.abs(attr_off) });
            }
        }
        // Lone '<' with nothing tag-like after it.
        try self.append(.{ .junk = .{
            .msg = "stray '<' in markup",
            .off = self.abs(start),
            .end = self.abs(start + 1),
        } });
        return start + 1;
    }

    fn startsWithAt(self: *const Scanner, i: usize, prefix: []const u8) bool {
        if (i + prefix.len > self.src.len) return false;
        return std.mem.eql(u8, self.src[i .. i + prefix.len], prefix);
    }
};

fn ctrlKindFromString(s: []const u8) ?CtrlKind {
    if (std.mem.eql(u8, s, "if")) return .if_;
    if (std.mem.eql(u8, s, "for")) return .for_;
    if (std.mem.eql(u8, s, "switch")) return .switch_;
    return null;
}

fn legacyEndFromString(s: []const u8) ?CtrlKind {
    if (std.mem.eql(u8, s, "endif")) return .if_;
    if (std.mem.eql(u8, s, "endfor")) return .for_;
    if (std.mem.eql(u8, s, "endswitch")) return .switch_;
    return null;
}

pub fn isTagChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-' or c == '.';
}

pub fn isAttrNameChar(c: u8) bool {
    return isTagChar(c) or c == ':' or c == '.';
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// -- tests ---------------------------------------------------------------

const testing = std.testing;

/// Non-text tokens in order (markup whitespace becomes `text` runs; structural
/// assertions below only care about the latter).
fn structToks(a: std.mem.Allocator, toks: []const Token) ![]const Token {
    var out = std.array_list.Managed(Token).init(a);
    for (toks) |t| {
        if (t == .text) continue;
        try out.append(t);
    }
    return out.toOwnedSlice();
}

test "scan: open and close tag with offsets" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var s = Scanner.init(arena.allocator(), "<column></column>", 0);
    const toks = try s.run();
    try testing.expectEqual(@as(usize, 2), toks.len);
    try testing.expectEqualStrings("column", toks[0].open_tag.tag);
    try testing.expectEqual(@as(usize, 0), toks[0].off());
    try testing.expectEqual(@as(usize, 8), toks[1].off());
    try testing.expectEqual(@as(usize, 17), toks[1].end());
}

test "scan: newline between attributes tolerated (F5)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var s = Scanner.init(arena.allocator(), "<column\n  class=\"gap-2\"></column>", 0);
    const toks = try s.run();
    try testing.expectEqual(@as(usize, 2), toks.len);
    try testing.expectEqual(@as(usize, 1), toks[0].open_tag.attrs.len);
}

test "scan: brace matching is string-aware (F5)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var s = Scanner.init(arena.allocator(), "<label>{\"}\"}</label>", 0);
    const toks = try s.run();
    // open label, expression (one!), close label
    try testing.expectEqual(@as(usize, 3), toks.len);
    switch (toks[1]) {
        .expression => |e| try testing.expectEqualStrings("{\"}\"}", e.raw),
        else => return error.TestUnexpected,
    }
}

test "scan: control flow classification" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const markup =
        \\{if ctx.a}
        \\{:else if ctx.b}
        \\{for items as item}
        \\{switch s}{:case "x"}{:else}{/switch}
        \\{/if}
    ;
    var s = Scanner.init(arena.allocator(), markup, 0);
    const toks = try structToks(arena.allocator(), try s.run());
    try testing.expect(toks[0] == .ctrl_open and toks[0].ctrl_open.kind == .if_);
    try testing.expect(toks[1] == .ctrl_mid and toks[1].ctrl_mid.kind == .else_);
    try testing.expect(toks[2] == .ctrl_open and toks[2].ctrl_open.kind == .for_);
    try testing.expect(toks[3] == .ctrl_open and toks[3].ctrl_open.kind == .switch_);
    try testing.expect(toks[4] == .ctrl_mid and toks[4].ctrl_mid.kind == .case_);
    try testing.expect(toks[5] == .ctrl_mid and toks[5].ctrl_mid.kind == .else_);
    try testing.expect(toks[6] == .ctrl_close and toks[6].ctrl_close.kind == .switch_);
    try testing.expect(toks[7] == .ctrl_close and toks[7].ctrl_close.kind == .if_);
}

test "scan: legacy aliases flagged" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var s = Scanner.init(arena.allocator(), "{if a}{endif}", 0);
    const toks = try structToks(arena.allocator(), try s.run());
    try testing.expect(toks[1] == .ctrl_close and toks[1].ctrl_close.legacy);
}

test "scan: junk token on unterminated expression, scanning recovers" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var s = Scanner.init(arena.allocator(), "<label>{oops", 0);
    const toks = try s.run();
    try testing.expect(toks[1] == .junk);
}

test "scan: self-closing tag" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var s = Scanner.init(arena.allocator(), "<input buffer={&x} />", 0);
    const toks = try s.run();
    try testing.expect(toks[0] == .open_tag and toks[0].open_tag.self_closing);
    try testing.expectEqual(@as(usize, 1), toks[0].open_tag.attrs.len);
}

test "scan: fragment open and close" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var s = Scanner.init(arena.allocator(), "<>x</>", 0);
    const toks = try s.run();
    try testing.expectEqual(@as(usize, 3), toks.len);
    try testing.expect(toks[0] == .open_tag and toks[0].open_tag.tag.len == 0);
    try testing.expect(toks[2] == .close_tag and toks[2].close_tag.tag.len == 0);
}
