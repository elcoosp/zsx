const std = @import("std");
const ast = @import("ast.zig");

pub const Element = ast.Element;
pub const Attribute = ast.Attribute;
pub const AttributeValue = ast.AttributeValue;
pub const Child = ast.Child;

pub fn parse(comptime src: []const u8) Element {
    return comptime blk: {
        var pos: usize = 0;
        const el = parseElement(src, &pos);
        if (pos != src.len) @compileError("trailing input after root element");
        break :blk el;
    };
}

fn parseElement(comptime src: []const u8, pos: *usize) Element {
    if (pos.* >= src.len or src[pos.*] != '<') @compileError("expected '<'");
    pos.* += 1;
    const tag_start = pos.*;
    while (pos.* < src.len and isTagChar(src[pos.*])) pos.* += 1;
    if (pos.* == tag_start) @compileError("expected tag name");
    const tag = src[tag_start..pos.*];

    var attrs_buf: [16]Attribute = undefined;
    var attr_count: usize = 0;

    while (true) {
        while (pos.* < src.len and src[pos.*] == ' ') pos.* += 1;
        if (pos.* >= src.len) @compileError("unexpected EOF in opening tag");
        const c = src[pos.*];
        if (c == '>') {
            pos.* += 1;
            break;
        }
        if (c == '/') {
            pos.* += 1;
            if (pos.* >= src.len or src[pos.*] != '>') @compileError("expected '>' after '/'");
            pos.* += 1;
            return .{
                .tag = tag,
                .attributes = attrs_buf[0..attr_count],
                .children = &[_]Child{},
            };
        }
        if (attr_count >= attrs_buf.len) @compileError("too many attributes");
        attrs_buf[attr_count] = parseAttribute(src, pos);
        attr_count += 1;
    }

    var children_buf: [32]Child = undefined;
    var child_count: usize = 0;

    while (true) {
        if (pos.* >= src.len) @compileError("unexpected EOF inside element");
        if (src[pos.*] == '<' and pos.* + 1 < src.len and src[pos.* + 1] == '/') {
            pos.* += 2;
            const close_start = pos.*;
            while (pos.* < src.len and isTagChar(src[pos.*])) pos.* += 1;
            const close_tag = src[close_start..pos.*];
            if (!std.mem.eql(u8, close_tag, tag)) @compileError("mismatched closing tag");
            if (pos.* >= src.len or src[pos.*] != '>') @compileError("expected '>' after closing tag");
            pos.* += 1;
            break;
        }
        if (child_count >= children_buf.len) @compileError("too many children");
        children_buf[child_count] = parseChild(src, pos);
        child_count += 1;
    }

    return .{
        .tag = tag,
        .attributes = attrs_buf[0..attr_count],
        .children = children_buf[0..child_count],
    };
}

fn parseAttribute(comptime src: []const u8, pos: *usize) Attribute {
    const name_start = pos.*;
    while (pos.* < src.len and isAttrNameChar(src[pos.*])) pos.* += 1;
    if (pos.* == name_start) @compileError("expected attribute name");
    const name = src[name_start..pos.*];

    if (pos.* >= src.len or src[pos.*] != '=') {
        return .{ .name = name, .value = .boolean };
    }
    pos.* += 1;

    if (pos.* >= src.len) @compileError("unexpected EOF in attribute value");

    const c = src[pos.*];
    if (c == '"') {
        pos.* += 1;
        const val_start = pos.*;
        while (pos.* < src.len and src[pos.*] != '"') pos.* += 1;
        if (pos.* >= src.len) @compileError("unterminated string attribute");
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
        if (pos.* >= src.len) @compileError("unterminated expression attribute");
        const val = src[val_start..pos.*];
        pos.* += 1;
        return .{ .name = name, .value = .{ .expression = val } };
    }
    @compileError("expected quoted string or {expression} in attribute value");
}

fn parseChild(comptime src: []const u8, pos: *usize) Child {
    if (src[pos.*] == '<') {
        return .{ .element = parseElement(src, pos) };
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
        if (pos.* >= src.len) @compileError("unterminated expression child");
        const val = src[val_start..pos.*];
        pos.* += 1;
        return .{ .expression = val };
    }
    const start = pos.*;
    while (pos.* < src.len and src[pos.*] != '<' and src[pos.*] != '{') pos.* += 1;
    if (pos.* == start) @compileError("expected text content");
    return .{ .text = src[start..pos.*] };
}

fn isTagChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-';
}

fn isAttrNameChar(c: u8) bool {
    return isTagChar(c) or c == ':' or c == '.';
}

test "parse simple element" {
    const el = parse("<column></column>");
    try std.testing.expectEqualStrings("column", el.tag);
    try std.testing.expectEqual(@as(usize, 0), el.attributes.len);
    try std.testing.expectEqual(@as(usize, 0), el.children.len);
}

test "parse boolean attribute" {
    const el = parse("<column flex></column>");
    try std.testing.expectEqual(@as(usize, 1), el.attributes.len);
    try std.testing.expectEqualStrings("flex", el.attributes[0].name);
    const v = el.attributes[0].value;
    switch (v) {
        .boolean => {},
        else => return error.TestUnexpectedResult,
    }
}

test "parse expression attribute" {
    const el = parse("<div gap={8}></div>");
    try std.testing.expectEqualStrings("gap", el.attributes[0].name);
    const v = el.attributes[0].value;
    switch (v) {
        .expression => |expr| try std.testing.expectEqualStrings("8", expr),
        else => return error.TestUnexpectedResult,
    }
}

test "parse string attribute" {
    const el = parse("<div class=\"p-4\"></div>");
    try std.testing.expectEqualStrings("class", el.attributes[0].name);
    const v = el.attributes[0].value;
    switch (v) {
        .string => |s| try std.testing.expectEqualStrings("p-4", s),
        else => return error.TestUnexpectedResult,
    }
}

test "parse self-closing" {
    const el = parse("<input />");
    try std.testing.expectEqualStrings("input", el.tag);
    try std.testing.expectEqual(@as(usize, 0), el.children.len);
}

test "parse text child" {
    const el = parse("<label>Hello</label>");
    try std.testing.expectEqual(@as(usize, 1), el.children.len);
    const c = el.children[0];
    switch (c) {
        .text => |t| try std.testing.expectEqualStrings("Hello", t),
        else => return error.TestUnexpectedResult,
    }
}

test "parse nested element" {
    const el = parse("<column><label>Hi</label></column>");
    try std.testing.expectEqual(@as(usize, 1), el.children.len);
    const c = el.children[0];
    switch (c) {
        .element => |child_el| {
            try std.testing.expectEqualStrings("label", child_el.tag);
            try std.testing.expectEqual(@as(usize, 1), child_el.children.len);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse expression child" {
    const el = parse("<label>{greeting}</label>");
    try std.testing.expectEqual(@as(usize, 1), el.children.len);
    const c = el.children[0];
    switch (c) {
        .expression => |expr| try std.testing.expectEqualStrings("greeting", expr),
        else => return error.TestUnexpectedResult,
    }
}

test "parse multiple attributes" {
    const el = parse("<button class=\"bg-blue-500\" on_click={save} disabled></button>");
    try std.testing.expectEqual(@as(usize, 3), el.attributes.len);
    try std.testing.expectEqualStrings("class", el.attributes[0].name);
    try std.testing.expectEqualStrings("on_click", el.attributes[1].name);
    try std.testing.expectEqualStrings("disabled", el.attributes[2].name);
}
