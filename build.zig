const std = @import("std");
const zsx = @import("zsx.zig");

pub const addViews = @import("zsx.zig").addViews;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const update_golden = b.option(bool, "update-golden", "Rewrite spec/golden from the current views") orelse false;
    const fuzz_iterations = b.option(usize, "fuzz-iterations", "Iterations for `zig build fuzz`") orelse 20_000;
    const fuzz_seed = b.option(u64, "fuzz-seed", "PRNG seed for `zig build fuzz`") orelse 0x5eed_2a17;

    const zsx_files = zsx.discoverViews(b, "src/views", &.{});

    const shadcn_mod = b.createModule(.{ .root_source_file = b.path("src/lib/shadcn.zig"), .target = target, .optimize = optimize });
    const views = zsx.addViewsLocal(b, .{
        .paths = zsx_files,
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

    // Real backends are opt-in so a normal build never fetches dvui/nanoui.
    const real = b.option(bool, "real", "Build the real DVUI/Nanoui backends (fetches lazy dependencies)") orelse false;

    if (real) {
        const dvui = b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .sdl3 });
        const real_hello_mod = b.createModule(.{ .root_source_file = b.path("src/hello_dvui.zig"), .target = target, .optimize = optimize });
        real_hello_mod.addImport("dvui", dvui.module("dvui_sdl3"));
        real_hello_mod.addImport("sdl-backend", dvui.module("sdl3"));
        real_hello_mod.addImport("shadcn", shadcn_mod);
        for (views) |v| real_hello_mod.addImport(v.name, v.module);
        const real_hello_exe = b.addExecutable(.{ .name = "zsx-hello-dvui", .root_module = real_hello_mod });
        const install_real = b.addInstallArtifact(real_hello_exe, .{});
        b.step("build-app-dvui", "Build DVUI binary (real backend)").dependOn(&install_real.step);
        b.step("build-app", "Alias for build-app-dvui").dependOn(&install_real.step);

        const release_mod = b.createModule(.{ .root_source_file = b.path("src/hello_dvui.zig"), .target = target, .optimize = .ReleaseSafe });
        release_mod.addImport("dvui", dvui.module("dvui_sdl3"));
        release_mod.addImport("sdl-backend", dvui.module("sdl3"));
        release_mod.addImport("shadcn", shadcn_mod);
        for (views) |v| release_mod.addImport(v.name, v.module);
        const install_release = b.addInstallArtifact(b.addExecutable(.{ .name = "zsx-hello-dvui-release", .root_module = release_mod }), .{});
        b.step("build-app-dvui-release", "Build DVUI binary, ReleaseSafe").dependOn(&install_release.step);

        const nanoui = b.dependency("nanoui", .{ .target = target, .optimize = optimize });
        const real_nanoui_mod = b.createModule(.{ .root_source_file = b.path("src/hello_nanoui.zig"), .target = target, .optimize = optimize, .link_libc = true });
        real_nanoui_mod.addImport("nanoui", nanoui.module("nanoui"));
        real_nanoui_mod.addImport("shadcn", shadcn_mod);
        for (views) |v| real_nanoui_mod.addImport(v.name, v.module);
        const real_nanoui_exe = b.addExecutable(.{ .name = "zsx-hello-nanoui", .root_module = real_nanoui_mod });
        const install_real_nanoui = b.addInstallArtifact(real_nanoui_exe, .{});
        b.step("build-app-nanoui", "Build the real nanoui app").dependOn(&install_real_nanoui.step);

        const build_all_step = b.step("build-all", "Build both real binaries");
        build_all_step.dependOn(&install_real.step);
        build_all_step.dependOn(&install_real_nanoui.step);

        const snapshot_mod = b.createModule(.{ .root_source_file = b.path("src/snapshot_test.zig"), .target = target, .optimize = optimize });
        snapshot_mod.addImport("dvui", dvui.module("dvui_sdl3"));
        snapshot_mod.addImport("sdl-backend", dvui.module("sdl3"));
        snapshot_mod.addImport("nanoui", nanoui.module("nanoui"));
        snapshot_mod.addImport("shadcn", shadcn_mod);
        for (views) |v| snapshot_mod.addImport(v.name, v.module);
        const snapshot_run = b.addRunArtifact(b.addTest(.{ .root_module = snapshot_mod }));
        snapshot_run.has_side_effects = true;
        b.step("snapshot", "Generate component screenshots").dependOn(&snapshot_run.step);
    } else {
        const hint = "real backends are opt-in: rerun with -Dreal=true";
        inline for (.{ "build-app-dvui", "build-app", "build-app-dvui-release", "build-app-nanoui", "build-all", "snapshot" }) |name| {
            b.step(name, "Requires -Dreal=true").dependOn(&b.addFail(hint).step);
        }
    }

    // --- M0 tooling ---------------------------------------------------------

    const check_meta_exe = b.addExecutable(.{
        .name = "zsx-check-meta",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/check_meta.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    const run_check_meta = b.addRunArtifact(check_meta_exe);
    run_check_meta.setCwd(b.path("."));
    run_check_meta.addArg("--root");
    run_check_meta.addArg(".");
    b.step("check-meta", "Fail when version/metadata drift").dependOn(&run_check_meta.step);

    const check_docs_exe = b.addExecutable(.{
        .name = "zsx-check-docs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/check_docs.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    const run_check_docs = b.addRunArtifact(check_docs_exe);
    run_check_docs.setCwd(b.path("."));
    run_check_docs.addArg("--root");
    run_check_docs.addArg(".");
    b.step("check-docs", "Check required docs and relative links").dependOn(&run_check_docs.step);

    const preprocess_mod = b.createModule(.{
        .root_source_file = b.path("src/rt/preprocess.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    const checker_mod = b.createModule(.{
        .root_source_file = b.path("src/rt/checker.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    const golden_mod = b.createModule(.{
        .root_source_file = b.path("tools/golden.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    golden_mod.addImport("zsx_preprocess", preprocess_mod);
    const golden_exe = b.addExecutable(.{ .name = "zsx-golden", .root_module = golden_mod });
    const run_golden = b.addRunArtifact(golden_exe);
    run_golden.setCwd(b.path("."));
    run_golden.addArg("--root");
    run_golden.addArg(".");
    if (update_golden) run_golden.addArg("--update");
    for (zsx_files) |p| {
        run_golden.addArg("--view");
        run_golden.addArg(p);
    }
    run_golden.has_side_effects = true;
    b.step("golden", "Diff generated views against spec/golden").dependOn(&run_golden.step);

    const bench_mod = b.createModule(.{
        .root_source_file = b.path("tools/bench.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    bench_mod.addImport("zsx_preprocess", preprocess_mod);
    bench_mod.addImport("zsx_checker", checker_mod);
    const bench_exe = b.addExecutable(.{ .name = "zsx-bench", .root_module = bench_mod });
    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.setCwd(b.path("."));
    run_bench.addArg("--out");
    run_bench.addArg("bench/baseline.json");
    run_bench.has_side_effects = true;
    b.step("bench", "Run the benchmark suite (writes bench/baseline.json)").dependOn(&run_bench.step);

    const run_bench_smoke = b.addRunArtifact(bench_exe);
    run_bench_smoke.setCwd(b.path("."));
    run_bench_smoke.addArg("--smoke");
    run_bench_smoke.has_side_effects = true;
    b.step("bench-smoke", "Fast benchmark sanity check").dependOn(&run_bench_smoke.step);

    const fuzz_mod = b.createModule(.{
        .root_source_file = b.path("src/rt/fuzz.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    const fuzz_exe = b.addExecutable(.{
        .name = "zsx-fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/fuzz.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    fuzz_exe.root_module.addImport("zsx_fuzz", fuzz_mod);
    const run_fuzz = b.addRunArtifact(fuzz_exe);
    run_fuzz.setCwd(b.path("."));
    run_fuzz.addArg("--iterations");
    run_fuzz.addArg(b.fmt("{d}", .{fuzz_iterations}));
    run_fuzz.addArg("--seed");
    run_fuzz.addArg(b.fmt("0x{x}", .{fuzz_seed}));
    run_fuzz.has_side_effects = true;
    b.step("fuzz", "Property/mutation fuzz the front-end").dependOn(&run_fuzz.step);

    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    const cli_exe = b.addExecutable(.{ .name = "zsx", .root_module = cli_mod });
    const install_cli = b.addInstallArtifact(cli_exe, .{});
    b.getInstallStep().dependOn(&install_cli.step);
    b.step("cli", "Build the zsx CLI").dependOn(&install_cli.step);

    const cli_cmd = b.option([]const u8, "cmd", "CLI subcommand for `zig build zsx`") orelse "";
    const cli_extra = b.option([]const u8, "cmd-args", "Extra space-separated CLI args") orelse "";
    const run_cli = b.addRunArtifact(cli_exe);
    if (cli_cmd.len != 0) run_cli.addArg(cli_cmd);
    if (cli_extra.len != 0) {
        var it = std.mem.tokenizeScalar(u8, cli_extra, ' ');
        while (it.next()) |arg| run_cli.addArg(arg);
    }
    run_cli.has_side_effects = true;
    b.step("zsx", "Run the ZSX CLI").dependOn(&run_cli.step);
}
