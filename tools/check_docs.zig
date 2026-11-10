//! `zig build check-docs` — required docs exist and relative links resolve.

const std = @import("std");

const required = [_][]const u8{
    "AGENTS.md",
    "docs/STATE.md",
    "docs/ZSX_MASTER_PLAN.md",
    "docs/adr/0000-template.md",
    "docs/adr/0001-single-source-version-and-component-count.md",
    "docs/adr/0002-zig-version-policy.md",
    "docs/rfc/0000-template.md",
};

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

    var ok = true;
    for (required) |rel| {
        const path = try std.fs.path.join(a, &.{ root, rel });
        dir.access(io, path, .{}) catch {
            std.debug.print("check-docs: missing required file {s}\n", .{rel});
            ok = false;
        };
    }

    var files = std.array_list.Managed([]const u8).init(a);
    try files.append("AGENTS.md");
    try files.append("docs/STATE.md");
    try files.append("docs/ZSX_MASTER_PLAN.md");
    try collectMarkdown(a, io, dir, root, "docs/adr", &files);
    try collectMarkdown(a, io, dir, root, "docs/rfc", &files);

    for (files.items) |rel| {
        const path = try std.fs.path.join(a, &.{ root, rel });
        const src = dir.readFileAlloc(io, path, a, .limited(4 * 1024 * 1024)) catch continue;
        const base = std.fs.path.dirname(rel) orelse ".";
        if (!try checkLinks(a, io, dir, root, base, rel, src)) ok = false;
    }

    if (!ok) return error.DocCheckFailed;
    std.debug.print("check-docs: ok ({d} files)\n", .{files.items.len});
}

fn collectMarkdown(
    a: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    root: []const u8,
    rel_dir: []const u8,
    out: *std.array_list.Managed([]const u8),
) !void {
    const path = try std.fs.path.join(a, &.{ root, rel_dir });
    var d = dir.openDir(io, path, .{ .iterate = true }) catch return;
    defer d.close(io);
    var it = d.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;
        try out.append(try std.fs.path.join(a, &.{ rel_dir, entry.name }));
    }
}

fn checkLinks(
    a: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    root: []const u8,
    base: []const u8,
    rel: []const u8,
    src: []const u8,
) !bool {
    var ok = true;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, src, pos, "](")) |open| {
        pos = open + 2;
        const close = std.mem.indexOfScalarPos(u8, src, pos, ')') orelse break;
        var target = std.mem.trim(u8, src[pos..close], " \t\r\n");
        pos = close + 1;
        if (target.len == 0) continue;
        if (std.mem.startsWith(u8, target, "http://") or
            std.mem.startsWith(u8, target, "https://") or
            std.mem.startsWith(u8, target, "mailto:") or
            std.mem.startsWith(u8, target, "#")) continue;
        if (std.mem.indexOfScalar(u8, target, '#')) |hash| target = target[0..hash];
        target = std.mem.trim(u8, target, " \t\r\n<>");
        if (target.len == 0) continue;

        const resolved = try std.fs.path.resolve(a, &.{ root, base, target });
        dir.access(io, resolved, .{}) catch {
            std.debug.print("check-docs: {s}: broken link '{s}'\n", .{ rel, target });
            ok = false;
        };
    }
    return ok;
}
