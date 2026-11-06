const std = @import("std");
const dvui = @import("dvui");
const components = @import("views/component_lib_demo_gen.zig");
const adapter = @import("adapters/dvui.zig");

const Ctx = struct {
    pub const Heading = @import("lib/shadcn.zig").Heading;
    pub const Caption = @import("lib/shadcn.zig").Caption;
    pub const Link = @import("lib/shadcn.zig").Link;
    pub const Section = @import("lib/shadcn.zig").Section;
};

var g_ctx: Ctx = .{};
const A = adapter.Adapter(dvui);

pub const dvui_app: dvui.App = .{
    .config = .{ .options = .{
        .size = .{ .w = 700, .h = 500 },
        .min_size = .{ .w = 350, .h = 250 },
        .org = "com.example.zsx",
        .app = "zsx-component-lib",
        .title = "ZSX Component Library",
    } },
    .frameFn = frame,
    .initFn = appInit,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

fn appInit(win: *dvui.Window) !void {
    win.themeSet(dvui.Theme.builtin.adwaita_light);
}

fn frame() !dvui.App.Result {
    const win = dvui.currentWindow();
    // Force light theme every frame — dvui re-queries system preference during begin()
    if (win.theme.dark) {
        win.themeSet(dvui.Theme.builtin.adwaita_light);
    }
    components.view(A, win, &g_ctx);
    return .ok;
}
