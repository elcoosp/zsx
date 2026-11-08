const std = @import("std");

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
pub const Spacing = struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0 };

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

pub fn DefaultResolver() type {
    return struct {
        pub const parseClasses = @import("style.zig").parseClasses;
        pub const parseNumeric = @import("style.zig").parseNumeric;
    };
}

pub fn parseClasses(comptime class: []const u8) !Style {
    var style = Style{};
    comptime var i: usize = 0;
    inline while (i < class.len) {
        while (i < class.len and class[i] == ' ') i += 1;
        if (i >= class.len) break;
        const start = i;
        while (i < class.len and class[i] != ' ') i += 1;
        try applyToken(&style, class[start..i]);
    }
    return style;
}

fn applyToken(style: *Style, comptime token: []const u8) !void {
    const E = std.mem.eql;
    if (E(u8, token, "bg-blue-500")) {
        style.background = .{ .r = 59, .g = 130, .b = 246 };
    } else if (E(u8, token, "bg-blue-600")) {
        style.hover_background = .{ .r = 37, .g = 99, .b = 235 };
    } else if (E(u8, token, "bg-gray-100")) {
        style.background = .{ .r = 243, .g = 244, .b = 246 };
    } else if (E(u8, token, "bg-red-500")) {
        style.background = .{ .r = 239, .g = 68, .b = 68 };
    } else if (E(u8, token, "bg-green-500")) {
        style.background = .{ .r = 34, .g = 197, .b = 94 };
    } else if (E(u8, token, "bg-yellow-500")) {
        style.background = .{ .r = 234, .g = 179, .b = 8 };
    } else if (E(u8, token, "bg-slate-100")) {
        style.background = .{ .r = 241, .g = 245, .b = 249 };
    } else if (E(u8, token, "bg-slate-500")) {
        style.background = .{ .r = 100, .g = 116, .b = 139 };
    } else if (E(u8, token, "bg-slate-900")) {
        style.background = .{ .r = 15, .g = 23, .b = 42 };
    } else if (E(u8, token, "bg-transparent")) {
        style.background = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    } else if (E(u8, token, "text-white")) {
        style.foreground = Color.white;
    } else if (E(u8, token, "text-black")) {
        style.foreground = Color.black;
    } else if (E(u8, token, "text-gray-100")) {
        style.foreground = .{ .r = 243, .g = 244, .b = 246 };
    } else if (E(u8, token, "text-gray-300")) {
        style.foreground = .{ .r = 209, .g = 213, .b = 219 };
    } else if (E(u8, token, "text-gray-500")) {
        style.foreground = .{ .r = 107, .g = 114, .b = 128 };
    } else if (E(u8, token, "text-gray-700")) {
        style.foreground = .{ .r = 55, .g = 65, .b = 81 };
    } else if (E(u8, token, "text-gray-900")) {
        style.foreground = .{ .r = 17, .g = 24, .b = 39 };
    } else if (E(u8, token, "text-red-500")) {
        style.foreground = .{ .r = 239, .g = 68, .b = 68 };
    } else if (E(u8, token, "text-green-500")) {
        style.foreground = .{ .r = 34, .g = 197, .b = 94 };
    } else if (E(u8, token, "text-slate-500")) {
        style.foreground = .{ .r = 100, .g = 116, .b = 139 };
    } else if (E(u8, token, "text-slate-900")) {
        style.foreground = .{ .r = 15, .g = 23, .b = 42 };
    } else if (E(u8, token, "text-xs")) {
        style.font_size = 12;
    } else if (E(u8, token, "text-sm")) {
        style.font_size = 14;
    } else if (E(u8, token, "text-lg")) {
        style.font_size = 18;
    } else if (E(u8, token, "text-xl")) {
        style.font_size = 20;
    } else if (E(u8, token, "text-2xl")) {
        style.font_size = 24;
    } else if (E(u8, token, "text-3xl")) {
        style.font_size = 30;
    } else if (E(u8, token, "font-bold")) {
        style.font_weight = .bold;
    } else if (E(u8, token, "font-semibold")) {
        style.font_weight = .semibold;
    } else if (E(u8, token, "font-normal")) {
        style.font_weight = .regular;
    } else if (E(u8, token, "p-1")) {
        style.padding = .{ .x = 4, .y = 4, .w = 4, .h = 4 };
    } else if (E(u8, token, "p-2")) {
        style.padding = .{ .x = 8, .y = 8, .w = 8, .h = 8 };
    } else if (E(u8, token, "p-3")) {
        style.padding = .{ .x = 12, .y = 12, .w = 12, .h = 12 };
    } else if (E(u8, token, "p-4")) {
        style.padding = .{ .x = 16, .y = 16, .w = 16, .h = 16 };
    } else if (E(u8, token, "p-6")) {
        style.padding = .{ .x = 24, .y = 24, .w = 24, .h = 24 };
    } else if (E(u8, token, "p-8")) {
        style.padding = .{ .x = 32, .y = 32, .w = 32, .h = 32 };
    } else if (E(u8, token, "px-2")) {
        const cur = style.padding orelse Spacing{};
        style.padding = .{ .x = 8, .y = cur.y, .w = 8, .h = cur.h };
    } else if (E(u8, token, "px-3")) {
        const cur = style.padding orelse Spacing{};
        style.padding = .{ .x = 12, .y = cur.y, .w = 12, .h = cur.h };
    } else if (E(u8, token, "px-4")) {
        const cur = style.padding orelse Spacing{};
        style.padding = .{ .x = 16, .y = cur.y, .w = 16, .h = cur.h };
    } else if (E(u8, token, "px-6")) {
        const cur = style.padding orelse Spacing{};
        style.padding = .{ .x = 24, .y = cur.y, .w = 24, .h = cur.h };
    } else if (E(u8, token, "py-1")) {
        const cur = style.padding orelse Spacing{};
        style.padding = .{ .x = cur.x, .y = 4, .w = cur.w, .h = 4 };
    } else if (E(u8, token, "py-2")) {
        const cur = style.padding orelse Spacing{};
        style.padding = .{ .x = cur.x, .y = 8, .w = cur.w, .h = 8 };
    } else if (E(u8, token, "py-3")) {
        const cur = style.padding orelse Spacing{};
        style.padding = .{ .x = cur.x, .y = 12, .w = cur.w, .h = 12 };
    } else if (E(u8, token, "py-6")) {
        const cur = style.padding orelse Spacing{};
        style.padding = .{ .x = cur.x, .y = 24, .w = cur.w, .h = 24 };
    } else if (E(u8, token, "gap-1")) {
        style.gap = 4;
    } else if (E(u8, token, "gap-2")) {
        style.gap = 8;
    } else if (E(u8, token, "gap-4")) {
        style.gap = 16;
    } else if (E(u8, token, "rounded-md")) {
        style.radius = 6;
    } else if (E(u8, token, "rounded-lg")) {
        style.radius = 8;
    } else if (E(u8, token, "rounded-full")) {
        style.radius = 9999;
    } else {
        return error.ZsxUnknownClass;
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

test "parseClasses maps bg-blue-500" {
    const s = comptime try parseClasses("bg-blue-500");
    try std.testing.expect(s.background != null);
    try std.testing.expectEqual(@as(u8, 59), s.background.?.r);
}

test "parseClasses merges px and py" {
    const s = comptime try parseClasses("px-4 py-2");
    try std.testing.expect(s.padding != null);
    try std.testing.expectEqual(@as(f32, 16), s.padding.?.x);
    try std.testing.expectEqual(@as(f32, 8), s.padding.?.y);
}

test "parseClasses errors on unknown class" {
    try std.testing.expectError(error.ZsxUnknownClass, comptime parseClasses("bg-nonexistent-class"));
}

test "parseNumeric parses digits" {
    try std.testing.expectEqual(@as(f32, 16), comptime parseNumeric("16"));
    try std.testing.expectEqual(@as(f32, 0), comptime parseNumeric("0"));
}

test "DefaultResolver delegates to module-level fns" {
    const R = DefaultResolver();
    try std.testing.expectEqual(@as(f32, 16), comptime R.parseNumeric("16"));
    const s = comptime try R.parseClasses("bg-blue-500");
    try std.testing.expectEqual(@as(u8, 59), s.background.?.r);
}
