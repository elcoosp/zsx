const std = @import("std");
const nanoui = @import("nanoui");
const playground = @import("playground");
const adapter = @import("adapters/nanoui.zig");

const Ctx = struct {
    pub const Badge = @import("shadcn").Badge;
    pub const Button = @import("shadcn").Button;
    pub const Card = @import("shadcn").Card;
    pub const Heading = @import("shadcn").Heading;
    pub const Caption = @import("shadcn").Caption;
    pub const Link = @import("shadcn").Link;
    pub const Section = @import("shadcn").Section;
    pub const Input = @import("shadcn").Input;
    pub const Textarea = @import("shadcn").Textarea;
    pub const Checkbox = @import("shadcn").Checkbox;
    pub const Progress = @import("shadcn").Progress;
    pub const Divider = @import("shadcn").Divider;
    pub const Slider = @import("shadcn").Slider;
    pub const Switch = @import("shadcn").Switch;
    pub const Skeleton = @import("shadcn").Skeleton;

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
