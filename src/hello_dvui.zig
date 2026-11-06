const std = @import("std");
const dvui = @import("dvui");
const playground = @import("views/playground_gen.zig");
const adapter = @import("adapters/dvui.zig");

const Ctx = struct {
    pub const Badge = @import("lib/shadcn.zig").Badge;
    pub const Button = @import("lib/shadcn.zig").Button;
    pub const Card = @import("lib/shadcn.zig").Card;
    pub const Heading = @import("lib/shadcn.zig").Heading;
    pub const Caption = @import("lib/shadcn.zig").Caption;
    pub const Link = @import("lib/shadcn.zig").Link;
    pub const Section = @import("lib/shadcn.zig").Section;
    pub const Input = @import("lib/shadcn.zig").Input;
    pub const Textarea = @import("lib/shadcn.zig").Textarea;
    pub const Checkbox = @import("lib/shadcn.zig").Checkbox;

    name: [64]u8 = @splat(0),
    notes: [256]u8 = @splat(0),
    remember: bool = false,
    email: [128]u8 = @splat(0),
};

var g_ctx: Ctx = .{};
const A = adapter.Adapter(dvui);

pub const dvui_app: dvui.App = .{
    .config = .{ .options = .{
        .size = .{ .w = 700, .h = 700 },
        .min_size = .{ .w = 350, .h = 300 },
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

    playground.view(A, win, &g_ctx);
    return .ok;
}
