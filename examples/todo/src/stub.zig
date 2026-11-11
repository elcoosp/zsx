// Stub adapter — records calls, supports queued clicks for testing.
const std = @import("std");

pub const Context = struct {};
pub const BoxWidget = struct {};

var _buttons: usize = 0;
var _labels: usize = 0;
var _dividers: usize = 0;
var _text_entries: usize = 0;
var _queued_clicks: usize = 0;
var _box: BoxWidget = .{};
var _last_button_label: [128]u8 = @splat(0);
var _last_button_len: usize = 0;

pub fn resetCounters() void {
    _buttons = 0;
    _labels = 0;
    _dividers = 0;
    _text_entries = 0;
    _queued_clicks = 0;
    _last_button_len = 0;
}

pub fn buttonsRendered() usize {
    return _buttons;
}
pub fn labelsRendered() usize {
    return _labels;
}
pub fn dividersRendered() usize {
    return _dividers;
}
pub fn textEntriesRendered() usize {
    return _text_entries;
}
pub fn lastButtonLabel() []const u8 {
    return _last_button_label[0.._last_button_len];
}

pub fn queueClick() void {
    _queued_clicks += 1;
}

pub fn clickButtonByLabel(label: []const u8) void {
    _last_button_len = @min(label.len, 128);
    @memcpy(_last_button_label[0.._last_button_len], label[0.._last_button_len]);
    _queued_clicks += 1;
}

pub const Adapter = struct {
    pub const Box = struct {
        inner: *BoxWidget,
        pub fn end(self: Box) void {
            _ = self;
        }
    };

    pub fn column(c: *Context, opts: anytype) Box {
        _ = c;
        _ = opts;
        return .{ .inner = &_box };
    }
    pub fn row(c: *Context, opts: anytype) Box {
        _ = c;
        _ = opts;
        return .{ .inner = &_box };
    }
    pub fn text(c: *Context, str: []const u8, opts: anytype) void {
        _ = c;
        _ = opts;
        _ = str;
        _labels += 1;
    }
    pub fn button(c: *Context, title: []const u8, opts: anytype) bool {
        _ = c;
        _ = opts;
        _buttons += 1;
        if (_queued_clicks > 0 and std.mem.eql(u8, title, _last_button_label[0.._last_button_len])) {
            _queued_clicks -= 1;
            return true;
        }
        return false;
    }
    pub fn textEntry(c: *Context, buffer: []u8, opts: anytype) void {
        _ = c;
        _ = buffer;
        _ = opts;
        _text_entries += 1;
    }
    pub fn divider(c: *Context, opts: anytype) void {
        _ = c;
        _ = opts;
        _dividers += 1;
    }
};
