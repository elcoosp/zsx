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

pub fn parseElement(comptime src: []const u8, pos: *usize) Element {
    if (pos.* >= src.len or src[pos.*] != '<') @compileError("expected '<'");
    pos.* += 1;
    const tag_start = pos.*;
    while (pos.* < src.len and isTagChar(src[pos.*])) pos.* += 1;
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
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-' or c == '.';
}

fn isAttrNameChar(c: u8) bool {
    return isTagChar(c) or c == ':' or c == '.';
}

test "parse simple element" {
    comptime {
        const el = parse("<column></column>");
        if (!std.mem.eql(u8, el.tag, "column")) @compileError("tag should be column");
        if (el.attributes.len != 0) @compileError("should have 0 attributes");
        if (el.children.len != 0) @compileError("should have 0 children");
    }
}

test "parse boolean attribute" {
    comptime {
        const el = parse("<column flex></column>");
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
        const el = parse("<div gap={8}></div>");
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
        const el = parse("<div class=\"p-4\"></div>");
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
        const el = parse("<input />");
        if (!std.mem.eql(u8, el.tag, "input")) @compileError("tag should be input");
        if (el.children.len != 0) @compileError("should have 0 children");
    }
}

test "parse text child" {
    comptime {
        const el = parse("<label>Hello</label>");
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
        const el = parse("<column><label>Hi</label></column>");
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
        const el = parse("<label>{greeting}</label>");
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
        const el = parse("<button class=\"bg-blue-500\" on_click={save} disabled></button>");
        if (el.attributes.len != 3) @compileError("should have 3 attributes");
        if (!std.mem.eql(u8, el.attributes[0].name, "class")) @compileError("attr 0 should be class");
        if (!std.mem.eql(u8, el.attributes[1].name, "on_click")) @compileError("attr 1 should be on_click");
        if (!std.mem.eql(u8, el.attributes[2].name, "disabled")) @compileError("attr 2 should be disabled");
    }
}
