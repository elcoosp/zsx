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
var g_diag_count: u32 = 0;
const A = adapter.Adapter(dvui);

fn makeLightTheme() dvui.Theme {
    var theme = dvui.Theme.builtin.adwaita_light;
    theme.dark = false;
    const white = dvui.Color{ .r = 250, .g = 250, .b = 250, .a = 255 };
    const off_white = dvui.Color{ .r = 240, .g = 240, .b = 240, .a = 255 };
    const blue = dvui.Color{ .r = 59, .g = 130, .b = 246, .a = 255 };
    // Top-level `fill` IS the content style fill (no `content` field exists)
    theme.fill = white;
    theme.window.fill = white;
    theme.control.fill = off_white;
    theme.highlight.fill = blue;
    return theme;
}

fn applyLightTheme(win: *dvui.Window) void {
    win.themeSet(makeLightTheme());
}

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
    .initFn = appInit,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

fn appInit(win: *dvui.Window) !void {
    applyLightTheme(win);
    if (g_diag_count < 1) {
        std.debug.print("[DIAG] appInit: dark={} window.fill.isSet={}\n", .{
            win.theme.dark, win.theme.window.fill != null,
        });
        g_diag_count += 1;
    }
}

fn frame() !dvui.App.Result {
    const win = dvui.currentWindow();
    if (win.theme.dark or win.theme.window.fill == null) {
        applyLightTheme(win);
        if (g_diag_count < 3) {
            std.debug.print("[DIAG] frame force: dark={} window.fill.isSet={}\n", .{
                win.theme.dark, win.theme.window.fill != null,
            });
            g_diag_count += 1;
        }
    }
    components.view(A, win, &g_ctx);
    return .ok;
}
