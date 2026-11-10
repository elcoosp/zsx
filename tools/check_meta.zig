//! `zig build check-meta` — fail when release metadata drifts.
//! Source of truth: VERSION. Consumers: build.zig.zon, CHANGELOG.md, README.md.

const std = @import("std");

const failure = error.MetaDrift;

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    const dir = std.Io.Dir.cwd();

    var root: []const u8 = ".";
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--root")) {
            i += 1;
            root = args[i];
        }
    }

    const version = try readTrimmed(a, io, dir, root, "VERSION");
    var ok = true;

    const zon = try readTrimmed(a, io, dir, root, "build.zig.zon");
    const zon_version = extractAfter(zon, ".version = \"", "\"") orelse {
        fail("build.zig.zon: missing `.version = \"…\"`", .{});
        return failure;
    };
    if (!std.mem.eql(u8, zon_version, version)) {
        fail("build.zig.zon version '{s}' != VERSION '{s}'", .{ zon_version, version });
        ok = false;
    }

    const changelog = try readTrimmed(a, io, dir, root, "CHANGELOG.md");
    const cl_version = extractAfter(changelog, "## [", "]") orelse {
        fail("CHANGELOG.md: missing `## [version]` heading", .{});
        return failure;
    };
    if (!std.mem.eql(u8, cl_version, version)) {
        fail("CHANGELOG.md first heading '{s}' != VERSION '{s}'", .{ cl_version, version });
        ok = false;
    }

    const readme = try readTrimmed(a, io, dir, root, "README.md");
    const readme_version = extractAfter(readme, "Version **", "**") orelse {
        fail("README.md: missing `Version **…**` status line", .{});
        return failure;
    };
    if (!std.mem.eql(u8, readme_version, version)) {
        fail("README.md status version '{s}' != VERSION '{s}'", .{ readme_version, version });
        ok = false;
    }

    const shadcn = try readTrimmed(a, io, dir, root, "src/lib/shadcn.zig");
    const count = countComponents(shadcn);
    var count_buf: [64]u8 = undefined;
    const count_phrase = try std.fmt.bufPrint(&count_buf, "{d} shadcn-inspired components", .{count});
    if (std.mem.indexOf(u8, readme, count_phrase) == null) {
        fail("README.md: missing phrase '{s}' (derived from src/lib/shadcn.zig)", .{count_phrase});
        ok = false;
    }
    const table_phrase = try std.fmt.bufPrint(&count_buf, "| `src/lib/shadcn.zig` | {d} components |", .{count});
    if (std.mem.indexOf(u8, readme, table_phrase) == null) {
        fail("README.md: missing structure-table row '{s}'", .{table_phrase});
        ok = false;
    }

    if (!ok) return failure;
    std.debug.print("check-meta: ok (version {s}, {d} components)\n", .{ version, count });
}

fn readTrimmed(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, root: []const u8, name: []const u8) ![]const u8 {
    const path = try std.fs.path.join(a, &.{ root, name });
    const bytes = dir.readFileAlloc(io, path, a, .limited(4 * 1024 * 1024)) catch |e| {
        fail("cannot read {s}: {s}", .{ path, @errorName(e) });
        return error.ReadFailed;
    };
    return std.mem.trim(u8, bytes, " \t\r\n");
}

fn extractAfter(haystack: []const u8, prefix: []const u8, suffix: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, haystack, prefix) orelse return null;
    const rest = haystack[start + prefix.len ..];
    const end = std.mem.indexOf(u8, rest, suffix) orelse return null;
    return rest[0..end];
}

fn countComponents(src: []const u8) usize {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        const marker = "pub inline fn ";
        if (!std.mem.startsWith(u8, line, marker)) continue;
        if (line.len <= marker.len) continue;
        const first = line[marker.len];
        if (first >= 'A' and first <= 'Z') count += 1;
    }
    return count;
}

fn fail(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("check-meta: " ++ fmt ++ "\n", args);
}
