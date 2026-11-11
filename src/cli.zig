//! `zsx` CLI — fully native since M1/M2.
//!
//! `check` runs the structural checker (`src/rt/checker.zig`) over the
//! tolerant scanner (`src/rt/scan.zig`) and reports `diag.zig` diagnostics;
//! `fmt` reformats markup through `src/rt/fmt.zig`. Neither shells out to
//! Python any more — the scripts under `scripts/` are deprecated and unused
//! by the CLI.
//!
//! Exit codes (parity with the deprecated Python tools):
//! - `check`: 0 = clean or warnings only, 1 = at least one error,
//!   2 = a file could not be read or the arguments were invalid;
//! - `fmt`: 0 = everything formatted (or written), 1 = `--check` found files
//!   that need formatting, 2 = read/argument failure.

const std = @import("std");
const diag = @import("rt/diag.zig");
const checker = @import("rt/checker.zig");
const fmt = checker.fmt;

const max_file_bytes = 10 * 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    const dir = std.Io.Dir.cwd();

    if (args.len < 2) {
        printHelp();
        return error.MissingCommand;
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "version")) {
        const version = dir.readFileAlloc(io, "VERSION", a, .limited(64)) catch "unknown\n";
        try std.Io.File.stdout().writeStreamingAll(io, std.mem.trim(u8, version, " \t\r\n"));
        try std.Io.File.stdout().writeStreamingAll(io, "\n");
        return;
    }
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        printHelp();
        return;
    }
    if (std.mem.eql(u8, cmd, "fmt")) {
        return runFmt(init, args[2..]);
    }
    if (std.mem.eql(u8, cmd, "check")) {
        return runCheck(init, args[2..]);
    }
    std.debug.print("zsx: unknown command '{s}'\n", .{cmd});
    printHelp();
    return error.UnknownCommand;
}

fn printHelp() void {
    std.debug.print(
        \\usage: zsx <command> [options]
        \\
        \\commands:
        \\  fmt [--check|--write] [paths...]   format .zsx markup (native; default = dry run)
        \\  check [paths...]                   validate .zsx structure (native)
        \\                                     --no-class-check skips unknown-class warnings
        \\                                     --format json prints machine-readable
        \\                                     diagnostics (stdout) instead of code frames
        \\  version                            print the ZSX version
        \\
    , .{});
}

/// Native `zsx fmt`: reformat markup inside `zsx!{ }` blocks. Default is a
/// dry run listing files that would change; `--write` applies; `--check`
/// exits 1 when anything needs formatting (CI-friendly).
fn runFmt(init: std.process.Init, rest: []const []const u8) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const dir = std.Io.Dir.cwd();

    var check_mode = false;
    var write_mode = false;
    var paths = std.array_list.Managed([]const u8).init(a);
    for (rest) |arg| {
        if (std.mem.eql(u8, arg, "--check")) {
            check_mode = true;
        } else if (std.mem.eql(u8, arg, "--write")) {
            write_mode = true;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            std.debug.print("zsx fmt: unknown flag '{s}'\n", .{arg});
            std.process.exit(2);
        } else {
            try paths.append(arg);
        }
    }

    if (paths.items.len == 0) {
        try collectZsxFiles(a, io, dir, &paths);
        std.mem.sort([]const u8, paths.items, {}, lessThanStr);
    }
    if (paths.items.len == 0) {
        try stdout(io, "zsx fmt: no .zsx files found\n");
        return;
    }

    var needs_format = std.array_list.Managed([]const u8).init(a);
    var io_errors: usize = 0;
    for (paths.items) |path| {
        const src = dir.readFileAlloc(io, path, a, .limited(max_file_bytes)) catch |e| {
            const line = try std.fmt.allocPrint(a, "zsx fmt: {s}: {s}\n", .{ path, @errorName(e) });
            try stderr(io, line);
            io_errors += 1;
            continue;
        };
        const formatted = fmt.formatSource(a, src, .{}) catch |e| {
            const line = try std.fmt.allocPrint(a, "zsx fmt: {s}: {s}\n", .{ path, @errorName(e) });
            try stderr(io, line);
            io_errors += 1;
            continue;
        };
        if (std.mem.eql(u8, formatted, src)) continue;
        try needs_format.append(path);
        if (write_mode) {
            const f = dir.createFile(io, path, .{ .truncate = true }) catch |e| {
                const line = try std.fmt.allocPrint(a, "zsx fmt: {s}: {s}\n", .{ path, @errorName(e) });
                try stderr(io, line);
                io_errors += 1;
                continue;
            };
            defer f.close(io);
            try f.writeStreamingAll(io, formatted);
        }
    }

    if (io_errors != 0) {
        const line = try std.fmt.allocPrint(a, "zsx fmt: {d} file(s) failed\n", .{io_errors});
        try stderr(io, line);
        std.process.exit(2);
    }

    if (check_mode) {
        for (needs_format.items) |p| {
            const line = try std.fmt.allocPrint(a, "would format: {s}\n", .{p});
            try stdout(io, line);
        }
        if (needs_format.items.len != 0) std.process.exit(1);
        try stdout(io, "all formatted\n");
        return;
    }

    if (write_mode) {
        for (needs_format.items) |p| {
            const line = try std.fmt.allocPrint(a, "formatted: {s}\n", .{p});
            try stdout(io, line);
        }
        if (needs_format.items.len == 0) try stdout(io, "all formatted\n");
        return;
    }

    // Dry run (default).
    for (needs_format.items) |p| {
        const line = try std.fmt.allocPrint(a, "would format: {s}\n", .{p});
        try stdout(io, line);
    }
    if (needs_format.items.len != 0) {
        const line = try std.fmt.allocPrint(a, "\n{d} file(s) need formatting. Run with --write to apply.\n", .{needs_format.items.len});
        try stdout(io, line);
        return;
    }
    try stdout(io, "all formatted\n");
}

/// Native `zsx check`: validate `.zsx` files without compiling.
///
/// `--format json` switches the presentation from human code frames (stderr)
/// to one compact JSON document on stdout (`diag.List.toJson`): stable
/// `ZSX0xxx` codes, names, severities, line/col and byte spans per diagnostic.
/// Exit codes are presentation-independent: 0 = clean or warnings only,
/// 1 = at least one error, 2 = a file could not be read or arguments were
/// invalid — the same contract in both modes, so CI wrappers can keep their
/// existing handling.
fn runCheck(init: std.process.Init, rest: []const []const u8) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const dir = std.Io.Dir.cwd();

    var opts: checker.Options = .{};
    var json_format = false;
    var paths = std.array_list.Managed([]const u8).init(a);
    var i: usize = 0;
    while (i < rest.len) : (i += 1) {
        const arg = rest[i];
        if (std.mem.eql(u8, arg, "--no-class-check")) {
            opts.check_classes = false;
        } else if (std.mem.eql(u8, arg, "--format")) {
            // Value form: `--format json`. A missing or unknown format is an
            // argument error (exit 2), matching the unreadable-file contract.
            i += 1;
            if (i >= rest.len) {
                std.debug.print("zsx check: --format requires a value (json)\n", .{});
                std.process.exit(2);
            }
            if (!std.mem.eql(u8, rest[i], "json")) {
                std.debug.print("zsx check: unknown format '{s}' (only 'json' is supported)\n", .{rest[i]});
                std.process.exit(2);
            }
            json_format = true;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            std.debug.print("zsx check: unknown flag '{s}'\n", .{arg});
            std.process.exit(2);
        } else {
            try paths.append(arg);
        }
    }

    // No paths given: walk the current directory like the Python tool did,
    // skipping caches, build output and VCS internals.
    if (paths.items.len == 0) {
        try collectZsxFiles(a, io, dir, &paths);
        std.mem.sort([]const u8, paths.items, {}, lessThanStr);
    }

    if (paths.items.len == 0) {
        try stderr(io, "zsx check: no .zsx files found\n");
        return;
    }

    var error_total: usize = 0;
    var warning_total: usize = 0;
    var io_errors: usize = 0;
    // One list across all files: diagnostics carry their own `.file`, so the
    // JSON document is a single, self-contained report; text mode still
    // renders per file, slicing the list at the boundaries below.
    var combined = diag.List.init(a);
    for (paths.items) |path| {
        const src = dir.readFileAlloc(io, path, a, .limited(max_file_bytes)) catch |e| {
            const line = try std.fmt.allocPrint(a, "zsx check: cannot read {s}: {s}\n", .{ path, @errorName(e) });
            try stderr(io, line);
            io_errors += 1;
            continue;
        };
        const first = combined.count();
        try checker.checkSource(a, src, path, opts, &combined);
        // Render with code frames: one Renderer per file reuses the O(n)
        // line index for every diagnostic of that file (see render.zig).
        if (!json_format) {
            if (combined.count() != first) {
                const r = try checker.render.Renderer.init(a, src);
                for (combined.items.items[first..]) |d| {
                    try stderr(io, try r.render(d, .{}));
                    try stderr(io, "\n");
                }
            }
        }
        var file_errors: usize = 0;
        var file_warnings: usize = 0;
        for (combined.items.items[first..]) |d| {
            if (d.severity == .err) file_errors += 1 else file_warnings += 1;
        }
        error_total += file_errors;
        warning_total += file_warnings;
    }

    if (json_format) {
        // Machine-readable mode prints the report even when files failed to
        // read (the JSON covers what was checked; the I/O note goes to
        // stderr and still drives exit code 2).
        try stdout(io, try combined.toJson(a));
        try stdout(io, "\n");
    }

    if (io_errors != 0) {
        const line = try std.fmt.allocPrint(a, "zsx check: {d} file(s) unreadable\n", .{io_errors});
        try stderr(io, line);
        std.process.exit(2);
    }

    if (error_total != 0) {
        const line = try std.fmt.allocPrint(a, "zsx check: {d} error(s), {d} warning(s) in {d} file(s)\n", .{ error_total, warning_total, paths.items.len });
        try stderr(io, line);
        std.process.exit(1);
    }

    const line = try std.fmt.allocPrint(a, "zsx check: {d} file(s) clean, {d} warning(s)\n", .{ paths.items.len, warning_total });
    try stderr(io, line);
}

fn stderr(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(io, bytes);
}

fn stdout(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
}

fn lessThanStr(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn excludedDirName(name: []const u8) bool {
    const excluded = [_][]const u8{ ".git", ".zig-cache", "zig-out", "zig-pkg", "node_modules", ".venv" };
    for (excluded) |e| {
        if (std.mem.eql(u8, name, e)) return true;
    }
    return false;
}

/// Collect every `*.zsx` under `dir`, pruning cache/build/VCS directories.
///
/// Implemented as a flat work-queue walk — each directory is opened, iterated
/// to exhaustion, and closed before the next one is touched. `std.Io.Dir.walk`
/// resumes parent iterators after closing child handles, which currently
/// panics on Linux 0.17.1 (`BADF` in `dirReadLinux`); interleaving handles
/// through a queue sidesteps that entirely.
fn collectZsxFiles(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, paths: *std.array_list.Managed([]const u8)) !void {
    var queue = std.array_list.Managed([]const u8).init(a);
    try queue.append("."); // "." = the starting directory itself

    while (queue.pop()) |rel| {
        // Open every directory explicitly (including the root): `cwd()` has no
        // real fd, so neither `iterate()`'s rewind-seek nor getdents itself
        // work on it. An opened `.` has real fd-backed iteration rights.
        var d = try dir.openDir(io, rel, .{ .iterate = true });
        defer d.close(io);

        var it = d.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind == .directory) {
                if (excludedDirName(entry.name)) continue;
                try queue.append(try std.fs.path.join(a, &.{ rel, entry.name }));
                continue;
            }
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".zsx")) continue;
            try paths.append(try std.fs.path.join(a, &.{ rel, entry.name }));
        }
    }
}
