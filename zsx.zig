//! ZSX build helper.
//!
//! Import from your `build.zig` after adding zsx to `build.zig.zon`:
//!
//!     const zsx = @import("zsx");
//!
//!     pub fn build(b: *std.Build) void {
//!         const target = b.standardTargetOptions(.{});
//!         const optimize = b.standardOptimizeOption(.{});
//!         const app = b.createModule(.{
//!             .root_source_file = b.path("src/main.zig"),
//!             .target = target, .optimize = optimize,
//!         });
//!         const views = zsx.addViews(b, .{
//!             .paths = &.{ "src/views/dashboard.zsx" },
//!             .target = target, .optimize = optimize,
//!         });
//!         for (views) |v| app.addImport(v.name, v.module);
//!         b.installArtifact(b.addExecutable(.{ .name = "app", .root_module = app }));
//!     }

const std = @import("std");

pub const View = struct { name: []const u8, module: *std.Build.Module };

pub const NamedImport = struct { name: []const u8, module: *std.Build.Module };

pub const Options = struct {
    paths: []const []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const NamedImport = &.{},
};

pub fn addViewsLocal(b: *std.Build, opts: Options) []View {
    return addViewsFrom(b, opts, b.path("src/gen.zig"));
}

pub fn addViews(b: *std.Build, opts: Options) []View {
    const zsx_dep = b.dependency("zsx", .{
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    return addViewsFrom(b, opts, zsx_dep.path("src/gen.zig"));
}

fn addViewsFrom(b: *std.Build, opts: Options, gen_path: std.Build.LazyPath) []View {
    const gen_exe = b.addExecutable(.{
        .name = "zsx-gen",
        .root_module = b.createModule(.{
            .root_source_file = gen_path,
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });

    const views = b.allocator.alloc(View, opts.paths.len) catch @panic("OOM");
    for (opts.paths, 0..) |path, idx| {
        const run = b.addRunArtifact(gen_exe);
        run.addArg("--input");
        run.addFileArg(b.path(path));
        run.addArg("--output");
        const out_name = b.fmt("{s}.zig", .{std.fs.path.stem(path)});
        const out_path = run.addOutputFileArg(out_name);
        run.addArg("--src-name");
        run.addArg(path);
        run.addArg("--file-index");
        run.addArg(b.fmt("{d}", .{idx}));

        const mod = b.createModule(.{
            .root_source_file = out_path,
            .target = opts.target,
            .optimize = opts.optimize,
        });
        for (opts.imports) |imp| mod.addImport(imp.name, imp.module);

        views[idx] = .{ .name = std.fs.path.stem(path), .module = mod };
    }
    return views;
}
