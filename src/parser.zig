const std = @import("std");
const ast = @import("ast.zig");

pub const ParseError = error{
    UnexpectedEof,
    ExpectedTagStart,
    ExpectedTagName,
    ExpectedClose,
    MismatchedTag,
    ExpectedAttrName,
    UnterminatedString,
    UnterminatedExpression,
    TooManyNestingLevels,
    TrailingInput,
    OutOfMemory,
};

pub const Result = struct {
    arena: std.heap.ArenaAllocator,
    root: ast.Element,

    pub fn deinit(self: *Result) void {
        self.arena.deinit();
    }
};

pub fn parse(source: []const u8) ParseError!Result {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();

    var pos: usize = 0;
    const root = try parseElement(alloc, source, &pos, 0);
    if (pos != source.len) return error.TrailingInput;
    return .{ .arena = arena, .root = root };
}

fn parseElement(alloc: std.mem.Allocator, src: []const u8, pos: *usize, depth: usize) ParseError!ast.Element {
    if (depth > 256) return error.TooManyNestingLevels;
    if (pos.* >= src.len or src[pos.*] != '<') return error.ExpectedTagStart;
    pos.* += 1;

    const tag_start = pos.*;
    while (pos.* < src.len and isTagChar(src[pos.*])) pos.* += 1;
    if (pos.* == tag_start) return error.ExpectedTagName;
    const tag = try alloc.dupe(u8, src[tag_start..pos.*]);

    var attrs: std.ArrayList(ast.Attribute) = .empty;
    errdefer attrs.deinit(alloc);
    var self_closed = false;

    while (true) {
        while (pos.* < src.len and src[pos.*] == ' ') pos.* += 1;
        if (pos.* >= src.len) return error.UnexpectedEof;
        const c = src[pos.*];
        if (c == '>') {
            pos.* += 1;
            break;
        }
        if (c == '/') {
            pos.* += 1;
            if (pos.* >= src.len or src[pos.*] != '>') return error.ExpectedClose;
            pos.* += 1;
            self_closed = true;
            break;
        }
        const attr = try parseAttribute(alloc, src, pos);
        try attrs.append(alloc, attr);
    }

    var children: std.ArrayList(ast.Child) = .empty;
    errdefer children.deinit(alloc);

    if (!self_closed) {
        while (true) {
            if (pos.* >= src.len) return error.UnexpectedEof;
            if (src[pos.*] == '<' and pos.* + 1 < src.len and src[pos.* + 1] == '/') {
                pos.* += 2;
                const close_start = pos.*;
                while (pos.* < src.len and isTagChar(src[pos.*])) pos.* += 1;
                const close_tag = src[close_start..pos.*];
                if (!std.mem.eql(u8, close_tag, tag)) return error.MismatchedTag;
                if (pos.* >= src.len or src[pos.*] != '>') return error.ExpectedClose;
                pos.* += 1;
                break;
            }
            const child = try parseChild(alloc, src, pos, depth + 1);
            try children.append(alloc, child);
        }
    }

    return .{
        .tag = tag,
        .attributes = try attrs.toOwnedSlice(alloc),
        .children = try children.toOwnedSlice(alloc),
    };
}

fn parseAttribute(alloc: std.mem.Allocator, src: []const u8, pos: *usize) ParseError!ast.Attribute {
    const name_start = pos.*;
    while (pos.* < src.len and isAttrNameChar(src[pos.*])) pos.* += 1;
    if (pos.* == name_start) return error.ExpectedAttrName;
    const name = try alloc.dupe(u8, src[name_start..pos.*]);

    if (pos.* >= src.len or src[pos.*] != '=') {
        return .{ .name = name, .value = .boolean };
    }
    pos.* += 1;
    if (pos.* >= src.len) return error.UnexpectedEof;

    const c = src[pos.*];
    if (c == '"') {
        pos.* += 1;
        const val_start = pos.*;
        while (pos.* < src.len and src[pos.*] != '"') pos.* += 1;
        if (pos.* >= src.len) return error.UnterminatedString;
        const val = try alloc.dupe(u8, src[val_start..pos.*]);
        pos.* += 1;
        return .{ .name = name, .value = .{ .string = val } };
    }
    if (c == '{') {
        pos.* += 1;
        const val_start = pos.*;
        var bracket_depth: usize = 1;
        while (pos.* < src.len and bracket_depth > 0) {
            if (src[pos.*] == '{') bracket_depth += 1;
            if (src[pos.*] == '}') bracket_depth -= 1;
            if (bracket_depth > 0) pos.* += 1;
        }
        if (pos.* >= src.len) return error.UnterminatedExpression;
        const val = try alloc.dupe(u8, src[val_start..pos.*]);
        pos.* += 1;
        return .{ .name = name, .value = .{ .expression = val } };
    }
    return error.ExpectedAttrName;
}

fn parseChild(alloc: std.mem.Allocator, src: []const u8, pos: *usize, depth: usize) ParseError!ast.Child {
    if (src[pos.*] == '<') {
        return .{ .element = try parseElement(alloc, src, pos, depth) };
    }
    if (src[pos.*] == '{') {
        pos.* += 1;
        const val_start = pos.*;
        var bracket_depth: usize = 1;
        while (pos.* < src.len and bracket_depth > 0) {
            if (src[pos.*] == '{') bracket_depth += 1;
            if (src[pos.*] == '}') bracket_depth -= 1;
            if (bracket_depth > 0) pos.* += 1;
        }
        if (pos.* >= src.len) return error.UnterminatedExpression;
        const val = try alloc.dupe(u8, src[val_start..pos.*]);
        pos.* += 1;
        return .{ .expression = val };
    }
    const start = pos.*;
    while (pos.* < src.len and src[pos.*] != '<' and src[pos.*] != '{') pos.* += 1;
    if (pos.* == start) return error.ExpectedTagName;
    return .{ .text = try alloc.dupe(u8, src[start..pos.*]) };
}

fn isTagChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-';
}

fn isAttrNameChar(c: u8) bool {
    return isTagChar(c) or c == ':' or c == '.';
}

test "parse simple element" {
    var r = try parse("<column></column>");
    defer r.deinit();
    try std.testing.expectEqualStrings("column", r.root.tag);
    try std.testing.expectEqual(@as(usize, 0), r.root.attributes.len);
    try std.testing.expectEqual(@as(usize, 0), r.root.children.len);
}

test "parse boolean attribute" {
    var r = try parse("<column flex></column>");
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 1), r.root.attributes.len);
    try std.testing.expectEqualStrings("flex", r.root.attributes[0].name);
    switch (r.root.attributes[0].value) {
        .boolean => {},
        else => return error.TestUnexpectedResult,
    }
}

test "parse expression attribute" {
    var r = try parse("<div gap={8}></div>");
    defer r.deinit();
    try std.testing.expectEqualStrings("gap", r.root.attributes[0].name);
    switch (r.root.attributes[0].value) {
        .expression => |e| try std.testing.expectEqualStrings("8", e),
        else => return error.TestUnexpectedResult,
    }
}

test "parse string attribute" {
    var r = try parse("<div class=\"p-4\"></div>");
    defer r.deinit();
    switch (r.root.attributes[0].value) {
        .string => |s| try std.testing.expectEqualStrings("p-4", s),
        else => return error.TestUnexpectedResult,
    }
}

test "parse self closing" {
    var r = try parse("<input />");
    defer r.deinit();
    try std.testing.expectEqualStrings("input", r.root.tag);
    try std.testing.expectEqual(@as(usize, 0), r.root.children.len);
}

test "parse text child" {
    var r = try parse("<label>Hello</label>");
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 1), r.root.children.len);
    switch (r.root.children[0]) {
        .text => |t| try std.testing.expectEqualStrings("Hello", t),
        else => return error.TestUnexpectedResult,
    }
}

test "parse expression child" {
    var r = try parse("<label>{ctx.user.name}</label>");
    defer r.deinit();
    switch (r.root.children[0]) {
        .expression => |e| try std.testing.expectEqualStrings("ctx.user.name", e),
        else => return error.TestUnexpectedResult,
    }
}

test "parse nested element" {
    var r = try parse("<column><label>Hi</label></column>");
    defer r.deinit();
    switch (r.root.children[0]) {
        .element => |el| try std.testing.expectEqualStrings("label", el.tag),
        else => return error.TestUnexpectedResult,
    }
}

test "parse multiple attributes" {
    var r = try parse("<button class=\"bg-blue-500\" on_click={ctx.save} disabled></button>");
    defer r.deinit();
    try std.testing.expectEqual(@as(usize, 3), r.root.attributes.len);
    try std.testing.expectEqualStrings("class", r.root.attributes[0].name);
    try std.testing.expectEqualStrings("on_click", r.root.attributes[1].name);
    try std.testing.expectEqualStrings("disabled", r.root.attributes[2].name);
}
