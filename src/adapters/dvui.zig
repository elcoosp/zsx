const std = @import("std");

pub fn Adapter(comptime dvui: type) type {
    return struct {
        pub fn column(c: anytype, opts: anytype) Box {
            _ = c;
            return openBox(dvui, dvui.enums.Direction.vertical, opts);
        }
        pub fn row(c: anytype, opts: anytype) Box {
            _ = c;
            return openBox(dvui, dvui.enums.Direction.horizontal, opts);
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
        fn openBox(dvui_mod: type, direction: dvui_mod.enums.Direction, opts: anytype) Box {
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
            if (@hasField(@TypeOf(opts), "radius")) {
                if (@hasField(dvui_mod.Options, "radius")) o.radius = opts.radius;
                if (@hasField(dvui_mod.Options, "corners")) {
                    const r = opts.radius;
                    o.corners = .{ .tl = .round(r), .tr = .round(r), .br = .round(r), .bl = .round(r) };
                }
            }
            if (@hasField(@TypeOf(opts), "gap")) {
                if (@hasField(dvui_mod.Options, "gap")) o.gap = opts.gap;
            }
            if (@hasField(@TypeOf(opts), "expand")) {
                if (@hasField(dvui_mod.Options, "expand")) {
                    o.expand = switch (opts.expand) {
                        .none => .none, .horizontal => .horizontal, .vertical => .vertical, .both => .both,
                    };
                }
            }
            if (@hasField(@TypeOf(opts), "id_extra")) {
                if (@hasField(dvui_mod.Options, "id_extra")) o.id_extra = opts.id_extra;
            }
            return o;
        }
    };
}

pub const StubDvui = struct {
    pub const Color = struct { r: u8 = 0, g: u8 = 0, b: u8 = 0, a: u8 = 255 };
    pub const ColorOrGradient = union(enum) { color: Color };
    pub const Rect = struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0 };
    pub const Expand = enum { none, horizontal, vertical, both };
    pub const Direction = enum { vertical, horizontal };
    pub const enums = struct { pub const Direction = StubDvui.Direction; };
    pub const Options = struct {
        color_fill: ?ColorOrGradient = null,
        color_text: ?ColorOrGradient = null,
        padding: ?Rect = null,
        radius: ?f32 = null,
        gap: ?f32 = null,
        expand: ?Expand = null,
        id_extra: ?usize = null,
    };
    pub const BoxWidget = struct {
        ended: bool = false,
        pub fn deinit(self: *BoxWidget) void { self.ended = true; }
    };
    pub const Context = struct {};

    var _box: BoxWidget = .{};
    var _buttons_rendered: usize = 0;
    var _labels_rendered: usize = 0;
    var _last_button_padding: ?Rect = null;
    var _last_button_radius: ?f32 = null;
    var _queued_clicks: usize = 0;

    pub fn buttonsRendered() usize { return _buttons_rendered; }
    pub fn labelsRendered() usize { return _labels_rendered; }
    pub fn lastButtonPadding() ?Rect { return _last_button_padding; }
    pub fn lastButtonRadius() ?f32 { return _last_button_radius; }
    pub fn queue_click() void { _queued_clicks += 1; }
    pub fn resetCounters() void {
        _buttons_rendered = 0;
        _labels_rendered = 0;
        _queued_clicks = 0;
        _last_button_padding = null;
        _last_button_radius = null;
    }
    pub fn box(src: anytype, init: anytype, opts: Options) *BoxWidget {
        _ = src; _ = init; _ = opts;
        _box.ended = false;
        return &_box;
    }
    pub fn button(src: anytype, label: []const u8, init: anytype, opts: Options) bool {
        _ = src; _ = label; _ = init;
        _buttons_rendered += 1;
        _last_button_padding = opts.padding;
        _last_button_radius = opts.radius;
        if (_queued_clicks > 0) { _queued_clicks -= 1; return true; }
        return false;
    }
    pub fn labelNoFmt(src: anytype, text: []const u8, init: anytype, opts: Options) void {
        _ = src; _ = text; _ = init; _ = opts;
        _labels_rendered += 1;
    }
};

test "stub column" {
    const A = Adapter(StubDvui);
    var c: StubDvui.Context = .{};
    const b = A.column(&c, .{});
    b.end();
}
test "stub text counts" {
    const A = Adapter(StubDvui);
    var c: StubDvui.Context = .{};
    StubDvui.resetCounters();
    A.text(&c, "hi", .{});
    try std.testing.expectEqual(@as(usize, 1), StubDvui.labelsRendered());
}
test "stub button tracks padding and radius" {
    const A = Adapter(StubDvui);
    var c: StubDvui.Context = .{};
    StubDvui.resetCounters();
    _ = A.button(&c, "Save", .{ .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 }, .radius = 8 });
    try std.testing.expectEqual(@as(usize, 1), StubDvui.buttonsRendered());
    try std.testing.expectEqual(@as(f32, 8), StubDvui.lastButtonPadding().?.y);
    try std.testing.expectEqual(@as(f32, 8), StubDvui.lastButtonRadius().?);
}
