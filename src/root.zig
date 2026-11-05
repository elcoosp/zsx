const std = @import("std");

pub const Feature = @import("feature.zig").Feature;
pub const Capabilities = @import("capabilities.zig").Capabilities;
pub const StyleRef = @import("style_ref.zig").StyleRef;
pub const Backend = @import("backend.zig").Backend;

pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const style = @import("style.zig");

test {
    _ = @import("style.zig");
}

test {
    _ = @import("adapters/dvui.zig");
}

test {
    _ = @import("adapters/nanoui.zig");
}

test {
    _ = @import("views/demo_gen.zig");
}

test {
    _ = @import("views/component_demo_gen.zig");
}

const User = struct { name: []const u8 };
const Ctx = struct {
    user: User,
    show_save: bool = true,
    items: []const []const u8 = &[_][]const u8{},
    save_called: bool = false,
    pub fn save(self: *@This()) void {
        self.save_called = true;
    }
};

const CtxWithComponents = struct {
    buttons_via_component: usize = 0,
    badges_via_component: usize = 0,
    pub fn Button(self: *@This(), ui: anytype, c: anytype, props: anytype) void {
        _ = ui.button(c, props.text, .{});
        self.buttons_via_component += 1;
    }
    pub fn Badge(self: *@This(), ui: anytype, c: anytype, props: anytype) void {
        _ = ui;
        _ = c;
        _ = props;
        self.badges_via_component += 1;
    }
};

test "dvui: if-true with items" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = Ctx{
        .user = .{ .name = "Alice" },
        .show_save = true,
        .items = &[_][]const u8{ "one", "two", "three" },
    };
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
    try std.testing.expectEqual(@as(usize, 3), dvui_adapter.StubDvui.labelsRendered());
}

test "dvui: if-false with no items" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = Ctx{
        .user = .{ .name = "Bob" },
        .show_save = false,
        .items = &[_][]const u8{},
    };
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
    try std.testing.expectEqual(@as(usize, 0), dvui_adapter.StubDvui.buttonsRendered());
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.labelsRendered());
}

test "nanoui: if-true with items, font_weight flows as bold" {
    const nanoui_adapter = @import("adapters/nanoui.zig");
    const demo = @import("views/demo_gen.zig");
    const A = nanoui_adapter.Adapter(nanoui_adapter.StubNanoui);
    var c: nanoui_adapter.StubNanoui.Context = .{};
    nanoui_adapter.StubNanoui.resetCounters();
    var ctx = Ctx{
        .user = .{ .name = "Alice" },
        .show_save = true,
        .items = &[_][]const u8{ "one", "two", "three" },
    };
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
    try std.testing.expectEqual(@as(usize, 1), nanoui_adapter.StubNanoui.buttonsRendered());
    try std.testing.expectEqual(@as(usize, 3), nanoui_adapter.StubNanoui.labelsRendered());
    try std.testing.expectEqual(@as(f32, 18), nanoui_adapter.StubNanoui.lastTextSize());
    try std.testing.expectEqual(nanoui_adapter.StubNanoui.Weight.bold, nanoui_adapter.StubNanoui.lastTextWeight());
}

test "nanoui: if-false with no items, font_weight stays regular" {
    const nanoui_adapter = @import("adapters/nanoui.zig");
    const demo = @import("views/demo_gen.zig");
    const A = nanoui_adapter.Adapter(nanoui_adapter.StubNanoui);
    var c: nanoui_adapter.StubNanoui.Context = .{};
    nanoui_adapter.StubNanoui.resetCounters();
    var ctx = Ctx{
        .user = .{ .name = "Bob" },
        .show_save = false,
        .items = &[_][]const u8{},
    };
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
    try std.testing.expectEqual(@as(usize, 0), nanoui_adapter.StubNanoui.buttonsRendered());
    try std.testing.expectEqual(@as(usize, 1), nanoui_adapter.StubNanoui.labelsRendered());
    try std.testing.expectEqual(@as(f32, 14), nanoui_adapter.StubNanoui.lastTextSize());
    try std.testing.expectEqual(nanoui_adapter.StubNanoui.Weight.regular, nanoui_adapter.StubNanoui.lastTextWeight());
}

test "component: <Button> invokes ctx.Button, <Badge> invokes ctx.Badge" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/component_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = CtxWithComponents{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.buttons_via_component);
    try std.testing.expectEqual(@as(usize, 1), ctx.badges_via_component);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "component: <Button> passes .text prop from child" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/component_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};

    const CtxCaptures = struct {
        captured_text: []const u8 = "",
        pub fn Button(self: *@This(), ui: anytype, c_: anytype, props: anytype) void {
            _ = ui;
            _ = c_;
            self.captured_text = props.text;
        }
        pub fn Badge(self: *@This(), ui: anytype, c_: anytype, props: anytype) void {
            _ = self;
            _ = ui;
            _ = c_;
            _ = props;
        }
    };
    var ctx = CtxCaptures{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqualStrings("Hello", ctx.captured_text);
}
