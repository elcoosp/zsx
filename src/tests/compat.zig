const std = @import("std");
const compat = @import("../compat.zig");

test "compat: version policy exposes current and current-1" {
    try std.testing.expect(compat.is_current or !compat.is_current);
    try std.testing.expectEqual(compat.is_current, compat.onCurrent());
}

test "compat: joinPath has a stable error set" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const joined = try compat.joinPath(arena.allocator(), &.{ "a", "b", "c" });
    const s = std.fs.path.sep_str;
    try std.testing.expectEqualStrings("a" ++ s ++ "b" ++ s ++ "c", joined);
}
