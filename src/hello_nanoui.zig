const std = @import("std");
const nanoui = @import("nanoui");
const playground = @import("views/playground_gen.zig");
const adapter = @import("adapters/nanoui.zig");

const Ctx = struct {
    pub const Badge = @import("lib/shadcn.zig").Badge;
    pub const Button = @import("lib/shadcn.zig").Button;
    pub const Card = @import("lib/shadcn.zig").Card;
    pub const Heading = @import("lib/shadcn.zig").Heading;
    pub const Caption = @import("lib/shadcn.zig").Caption;
    pub const Link = @import("lib/shadcn.zig").Link;
    pub const Section = @import("lib/shadcn.zig").Section;
    pub const Input = @import("lib/shadcn.zig").Input;
    pub const Textarea = @import("lib/shadcn.zig").Textarea;
    pub const Checkbox = @import("lib/shadcn.zig").Checkbox;
    pub const Progress = @import("lib/shadcn.zig").Progress;
    pub const Divider = @import("lib/shadcn.zig").Divider;
    pub const Slider = @import("lib/shadcn.zig").Slider;
    pub const Switch = @import("lib/shadcn.zig").Switch;
    pub const Skeleton = @import("lib/shadcn.zig").Skeleton;

    name: [64]u8 = @splat(0),
    notes: [256]u8 = @splat(0),
    remember: bool = false,
    completion: f32 = 0.42,
    volume: f32 = 0.5,
    notifications: bool = true,
    email: [128]u8 = @splat(0),
};

const A = adapter.Adapter(nanoui.ui);

fn viewFn(ctx: *Ctx, c: *nanoui.ui.Context) void {
    playground.view(A, c, ctx);
}

pub fn main(init: std.process.Init) !void {
    const app = try nanoui.App.create(init, .{ .name = "zsx-playground" });
    var ctx = Ctx{};
    const view = nanoui.ui.View.init(&ctx, viewFn);
    _ = try app.newWindow(.{
        .title = "ZSX Playground",
        .width = 700,
        .height = 700,
        .content = .{ .view = view },
    });
    try app.run();
}
