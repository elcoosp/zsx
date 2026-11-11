const std = @import("std");
const Color = struct { r: u8 = 0, g: u8 = 0, b: u8 = 0, a: u8 = 255 };

pub inline fn Heading(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const size: u32 = if (@hasField(@TypeOf(props), "size")) props.size else 2;
    const fs: f32 = switch (size) {
        1 => 24,
        2 => 20,
        3 => 18,
        4 => 16,
        5 => 14,
        else => 12,
    };
    ui.text(c, props.text, .{
        .color_text = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .font_size = fs,
        .font_weight = 700,
        .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        .id_extra = if (@hasField(@TypeOf(props), "id_extra")) props.id_extra else null,
    });
}

pub inline fn Button(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const variant: []const u8 = if (@hasField(@TypeOf(props), "variant")) props.variant else "primary";
    const fill: Color = if (std.mem.eql(u8, variant, "primary"))
        .{ .r = 59, .g = 130, .b = 246 }
    else if (std.mem.eql(u8, variant, "secondary"))
        .{ .r = 243, .g = 244, .b = 246 }
    else
        .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    _ = ui.button(c, props.text, .{
        .color_fill = .{ .color = fill },
        .color_text = .{ .color = .{ .r = 255, .g = 255, .b = 255 } },
        .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 },
        .radius = 8,
        .id_extra = if (@hasField(@TypeOf(props), "id_extra")) props.id_extra else null,
    });
}
