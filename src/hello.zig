const std = @import("std");
const demo = @import("demo");
const dvui_adapter = @import("adapters/dvui.zig");

pub fn main() !void {
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);

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

    var c: dvui_adapter.StubDvui.Context = .{};
    var ctx = Ctx{
        .user = .{ .name = "Alice" },
        .items = &[_][]const u8{ "alpha", "beta", "gamma" },
    };

    dvui_adapter.StubDvui.resetCounters();
    demo.view(A, &c, &ctx);

    std.debug.print("rendered {d} buttons, {d} labels\n", .{
        dvui_adapter.StubDvui.buttonsRendered(),
        dvui_adapter.StubDvui.labelsRendered(),
    });
    if (ctx.save_called) {
        std.debug.print("save handler fired\n", .{});
    } else {
        std.debug.print("save handler not fired\n", .{});
    }
}
