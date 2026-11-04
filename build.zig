const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zsx_mod = b.addModule("zsx", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run tests");
    const tests = b.addTest(.{
        .root_module = zsx_mod,
    });
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
