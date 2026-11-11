const std = @import("std");
const zsx = @import("zsx");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zsx_dep = b.dependency("zsx", .{
        .target = target,
        .optimize = optimize,
    });
    // The zsx package root doubles as the tooling API (`zsx.lossless`, ...);
    // build a module from it so runtime code can `@import("zsx")`.
    const zsx_mod = b.createModule(.{
        .root_source_file = zsx_dep.path("zsx.zig"),
        .target = target,
        .optimize = optimize,
    });

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_mod.addImport("zsx", zsx_mod);

    const exe = b.addExecutable(.{ .name = "lossless-demo", .root_module = main_mod });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.has_side_effects = true;
    b.step("run", "Run the lossless demo").dependOn(&run.step);

    const tests = b.addTest(.{ .root_module = main_mod });
    const test_step = b.step("test", "Run lossless demo smoke tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
