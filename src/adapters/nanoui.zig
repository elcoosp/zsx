const std = @import("std");

pub fn Adapter(comptime ui: type) type {
    return struct {
        var text_buffers: std.AutoHashMapUnmanaged(u64, *ui.TextBuffer) = .empty;

        pub fn column(c: anytype, opts: anytype) Box {
            var d = ui.div(c).column();
            d = applyOpts(ui, d, opts);
            return .{ .inner = d };
        }

        pub fn row(c: anytype, opts: anytype) Box {
            var d = ui.div(c).row();
            d = applyOpts(ui, d, opts);
            return .{ .inner = d };
        }

        pub fn text(c: anytype, str: []const u8, opts: anytype) void {
            var ts = ui.TextStyle{};
            if (@hasField(@TypeOf(opts), "color_text")) {
                const col = opts.color_text;
                ts.color = .{
                    .r = @as(f32, @floatFromInt(col.r)) / 255.0,
                    .g = @as(f32, @floatFromInt(col.g)) / 255.0,
                    .b = @as(f32, @floatFromInt(col.b)) / 255.0,
                    .a = @as(f32, @floatFromInt(col.a)) / 255.0,
                };
            }
            if (@hasField(@TypeOf(opts), "font_size")) {
                const fs = opts.font_size;
                if (@TypeOf(fs) == f32) {
                    ts.size = fs;
                } else if (@TypeOf(fs) == comptime_float) {
                    ts.size = @floatCast(fs);
                } else {
                    ts.size = @as(f32, @floatFromInt(fs));
                }
            }
            if (@hasField(@TypeOf(opts), "font_weight")) {
                const fw = opts.font_weight;
                const w: u32 = if (@TypeOf(fw) == u32)
                    fw
                else if (@TypeOf(fw) == comptime_int)
                    @intCast(fw)
                else
                    @as(u32, @intFromFloat(fw));
                ts.weight = switch (w) {
                    400 => .regular,
                    500 => .medium,
                    600 => .semibold,
                    700 => .bold,
                    else => .regular,
                };
            }
            ui.text(c, str, ts);
        }

        pub fn button(c: anytype, title: []const u8, opts: anytype) bool {
            var bo = ui.ButtonOptions{};
            if (@hasField(@TypeOf(opts), "color_fill")) {
                const col = opts.color_fill;
                if (col.r > 200 and col.g < 100 and col.b < 100) {
                    bo.variant = .danger;
                } else if (col.b > 200 and col.r < 150) {
                    bo.variant = .primary;
                }
            }
            return ui.button(c, title, bo).clicked;
        }

        pub fn textEntry(c: anytype, buffer: []u8, opts: anytype) void {
            if (@hasDecl(ui, "textField")) {
                const Opts = ui.TextFieldOptions;
                var o: Opts = .{};
                if (@hasField(Opts, "placeholder")) {
                    if (@hasField(@TypeOf(opts), "placeholder")) {
                        if (opts.placeholder) |p| o.placeholder = p;
                    }
                }
                if (@hasField(Opts, "id_extra")) {
                    if (@hasField(@TypeOf(opts), "id_extra")) o.id_extra = opts.id_extra;
                }
                const id: u64 = blk: {
                    if (!@hasField(@TypeOf(opts), "id_extra")) break :blk 0;
                    const raw = opts.id_extra;
                    if (@typeInfo(@TypeOf(raw)) == .optional) {
                        break :blk @as(u64, @intCast(raw orelse 0));
                    }
                    break :blk @as(u64, @intCast(raw));
                };
                const gop = text_buffers.getOrPut(std.heap.c_allocator, id) catch return;
                if (!gop.found_existing) {
                    const tb = std.heap.c_allocator.create(ui.TextBuffer) catch return;
                    tb.* = .{};
                    // Seed only if caller's buffer has non-zero prefix
                    const seed_len = std.mem.indexOfScalar(u8, buffer, 0) orelse buffer.len;
                    if (seed_len > 0) tb.set(buffer[0..seed_len]);
                    gop.value_ptr.* = tb;
                }
                const tb: *ui.TextBuffer = gop.value_ptr.*;
                _ = ui.textField(c, tb, o);
                // Sync back to caller's slice
                const txt = tb.text();
                const n = @min(txt.len, buffer.len);
                @memcpy(buffer[0..n], txt[0..n]);
                if (n < buffer.len) @memset(buffer[n..], 0);
            } else {
                ui.textEntry(c, buffer, opts);
            }
        }

        pub fn textArea(c: anytype, buffer: []u8, opts: anytype) void {
            if (@hasDecl(ui, "textArea")) {
                const Opts = ui.AreaOptions;
                var o: Opts = .{};
                if (@hasField(Opts, "placeholder")) {
                    if (@hasField(@TypeOf(opts), "placeholder")) {
                        if (opts.placeholder) |p| o.placeholder = p;
                    }
                }
                if (@hasField(Opts, "id_extra")) {
                    if (@hasField(@TypeOf(opts), "id_extra")) o.id_extra = opts.id_extra;
                }
                const id: u64 = blk: {
                    if (!@hasField(@TypeOf(opts), "id_extra")) break :blk 0;
                    const raw = opts.id_extra;
                    if (@typeInfo(@TypeOf(raw)) == .optional) break :blk @as(u64, @intCast(raw orelse 0));
                    break :blk @as(u64, @intCast(raw));
                };
                const gop = text_buffers.getOrPut(std.heap.c_allocator, id) catch return;
                if (!gop.found_existing) {
                    const tb = std.heap.c_allocator.create(ui.TextBuffer) catch return;
                    tb.* = .{};
                    const seed_len = std.mem.indexOfScalar(u8, buffer, 0) orelse buffer.len;
                    if (seed_len > 0) tb.set(buffer[0..seed_len]);
                    gop.value_ptr.* = tb;
                }
                const tb: *ui.TextBuffer = gop.value_ptr.*;
                _ = ui.textArea(c, tb, o);
                const txt = tb.text();
                const n = @min(txt.len, buffer.len);
                @memcpy(buffer[0..n], txt[0..n]);
                if (n < buffer.len) @memset(buffer[n..], 0);
            } else {
                textEntry(c, buffer, opts);
            }
        }

        pub fn checkbox(c: anytype, title: []const u8, value: *bool, opts: anytype) bool {
            // nanoui's checkbox takes no options — id_extra has no destination.
            // Field is accepted by the adapter for interface symmetry with DVUI,
            // and silently ignored.
            _ = opts;
            if (@hasDecl(ui, "checkbox")) {
                return ui.checkbox(c, title, value);
            }
            return false;
        }

        pub fn progress(c: anytype, value: f32, opts: anytype) void {
            _ = opts;
            if (@hasDecl(ui, "progress")) {
                const clamped = if (value < 0.0) 0.0 else if (value > 1.0) 1.0 else value;
                ui.progress(c, clamped, .fill);
            }
        }

        pub fn divider(c: anytype, opts: anytype) void {
            _ = opts;
            var d = ui.div(c).wFull().h(1.0);
            d = d.bg(.{ .r = 0.86, .g = 0.86, .b = 0.86, .a = 1.0 });
            defer d.end();
        }

        pub fn slider(c: anytype, value: *f32, opts: anytype) bool {
            _ = opts;
            if (@hasDecl(ui, "slider")) {
                return ui.slider(c, value, .{});
            }
            return false;
        }

        pub fn toggle(c: anytype, label: []const u8, value: *bool, opts: anytype) bool {
            _ = opts;
            if (@hasDecl(ui, "toggle")) {
                return ui.toggle(c, label, value);
            }
            return false;
        }

        pub fn skeleton(c: anytype, opts: anytype) void {
            if (@hasDecl(ui, "div")) {
                var d = ui.div(c);
                if (@hasField(@TypeOf(opts), "width")) d = d.w(opts.width);
                if (@hasField(@TypeOf(opts), "height")) d = d.h(opts.height);
                if (@hasField(@TypeOf(opts), "radius")) d = d.rounded(opts.radius);
                d = d.bg(.{ .r = 0.9, .g = 0.91, .b = 0.92, .a = 1.0 });
                d.end();
            }
        }








        pub const Box = struct {
            inner: ui.Div,

            pub fn end(self: Box) void {
                self.inner.end();
            }
        };

        fn applyOpts(ui_mod: type, d: ui_mod.Div, opts: anytype) ui_mod.Div {
            var out = d;
            if (@hasField(@TypeOf(opts), "padding")) {
                const p = opts.padding;
                const px: f32 = @as(f32, @floatFromInt(p.x));
                const py: f32 = @as(f32, @floatFromInt(p.y));
                const pw: f32 = @as(f32, @floatFromInt(p.w));
                const ph: f32 = @as(f32, @floatFromInt(p.h));
                if (px == py and px == pw and px == ph) {
                    out = out.p(px);
                } else {
                    out = out.px(px);
                    out = out.py(py);
                }
            }
            if (@hasField(@TypeOf(opts), "gap")) {
                out = out.gap(@as(f32, @floatFromInt(opts.gap)));
            }
            if (@hasField(@TypeOf(opts), "radius")) {
                out = out.rounded(@as(f32, @floatFromInt(opts.radius)));
            }
            if (@hasField(@TypeOf(opts), "color_fill")) {
                const col = opts.color_fill;
                const c: ui_mod.Color = .{
                    .r = @as(f32, @floatFromInt(col.r)) / 255.0,
                    .g = @as(f32, @floatFromInt(col.g)) / 255.0,
                    .b = @as(f32, @floatFromInt(col.b)) / 255.0,
                    .a = @as(f32, @floatFromInt(col.a)) / 255.0,
                };
                out = out.bg(c);
            }
            return out;
        }
    };
}

pub const StubNanoui = struct {
    pub const Color = struct {
        r: f32 = 0,
        g: f32 = 0,
        b: f32 = 0,
        a: f32 = 1,
    };

    pub const Weight = enum { regular, medium, semibold, bold };

    pub const TextStyle = struct {
        size: f32 = 14,
        weight: Weight = .regular,
        color: ?Color = null,
    };

    pub const Interaction = struct {
        clicked: bool = false,
    };

    pub const ButtonOptions = struct {
        variant: enum { primary, secondary, ghost } = .primary,
        disabled: bool = false,
    };

    pub const Context = struct {};

    pub const Div = struct {
        pub fn column(self: Div) Div {
            return self;
        }
        pub fn row(self: Div) Div {
            return self;
        }
        pub fn p(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn px(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn py(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn gap(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn rounded(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn bg(self: Div, c: Color) Div {
            _ = c;
            return self;
        }
        pub fn w(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn h(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn end(self: Div) void {
            _ = self;
        }
    };

    var _buttons_rendered: usize = 0;
    var _text_entries_rendered: usize = 0;
    var _text_areas_rendered: usize = 0;
    var _checkboxes_rendered: usize = 0;
    var _progresses_rendered: usize = 0;
    var _dividers_rendered: usize = 0;
    var _sliders_rendered: usize = 0;
    var _toggles_rendered: usize = 0;
    var _skeletons_rendered: usize = 0;
    var _labels_rendered: usize = 0;
    var _last_text_size: f32 = 0;
    var _last_text_weight: Weight = .regular;

    pub fn buttonsRendered() usize {
        return _buttons_rendered;
    }
    pub fn textEntriesRendered() usize {
        return _text_entries_rendered;
    }
    pub fn progressesRendered() usize {
        return _progresses_rendered;
    }
    pub fn dividersRendered() usize {
        return _dividers_rendered;
    }
    pub fn slidersRendered() usize {
        return _sliders_rendered;
    }

    pub fn labelsRendered() usize {
        return _labels_rendered;
    }

    pub fn lastTextSize() f32 {
        return _last_text_size;
    }

    pub fn lastTextWeight() Weight {
        return _last_text_weight;
    }

    pub fn resetCounters() void {
        _buttons_rendered = 0;
        _text_entries_rendered = 0;
        _labels_rendered = 0;
        _last_text_size = 0;
        _last_text_weight = .regular;
    }

    pub fn div(c: *Context) Div {
        _ = c;
        return .{};
    }

    pub fn text(c: *Context, str: []const u8, style: TextStyle) void {
        _ = c;
        _ = str;
        _labels_rendered += 1;
        _last_text_size = style.size;
        _last_text_weight = style.weight;
    }

    pub fn button(c: *Context, title: []const u8, opts: ButtonOptions) Interaction {
        _ = c;
        _ = title;
        _ = opts;
        _buttons_rendered += 1;
        return .{};
    }

    pub fn textEntry(c: *Context, buffer: []u8, opts: anytype) void {
        _ = c; _ = buffer; _ = opts;
        _text_entries_rendered += 1;
    }

    pub fn textArea(c: *Context, buffer: []u8, opts: anytype) void {
        _ = c; _ = buffer; _ = opts;
        _text_areas_rendered += 1;
    }

    pub fn checkbox(c: *Context, title: []const u8, value: *bool, opts: anytype) bool {
        _ = c; _ = title; _ = value; _ = opts;
        _checkboxes_rendered += 1;
        return false;
    }

    pub fn progress(c: *Context, value: f32, opts: anytype) void {
        _ = c; _ = value; _ = opts;
        _progresses_rendered += 1;
    }

    pub fn divider(c: *Context, opts: anytype) void {
        _ = c; _ = opts;
        _dividers_rendered += 1;
    }

    pub fn slider(c: *Context, value: *f32, opts: anytype) bool {
        _ = c; _ = value; _ = opts;
        _sliders_rendered += 1;
        return false;
    }
    pub fn toggle(c: *Context, label: []const u8, value: *bool, opts: anytype) bool {
        _ = c; _ = label; _ = value; _ = opts;
        _toggles_rendered += 1;
        return false;
    }

    pub fn skeleton(c: *Context, opts: anytype) void {
        _ = c; _ = opts;
        _skeletons_rendered += 1;
    }






};

test "nanoui adapter column opens and ends" {
    const A = Adapter(StubNanoui);
    var c: StubNanoui.Context = .{};
    const b = A.column(&c, .{});
    b.end();
}

test "nanoui adapter text applies font_size" {
    const A = Adapter(StubNanoui);
    var c: StubNanoui.Context = .{};
    StubNanoui.resetCounters();
    A.text(&c, "hello", .{ .font_size = 18 });
    try std.testing.expectEqual(@as(f32, 18), StubNanoui.lastTextSize());
}

test "nanoui adapter text applies font_weight bold" {
    const A = Adapter(StubNanoui);
    var c: StubNanoui.Context = .{};
    StubNanoui.resetCounters();
    A.text(&c, "hi", .{ .font_weight = 700 });
    try std.testing.expectEqual(StubNanoui.Weight.bold, StubNanoui.lastTextWeight());
}

test "nanoui adapter text applies font_weight regular" {
    const A = Adapter(StubNanoui);
    var c: StubNanoui.Context = .{};
    StubNanoui.resetCounters();
    A.text(&c, "hi", .{ .font_weight = 400 });
    try std.testing.expectEqual(StubNanoui.Weight.regular, StubNanoui.lastTextWeight());
}

test "nanoui adapter text applies font_weight semibold" {
    const A = Adapter(StubNanoui);
    var c: StubNanoui.Context = .{};
    StubNanoui.resetCounters();
    A.text(&c, "hi", .{ .font_weight = 600 });
    try std.testing.expectEqual(StubNanoui.Weight.semibold, StubNanoui.lastTextWeight());
}

test "nanoui adapter button counts" {
    const A = Adapter(StubNanoui);
    var c: StubNanoui.Context = .{};
    StubNanoui.resetCounters();
    _ = A.button(&c, "Save", .{});
    try std.testing.expectEqual(@as(usize, 1), StubNanoui.buttonsRendered());
}
