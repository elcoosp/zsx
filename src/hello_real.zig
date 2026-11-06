const std = @import("std");
const dvui = @import("dvui");
const dashboard = @import("views/dashboard_gen.zig");
const adapter = @import("adapters/dvui.zig");

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
    refresh_called: bool = false,

    pub fn refresh(self: *@This()) void {
        self.refresh_called = true;
    }
};

var g_ctx: Ctx = .{};
const A = adapter.Adapter(dvui);

pub const dvui_app: dvui.App = .{
    .config = .{ .options = .{
        .size = .{ .w = 700, .h = 500 },
        .min_size = .{ .w = 350, .h = 250 },
        .org = "com.example.zsx",
        .app = "zsx-dashboard",
        .title = "ZSX Dashboard",
    } },
    .frameFn = frame,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

fn frame() !dvui.App.Result {
    dashboard.view(A, dvui.currentWindow(), &g_ctx);
    return .ok;
}
