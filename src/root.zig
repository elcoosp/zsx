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

test "demo_gen renders against stub dvui" {
    const dvui_adapter = @import("adapters/dvui.zig");
    const demo = @import("views/demo_gen.zig");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    const User = struct { name: []const u8 };
    const Ctx = struct {
        user: User,
        save_called: bool = false,
        pub fn save(self: *@This()) void {
            self.save_called = true;
        }
    };
    var ctx = Ctx{ .user = .{ .name = "Alice" } };
    demo.view(A, &c, &ctx);
    try std.testing.expect(!ctx.save_called);
}
