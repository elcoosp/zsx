const std = @import("std");

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
    card_count: usize = 0,
    button_count: usize = 0,
    content_invocations: usize = 0,

    pub inline fn Card(self: *@This(), ui: anytype, c: anytype, comptime props: anytype) void {
        self.card_count += 1;
        var b = ui.column(c, .{ .padding = .{ .x = 12, .y = 12, .w = 12, .h = 12 } });
        defer b.end();
        self.content_invocations += 1;
        inline for ([_][]const u8{ "content", "header", "body", "footer" }) |slot_name| {
            if (comptime @hasField(@TypeOf(props), slot_name)) {
                const f = @field(props, slot_name);
                f(ui, c, self);
            }
        }
    }

    pub inline fn Button(self: *@This(), ui: anytype, c: anytype, comptime props: anytype) void {
        self.button_count += 1;
        _ = ui.button(c, props.text, .{});
    }
};

test "dvui: if-true with items" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("demo");
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
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("demo");
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
    const nanoui_adapter = @import("../adapters/nanoui.zig");
    const demo = @import("demo");
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
    const nanoui_adapter = @import("../adapters/nanoui.zig");
    const demo = @import("demo");
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

test "component: Card content renders two labels via comptime content fn" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("component_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = CtxWithComponents{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.card_count);
    try std.testing.expectEqual(@as(usize, 1), ctx.content_invocations);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.labelsRendered());
}

test "component: Button leaf fires without content fn" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("component_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = CtxWithComponents{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.button_count);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "component: content fn receives ctx pointer, can read its fields" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("component_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};

    const CtxCapture = struct {
        pub inline fn Card(self: *@This(), ui: anytype, c_: anytype, comptime props: anytype) void {
            var b = ui.column(c_, .{});
            defer b.end();
            inline for ([_][]const u8{ "content", "header", "body", "footer" }) |slot_name| {
                if (comptime @hasField(@TypeOf(props), slot_name)) {
                    const f = @field(props, slot_name);
                    f(ui, c_, self);
                }
            }
        }
        pub inline fn Button(self: *@This(), ui: anytype, c_: anytype, comptime props: anytype) void {
            _ = self;
            _ = ui.button(c_, props.text, .{});
        }
    };
    var ctx = CtxCapture{};
    dvui_adapter.StubDvui.resetCounters();
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.labelsRendered());
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}
