const std = @import("std");
const dvui = @import("dvui");
const nanoui = @import("nanoui");
const demo = @import("views/component_lib_demo_gen.zig");
const dvui_adapter = @import("adapters/dvui.zig");
const nanoui_adapter = @import("adapters/nanoui.zig");

const Ctx = struct {
    pub const Heading = @import("lib/shadcn.zig").Heading;
    pub const Caption = @import("lib/shadcn.zig").Caption;
    pub const Link = @import("lib/shadcn.zig").Link;
    pub const Section = @import("lib/shadcn.zig").Section;
};

var g_ctx: Ctx = .{};

fn nanouiView(ctx: *Ctx, c: *nanoui.ui.Context) void {
    const A = nanoui_adapter.Adapter(nanoui.ui);
    demo.view(A, c, ctx);
}

fn dvuiFrame() !dvui.App.Result {
    const A = dvui_adapter.Adapter(dvui);
    demo.view(A, dvui.currentWindow(), &g_ctx);
    return .ok;
}

test "snapshot: nanoui component library" {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    var ctx: Ctx = .{};
    var t: nanoui.ui.Tester = undefined;
    try t.init(
        gpa,
        nanoui.ui.View.init(&ctx, nanouiView),
        .{ .width = 700, .height = 500, .scale = 2 },
    );
    defer t.deinit();
    t.settle(2);
    try t.screenshot("/tmp/components-nanoui.png");
    std.debug.print("wrote /tmp/components-nanoui.png\n", .{});
}

test "snapshot: dvui component library" {
    var t = try dvui.testing.init(.{ .image_dir = "/tmp", });
    defer t.deinit();
    try t.saveImage(dvuiFrame, null, "/tmp/components-dvui.png");
    std.debug.print("wrote /tmp/components-dvui.png\n", .{});
}
