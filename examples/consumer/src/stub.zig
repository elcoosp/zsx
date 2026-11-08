// Minimal adapter — the primitives our views call. Real consumers swap this
// for src/adapters/dvui.zig, nanoui.zig, or html.zig.
const std = @import("std");

pub const Context = struct {};
pub const BoxWidget = struct {};

var _buttons: usize = 0;
var _labels: usize = 0;
var _box: BoxWidget = .{};

pub fn resetCounters() void {
    _buttons = 0;
    _labels = 0;
}
pub fn buttonsRendered() usize { return _buttons; }
pub fn labelsRendered() usize { return _labels; }

pub const Adapter = struct {
    pub const Box = struct {
        inner: *BoxWidget,
        pub fn end(self: Box) void { _ = self; }
    };

    pub fn column(c: *Context, opts: anytype) Box {
        _ = c; _ = opts;
        return .{ .inner = &_box };
    }
    pub fn row(c: *Context, opts: anytype) Box {
        _ = c; _ = opts;
        return .{ .inner = &_box };
    }
    pub fn text(c: *Context, str: []const u8, opts: anytype) void {
        _ = c; _ = opts;
        _labels += 1;
        std.debug.print("[stub] label: {s}\n", .{str});
    }
    pub fn button(c: *Context, title: []const u8, opts: anytype) bool {
        _ = c; _ = opts;
        _buttons += 1;
        std.debug.print("[stub] button: {s}\n", .{title});
        return false;
    }
};
