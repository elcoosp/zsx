const std = @import("std");
const style_mod = @import("../style.zig");

pub const Color = style_mod.Color;
pub const Padding = style_mod.Spacing;

pub const ButtonOptions = struct {
    color_fill: Color,
    color_text: Color,
    padding: Padding,
    radius: f32,
    id_extra: ?usize = null,
};

pub const TextOptions = struct {
    color_text: Color,
    font_size: f32,
    font_weight: u32 = 400,
    padding: Padding,
    id_extra: ?usize = null,
};

pub const InputOptions = struct {
    placeholder: ?[]const u8 = null,
    id_extra: ?usize = null,
};

pub const TextareaOptions = struct {
    placeholder: ?[]const u8 = null,
    id_extra: ?usize = null,
};

pub const CheckboxOptions = struct {
    id_extra: ?usize = null,
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
    var opts = ButtonOptions{
        .color_fill = style.fill,
        .color_text = style.text,
        .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 },
        .radius = 8,
    };
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    if (@hasField(@TypeOf(props), "class")) {
        const overrides = comptime style_mod.parseClasses(props.class);
        if (overrides.padding) |p| opts.padding = p;
        if (overrides.radius) |r| opts.radius = r;
        if (overrides.background) |bg| opts.color_fill = bg;
        if (overrides.foreground) |fg| opts.color_text = fg;
    }
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
    var opts = TextOptions{
        .color_text = text_color,
        .font_size = 14,
        .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
    };
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    ui.text(c, props.text, opts);
}

pub inline fn Card(self: anytype, ui: anytype, c: anytype, comptime props: anytype, comptime content: anytype) void {
    const card_id: ?usize = if (@hasField(@TypeOf(props), "id_extra")) @as(?usize, props.id_extra) else null;
    var b = ui.column(c, .{
        .padding = .{ .x = 12, .y = 12, .w = 12, .h = 12 },
        .radius = 8,
        .id_extra = card_id,
    });
    defer b.end();
    const SelfT = @TypeOf(self);
    if (@typeInfo(SelfT) == .pointer and @typeInfo(@typeInfo(SelfT).pointer.child) == .pointer) {
        content(ui, c, self.*);
    } else {
        content(ui, c, self);
    }
}

pub inline fn Heading(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const size_u32: u32 = if (@hasField(@TypeOf(props), "size")) props.size else 2;
    const font_size: f32 = switch (size_u32) {
        1 => 24, 2 => 20, 3 => 18, 4 => 16, 5 => 14, else => 12,
    };
    var opts = TextOptions{
        .color_text = Color.black,
        .font_size = font_size,
        .font_weight = 700,
        .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    };
    if (@hasField(@TypeOf(props), "color")) opts.color_text = props.color;
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    if (@hasField(@TypeOf(props), "class")) {
        const overrides = comptime style_mod.parseClasses(props.class);
        if (overrides.foreground) |fg| opts.color_text = fg;
        if (overrides.font_size) |fs| opts.font_size = fs;
        if (overrides.font_weight) |fw| opts.font_weight = switch (fw) {
            .regular => 400, .semibold => 600, .bold => 700,
        };
    }
    ui.text(c, props.text, opts);
}

pub inline fn Caption(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    var opts = TextOptions{
        .color_text = .{ .r = 107, .g = 114, .b = 128 },
        .font_size = 12,
        .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    };
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    ui.text(c, props.text, opts);
}

pub inline fn Link(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    var opts = TextOptions{
        .color_text = .{ .r = 59, .g = 130, .b = 246 },
        .font_size = 14,
        .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    };
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    ui.text(c, props.text, opts);
}

pub inline fn Section(self: anytype, ui: anytype, c: anytype, comptime props: anytype, comptime content: anytype) void {
    const section_id: ?usize = if (@hasField(@TypeOf(props), "id_extra")) @as(?usize, props.id_extra) else null;
    var box = ui.column(c, .{
        .padding = .{ .x = 12, .y = 12, .w = 12, .h = 12 },
        .gap = 8,
        .id_extra = section_id,
    });
    defer box.end();
    const title: []const u8 = if (@hasField(@TypeOf(props), "title")) props.title else "";
    if (title.len > 0) {
        // Inline Heading call — passing self to Heading makes Zig unify
        // self's type across two anytype calls, which can infer **Ctx.
        var h_opts = TextOptions{
            .color_text = Color.black,
            .font_size = 18,
            .font_weight = 700,
            .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        };
        if (@hasField(@TypeOf(props), "id_extra")) h_opts.id_extra = props.id_extra;
        ui.text(c, title, h_opts);
    }
    const SelfT = @TypeOf(self);
    if (@typeInfo(SelfT) == .pointer and @typeInfo(@typeInfo(SelfT).pointer.child) == .pointer) {
        content(ui, c, self.*);
    } else {
        content(ui, c, self);
    }
}

pub inline fn Input(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    var opts = InputOptions{};
    if (@hasField(@TypeOf(props), "placeholder")) opts.placeholder = props.placeholder;
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    const buf: []u8 = props.buffer;
    ui.textEntry(c, buf, opts);
}

pub inline fn Textarea(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    var opts = TextareaOptions{};
    if (@hasField(@TypeOf(props), "placeholder")) opts.placeholder = props.placeholder;
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    const buf: []u8 = props.buffer;
    ui.textArea(c, buf, opts);
}

/// Checkbox + label. Value is `*bool` on the context.
pub inline fn Checkbox(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    var opts = CheckboxOptions{};
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    const val: *bool = props.checked;
    _ = ui.checkbox(c, props.text, val, opts);
}


pub inline fn Progress(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    ui.progress(c, props.value, .{});
}

pub inline fn Divider(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    _ = props;
    ui.divider(c, .{});
}

pub inline fn Slider(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const value: *f32 = props.value;
    _ = ui.slider(c, value, .{});
}
