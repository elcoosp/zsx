const std = @import("std");

pub fn Adapter(comptime dvui: type) type {
    return struct {
        pub fn column(c: anytype, opts: anytype) Box {
            _ = c;
            return openBox(dvui, dvui.Direction.vertical, opts);
        }

        pub fn row(c: anytype, opts: anytype) Box {
            _ = c;
            return openBox(dvui, dvui.Direction.horizontal, opts);
        }

        pub fn text(c: anytype, str: []const u8, opts: anytype) void {
            _ = c;
            dvui.labelNoFmt(@src(), str, .{}, optionsFrom(dvui, opts));
        }

        pub fn button(c: anytype, title: []const u8, opts: anytype) bool {
            _ = c;
            return dvui.button(@src(), title, .{}, optionsFrom(dvui, opts));
        }

        pub const Box = struct {
            inner: *dvui.BoxWidget,

            pub fn end(self: Box) void {
                self.inner.deinit();
            }
        };

        fn openBox(dvui_mod: type, direction: dvui_mod.Direction, opts: anytype) Box {
            const o = optionsFrom(dvui_mod, opts);
            const b = dvui_mod.box(@src(), .{ .dir = direction }, o);
            return .{ .inner = b };
        }

        fn optionsFrom(dvui_mod: type, opts: anytype) dvui_mod.Options {
            var o = dvui_mod.Options{};
            if (@hasField(@TypeOf(opts), "color_fill")) {
                const c = opts.color_fill;
                o.color_fill = .{ .color = .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } };
            }
            if (@hasField(@TypeOf(opts), "color_text")) {
                const c = opts.color_text;
                o.color_text = .{ .color = .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a } };
            }
            if (@hasField(@TypeOf(opts), "padding")) {
                const p = opts.padding;
                o.padding = .{ .x = p.x, .y = p.y, .w = p.w, .h = p.h };
            }
            if (@hasField(@TypeOf(opts), "radius")) o.radius = opts.radius;
            if (@hasField(@TypeOf(opts), "gap")) o.gap = opts.gap;
            if (@hasField(@TypeOf(opts), "expand")) o.expand = opts.expand;
            return o;
        }
    };
}

pub const StubDvui = struct {
    pub const Color = struct {
        r: u8 = 0,
        g: u8 = 0,
        b: u8 = 0,
        a: u8 = 255,
    };

    pub const ColorOrGradient = union(enum) {
        color: Color,
    };

    pub const Rect = struct {
        x: f32 = 0,
        y: f32 = 0,
        w: f32 = 0,
        h: f32 = 0,
    };

    pub const Direction = enum { vertical, horizontal };

    pub const Expand = enum { none, horizontal, vertical, both };

    pub const Options = struct {
        color_fill: ?ColorOrGradient = null,
        color_text: ?ColorOrGradient = null,
        padding: ?Rect = null,
        radius: ?f32 = null,
        gap: ?f32 = null,
        expand: ?Expand = null,
    };

    pub const BoxWidget = struct {
        ended: bool = false,
        pub fn deinit(self: *BoxWidget) void {
            self.ended = true;
        }
    };

    pub const Context = struct {};

    var _box: BoxWidget = .{};
    var _buttons_rendered: usize = 0;
    var _labels_rendered: usize = 0;

    pub fn buttonsRendered() usize {
        return _buttons_rendered;
    }

    pub fn labelsRendered() usize {
        return _labels_rendered;
    }

    pub fn resetCounters() void {
        _buttons_rendered = 0;
        _labels_rendered = 0;
    }

    pub fn box(src: anytype, init: anytype, opts: Options) *BoxWidget {
        _ = src;
        _ = init;
        _ = opts;
        _box.ended = false;
        return &_box;
    }

    pub fn button(src: anytype, label: []const u8, init: anytype, opts: Options) bool {
        _ = src;
        _ = label;
        _ = init;
        _ = opts;
        _buttons_rendered += 1;
        return false;
    }

    pub fn labelNoFmt(src: anytype, text: []const u8, init: anytype, opts: Options) void {
        _ = src;
        _ = text;
        _ = init;
        _ = opts;
        _labels_rendered += 1;
    }
};

test "dvui adapter column opens and ends" {
    const A = Adapter(StubDvui);
    var c: StubDvui.Context = .{};
    const b = A.column(&c, .{});
    b.end();
}

test "dvui adapter text counts labels" {
    const A = Adapter(StubDvui);
    var c: StubDvui.Context = .{};
    StubDvui.resetCounters();
    A.text(&c, "hi", .{});
    try std.testing.expectEqual(@as(usize, 1), StubDvui.labelsRendered());
}

test "dvui adapter button counts buttons" {
    const A = Adapter(StubDvui);
    var c: StubDvui.Context = .{};
    StubDvui.resetCounters();
    _ = A.button(&c, "Save", .{ .color_fill = .{ .r = 59, .g = 130, .b = 246, .a = 255 } });
    try std.testing.expectEqual(@as(usize, 1), StubDvui.buttonsRendered());
}
