const std = @import("std");
const zsx = @import("zsx.zig");

pub const addViews = @import("zsx.zig").addViews;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zsx_files = [_][]const u8{
        "src/views/demo.zsx",
        "src/views/component_demo.zsx",
        "src/views/shadcn_demo.zsx",
        "src/views/shadcn_lib_demo.zsx",
        "src/views/onclick_demo.zsx",
        "src/views/struct_loop_demo.zsx",
        "src/views/card_if_demo.zsx",
        "src/views/else_if_demo.zsx",
        "src/views/fragment_demo.zsx",
        "src/views/class_override_demo.zsx",
        "src/views/nested_card_demo.zsx",
        "src/views/dashboard.zsx",
        "src/views/input_demo.zsx",
        "src/views/playground.zsx",
        "src/views/component_lib_demo.zsx",
        "src/views/extended_styles_demo.zsx",
        "src/views/path_demo.zsx",
        "src/views/switch_demo.zsx",
        "src/views/slots_demo.zsx",
    };

    const shadcn_mod = b.createModule(.{ .root_source_file = b.path("src/lib/shadcn.zig"), .target = target, .optimize = optimize });
    const views = zsx.addViewsLocal(b, .{
        .paths = &zsx_files,
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "shadcn", .module = shadcn_mod }},
    });


    const test_mod = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    test_mod.addImport("shadcn", shadcn_mod);
    for (views) |v| test_mod.addImport(v.name, v.module);
    const rt_parser_test = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/rt/parser.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = test_mod })).step);
    test_step.dependOn(&b.addRunArtifact(rt_parser_test).step);

    const hello_mod = b.createModule(.{ .root_source_file = b.path("src/hello.zig"), .target = target, .optimize = optimize });
    hello_mod.addImport("shadcn", shadcn_mod);
    for (views) |v| hello_mod.addImport(v.name, v.module);
    const hello_run = b.addRunArtifact(b.addExecutable(.{ .name = "zsx-hello", .root_module = hello_mod }));
    hello_run.has_side_effects = true;
    b.step("example", "Run the hello example").dependOn(&hello_run.step);

    const nanoui_hello_mod = b.createModule(.{ .root_source_file = b.path("src/nanoui_hello.zig"), .target = target, .optimize = optimize });
    nanoui_hello_mod.addImport("shadcn", shadcn_mod);
    for (views) |v| nanoui_hello_mod.addImport(v.name, v.module);
    const nanoui_hello_run = b.addRunArtifact(b.addExecutable(.{ .name = "zsx-nanoui-hello", .root_module = nanoui_hello_mod }));
    nanoui_hello_run.has_side_effects = true;
    b.step("example-nanoui", "Run the nanoui example").dependOn(&nanoui_hello_run.step);

    const dvui_dep = b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .sdl3 });

    const real_hello_mod = b.createModule(.{ .root_source_file = b.path("src/hello_dvui.zig"), .target = target, .optimize = optimize });
    real_hello_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    real_hello_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));
    real_hello_mod.addImport("shadcn", shadcn_mod);
    for (views) |v| real_hello_mod.addImport(v.name, v.module);
    const real_hello_exe = b.addExecutable(.{ .name = "zsx-hello-dvui", .root_module = real_hello_mod });
    const install_real = b.addInstallArtifact(real_hello_exe, .{});
    b.getInstallStep().dependOn(&install_real.step);
    b.step("build-app-dvui", "Build DVUI binary (real backend)").dependOn(&install_real.step);
    b.step("build-app", "Alias for build-app-dvui").dependOn(&install_real.step);

    const nanoui_dep = b.dependency("nanoui", .{ .target = target, .optimize = optimize });
    const real_nanoui_mod = b.createModule(.{ .root_source_file = b.path("src/hello_nanoui.zig"), .target = target, .optimize = optimize, .link_libc = true });
    real_nanoui_mod.addImport("nanoui", nanoui_dep.module("nanoui"));
    real_nanoui_mod.addImport("shadcn", shadcn_mod);
    for (views) |v| real_nanoui_mod.addImport(v.name, v.module);
    const real_nanoui_exe = b.addExecutable(.{ .name = "zsx-hello-nanoui", .root_module = real_nanoui_mod });
    const install_real_nanoui = b.addInstallArtifact(real_nanoui_exe, .{});
    b.getInstallStep().dependOn(&install_real_nanoui.step);
    b.step("build-app-nanoui", "Build the real nanoui app").dependOn(&install_real_nanoui.step);
    const build_all_step = b.step("build-all", "Build both real binaries");
    build_all_step.dependOn(&install_real.step);
    build_all_step.dependOn(&install_real_nanoui.step);

    const snapshot_mod = b.createModule(.{ .root_source_file = b.path("src/snapshot_test.zig"), .target = target, .optimize = optimize });
    snapshot_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    snapshot_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));
    snapshot_mod.addImport("nanoui", nanoui_dep.module("nanoui"));
    snapshot_mod.addImport("shadcn", shadcn_mod);
    for (views) |v| snapshot_mod.addImport(v.name, v.module);
    const snapshot_run = b.addRunArtifact(b.addTest(.{ .root_module = snapshot_mod }));
    snapshot_run.has_side_effects = true;
    b.step("snapshot", "Generate component screenshots").dependOn(&snapshot_run.step);

    const release_mod = b.createModule(.{ .root_source_file = b.path("src/hello_dvui.zig"), .target = target, .optimize = .ReleaseSafe });
    release_mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    release_mod.addImport("sdl-backend", dvui_dep.module("sdl3"));
    release_mod.addImport("shadcn", shadcn_mod);
    for (views) |v| release_mod.addImport(v.name, v.module);
    const install_release = b.addInstallArtifact(b.addExecutable(.{ .name = "zsx-hello-dvui-release", .root_module = release_mod }), .{});
    b.step("build-app-dvui-release", "Build DVUI binary, ReleaseSafe").dependOn(&install_release.step);
}
