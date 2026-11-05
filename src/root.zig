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

test {
    _ = @import("views/shadcn_demo_gen.zig");
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
    card_count: usize = 0,
    button_count: usize = 0,
    content_invocations: usize = 0,

    pub inline fn Card(self: *@This(), ui: anytype, c: anytype, comptime props: anytype, comptime content: anytype) void {
        _ = props;
        self.card_count += 1;
        var b = ui.column(c, .{ .padding = .{ .x = 12, .y = 12, .w = 12, .h = 12 } });
        defer b.end();
        self.content_invocations += 1;
        content(ui, c, self);
    }

    pub inline fn Button(self: *@This(), ui: anytype, c: anytype, comptime props: anytype) void {
        self.button_count += 1;
        _ = ui.button(c, props.text, .{});
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

test "component: Card content renders two labels via comptime content fn" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/component_demo_gen.zig");
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
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/component_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = CtxWithComponents{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.button_count);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "component: content fn receives ctx pointer, can read its fields" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/component_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};

    const CtxCapture = struct {
        pub inline fn Card(self: *@This(), ui: anytype, c_: anytype, comptime props: anytype, comptime content: anytype) void {
            _ = props;
            var b = ui.column(c_, .{});
            defer b.end();
            content(ui, c_, self);
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

const ShadcnCtx = struct {
    primary_count: usize = 0,
    ghost_count: usize = 0,
    badge_green_count: usize = 0,
    last_primary_text: []const u8 = "",
    last_ghost_text: []const u8 = "",

    pub inline fn Button(self: *@This(), ui: anytype, c: anytype, comptime props: anytype) void {
        const variant: []const u8 = if (@hasField(@TypeOf(props), "variant")) props.variant else "default";
        if (std.mem.eql(u8, variant, "primary")) {
            self.primary_count += 1;
            self.last_primary_text = props.text;
        } else if (std.mem.eql(u8, variant, "ghost")) {
            self.ghost_count += 1;
            self.last_ghost_text = props.text;
        }
        _ = ui.button(c, props.text, .{});
    }

    pub inline fn Badge(self: *@This(), ui: anytype, c: anytype, comptime props: anytype) void {
        _ = ui;
        _ = c;
        const color: []const u8 = if (@hasField(@TypeOf(props), "color")) props.color else "";
        if (std.mem.eql(u8, color, "green")) {
            self.badge_green_count += 1;
        }
    }
};

test "shadcn: Button variant primary renders via ctx.Button" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/shadcn_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ShadcnCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.primary_count);
    try std.testing.expectEqualStrings("Save", ctx.last_primary_text);
}

test "shadcn: Button variant ghost fires separately" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/shadcn_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    var ctx = ShadcnCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.ghost_count);
    try std.testing.expectEqualStrings("Cancel", ctx.last_ghost_text);
}

test "shadcn: Badge color green passes through" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/shadcn_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    var ctx = ShadcnCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.badge_green_count);
}
