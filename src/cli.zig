//! `zsx` CLI — M0 stub.
//!
//! `fmt` and `check` temporarily wrap the Python tools so CI and docs have one
//! command surface before the native implementations land in M1.

const std = @import("std");

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
        return runPython(init, a, "scripts/zsx-fmt.py", args[2..]);
    }
    if (std.mem.eql(u8, cmd, "check")) {
        return runPython(init, a, "scripts/zsx-check.py", args[2..]);
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
        \\  fmt [--check] [paths...]   format .zsx markup (currently wraps Python)
        \\  check [paths...]           validate .zsx structure (currently wraps Python)
        \\  version                    print the ZSX version
        \\
    , .{});
}

fn runPython(init: std.process.Init, a: std.mem.Allocator, script: []const u8, extra: []const []const u8) !void {
    var argv = std.array_list.Managed([]const u8).init(a);
    try argv.append("python3");
    try argv.append(script);
    try argv.appendSlice(extra);

    const result = std.process.run(a, init.io, .{ .argv = argv.items }) catch |e| {
        std.debug.print("zsx: failed to run python3: {s}\n", .{@errorName(e)});
        return e;
    };
    try std.Io.File.stdout().writeStreamingAll(init.io, result.stdout);
    try std.Io.File.stderr().writeStreamingAll(init.io, result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) std.process.exit(code),
        else => std.process.exit(1),
    }
}
