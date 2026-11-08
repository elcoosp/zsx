const std = @import("std");
const ast = @import("ast.zig");

pub const Element = ast.Element;
pub const Attribute = ast.Attribute;
pub const AttributeValue = ast.AttributeValue;
pub const Child = ast.Child;

pub fn parse(comptime src: []const u8, comptime src_name: []const u8) Element {
    @setEvalBranchQuota(1_000_000);
    return comptime blk: {
        var pos: usize = 0;
        const el = parseElement(src, src_name, &pos);
        if (pos != src.len) fail(src, src_name, pos, "trailing input after root element");
        break :blk el;
    };
}

pub fn parseElement(comptime src: []const u8, comptime src_name: []const u8, pos: *usize) Element {
    @setEvalBranchQuota(1_000_000);
    if (pos.* >= src.len or src[pos.*] != '<') fail(src, src_name, pos.*, "expected '<'");
    pos.* += 1;
    const tag_start = pos.*;
    while (pos.* < src.len and isTagChar(src[pos.*])) pos.* += 1;
    const tag = src[tag_start..pos.*];

    var attrs_buf: [16]Attribute = undefined;
    var attr_count: usize = 0;

    while (true) {
        while (pos.* < src.len and src[pos.*] == ' ') pos.* += 1;
        if (pos.* >= src.len) fail(src, src_name, pos.*, "unexpected EOF in opening tag");
        const c = src[pos.*];
        if (c == '>') {
            pos.* += 1;
            break;
        }
        if (c == '/') {
            pos.* += 1;
            if (pos.* >= src.len or src[pos.*] != '>') fail(src, src_name, pos.*, "expected '>' after '/'");
            pos.* += 1;
            return .{
                .tag = tag,
                .attributes = attrs_buf[0..attr_count],
                .children = &[_]Child{},
            };
        }
        if (attr_count >= attrs_buf.len) fail(src, src_name, pos.*, "too many attributes (max 16)");
        attrs_buf[attr_count] = parseAttribute(src, src_name, pos);
        attr_count += 1;
    }

    var children_buf: [32]Child = undefined;
    var child_count: usize = 0;

    while (true) {
        if (pos.* >= src.len) fail(src, src_name, pos.*, "unexpected EOF inside element");
        if (src[pos.*] == '<' and pos.* + 1 < src.len and src[pos.* + 1] == '/') {
            pos.* += 2;
            const close_start = pos.*;
            while (pos.* < src.len and isTagChar(src[pos.*])) pos.* += 1;
            const close_tag = src[close_start..pos.*];
            if (!std.mem.eql(u8, close_tag, tag)) {
                fail(src, src_name, close_start, "mismatched closing tag: <" ++ tag ++ "> closed by </" ++ close_tag ++ ">");
            }
            if (pos.* >= src.len or src[pos.*] != '>') fail(src, src_name, pos.*, "expected '>' after closing tag");
            pos.* += 1;
            break;
        }
        if (child_count >= children_buf.len) fail(src, src_name, pos.*, "too many children (max 32)");
        children_buf[child_count] = parseChild(src, src_name, pos);
        child_count += 1;
    }

    return .{
        .tag = tag,
        .attributes = attrs_buf[0..attr_count],
        .children = children_buf[0..child_count],
    };
}

fn parseAttribute(comptime src: []const u8, comptime src_name: []const u8, pos: *usize) Attribute {
    @setEvalBranchQuota(1_000_000);
    const name_start = pos.*;
    while (pos.* < src.len and isAttrNameChar(src[pos.*])) pos.* += 1;
    if (pos.* == name_start) fail(src, src_name, pos.*, "expected attribute name");
    const name = src[name_start..pos.*];

    if (pos.* >= src.len or src[pos.*] != '=') {
        return .{ .name = name, .value = .boolean };
    }
    pos.* += 1;

    if (pos.* >= src.len) fail(src, src_name, pos.*, "unexpected EOF in attribute value");

    const c = src[pos.*];
    if (c == '"') {
        pos.* += 1;
        const val_start = pos.*;
        while (pos.* < src.len and src[pos.*] != '"') pos.* += 1;
        if (pos.* >= src.len) fail(src, src_name, val_start, "unterminated string attribute");
        const val = src[val_start..pos.*];
        pos.* += 1;
        return .{ .name = name, .value = .{ .string = val } };
    }
    if (c == '{') {
        pos.* += 1;
        const val_start = pos.*;
        var depth: usize = 1;
        while (pos.* < src.len and depth > 0) {
            if (src[pos.*] == '{') depth += 1;
            if (src[pos.*] == '}') depth -= 1;
            if (depth > 0) pos.* += 1;
        }
        if (pos.* >= src.len) fail(src, src_name, val_start, "unterminated expression attribute");
        const val = src[val_start..pos.*];
        pos.* += 1;
        return .{ .name = name, .value = .{ .expression = val } };
    }
    fail(src, src_name, pos.*, "expected quoted string or {expression} in attribute value");
}

fn parseChild(comptime src: []const u8, comptime src_name: []const u8, pos: *usize) Child {
    @setEvalBranchQuota(1_000_000);
    if (src[pos.*] == '<') {
        return .{ .element = parseElement(src, src_name, pos) };
    }
    if (src[pos.*] == '{') {
        pos.* += 1;
        const val_start = pos.*;
        var depth: usize = 1;
        while (pos.* < src.len and depth > 0) {
            if (src[pos.*] == '{') depth += 1;
            if (src[pos.*] == '}') depth -= 1;
            if (depth > 0) pos.* += 1;
        }
        if (pos.* >= src.len) fail(src, src_name, val_start, "unterminated expression child");
        const val = src[val_start..pos.*];
        pos.* += 1;
        return .{ .expression = val };
    }
    const start = pos.*;
    while (pos.* < src.len and src[pos.*] != '<' and src[pos.*] != '{') pos.* += 1;
    if (pos.* == start) fail(src, src_name, pos.*, "expected text content");
    return .{ .text = src[start..pos.*] };
}

fn isTagChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-' or c == '.';
}

fn isAttrNameChar(c: u8) bool {
    return isTagChar(c) or c == ':' or c == '.';
}

fn fail(
    comptime src: []const u8,
    comptime src_name: []const u8,
    comptime offset: usize,
    comptime msg: []const u8,
) void {
    @setEvalBranchQuota(1_000_000);
    @compileError(formatSpan(src, src_name, offset) ++ msg);
}

fn formatSpan(
    comptime src: []const u8,
    comptime src_name: []const u8,
    comptime offset: usize,
) []const u8 {
    @setEvalBranchQuota(1_000_000);
    const clamped: usize = if (offset > src.len) src.len else offset;
    var line: usize = 1;
    var last_nl: usize = 0;
    var i: usize = 0;
    while (i < clamped) : (i += 1) {
        if (src[i] == '\n') {
            line += 1;
            last_nl = i + 1;
        }
    }
    const col = clamped - last_nl + 1;
    var out: []const u8 = "";
    out = out ++ src_name ++ ":" ++ fmtUsize(line) ++ ":" ++ fmtUsize(col) ++ ": ";
    return out;
}

fn fmtUsize(comptime n: usize) []const u8 {
    return comptime blk: {
        if (n == 0) break :blk "0";
        var tmp: [20]u8 = undefined;
        var len: usize = 0;
        var v = n;
        while (v > 0) {
            tmp[len] = '0' + @as(u8, @intCast(v % 10));
            v /= 10;
            len += 1;
        }
        var out: [20]u8 = undefined;
        for (0..len) |i| out[i] = tmp[len - 1 - i];
        const result: [len]u8 = out[0..len].*;
        break :blk &result;
    };
}

test "formatSpan line 1 col 1" {
    try std.testing.expectEqualStrings(
        "views/x.zsx:1:1: ",
        comptime formatSpan("abc", "views/x.zsx", 0),
    );
}

test "formatSpan line 2 col 2" {
    try std.testing.expectEqualStrings(
        "views/x.zsx:2:2: ",
        comptime formatSpan("abc\ndef\nghi", "views/x.zsx", 5),
    );
}

test "formatSpan line 3 col 1" {
    try std.testing.expectEqualStrings(
        "v:3:1: ",
        comptime formatSpan("abc\ndef\nghi", "v", 8),
    );
}

test "formatSpan offset at EOF clamps to src.len" {
    try std.testing.expectEqualStrings(
        "v:2:3: ",
        comptime formatSpan("a\nbc", "v", 100),
    );
}

test "fmtUsize small" {
    try std.testing.expectEqualStrings("0", comptime fmtUsize(0));
    try std.testing.expectEqualStrings("42", comptime fmtUsize(42));
    try std.testing.expectEqualStrings("1234", comptime fmtUsize(1234));
}

test "parse simple element" {
    comptime {
        const el = parse("<column></column>", "test.zsx");
        if (!std.mem.eql(u8, el.tag, "column")) @compileError("tag should be column");
        if (el.attributes.len != 0) @compileError("should have 0 attributes");
        if (el.children.len != 0) @compileError("should have 0 children");
    }
}

test "parse boolean attribute" {
    comptime {
        const el = parse("<column flex></column>", "test.zsx");
        if (el.attributes.len != 1) @compileError("should have 1 attribute");
        if (!std.mem.eql(u8, el.attributes[0].name, "flex")) @compileError("attr name should be flex");
        switch (el.attributes[0].value) {
            .boolean => {},
            else => @compileError("expected boolean attribute"),
        }
    }
}

test "parse expression attribute" {
    comptime {
        const el = parse("<div gap={8}></div>", "test.zsx");
        if (!std.mem.eql(u8, el.attributes[0].name, "gap")) @compileError("attr name should be gap");
        switch (el.attributes[0].value) {
            .expression => |expr| {
                if (!std.mem.eql(u8, expr, "8")) @compileError("expr should be 8");
            },
            else => @compileError("expected expression attribute"),
        }
    }
}

test "parse string attribute" {
    comptime {
        const el = parse("<div class=\"p-4\"></div>", "test.zsx");
        if (!std.mem.eql(u8, el.attributes[0].name, "class")) @compileError("attr name should be class");
        switch (el.attributes[0].value) {
            .string => |s| {
                if (!std.mem.eql(u8, s, "p-4")) @compileError("string should be p-4");
            },
            else => @compileError("expected string attribute"),
        }
    }
}

test "parse self-closing" {
    comptime {
        const el = parse("<input />", "test.zsx");
        if (!std.mem.eql(u8, el.tag, "input")) @compileError("tag should be input");
        if (el.children.len != 0) @compileError("should have 0 children");
    }
}

test "parse text child" {
    comptime {
        const el = parse("<label>Hello</label>", "test.zsx");
        if (el.children.len != 1) @compileError("should have 1 child");
        switch (el.children[0]) {
            .text => |t| {
                if (!std.mem.eql(u8, t, "Hello")) @compileError("text should be Hello");
            },
            else => @compileError("expected text child"),
        }
    }
}

test "parse nested element" {
    comptime {
        const el = parse("<column><label>Hi</label></column>", "test.zsx");
        if (el.children.len != 1) @compileError("should have 1 child");
        switch (el.children[0]) {
            .element => |child_el| {
                if (!std.mem.eql(u8, child_el.tag, "label")) @compileError("child tag should be label");
                if (child_el.children.len != 1) @compileError("child should have 1 child");
            },
            else => @compileError("expected element child"),
        }
    }
}

test "parse expression child" {
    comptime {
        const el = parse("<label>{greeting}</label>", "test.zsx");
        if (el.children.len != 1) @compileError("should have 1 child");
        switch (el.children[0]) {
            .expression => |expr| {
                if (!std.mem.eql(u8, expr, "greeting")) @compileError("expr should be greeting");
            },
            else => @compileError("expected expression child"),
        }
    }
}

test "parse multiple attributes" {
    comptime {
        const el = parse("<button class=\"bg-blue-500\" on_click={save} disabled></button>", "test.zsx");
        if (el.attributes.len != 3) @compileError("should have 3 attributes");
        if (!std.mem.eql(u8, el.attributes[0].name, "class")) @compileError("attr 0 should be class");
        if (!std.mem.eql(u8, el.attributes[1].name, "on_click")) @compileError("attr 1 should be on_click");
        if (!std.mem.eql(u8, el.attributes[2].name, "disabled")) @compileError("attr 2 should be disabled");
    }
}

test "parse path-qualified tag" {
    comptime {
        const el = parse("<shadcn.Button>Save</shadcn.Button>", "test.zsx");
        if (!std.mem.eql(u8, el.tag, "shadcn.Button")) @compileError("tag should be shadcn.Button");
    }
}
