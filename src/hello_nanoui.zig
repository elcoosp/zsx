const std = @import("std");
const nanoui = @import("nanoui");
const dashboard = @import("views/dashboard_gen.zig");
const adapter = @import("adapters/nanoui.zig");

const Task = struct {
    name: []const u8,
    urgent: bool = false,
    pending: bool = false,
};

const Ctx = struct {
    pub const Badge = @import("lib/shadcn.zig").Badge;
    pub const Button = @import("lib/shadcn.zig").Button;

    user_role: []const u8 = "admin",
    error_message: []const u8 = "",
    items: []const Task = &[_]Task{
        .{ .name = "write docs", .pending = true },
        .{ .name = "fix bug", .urgent = true },
        .{ .name = "ship it" },
    },
    refresh_count: usize = 0,
    count_buf: [16]u8 = undefined,
    count_str: []const u8 = "",

    pub fn refresh(self: *@This()) void {
        self.refresh_count += 1;
        self.count_str = std.fmt.bufPrint(&self.count_buf, "{d}", .{self.refresh_count}) catch "?";
    }
};

const A = adapter.Adapter(nanoui.ui);

fn viewFn(ctx: *Ctx, c: *nanoui.ui.Context) void {
    dashboard.view(A, c, ctx);
}

pub fn main(init: std.process.Init) !void {
    const app = try nanoui.App.create(init, .{ .name = "zsx-dashboard" });

    var ctx = Ctx{};
    const view = nanoui.ui.View.init(&ctx, viewFn);

    _ = try app.newWindow(.{
        .title = "ZSX Dashboard",
        .width = 700,
        .height = 500,
        .content = .{ .view = view },
    });

    try app.run();
}
