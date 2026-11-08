const std = @import("std");
const dvui = @import("dvui");
const playground = @import("playground");
const adapter = @import("adapters/dvui.zig");

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

var g_ctx: Ctx = .{};
const A = adapter.Adapter(dvui);

pub const dvui_app: dvui.App = .{
    .config = .{ .options = .{
        .size = .{ .w = 700, .h = 1000 },
        .min_size = .{ .w = 350, .h = 600 },
        .org = "com.example.zsx",
        .app = "zsx-playground",
        .title = "ZSX Playground",
        .window_init_options = .{ .color_scheme = .light },
    } },
    .frameFn = frame,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

fn frame() !dvui.App.Result {
    const win = dvui.currentWindow();
    var theme = dvui.Theme.builtin.adwaita_light;
    theme.dark = false;
    theme.window.fill = .{ .r = 250, .g = 250, .b = 250, .a = 255 };
    theme.fill = .{ .r = 250, .g = 250, .b = 250, .a = 255 };
    theme.control.fill = .{ .r = 240, .g = 240, .b = 240, .a = 255 };
    win.themeSet(theme);

    var bg = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
    defer bg.deinit();

    // Scroll container so content taller than the window remains reachable.
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = true });
    defer scroll.deinit();

    playground.view(A, win, &g_ctx);
    return .ok;
}
