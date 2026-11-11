// Minimal component library for the todo demo. Real consumers swap for
// the 15-component shadcn.zig from the zsx repo.
const std = @import("std");
const Color = struct { r: u8 = 0, g: u8 = 0, b: u8 = 0, a: u8 = 255 };

pub inline fn Heading(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const size: u32 = if (@hasField(@TypeOf(props), "size")) props.size else 2;
    const fs: f32 = switch (size) {
        1 => 24,
        2 => 20,
        3 => 18,
        else => 16,
    };
    ui.text(c, props.text, .{
        .color_text = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .font_size = fs,
        .font_weight = 700,
        .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        .id_extra = if (@hasField(@TypeOf(props), "id_extra")) props.id_extra else null,
    });
}

pub inline fn Caption(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    ui.text(c, props.text, .{
        .color_text = .{ .r = 107, .g = 114, .b = 128, .a = 255 },
        .font_size = 12,
        .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        .id_extra = if (@hasField(@TypeOf(props), "id_extra")) props.id_extra else null,
    });
}

pub inline fn Badge(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const color: []const u8 = if (@hasField(@TypeOf(props), "color")) props.color else "";
    const fg: Color = if (std.mem.eql(u8, color, "red"))
        .{ .r = 239, .g = 68, .b = 68 }
    else if (std.mem.eql(u8, color, "green"))
        .{ .r = 34, .g = 197, .b = 94 }
    else if (std.mem.eql(u8, color, "blue"))
        .{ .r = 59, .g = 130, .b = 246 }
    else
        .{ .r = 17, .g = 24, .b = 39 };
    ui.text(c, props.text, .{
        .color_text = fg,
        .font_size = 14,
        .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
        .id_extra = if (@hasField(@TypeOf(props), "id_extra")) props.id_extra else null,
    });
}

pub inline fn Button(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    const variant: []const u8 = if (@hasField(@TypeOf(props), "variant")) props.variant else "primary";
    const fill: Color = if (std.mem.eql(u8, variant, "primary"))
        .{ .r = 59, .g = 130, .b = 246 }
    else if (std.mem.eql(u8, variant, "secondary"))
        .{ .r = 243, .g = 244, .b = 246 }
    else if (std.mem.eql(u8, variant, "danger"))
        .{ .r = 239, .g = 68, .b = 68 }
    else
        .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    const clicked = ui.button(c, props.text, .{
        .color_fill = .{ .color = fill },
        .color_text = .{ .color = .{ .r = 255, .g = 255, .b = 255 } },
        .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 },
        .radius = 8,
        .id_extra = if (@hasField(@TypeOf(props), "id_extra")) props.id_extra else null,
    });
    if (clicked) {
        if (@hasField(@TypeOf(props), "on_click")) {
            props.on_click(self);
        }
    }
}

pub inline fn Input(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    var opts = struct { placeholder: ?[]const u8 = null, id_extra: ?usize = null }{};
    if (@hasField(@TypeOf(props), "placeholder")) opts.placeholder = props.placeholder;
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    const buf: []u8 = props.buffer;
    ui.textEntry(c, buf, opts);
}

pub inline fn Divider(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    _ = props;
    ui.divider(c, .{});
}
