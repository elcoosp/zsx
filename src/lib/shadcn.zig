const std = @import("std");

pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,
};

pub const Padding = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
};

pub const ButtonOptions = struct {
    color_fill: Color,
    color_text: Color,
    padding: Padding,
    radius: f32,
};

pub const TextOptions = struct {
    color_text: Color,
    font_size: f32,
    padding: Padding,
};

const VariantStyle = struct {
    fill: Color,
    text: Color,
};

fn variantStyle(name: []const u8) VariantStyle {
    if (std.mem.eql(u8, name, "primary")) {
        return .{ .fill = .{ .r = 59, .g = 130, .b = 246 }, .text = .{ .r = 255, .g = 255, .b = 255 } };
    }
    if (std.mem.eql(u8, name, "secondary")) {
        return .{ .fill = .{ .r = 243, .g = 244, .b = 246 }, .text = .{ .r = 17, .g = 24, .b = 39 } };
    }
    if (std.mem.eql(u8, name, "ghost")) {
        return .{ .fill = .{ .r = 0, .g = 0, .b = 0, .a = 0 }, .text = .{ .r = 17, .g = 24, .b = 39 } };
    }
    if (std.mem.eql(u8, name, "danger")) {
        return .{ .fill = .{ .r = 239, .g = 68, .b = 68 }, .text = .{ .r = 255, .g = 255, .b = 255 } };
    }
    return .{ .fill = .{ .r = 59, .g = 130, .b = 246 }, .text = .{ .r = 255, .g = 255, .b = 255 } };
}

pub inline fn Button(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    const variant: []const u8 = if (@hasField(@TypeOf(props), "variant")) props.variant else "primary";
    const style = variantStyle(variant);
    const opts = ButtonOptions{
        .color_fill = style.fill,
        .color_text = style.text,
        .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 },
        .radius = 8,
    };
    const clicked = ui.button(c, props.text, opts);
    if (clicked) {
        if (@hasField(@TypeOf(props), "on_click")) {
            props.on_click(self);
        }
    }
}

pub inline fn Badge(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const color: []const u8 = if (@hasField(@TypeOf(props), "color")) props.color else "";
    const text_color: Color = if (std.mem.eql(u8, color, "red"))
        .{ .r = 239, .g = 68, .b = 68 }
    else if (std.mem.eql(u8, color, "green"))
        .{ .r = 34, .g = 197, .b = 94 }
    else if (std.mem.eql(u8, color, "blue"))
        .{ .r = 59, .g = 130, .b = 246 }
    else
        .{ .r = 17, .g = 24, .b = 39 };
    ui.text(c, props.text, TextOptions{
        .color_text = text_color,
        .font_size = 14,
        .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
    });
}

pub inline fn Card(self: anytype, ui: anytype, c: anytype, comptime props: anytype, comptime content: anytype) void {
    _ = props;
    var b = ui.column(c, .{
        .padding = .{ .x = 12, .y = 12, .w = 12, .h = 12 },
        .radius = 8,
    });
    defer b.end();
    content(ui, c, self);
}
