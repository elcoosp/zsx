const std = @import("std");
const nanoui = @import("nanoui");
const playground = @import("playground");
const nanoui_adapter = @import("adapters/nanoui.zig");

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
    try t.screenshot("/tmp/playground-nanoui.png");
    std.debug.print("wrote /tmp/playground-nanoui.png\n", .{});
}
