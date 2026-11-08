const std = @import("std");
const demo = @import("demo");
const nanoui_adapter = @import("adapters/nanoui.zig");

pub fn main() !void {
    const A = nanoui_adapter.Adapter(nanoui_adapter.StubNanoui);

    const User = struct { name: []const u8 };
    const Ctx = struct {
        user: User,
        show_save: bool = true,
        items: []const []const u8,
        save_called: bool = false,
        pub fn save(self: *@This()) void {
            self.save_called = true;
        }
    };

    var c: nanoui_adapter.StubNanoui.Context = .{};
    var ctx = Ctx{
        .user = .{ .name = "Alice" },
        .items = &[_][]const u8{ "alpha", "beta", "gamma" },
    };

    nanoui_adapter.StubNanoui.resetCounters();
    demo.view(A, &c, &ctx);

    std.debug.print("nanoui rendered {d} buttons, {d} labels, last size {d}, last weight {s}\n", .{
        nanoui_adapter.StubNanoui.buttonsRendered(),
        nanoui_adapter.StubNanoui.labelsRendered(),
        @as(u32, @intFromFloat(nanoui_adapter.StubNanoui.lastTextSize())),
        @tagName(nanoui_adapter.StubNanoui.lastTextWeight()),
    });
    std.debug.print("save handler: {s}\n", .{if (ctx.save_called) "fired" else "not fired"});
}
