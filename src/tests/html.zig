const std = @import("std");

test {
    _ = @import("../adapters/html.zig");
}

const HtmlDemoCtx = struct {
    show_save: bool = true,
    items: []const []const u8 = &[_][]const u8{ "alpha", "beta" },
    pub fn save(_: *@This()) void {}
};

test "html adapter: demo view renders button and labels" {
    const html = @import("../adapters/html.zig");
    const demo = @import("demo");
    const A = html.Adapter(html.TestWriter);
    var w: html.TestWriter = .{};
    var ctx = HtmlDemoCtx{};
    demo.view(A, &w, &ctx);
    const out = w.output();
    try std.testing.expect(std.mem.indexOf(u8, out, "<button") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, ">Save</button>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "alpha") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "beta") != null);
}

test {
    _ = @import("../adapters/html.zig");
}

test {
    _ = @import("../rt/preprocess.zig");
}
