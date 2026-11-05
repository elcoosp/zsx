const std = @import("std");
const ast = @import("ast.zig");

pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
};

pub const FontWeight = enum { regular, semibold, bold };

pub const Expand = enum { none, horizontal, vertical, both };

pub const Spacing = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
};

pub const Style = struct {
    background: ?Color = null,
    hover_background: ?Color = null,
    foreground: ?Color = null,
    padding: ?Spacing = null,
    radius: ?f32 = null,
    gap: ?f32 = null,
    width: ?f32 = null,
    height: ?f32 = null,
    font_size: ?f32 = null,
    font_weight: ?FontWeight = null,
    expand: ?Expand = null,
};

pub fn parseClasses(comptime class: []const u8) Style {
    var style = Style{};
    comptime var i: usize = 0;
    inline while (i < class.len) {
        while (i < class.len and class[i] == ' ') i += 1;
        if (i >= class.len) break;
        const start = i;
        while (i < class.len and class[i] != ' ') i += 1;
        applyToken(&style, class[start..i]);
    }
    return style;
}

fn applyToken(style: *Style, comptime token: []const u8) void {
    if (std.mem.eql(u8, token, "bg-blue-500")) {
        style.background = .{ .r = 59, .g = 130, .b = 246 };
    } else if (std.mem.eql(u8, token, "bg-blue-600")) {
        style.hover_background = .{ .r = 37, .g = 99, .b = 235 };
    } else if (std.mem.eql(u8, token, "bg-gray-100")) {
        style.background = .{ .r = 243, .g = 244, .b = 246 };
    } else if (std.mem.eql(u8, token, "text-white")) {
        style.foreground = Color.white;
    } else if (std.mem.eql(u8, token, "text-black")) {
        style.foreground = Color.black;
    } else if (std.mem.eql(u8, token, "p-4")) {
        style.padding = .{ .x = 16, .y = 16, .w = 16, .h = 16 };
    } else if (std.mem.eql(u8, token, "p-2")) {
        style.padding = .{ .x = 8, .y = 8, .w = 8, .h = 8 };
    } else if (std.mem.eql(u8, token, "px-4")) {
        const cur: Spacing = style.padding orelse Spacing{};
        style.padding = .{ .x = 16, .y = cur.y, .w = 16, .h = cur.h };
    } else if (std.mem.eql(u8, token, "py-2")) {
        const cur: Spacing = style.padding orelse Spacing{};
        style.padding = .{ .x = cur.x, .y = 8, .w = cur.w, .h = 8 };
    } else if (std.mem.eql(u8, token, "rounded-lg")) {
        style.radius = 8;
    } else if (std.mem.eql(u8, token, "gap-2")) {
        style.gap = 8;
    } else if (std.mem.eql(u8, token, "text-lg")) {
        style.font_size = 18;
    } else if (std.mem.eql(u8, token, "font-bold")) {
        style.font_weight = .bold;
    } else {
        @compileError("unrecognized tailwind class '" ++ token ++ "'");
    }
}

pub fn parseNumeric(comptime s: []const u8) f32 {
    if (s.len == 0) @compileError("empty numeric attribute value");
    var result: f32 = 0;
    inline for (s) |ch| {
        if (ch < '0' or ch > '9') @compileError("non-numeric attribute value: '" ++ s ++ "'");
        result = result * 10.0 + @as(f32, @floatFromInt(ch - '0'));
    }
    return result;
}

pub fn firstText(comptime el: ast.Element) ?[]const u8 {
    inline for (el.children) |c| {
        switch (c) {
            .text => |t| return t,
            .expression => return null,
            .element => continue,
        }
    }
    return null;
}

pub fn styleFrom(comptime el: ast.Element) Style {
    var style = Style{};
    inline for (el.attributes) |attr| {
        if (comptime std.mem.eql(u8, attr.name, "class")) {
            switch (attr.value) {
                .string => |s| mergeStyle(&style, comptime parseClasses(s)),
                else => @compileError("class attribute must be a string"),
            }
        } else if (comptime std.mem.eql(u8, attr.name, "padding")) {
            switch (attr.value) {
                .expression => |e| {
                    const v = comptime parseNumeric(e);
                    style.padding = .{ .x = v, .y = v, .w = v, .h = v };
                },
                else => @compileError("padding must be an expression"),
            }
        } else if (comptime std.mem.eql(u8, attr.name, "width")) {
            switch (attr.value) {
                .expression => |e| style.width = comptime parseNumeric(e),
                else => @compileError("width must be an expression"),
            }
        } else if (comptime std.mem.eql(u8, attr.name, "height")) {
            switch (attr.value) {
                .expression => |e| style.height = comptime parseNumeric(e),
                else => @compileError("height must be an expression"),
            }
        } else if (comptime std.mem.eql(u8, attr.name, "flex")) {
            switch (attr.value) {
                .boolean => style.expand = .horizontal,
                else => @compileError("flex must be boolean"),
            }
        }
    }
    return style;
}

fn mergeStyle(dst: *Style, src: Style) void {
    if (src.background) |v| dst.background = v;
    if (src.hover_background) |v| dst.hover_background = v;
    if (src.foreground) |v| dst.foreground = v;
    if (src.padding) |v| dst.padding = v;
    if (src.radius) |v| dst.radius = v;
    if (src.gap) |v| dst.gap = v;
    if (src.width) |v| dst.width = v;
    if (src.height) |v| dst.height = v;
    if (src.font_size) |v| dst.font_size = v;
    if (src.font_weight) |v| dst.font_weight = v;
    if (src.expand) |v| dst.expand = v;
}

test "parseClasses maps bg-blue-500" {
    const s = comptime parseClasses("bg-blue-500");
    try std.testing.expect(s.background != null);
    try std.testing.expectEqual(@as(u8, 59), s.background.?.r);
}

test "parseClasses merges px and py" {
    const s = comptime parseClasses("px-4 py-2");
    try std.testing.expect(s.padding != null);
    try std.testing.expectEqual(@as(f32, 16), s.padding.?.x);
    try std.testing.expectEqual(@as(f32, 8), s.padding.?.y);
}

test "parseNumeric parses digits" {
    try std.testing.expectEqual(@as(f32, 16), parseNumeric("16"));
    try std.testing.expectEqual(@as(f32, 0), parseNumeric("0"));
}

test "firstText returns first text child" {
    const el = comptime ast.Element{
        .tag = "label",
        .attributes = &[_]ast.Attribute{},
        .children = &[_]ast.Child{ ast.Child{ .text = "hi" } },
    };
    try std.testing.expectEqualStrings("hi", firstText(el).?);
}

test "styleFrom merges class and attributes" {
    const el = comptime ast.Element{
        .tag = "div",
        .attributes = &[_]ast.Attribute{
            ast.Attribute{ .name = "class", .value = ast.AttributeValue{ .string = "bg-blue-500" } },
            ast.Attribute{ .name = "padding", .value = ast.AttributeValue{ .expression = "12" } },
        },
        .children = &[_]ast.Child{},
    };
    const s = comptime styleFrom(el);
    try std.testing.expect(s.background != null);
    try std.testing.expectEqual(@as(f32, 12), s.padding.?.x);
}

test "styleFrom handles flex attribute" {
    const el = comptime ast.Element{
        .tag = "column",
        .attributes = &[_]ast.Attribute{
            ast.Attribute{ .name = "flex", .value = ast.AttributeValue{ .boolean = {} } },
        },
        .children = &[_]ast.Child{},
    };
    const s = comptime styleFrom(el);
    try std.testing.expect(s.expand != null);
    try std.testing.expectEqual(Expand.horizontal, s.expand.?);
}

test "styleFrom leaves expand null without flex" {
    const el = comptime ast.Element{
        .tag = "column",
        .attributes = &[_]ast.Attribute{},
        .children = &[_]ast.Child{},
    };
    const s = comptime styleFrom(el);
    try std.testing.expect(s.expand == null);
}
