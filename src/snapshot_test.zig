const std = @import("std");
const nanoui = @import("nanoui");
const playground = @import("views/playground_gen.zig");
const nanoui_adapter = @import("adapters/nanoui.zig");

const Ctx = struct {
    pub const Badge = @import("lib/shadcn.zig").Badge;
    pub const Button = @import("lib/shadcn.zig").Button;
    pub const Card = @import("lib/shadcn.zig").Card;
    pub const Heading = @import("lib/shadcn.zig").Heading;
    pub const Caption = @import("lib/shadcn.zig").Caption;
    pub const Link = @import("lib/shadcn.zig").Link;
    pub const Section = @import("lib/shadcn.zig").Section;
    pub const Input = @import("lib/shadcn.zig").Input;

    name: [64]u8 = @splat(0),
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
