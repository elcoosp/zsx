const std = @import("std");
const zsx = @import("zsx");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shadcn = b.createModule(.{
        .root_source_file = b.path("src/shadcn.zig"),
        .target = target,
        .optimize = optimize,
    });

    const views = zsx.addViews(b, .{
        .paths = &.{"src/views/todo.zsx"},
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "shadcn", .module = shadcn }},
    });

    const app = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    app.addImport("shadcn", shadcn);
    for (views) |v| app.addImport(v.name, v.module);

    const exe = b.addExecutable(.{ .name = "todo", .root_module = app });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.has_side_effects = true;
    const run_step = b.step("run", "Run the todo demo (stub adapter)");
    run_step.dependOn(&run.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("shadcn", shadcn);
    for (views) |v| test_mod.addImport(v.name, v.module);
    const tests = b.addTest(.{ .root_module = test_mod });
    const test_step = b.step("test", "Run todo tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
