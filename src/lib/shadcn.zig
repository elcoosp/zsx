const std = @import("std");
const style_mod = @import("style.zig");
pub const style = style_mod;

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
    const btn_style = variantStyle(variant);
    var opts = ButtonOptions{
        .color_fill = btn_style.fill,
        .color_text = btn_style.text,
        .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 },
        .radius = 8,
    };
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    if (@hasField(@TypeOf(props), "class")) {
        const overrides = comptime (style_mod.parseClasses(props.class) catch @compileError("zsx: unknown class"));
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

pub inline fn Card(self: anytype, ui: anytype, c: anytype, comptime props: anytype) void {
    const card_id: ?usize = if (@hasField(@TypeOf(props), "id_extra")) @as(?usize, props.id_extra) else null;
    var b = ui.column(c, .{
        .padding = .{ .x = 12, .y = 12, .w = 12, .h = 12 },
        .radius = 8,
        .id_extra = card_id,
    });
    defer b.end();
    callComponentFns(self, ui, c, props);
}

pub inline fn Heading(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const size_u32: u32 = if (@hasField(@TypeOf(props), "size")) props.size else 2;
    const font_size: f32 = switch (size_u32) {
        1 => 24,
        2 => 20,
        3 => 18,
        4 => 16,
        5 => 14,
        else => 12,
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
        const overrides = comptime (style_mod.parseClasses(props.class) catch @compileError("zsx: unknown class"));
        if (overrides.foreground) |fg| opts.color_text = fg;
        if (overrides.font_size) |fs| opts.font_size = fs;
        if (overrides.font_weight) |fw| opts.font_weight = switch (fw) {
            .regular => 400,
            .semibold => 600,
            .bold => 700,
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

pub inline fn Section(self: anytype, ui: anytype, c: anytype, comptime props: anytype) void {
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
    callComponentFns(self, ui, c, props);
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

pub const SwitchOptions = struct {
    id_extra: ?usize = null,
};

pub const SkeletonOptions = struct {
    width: f32 = 200,
    height: f32 = 16,
    radius: f32 = 4,
    id_extra: ?usize = null,
};

pub inline fn Switch(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    var opts = SwitchOptions{};
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    const val: *bool = props.checked;
    const label: []const u8 = if (@hasField(@TypeOf(props), "text")) props.text else "";
    _ = ui.toggle(c, label, val, opts);
}

pub inline fn Skeleton(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    var opts = SkeletonOptions{};
    if (@hasField(@TypeOf(props), "width")) opts.width = props.width;
    if (@hasField(@TypeOf(props), "height")) opts.height = props.height;
    if (@hasField(@TypeOf(props), "radius")) opts.radius = props.radius;
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    ui.skeleton(c, opts);
}

inline fn callComponentFns(self: anytype, ui: anytype, c: anytype, comptime props: anytype) void {
    const SelfT = @TypeOf(self);
    const is_double_ptr = @typeInfo(SelfT) == .pointer and @typeInfo(@typeInfo(SelfT).pointer.child) == .pointer;
    inline for ([_][]const u8{ "content", "header", "body", "footer" }) |slot_name| {
        if (comptime @hasField(@TypeOf(props), slot_name)) {
            const f = @field(props, slot_name);
            if (comptime is_double_ptr) {
                f(ui, c, self.*);
            } else {
                f(ui, c, self);
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────
// v0.2.0 additions: Label, Alert, Breadcrumb, Tabs, Pagination
// ─────────────────────────────────────────────────────────────

/// Form label — bold small-caps text styled for field headings.
pub inline fn Label(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    var opts = TextOptions{
        .color_text = Color{ .r = 17, .g = 24, .b = 39 },
        .font_size = 14,
        .font_weight = 600,
        .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    };
    if (@hasField(@TypeOf(props), "id_extra")) opts.id_extra = props.id_extra;
    ui.text(c, props.text, opts);
}

/// Alert block — colored border + title + text. Variants: info, success, warning, error.
pub inline fn Alert(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const variant: []const u8 = if (@hasField(@TypeOf(props), "variant")) props.variant else "info";
    const border: Color = if (std.mem.eql(u8, variant, "error"))
        Color{ .r = 239, .g = 68, .b = 68 }
    else if (std.mem.eql(u8, variant, "warning"))
        Color{ .r = 234, .g = 179, .b = 8 }
    else if (std.mem.eql(u8, variant, "success"))
        Color{ .r = 34, .g = 197, .b = 94 }
    else
        Color{ .r = 59, .g = 130, .b = 246 };

    const alert_id: ?usize = if (@hasField(@TypeOf(props), "id_extra")) @as(?usize, props.id_extra) else null;
    var box = ui.column(c, .{
        .padding = .{ .x = 12, .y = 8, .w = 12, .h = 8 },
        .radius = 6,
        .id_extra = alert_id,
    });
    defer box.end();

    if (@hasField(@TypeOf(props), "title")) {
        ui.text(c, props.title, .{
            .color_text = border,
            .font_size = 14,
            .font_weight = 700,
            .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            .id_extra = if (alert_id) |id| id + 1 else null,
        });
    }
    if (@hasField(@TypeOf(props), "text") and props.text.len > 0) {
        ui.text(c, props.text, .{
            .color_text = Color{ .r = 17, .g = 24, .b = 39 },
            .font_size = 14,
            .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            .id_extra = if (alert_id) |id| id + 2 else null,
        });
    }
}

/// Breadcrumb navigation — "Home / Users / Alice" rendered as path.
/// Takes a slash-separated string in `path`.
pub inline fn Breadcrumb(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const path: []const u8 = props.path;
    const base_id: usize = if (@hasField(@TypeOf(props), "id_extra")) props.id_extra else 0;

    var b = ui.row(c, .{
        .gap = 4,
        .id_extra = base_id,
    });
    defer b.end();

    var it = std.mem.splitScalar(u8, path, '/');
    var first = true;
    var seg_idx: usize = 0;
    while (it.next()) |seg| : (seg_idx += 1) {
        const trimmed = std.mem.trim(u8, seg, " \t");
        if (trimmed.len == 0) continue;
        if (!first) {
            ui.text(c, " / ", .{
                .color_text = Color{ .r = 107, .g = 114, .b = 128 },
                .font_size = 14,
                .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            });
        }
        first = false;
        ui.text(c, trimmed, .{
            .color_text = Color{ .r = 59, .g = 130, .b = 246 },
            .font_size = 14,
            .padding = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        });
    }
}

/// Tabs — labels is a comma-separated string, selected is a `*usize`.
/// Content is the `.content` fn field (emitted by the generator when the tag has children).
pub inline fn Tabs(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    const labels_str: []const u8 = props.labels;
    const selected: *usize = props.selected;
    const base_id: usize = if (@hasField(@TypeOf(props), "id_extra")) props.id_extra else 0;

    var b = ui.row(c, .{
        .gap = 2,
        .id_extra = base_id,
    });
    defer b.end();

    var it = std.mem.splitScalar(u8, labels_str, ',');
    var idx: usize = 0;
    while (it.next()) |raw| : (idx += 1) {
        const label = std.mem.trim(u8, raw, " \t");
        if (label.len == 0) continue;
        const is_active = idx == selected.*;
        const fill: Color = if (is_active)
            Color{ .r = 59, .g = 130, .b = 246 }
        else
            Color{ .r = 243, .g = 244, .b = 246 };
        const text_col: Color = if (is_active)
            Color{ .r = 255, .g = 255, .b = 255 }
        else
            Color{ .r = 17, .g = 24, .b = 39 };
        const clicked = ui.button(c, label, .{
            .color_fill = fill,
            .color_text = text_col,
            .padding = .{ .x = 12, .y = 6, .w = 12, .h = 6 },
            .radius = 4,
            .id_extra = base_id + 1000 + idx,
        });
        if (clicked) selected.* = idx;
    }

    // Render content if the generator passed a .content fn field.
    const SelfT = @TypeOf(self);
    const is_double_ptr = @typeInfo(SelfT) == .pointer and @typeInfo(@typeInfo(SelfT).pointer.child) == .pointer;
    inline for ([_][]const u8{"content"}) |slot_name| {
        if (comptime @hasField(@TypeOf(props), slot_name)) {
            const f = @field(props, slot_name);
            if (comptime is_double_ptr) {
                f(ui, c, self.*);
            } else {
                f(ui, c, self);
            }
        }
    }
}

/// Pagination — "‹ 1 2 3 4 5 ›". total is count, selected is a `*usize` (0-indexed).
pub inline fn Pagination(self: anytype, ui: anytype, c: anytype, props: anytype) void {
    _ = self;
    const total: usize = props.total;
    const selected: *usize = props.selected;
    const base_id: usize = if (@hasField(@TypeOf(props), "id_extra")) props.id_extra else 0;

    var b = ui.row(c, .{
        .gap = 4,
        .id_extra = base_id,
    });
    defer b.end();

    const prev_clicked = ui.button(c, "<", .{
        .color_fill = Color{ .r = 243, .g = 244, .b = 246 },
        .color_text = Color{ .r = 17, .g = 24, .b = 39 },
        .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
        .radius = 4,
        .id_extra = base_id + 2000,
    });
    if (prev_clicked and selected.* > 0) selected.* -= 1;

    // Comptime string literals for page labels. A stack buffer from
    // bufPrint goes out of scope at end of each loop iteration, and Nanoui
    // holds the label pointer for rendering after the fn returns — the
    // stack slot gets overwritten and renders as "?" (invalid UTF-8).
    const page_labels = [_][]const u8{
        "1",  "2",  "3",  "4",  "5",  "6",  "7",  "8",  "9",  "10",
        "11", "12", "13", "14", "15", "16", "17", "18", "19", "20",
    };
    var i: usize = 0;
    while (i < total) : (i += 1) {
        const is_active = i == selected.*;
        const fill: Color = if (is_active)
            Color{ .r = 59, .g = 130, .b = 246 }
        else
            Color{ .r = 243, .g = 244, .b = 246 };
        const text_col: Color = if (is_active)
            Color{ .r = 255, .g = 255, .b = 255 }
        else
            Color{ .r = 17, .g = 24, .b = 39 };
        const label: []const u8 = if (i < page_labels.len) page_labels[i] else "?";
        const clicked = ui.button(c, label, .{
            .color_fill = fill,
            .color_text = text_col,
            .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
            .radius = 4,
            .id_extra = base_id + 2100 + i,
        });
        if (clicked) selected.* = i;
    }

    const next_clicked = ui.button(c, ">", .{
        .color_fill = Color{ .r = 243, .g = 244, .b = 246 },
        .color_text = Color{ .r = 17, .g = 24, .b = 39 },
        .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
        .radius = 4,
        .id_extra = base_id + 2200,
    });
    if (next_clicked and selected.* + 1 < total) selected.* += 1;
}
