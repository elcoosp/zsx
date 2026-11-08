const std = @import("std");
const nanoui = @import("nanoui");
const playground = @import("playground");
const nanoui_adapter = @import("adapters/nanoui.zig");
const shadcn = @import("shadcn");

// Route logs through debug.print so the test framework doesn't treat
// nanoui's internal log.err calls as test failures.
pub const std_options: std.Options = .{ .logFn = logFn };

fn logFn(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime fmt: []const u8, args: anytype) void {
    _ = level;
    _ = scope;
    std.debug.print(fmt ++ "\n", args);
}

const Ctx = struct {
    pub const Badge = shadcn.Badge;
    pub const Button = shadcn.Button;
    pub const Card = shadcn.Card;
    pub const Heading = shadcn.Heading;
    pub const Caption = shadcn.Caption;
    pub const Link = shadcn.Link;
    pub const Section = shadcn.Section;
    pub const Input = shadcn.Input;
    pub const Textarea = shadcn.Textarea;
    pub const Checkbox = shadcn.Checkbox;
    pub const Progress = shadcn.Progress;
    pub const Divider = shadcn.Divider;
    pub const Slider = shadcn.Slider;
    pub const Switch = shadcn.Switch;
    pub const Skeleton = shadcn.Skeleton;

    name: [64]u8 = @splat(0),
    notes: [256]u8 = @splat(0),
    remember: bool = false,
    completion: f32 = 0.42,
    volume: f32 = 0.5,
    notifications: bool = true,
    email: [128]u8 = @splat(0),
};

fn nanouiView(ctx: *Ctx, c: *nanoui.ui.Context) void {
    const A = nanoui_adapter.Adapter(nanoui.ui);
    playground.view(A, c, ctx);
}

test "snapshot: nanoui playground" {
    var ctx: Ctx = .{};
    var t: nanoui.ui.Tester = undefined;
    try t.init(
        std.heap.page_allocator,
        nanoui.ui.View.init(&ctx, nanouiView),
        .{ .width = 700, .height = 700, .scale = 2 },
    );
    defer t.deinit();
    t.settle(2);

    // Ensure docs/screenshots exists
    std.Io.Dir.cwd().createDirPath(std.testing.io, "docs/screenshots") catch {};

    const full = "docs/screenshots/playground-nanoui.png";
    try t.screenshot(full);
    std.debug.print("wrote {s}\n", .{full});

}

const components_demo = @import("components_demo");

const ComponentsCtx = struct {
    pub const Label = shadcn.Label;
    pub const Alert = shadcn.Alert;
    pub const Breadcrumb = shadcn.Breadcrumb;
    pub const Tabs = shadcn.Tabs;
    pub const Pagination = shadcn.Pagination;
    pub const Heading = shadcn.Heading;
    pub const Caption = shadcn.Caption;
    pub const Input = shadcn.Input;

    name: [64]u8 = @splat(0),
    active_tab: usize = 0,
    active_page: usize = 0,
};

fn componentsView(ctx: *ComponentsCtx, c: *nanoui.ui.Context) void {
    const A = nanoui_adapter.Adapter(nanoui.ui);
    components_demo.view(A, c, ctx);
}

test "snapshot: nanoui components_demo" {
    var ctx: ComponentsCtx = .{};
    var t: nanoui.ui.Tester = undefined;
    try t.init(
        std.heap.page_allocator,
        nanoui.ui.View.init(&ctx, componentsView),
        .{ .width = 700, .height = 700, .scale = 2 },
    );
    defer t.deinit();
    t.settle(2);

    const path = "docs/screenshots/components-nanoui.png";
    try t.screenshot(path);
    std.debug.print("wrote {s}\n", .{path});
}
