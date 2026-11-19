//! Fuzz harness smoke test (M1 WP 1.9). The full campaign runs through
//! `zig build fuzz`; this keeps a deterministic slice in the normal suite.

const std = @import("std");
const fuzz = @import("../rt/fuzz.zig");

test "fuzz smoke: generator + mutations preserve front-end invariants" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var failure: ?fuzz.Failure = null;
    const report = try fuzz.run(arena.allocator(), .{ .iterations = 200, .seed = 0x51a7 }, &failure);
    try std.testing.expect(failure == null);
    try std.testing.expectEqual(@as(usize, 200), report.valid_cases);
    try std.testing.expectEqual(@as(usize, 200), report.mutated_cases);
}
