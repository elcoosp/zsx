const std = @import("std");
const stub = @import("stub.zig");
const home = @import("home");
const about = @import("about");

const Ctx = struct {
    show_details: bool = true,
};

pub fn main() !void {
    const A = stub.Adapter;
    var c: stub.Context = .{};
    var ctx = Ctx{};

    std.debug.print("=== home ===\n", .{});
    stub.resetCounters();
    home.view(A, &c, &ctx);
    std.debug.print("home: {d} labels, {d} buttons\n\n", .{ stub.labelsRendered(), stub.buttonsRendered() });

    std.debug.print("=== about (show_details=true) ===\n", .{});
    stub.resetCounters();
    about.view(A, &c, &ctx);
    std.debug.print("about: {d} labels, {d} buttons\n\n", .{ stub.labelsRendered(), stub.buttonsRendered() });

    std.debug.print("=== about (show_details=false) ===\n", .{});
    ctx.show_details = false;
    stub.resetCounters();
    about.view(A, &c, &ctx);
    std.debug.print("about: {d} labels, {d} buttons\n", .{ stub.labelsRendered(), stub.buttonsRendered() });
}

test "home renders 2 labels + 2 buttons" {
    const A = stub.Adapter;
    var c: stub.Context = .{};
    var ctx = Ctx{};
    stub.resetCounters();
    home.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), stub.labelsRendered());
    try std.testing.expectEqual(@as(usize, 2), stub.buttonsRendered());
}

test "about show_details=true renders 2 labels + 1 button" {
    const A = stub.Adapter;
    var c: stub.Context = .{};
    var ctx = Ctx{ .show_details = true };
    stub.resetCounters();
    about.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), stub.labelsRendered());
    try std.testing.expectEqual(@as(usize, 1), stub.buttonsRendered());
}

test "about show_details=false renders 2 labels + 1 button" {
    const A = stub.Adapter;
    var c: stub.Context = .{};
    var ctx = Ctx{ .show_details = false };
    stub.resetCounters();
    about.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), stub.labelsRendered());
    try std.testing.expectEqual(@as(usize, 1), stub.buttonsRendered());
}
