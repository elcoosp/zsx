const std = @import("std");

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
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("shadcn_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ShadcnCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.primary_count);
    try std.testing.expectEqualStrings("Save", ctx.last_primary_text);
}

test "shadcn: Button variant ghost fires separately" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("shadcn_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    var ctx = ShadcnCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.ghost_count);
    try std.testing.expectEqualStrings("Cancel", ctx.last_ghost_text);
}

test "shadcn: Badge color green passes through" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("shadcn_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    var ctx = ShadcnCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.badge_green_count);
}

const ShadcnLibCtx = struct {
    primary_count: usize = 0,
    secondary_count: usize = 0,
    ghost_count: usize = 0,
    danger_count: usize = 0,
    badge_red_count: usize = 0,
    badge_green_count: usize = 0,

    pub inline fn Button(self: *@This(), ui: anytype, c: anytype, props: anytype) void {
        const variant: []const u8 = if (@hasField(@TypeOf(props), "variant")) props.variant else "primary";
        if (std.mem.eql(u8, variant, "primary")) {
            self.primary_count += 1;
            _ = ui.button(c, props.text, .{
                .color_fill = .{ .r = 59, .g = 130, .b = 246, .a = 255 },
                .color_text = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
                .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 },
                .radius = 8,
            });
        } else if (std.mem.eql(u8, variant, "secondary")) {
            self.secondary_count += 1;
            _ = ui.button(c, props.text, .{
                .color_fill = .{ .r = 243, .g = 244, .b = 246, .a = 255 },
                .color_text = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
                .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 },
                .radius = 8,
            });
        } else if (std.mem.eql(u8, variant, "ghost")) {
            self.ghost_count += 1;
            _ = ui.button(c, props.text, .{
                .color_fill = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .color_text = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
                .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 },
                .radius = 8,
            });
        } else if (std.mem.eql(u8, variant, "danger")) {
            self.danger_count += 1;
            _ = ui.button(c, props.text, .{
                .color_fill = .{ .r = 239, .g = 68, .b = 68, .a = 255 },
                .color_text = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
                .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 },
                .radius = 8,
            });
        } else {
            _ = ui.button(c, props.text, .{});
        }
    }

    pub inline fn Badge(self: *@This(), ui: anytype, c: anytype, props: anytype) void {
        const color: []const u8 = if (@hasField(@TypeOf(props), "color")) props.color else "";
        if (std.mem.eql(u8, color, "red")) {
            self.badge_red_count += 1;
            ui.text(c, props.text, .{
                .color_text = .{ .r = 239, .g = 68, .b = 68, .a = 255 },
                .font_size = 14,
                .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
            });
        } else if (std.mem.eql(u8, color, "green")) {
            self.badge_green_count += 1;
            ui.text(c, props.text, .{
                .color_text = .{ .r = 34, .g = 197, .b = 94, .a = 255 },
                .font_size = 14,
                .padding = .{ .x = 8, .y = 4, .w = 8, .h = 4 },
            });
        } else {
            ui.text(c, props.text, .{});
        }
    }
};

test "shadcn-lib: Button variants dispatch correctly" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("shadcn_lib_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ShadcnLibCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.primary_count);
    try std.testing.expectEqual(@as(usize, 1), ctx.secondary_count);
    try std.testing.expectEqual(@as(usize, 1), ctx.ghost_count);
    try std.testing.expectEqual(@as(usize, 1), ctx.danger_count);
    try std.testing.expectEqual(@as(usize, 4), dvui_adapter.StubDvui.buttonsRendered());
}

test "shadcn-lib: Badge colors dispatch correctly" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("shadcn_lib_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ShadcnLibCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.badge_red_count);
    try std.testing.expectEqual(@as(usize, 1), ctx.badge_green_count);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.labelsRendered());
}

const OnClickCtx = struct {
    save_called: bool = false,
    button_rendered: usize = 0,

    pub fn save(self: *@This()) void {
        self.save_called = true;
    }

    pub inline fn Button(self: *@This(), ui: anytype, c: anytype, props: anytype) void {
        self.button_rendered += 1;
        if (ui.button(c, props.text, .{})) {
            if (@hasField(@TypeOf(props), "on_click")) {
                props.on_click(self);
            }
        }
    }
};

test "onclick: queued click fires on_click via props" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("onclick_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    dvui_adapter.StubDvui.queue_click();
    var ctx = OnClickCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expect(ctx.save_called);
    try std.testing.expectEqual(@as(usize, 1), ctx.button_rendered);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "onclick: no queued click means no save" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("onclick_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = OnClickCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
    try std.testing.expectEqual(@as(usize, 1), ctx.button_rendered);
}

const ShadcnLibraryCtx = struct {
    pub const Button = @import("shadcn").Button;
    pub const Badge = @import("shadcn").Badge;

    save_called: bool = false,
    button_count: usize = 0,
    label_count: usize = 0,

    pub fn save(self: *@This()) void {
        self.save_called = true;
    }
};

test "shadcn-lib-file: Button variant dispatches via library" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("shadcn_lib_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ShadcnLibraryCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 4), dvui_adapter.StubDvui.buttonsRendered());
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.labelsRendered());
}

test "shadcn-lib-file: Button on_click via library fires handler" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("onclick_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    dvui_adapter.StubDvui.queue_click();
    var ctx = ShadcnLibraryCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expect(ctx.save_called);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "shadcn-lib-file: Button on_click not fired without queue" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("onclick_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ShadcnLibraryCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
}
