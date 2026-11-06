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
        .window_init_options = .{
            .color_scheme = .light,
            .keybinds_zoom = true,
        },
    } },
    .frameFn = frame,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

fn frame() !dvui.App.Result {
    const win = dvui.currentWindow();
    // Force a light theme — SDL3 backend clears to black, theme provides widget fills
    var theme = dvui.Theme.builtin.adwaita_light;
    theme.dark = false;
    theme.window.fill = .{ .r = 250, .g = 250, .b = 250, .a = 255 };
    theme.fill = .{ .r = 250, .g = 250, .b = 250, .a = 255 };
    theme.control.fill = .{ .r = 240, .g = 240, .b = 240, .a = 255 };
    win.themeSet(theme);

    // Draw a full-window background box FIRST.
    // This covers the SDL3 backend's hardcoded black clear.
    // `.style = .window` pulls `theme.window.fill` (now white).
    var bg = dvui.box(@src(), .{}, .{
        .expand = .both,
        .background = true,
        .style = .window,
    });
    defer bg.deinit();

    components.view(A, win, &g_ctx);
    return .ok;
}
