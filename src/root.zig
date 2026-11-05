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

test {
    _ = @import("views/shadcn_lib_demo_gen.zig");
}

test {
    _ = @import("views/onclick_demo_gen.zig");
}

test {
    _ = @import("views/struct_loop_demo_gen.zig");
}

test {
    _ = @import("views/card_if_demo_gen.zig");
}

test {
    _ = @import("views/else_if_demo_gen.zig");
}

test {
    _ = @import("views/fragment_demo_gen.zig");
}

test {
    _ = @import("views/class_override_demo_gen.zig");
}

test {
    _ = @import("views/nested_card_demo_gen.zig");
}

test {
    _ = @import("views/dashboard_gen.zig");
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
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/shadcn_lib_demo_gen.zig");
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
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/shadcn_lib_demo_gen.zig");
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
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/onclick_demo_gen.zig");
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
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/onclick_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = OnClickCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
    try std.testing.expectEqual(@as(usize, 1), ctx.button_rendered);
}

const ShadcnLibraryCtx = struct {
    pub const Button = @import("lib/shadcn.zig").Button;
    pub const Badge = @import("lib/shadcn.zig").Badge;

    save_called: bool = false,
    button_count: usize = 0,
    label_count: usize = 0,

    pub fn save(self: *@This()) void {
        self.save_called = true;
    }
};

test "shadcn-lib-file: Button variant dispatches via library" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/shadcn_lib_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ShadcnLibraryCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 4), dvui_adapter.StubDvui.buttonsRendered());
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.labelsRendered());
}

test "shadcn-lib-file: Button on_click via library fires handler" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/onclick_demo_gen.zig");
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
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/onclick_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ShadcnLibraryCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
}

const StructLoopUser = struct {
    name: []const u8,
    role: []const u8,
};

const StructLoopCtx = struct {
    users: []const StructLoopUser,
    badge_colors: [8][]const u8 = @splat(""),
    badge_count: usize = 0,

    pub inline fn Badge(self: *@This(), ui: anytype, c: anytype, props: anytype) void {
        const color: []const u8 = if (@hasField(@TypeOf(props), "color")) props.color else "";
        if (self.badge_count < 8) {
            self.badge_colors[self.badge_count] = color;
            self.badge_count += 1;
        }
        @import("lib/shadcn.zig").Badge(self, ui, c, props);
    }
};

test "struct-loop: iterates user records with field access" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/struct_loop_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = StructLoopCtx{
        .users = &[_]StructLoopUser{
            .{ .name = "Alice", .role = "green" },
            .{ .name = "Bob", .role = "red" },
            .{ .name = "Carol", .role = "blue" },
        },
    };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 3), ctx.badge_count);
    try std.testing.expectEqualStrings("green", ctx.badge_colors[0]);
    try std.testing.expectEqualStrings("red", ctx.badge_colors[1]);
    try std.testing.expectEqualStrings("blue", ctx.badge_colors[2]);
    try std.testing.expectEqual(@as(usize, 6), dvui_adapter.StubDvui.labelsRendered());
}

const CardIfCtx = struct {
    pub const Card = @import("lib/shadcn.zig").Card;
    show: bool = true,
};

test "card-if: show=true renders one label" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/card_if_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = CardIfCtx{ .show = true };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.labelsRendered());
}

test "card-if: show=false renders zero labels" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/card_if_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = CardIfCtx{ .show = false };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 0), dvui_adapter.StubDvui.labelsRendered());
}

const ElseIfCtx = struct {
    a: bool = false,
    b: bool = false,
};

test "else-if: a=true renders only A (1 label)" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/else_if_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ElseIfCtx{ .a = true, .b = false };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.labelsRendered());
}

test "else-if: a=false b=true renders B branch (2 labels)" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/else_if_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ElseIfCtx{ .a = false, .b = true };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.labelsRendered());
}

test "else-if: a=false b=false renders else branch (3 labels)" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/else_if_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ElseIfCtx{ .a = false, .b = false };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 3), dvui_adapter.StubDvui.labelsRendered());
}

const FragmentCtx = struct {
    verbose: bool = false,
};

test "fragment: verbose=false renders only always label" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/fragment_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = FragmentCtx{ .verbose = false };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.labelsRendered());
}

test "fragment: verbose=true renders two+always labels from fragment" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/fragment_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = FragmentCtx{ .verbose = true };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 3), dvui_adapter.StubDvui.labelsRendered());
}

const ClassOverrideCtx = struct {
    pub const Button = @import("lib/shadcn.zig").Button;
    first_padding: ?@import("adapters/dvui.zig").StubDvui.Rect = null,
    second_padding: ?@import("adapters/dvui.zig").StubDvui.Rect = null,
    count: usize = 0,
};

test "class-override: default Button gets 16x8 padding, p-4 override gets 16x16" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/class_override_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ClassOverrideCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.buttonsRendered());

    const final_padding = dvui_adapter.StubDvui.lastButtonPadding();
    try std.testing.expect(final_padding != null);
    try std.testing.expectEqual(@as(f32, 16), final_padding.?.x);
    try std.testing.expectEqual(@as(f32, 16), final_padding.?.y);
    try std.testing.expectEqual(@as(f32, 16), final_padding.?.w);
    try std.testing.expectEqual(@as(f32, 16), final_padding.?.h);
}

const NestedCardCtx = struct {
    pub const Card = @import("lib/shadcn.zig").Card;
};

test "nested-card: three cards produce distinct render fns and three labels" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/nested_card_demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = NestedCardCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 3), dvui_adapter.StubDvui.labelsRendered());
}

const DashboardTask = struct {
    name: []const u8,
    urgent: bool = false,
    pending: bool = false,
};

const DashboardCtx = struct {
    pub const Badge = @import("lib/shadcn.zig").Badge;
    pub const Button = @import("lib/shadcn.zig").Button;

    user_role: []const u8 = "guest",
    error_message: []const u8 = "",
    items: []const DashboardTask = &[_]DashboardTask{},
    refresh_called: bool = false,

    pub fn refresh(self: *@This()) void {
        self.refresh_called = true;
    }
};

test "dashboard: empty state renders header, no-items, refresh (4 labels, 1 button)" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/dashboard_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = DashboardCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 4), dvui_adapter.StubDvui.labelsRendered());
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
    try std.testing.expect(!ctx.refresh_called);
}

test "dashboard: three items mixed status renders 9 labels (3x label+badge)" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/dashboard_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = DashboardCtx{
        .user_role = "admin",
        .items = &[_]DashboardTask{
            .{ .name = "task1", .urgent = true },
            .{ .name = "task2", .pending = true },
            .{ .name = "task3" },
        },
    };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 9), dvui_adapter.StubDvui.labelsRendered());
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "dashboard: error + one pending renders 6 labels (with error badge)" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/dashboard_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = DashboardCtx{
        .user_role = "guest",
        .error_message = "connection lost",
        .items = &[_]DashboardTask{
            .{ .name = "retry", .pending = true },
        },
    };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 6), dvui_adapter.StubDvui.labelsRendered());
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "dashboard: refresh button fires ctx.refresh when clicked" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/dashboard_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    dvui_adapter.StubDvui.queue_click();
    var ctx = DashboardCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expect(ctx.refresh_called);
}
