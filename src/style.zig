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
    } else if (std.mem.eql(u8, token, "bg-red-500")) {
        style.background = .{ .r = 239, .g = 68, .b = 68 };
    } else if (std.mem.eql(u8, token, "bg-green-500")) {
        style.background = .{ .r = 34, .g = 197, .b = 94 };
    } else if (std.mem.eql(u8, token, "bg-yellow-500")) {
        style.background = .{ .r = 234, .g = 179, .b = 8 };
    } else if (std.mem.eql(u8, token, "text-white")) {
        style.foreground = Color.white;
    } else if (std.mem.eql(u8, token, "text-black")) {
        style.foreground = Color.black;
    } else if (std.mem.eql(u8, token, "text-gray-100")) {
        style.foreground = .{ .r = 243, .g = 244, .b = 246 };
    } else if (std.mem.eql(u8, token, "text-gray-300")) {
        style.foreground = .{ .r = 209, .g = 213, .b = 219 };
    } else if (std.mem.eql(u8, token, "text-gray-500")) {
        style.foreground = .{ .r = 107, .g = 114, .b = 128 };
    } else if (std.mem.eql(u8, token, "text-gray-700")) {
        style.foreground = .{ .r = 55, .g = 65, .b = 81 };
    } else if (std.mem.eql(u8, token, "text-gray-900")) {
        style.foreground = .{ .r = 17, .g = 24, .b = 39 };
    } else if (std.mem.eql(u8, token, "text-red-500")) {
        style.foreground = .{ .r = 239, .g = 68, .b = 68 };
    } else if (std.mem.eql(u8, token, "text-green-500")) {
        style.foreground = .{ .r = 34, .g = 197, .b = 94 };
    } else if (std.mem.eql(u8, token, "p-4")) {
        style.padding = .{ .x = 16, .y = 16, .w = 16, .h = 16 };
    } else if (std.mem.eql(u8, token, "p-2")) {
        style.padding = .{ .x = 8, .y = 8, .w = 8, .h = 8 };
    } else if (std.mem.eql(u8, token, "p-1")) {
        style.padding = .{ .x = 4, .y = 4, .w = 4, .h = 4 };
    } else if (std.mem.eql(u8, token, "px-2")) {
        const cur: Spacing = style.padding orelse Spacing{};
        style.padding = .{ .x = 8, .y = cur.y, .w = 8, .h = cur.h };
    } else if (std.mem.eql(u8, token, "py-1")) {
        const cur: Spacing = style.padding orelse Spacing{};
        style.padding = .{ .x = cur.x, .y = 4, .w = cur.w, .h = 4 };
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
    } else if (std.mem.eql(u8, token, "font-normal")) {
        style.font_weight = .regular;
    } else if (std.mem.eql(u8, token, "font-semibold")) {
        style.font_weight = .semibold;
    } else if (std.mem.eql(u8, token, "font-normal")) {
        style.font_weight = .regular;
    } else if (std.mem.eql(u8, token, "font-semibold")) {
        style.font_weight = .semibold;
    } else if (std.mem.eql(u8, token, "font-bold")) {
        style.font_weight = .bold;
    } else if (std.mem.eql(u8, token, "bg-slate-100")) {
        style.background = .{ .r = 241, .g = 245, .b = 249 };
    } else if (std.mem.eql(u8, token, "bg-slate-500")) {
        style.background = .{ .r = 100, .g = 116, .b = 139 };
    } else if (std.mem.eql(u8, token, "bg-slate-900")) {
        style.background = .{ .r = 15, .g = 23, .b = 42 };
    } else if (std.mem.eql(u8, token, "text-slate-500")) {
        style.foreground = .{ .r = 100, .g = 116, .b = 139 };
    } else if (std.mem.eql(u8, token, "text-slate-900")) {
        style.foreground = .{ .r = 15, .g = 23, .b = 42 };
    } else if (std.mem.eql(u8, token, "p-3")) {
        style.padding = .{ .x = 12, .y = 12, .w = 12, .h = 12 };
    } else if (std.mem.eql(u8, token, "p-6")) {
        style.padding = .{ .x = 24, .y = 24, .w = 24, .h = 24 };
    } else if (std.mem.eql(u8, token, "p-8")) {
        style.padding = .{ .x = 32, .y = 32, .w = 32, .h = 32 };
    } else if (std.mem.eql(u8, token, "px-3")) {
        const cur: Spacing = style.padding orelse Spacing{};
        style.padding = .{ .x = 12, .y = cur.y, .w = 12, .h = cur.h };
    } else if (std.mem.eql(u8, token, "px-6")) {
        const cur: Spacing = style.padding orelse Spacing{};
        style.padding = .{ .x = 24, .y = cur.y, .w = 24, .h = cur.h };
    } else if (std.mem.eql(u8, token, "py-3")) {
        const cur: Spacing = style.padding orelse Spacing{};
        style.padding = .{ .x = cur.x, .y = 12, .w = cur.w, .h = 12 };
    } else if (std.mem.eql(u8, token, "py-6")) {
        const cur: Spacing = style.padding orelse Spacing{};
        style.padding = .{ .x = cur.x, .y = 24, .w = cur.w, .h = 24 };
    } else if (std.mem.eql(u8, token, "rounded-md")) {
        style.radius = 6;
    } else if (std.mem.eql(u8, token, "rounded-full")) {
        style.radius = 9999;
    } else if (std.mem.eql(u8, token, "text-sm")) {
        style.font_size = 14;
    } else if (std.mem.eql(u8, token, "text-xs")) {
        style.font_size = 12;
    } else if (std.mem.eql(u8, token, "text-xl")) {
        style.font_size = 20;
    } else if (std.mem.eql(u8, token, "text-2xl")) {
        style.font_size = 24;
    } else if (std.mem.eql(u8, token, "text-3xl")) {
        style.font_size = 30;
    } else if (std.mem.eql(u8, token, "gap-4")) {
        style.gap = 16;
    } else if (std.mem.eql(u8, token, "gap-1")) {
        style.gap = 4;
    } else if (std.mem.eql(u8, token, "bg-transparent")) {
        style.background = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
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

pub fn styleFromWith(comptime el: ast.Element, comptime resolver: type) Style {
    var style = Style{};
    inline for (el.attributes) |attr| {
        if (comptime std.mem.eql(u8, attr.name, "class")) {
            switch (attr.value) {
                .string => |s| mergeStyle(&style, comptime resolver.parseClasses(s)),
                else => @compileError("class attribute must be a string"),
            }
        } else if (comptime std.mem.eql(u8, attr.name, "padding")) {
            switch (attr.value) {
                .expression => |e| {
                    const v = comptime resolver.parseNumeric(e);
                    style.padding = .{ .x = v, .y = v, .w = v, .h = v };
                },
                else => @compileError("padding must be an expression"),
            }
        } else if (comptime std.mem.eql(u8, attr.name, "width")) {
            switch (attr.value) {
                .expression => |e| style.width = comptime resolver.parseNumeric(e),
                else => @compileError("width must be an expression"),
            }
        } else if (comptime std.mem.eql(u8, attr.name, "height")) {
            switch (attr.value) {
                .expression => |e| style.height = comptime resolver.parseNumeric(e),
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

pub fn styleFrom(comptime el: ast.Element) Style {
    return styleFromWith(el, DefaultResolver());
}

pub fn DefaultResolver() type {
    return struct {
        pub const parseClasses = @import("style.zig").parseClasses;
        pub const parseNumeric = @import("style.zig").parseNumeric;
    };
}

test "styleFromWith delegates to DefaultResolver" {
    const el = comptime ast.Element{
        .tag = "div",
        .attributes = &[_]ast.Attribute{
            .{ .name = "padding", .value = .{ .expression = "16" } },
        },
        .children = &[_]ast.Child{},
    };
    const s = comptime styleFromWith(el, DefaultResolver());
    try std.testing.expectEqual(@as(f32, 16), s.padding.?.x);
}

test "custom resolver overrides parseNumeric" {
    const Custom = struct {
        pub fn parseClasses(comptime class: []const u8) Style {
            return @import("style.zig").parseClasses(class);
        }
        pub fn parseNumeric(comptime s: []const u8) f32 {
            _ = s;
            return 99;
        }
    };
    const el = comptime ast.Element{
        .tag = "div",
        .attributes = &[_]ast.Attribute{
            .{ .name = "padding", .value = .{ .expression = "16" } },
        },
        .children = &[_]ast.Child{},
    };
    const s = comptime styleFromWith(el, Custom);
    try std.testing.expectEqual(@as(f32, 99), s.padding.?.x);
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
