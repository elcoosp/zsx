const std = @import("std");
const ast = @import("parser.zig");

pub const Color = struct { r: u8 = 0, g: u8 = 0, b: u8 = 0, a: u8 = 255 };
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

pub fn parseClasses(class: []const u8) !Style {
    var s = Style{};
    var i: usize = 0;
    while (i < class.len) {
        while (i < class.len and class[i] == ' ') i += 1;
        if (i >= class.len) break;
        const start = i;
        while (i < class.len and class[i] != ' ') i += 1;
        try applyToken(&s, class[start..i]);
    }
    return s;
}

fn applyToken(s: *Style, token: []const u8) !void {
    const E = std.mem.eql;
    if (E(u8, token, "bg-blue-500")) {
        s.background = .{ .r = 59, .g = 130, .b = 246 };
    } else if (E(u8, token, "bg-blue-600")) {
        s.hover_background = .{ .r = 37, .g = 99, .b = 235 };
    } else if (E(u8, token, "bg-gray-100")) {
        s.background = .{ .r = 243, .g = 244, .b = 246 };
    } else if (E(u8, token, "bg-red-500")) {
        s.background = .{ .r = 239, .g = 68, .b = 68 };
    } else if (E(u8, token, "bg-green-500")) {
        s.background = .{ .r = 34, .g = 197, .b = 94 };
    } else if (E(u8, token, "bg-yellow-500")) {
        s.background = .{ .r = 234, .g = 179, .b = 8 };
    } else if (E(u8, token, "bg-slate-100")) {
        s.background = .{ .r = 241, .g = 245, .b = 249 };
    } else if (E(u8, token, "bg-slate-500")) {
        s.background = .{ .r = 100, .g = 116, .b = 139 };
    } else if (E(u8, token, "bg-slate-900")) {
        s.background = .{ .r = 15, .g = 23, .b = 42 };
    } else if (E(u8, token, "bg-transparent")) {
        s.background = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    } else if (E(u8, token, "text-white")) {
        s.foreground = .{ .r = 255, .g = 255, .b = 255 };
    } else if (E(u8, token, "text-black")) {
        s.foreground = .{ .r = 0, .g = 0, .b = 0 };
    } else if (E(u8, token, "text-gray-100")) {
        s.foreground = .{ .r = 243, .g = 244, .b = 246 };
    } else if (E(u8, token, "text-gray-300")) {
        s.foreground = .{ .r = 209, .g = 213, .b = 219 };
    } else if (E(u8, token, "text-gray-500")) {
        s.foreground = .{ .r = 107, .g = 114, .b = 128 };
    } else if (E(u8, token, "text-gray-700")) {
        s.foreground = .{ .r = 55, .g = 65, .b = 81 };
    } else if (E(u8, token, "text-gray-900")) {
        s.foreground = .{ .r = 17, .g = 24, .b = 39 };
    } else if (E(u8, token, "text-red-500")) {
        s.foreground = .{ .r = 239, .g = 68, .b = 68 };
    } else if (E(u8, token, "text-green-500")) {
        s.foreground = .{ .r = 34, .g = 197, .b = 94 };
    } else if (E(u8, token, "text-slate-500")) {
        s.foreground = .{ .r = 100, .g = 116, .b = 139 };
    } else if (E(u8, token, "text-slate-900")) {
        s.foreground = .{ .r = 15, .g = 23, .b = 42 };
    } else if (E(u8, token, "text-xs")) {
        s.font_size = 12;
    } else if (E(u8, token, "text-sm")) {
        s.font_size = 14;
    } else if (E(u8, token, "text-lg")) {
        s.font_size = 18;
    } else if (E(u8, token, "text-xl")) {
        s.font_size = 20;
    } else if (E(u8, token, "text-2xl")) {
        s.font_size = 24;
    } else if (E(u8, token, "text-3xl")) {
        s.font_size = 30;
    } else if (E(u8, token, "font-bold")) {
        s.font_weight = .bold;
    } else if (E(u8, token, "font-semibold")) {
        s.font_weight = .semibold;
    } else if (E(u8, token, "font-normal")) {
        s.font_weight = .regular;
    } else if (E(u8, token, "p-1")) {
        s.padding = .{ .x = 4, .y = 4, .w = 4, .h = 4 };
    } else if (E(u8, token, "p-2")) {
        s.padding = .{ .x = 8, .y = 8, .w = 8, .h = 8 };
    } else if (E(u8, token, "p-3")) {
        s.padding = .{ .x = 12, .y = 12, .w = 12, .h = 12 };
    } else if (E(u8, token, "p-4")) {
        s.padding = .{ .x = 16, .y = 16, .w = 16, .h = 16 };
    } else if (E(u8, token, "p-6")) {
        s.padding = .{ .x = 24, .y = 24, .w = 24, .h = 24 };
    } else if (E(u8, token, "p-8")) {
        s.padding = .{ .x = 32, .y = 32, .w = 32, .h = 32 };
    } else if (E(u8, token, "px-2")) {
        const c = s.padding orelse Spacing{};
        s.padding = .{ .x = 8, .y = c.y, .w = 8, .h = c.h };
    } else if (E(u8, token, "px-3")) {
        const c = s.padding orelse Spacing{};
        s.padding = .{ .x = 12, .y = c.y, .w = 12, .h = c.h };
    } else if (E(u8, token, "px-4")) {
        const c = s.padding orelse Spacing{};
        s.padding = .{ .x = 16, .y = c.y, .w = 16, .h = c.h };
    } else if (E(u8, token, "px-6")) {
        const c = s.padding orelse Spacing{};
        s.padding = .{ .x = 24, .y = c.y, .w = 24, .h = c.h };
    } else if (E(u8, token, "py-1")) {
        const c = s.padding orelse Spacing{};
        s.padding = .{ .x = c.x, .y = 4, .w = c.w, .h = 4 };
    } else if (E(u8, token, "py-2")) {
        const c = s.padding orelse Spacing{};
        s.padding = .{ .x = c.x, .y = 8, .w = c.w, .h = 8 };
    } else if (E(u8, token, "py-3")) {
        const c = s.padding orelse Spacing{};
        s.padding = .{ .x = c.x, .y = 12, .w = c.w, .h = 12 };
    } else if (E(u8, token, "py-6")) {
        const c = s.padding orelse Spacing{};
        s.padding = .{ .x = c.x, .y = 24, .w = c.w, .h = 24 };
    } else if (E(u8, token, "gap-1")) {
        s.gap = 4;
    } else if (E(u8, token, "gap-2")) {
        s.gap = 8;
    } else if (E(u8, token, "gap-4")) {
        s.gap = 16;
    } else if (E(u8, token, "rounded-md")) {
        s.radius = 6;
    } else if (E(u8, token, "rounded-lg")) {
        s.radius = 8;
    } else if (E(u8, token, "rounded-full")) {
        s.radius = 9999;
    } else {
        return error.ZsxUnknownClass;
    }
}

pub fn parseNumeric(s: []const u8) !f32 {
    if (s.len == 0) return error.ZsxParseError;
    var r: f32 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') return error.ZsxParseError;
        r = r * 10.0 + @as(f32, @floatFromInt(ch - '0'));
    }
    return r;
}

pub fn styleFrom(el: ast.Element) !Style {
    var s = Style{};
    for (el.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "class")) {
            switch (attr.value) {
                .string => |v| mergeStyle(&s, try parseClasses(v)),
                else => return error.ZsxParseError,
            }
        } else if (std.mem.eql(u8, attr.name, "padding")) {
            switch (attr.value) {
                .expression => |e| {
                    const v = try parseNumeric(e);
                    s.padding = .{ .x = v, .y = v, .w = v, .h = v };
                },
                else => return error.ZsxParseError,
            }
        } else if (std.mem.eql(u8, attr.name, "width")) {
            switch (attr.value) {
                .expression => |e| s.width = try parseNumeric(e),
                else => return error.ZsxParseError,
            }
        } else if (std.mem.eql(u8, attr.name, "height")) {
            switch (attr.value) {
                .expression => |e| s.height = try parseNumeric(e),
                else => return error.ZsxParseError,
            }
        } else if (std.mem.eql(u8, attr.name, "flex")) {
            switch (attr.value) {
                .boolean => s.expand = .horizontal,
                else => return error.ZsxParseError,
            }
        }
    }
    return s;
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
