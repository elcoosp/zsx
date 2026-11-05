const std = @import("std");

pub const Feature = @import("feature.zig").Feature;
pub const Capabilities = @import("capabilities.zig").Capabilities;
pub const StyleRef = @import("style_ref.zig").StyleRef;
pub const Backend = @import("backend.zig").Backend;

pub const ast = @import("ast.zig");
pub const parse = @import("parser.zig").parse;
pub const style = @import("style.zig");

test "Feature enum" {
    const f: Feature = .background;
    try std.testing.expect(f == .background);
}

test "Capabilities supports" {
    const caps = Capabilities{ .background = true };
    try std.testing.expect(caps.supports(.background));
    try std.testing.expect(!caps.supports(.padding));
}

test "StyleRef defaults" {
    const ref = StyleRef{};
    try std.testing.expect(ref.raw_class == null);
    try std.testing.expect(ref.resolved == null);
}

test {
    _ = @import("style.zig");
}

test {
    _ = @import("backends/dvui.zig");
}

test {
    _ = @import("backends/nanoui.zig");
}
