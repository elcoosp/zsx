const std = @import("std");

pub fn Adapter(comptime ui: type) type {
    return struct {
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
                ts.size = @as(f32, @floatFromInt(opts.font_size));
            }
            ui.text(c, str, ts);
        }

        pub fn button(c: anytype, title: []const u8, opts: anytype) bool {
            _ = opts;
            return ui.button(c, title, .{}).clicked;
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
    var _labels_rendered: usize = 0;
    var _last_text_size: f32 = 0;
    var _last_text_weight: Weight = .regular;

    pub fn buttonsRendered() usize {
        return _buttons_rendered;
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
    try std.testing.expectEqual(@as(usize, 1), StubNanoui.labelsRendered());
}

test "nanoui adapter text applies color" {
    const A = Adapter(StubNanoui);
    var c: StubNanoui.Context = .{};
    StubNanoui.resetCounters();
    A.text(&c, "hi", .{ .color_text = .{ .r = 243, .g = 244, .b = 246, .a = 255 } });
    try std.testing.expectEqual(@as(usize, 1), StubNanoui.labelsRendered());
}

test "nanoui adapter button counts" {
    const A = Adapter(StubNanoui);
    var c: StubNanoui.Context = .{};
    StubNanoui.resetCounters();
    _ = A.button(&c, "Save", .{});
    try std.testing.expectEqual(@as(usize, 1), StubNanoui.buttonsRendered());
}
