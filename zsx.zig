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
//!             .dir = "src/views",          // discover every *.zsx
//!             .target = target, .optimize = optimize,
//!         });
//!         for (views) |v| app.addImport(v.name, v.module);
//!         b.installArtifact(b.addExecutable(.{ .name = "app", .root_module = app }));
//!     }

const std = @import("std");

pub const View = struct { name: []const u8, module: *std.Build.Module };

pub const NamedImport = struct { name: []const u8, module: *std.Build.Module };

pub const Options = struct {
    /// Explicit view paths. Combine with `dir` if needed; both are merged.
    paths: []const []const u8 = &.{},
    /// Directory scanned for `*.zsx` files at configure time (non-recursive).
    /// Adding a view then needs no `build.zig` edit (WP 2.10).
    dir: ?[]const u8 = null,
    /// File names (not paths) to skip when scanning `dir`.
    exclude: []const []const u8 = &.{},
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const NamedImport = &.{},
};

// --- Tooling front-end (M1) ---------------------------------------------
//
// The `zsx` CLI ships the same seam, but consumers can call it directly:
// validate `.zsx` sources in tests, editor plugins, or codegen pipelines
// without spawning a process.

/// Structured diagnostics: stable `ZSX0xxx` codes, severities, byte spans,
/// and the byte-offset → line/col index they render against.
pub const diag = @import("src/rt/diag.zig");

/// Tolerant markup tokenizer: never fails, keeps byte offsets, classifies
/// `{if}`/`{:else}`/`{/if}` control flow. Shared front-end for the checker
/// and the formatter.
pub const scan = @import("src/rt/scan.zig");

/// Structural checker: balanced tags, matched control flow, `{:else}`/`{:case}`
/// placement, unknown-class and legacy-alias warnings. The native
/// implementation behind `zsx check`.
pub const checker = @import("src/rt/checker.zig");

/// Native formatter for `zsx!{ }` markup: idempotent, Zig outside blocks
/// byte-exact. The implementation behind `zsx fmt`.
pub const fmt = checker.fmt;

/// Codemod behind `zsx migrate`: rewrites legacy `on_click=` to
/// `on:click=` and `{endif}`/`{endfor}`/`{endswitch}` to the current closers,
/// leaving the Zig side and untouched markup byte-exact.
pub const migrate = @import("src/rt/migrate.zig");

/// Static compile-cost analyzer behind `zsx check --explain-cost`: counts
/// markup elements/components/attrs, nesting, control flow and
/// `@setEvalBranchQuota` occurrences, and returns a deterministic score.
pub const cost = @import("src/rt/cost.zig");

/// Code-frame renderer: `render.Renderer.init(a, source)` once per file, then
/// `renderer.render(d, .{})` per diagnostic produces the header, the optional
/// `  help:` line and the annotated source snippet with a caret span. The
/// implementation behind `zsx check` output.
pub const render = checker.render;

/// Lossless front-end for `.zsx` sources (spikes S1 + S2): one string-, char-
/// and comment-aware pass partitions a file into typed byte-exact segments
/// (`zig_text`, `string`, `char_literal`, `line_comment`, `block_comment`,
/// `zsx_block`) and `Document.render` re-emits the source byte-for-byte.
/// This is the seam the future CST parser (RFC-0001) builds on, and the one
/// block scanner behind `preprocess`, `checker` and `fmt`.
///
///     const doc = try zsx.lossless.Document.init(arena, source);
///     for (doc.blocks) |blk| {
///         std.debug.print("{s}\n", .{doc.markup(blk)});
///     }
///     try std.testing.expectEqualStrings(source, try doc.render(arena));
pub const lossless = @import("src/rt/lossless.zig");

/// Check a `.zsx` source in one call:
///
///     const zsx = @import("zsx");
///
///     var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
///     defer arena.deinit();
///     var list = zsx.diag.List.init(arena.allocator());
///     try zsx.checker.checkSource(
///         arena.allocator(),
///         source,
///         "src/views/home.zsx",
///         .{},
///         &list,
///     );
///     if (list.hasErrors()) return error.InvalidZsx;
pub fn checkSource(a: std.mem.Allocator, source: []const u8, src_name: []const u8, opts: checker.Options, list: *diag.List) !void {
    return checker.checkSource(a, source, src_name, opts, list);
}

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

/// Scan `dir` for `*.zsx` files, excluding names in `exclude`, sorted by path
/// for a deterministic module/file-index mapping. Intended both for
/// `Options.dir` and for consumers that need the same list elsewhere (e.g. to
/// feed golden tests).
pub fn discoverViews(b: *std.Build, dir: []const u8, exclude: []const []const u8) []const []const u8 {
    // Re-run the configure phase when a file is added/removed in `dir`, so a
    // new view needs no `build.zig` edit (WP 2.10).
    b.dependOnDirectoryMetadata(b.path(dir));
    var list = std.array_list.Managed([]const u8).init(b.allocator);
    const io = b.graph.io;
    const d = std.Io.Dir.cwd().openDir(io, dir, .{ .iterate = true }) catch |e| {
        std.debug.print("zsx: cannot scan view dir '{s}': {any}\n", .{ dir, e });
        @panic("zsx: view dir not found");
    };
    defer d.close(io);
    var it = d.iterate();
    while (it.next(io) catch |e| {
        std.debug.print("zsx: cannot scan view dir '{s}': {any}\n", .{ dir, e });
        @panic("zsx: view dir scan failed");
    }) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zsx")) continue;
        var skip = false;
        for (exclude) |ex| {
            if (std.mem.eql(u8, ex, entry.name)) skip = true;
        }
        if (skip) continue;
        const full = std.fs.path.join(b.allocator, &.{ dir, entry.name }) catch @panic("OOM");
        list.append(full) catch @panic("OOM");
    }
    std.mem.sort([]const u8, list.items, {}, struct {
        fn lt(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.lt);
    return list.toOwnedSlice() catch @panic("OOM");
}

fn resolvePaths(b: *std.Build, opts: Options) []const []const u8 {
    var list = std.array_list.Managed([]const u8).init(b.allocator);
    list.appendSlice(opts.paths) catch @panic("OOM");
    if (opts.dir) |dir| {
        for (discoverViews(b, dir, opts.exclude)) |p| list.append(p) catch @panic("OOM");
    }
    if (list.items.len == 0) {
        std.debug.print("zsx: addViews needs `paths` and/or `dir`\n", .{});
        @panic("zsx: no views configured");
    }
    std.mem.sort([]const u8, list.items, {}, struct {
        fn lt(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.lt);
    return list.toOwnedSlice() catch @panic("OOM");
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

    const paths = resolvePaths(b, opts);
    const views = b.allocator.alloc(View, paths.len) catch @panic("OOM");
    for (paths, 0..) |path, idx| {
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
