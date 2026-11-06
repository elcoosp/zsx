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
        .app = "zsx-dashboard",
        .title = "ZSX Component Library",
        .window_init_options = .{
            .keybinds_zoom = true,
            .theme = dvui.Theme.builtin.adwaita_light,
            .color_scheme = .light,
        },
    } },
    .frameFn = frame,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

fn frame() !dvui.App.Result {
    components.view(A, dvui.currentWindow(), &g_ctx);
    return .ok;
}
