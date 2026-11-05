const std = @import("std");

pub const Feature = @import("feature.zig").Feature;
pub const Capabilities = @import("capabilities.zig").Capabilities;
pub const StyleRef = @import("style_ref.zig").StyleRef;
pub const Backend = @import("backend.zig").Backend;

pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const style = @import("style.zig");

test {
    _ = @import("style.zig");
}

test {
    _ = @import("adapters/dvui.zig");
}

test {
    _ = @import("views/demo_gen.zig");
}

const User = struct { name: []const u8 };
const Ctx = struct {
    user: User,
    show_save: bool = true,
    save_called: bool = false,
    pub fn save(self: *@This()) void {
        self.save_called = true;
    }
};

test "demo_gen with show_save=true renders button" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = Ctx{ .user = .{ .name = "Alice" }, .show_save = true };
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "demo_gen with show_save=false skips button" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = Ctx{ .user = .{ .name = "Bob" }, .show_save = false };
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
    try std.testing.expectEqual(@as(usize, 0), dvui_adapter.StubDvui.buttonsRendered());
}
