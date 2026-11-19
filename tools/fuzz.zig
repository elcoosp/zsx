//! `zig build fuzz` — property/mutation fuzzing for the ZSX front-end.
//!
//! Default is a few thousand iterations (fast CI); the nightly workflow runs
//! more. On failure the exact input is written under `spec/fuzz/failures/` so
//! it can be minimized and checked in as a reproducer.

const std = @import("std");
const fuzz = @import("zsx_fuzz");

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);

    var cfg: fuzz.Config = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--iterations")) {
            i += 1;
            if (i >= args.len) return error.MissingIterations;
            cfg.iterations = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--seed")) {
            i += 1;
            if (i >= args.len) return error.MissingSeed;
            cfg.seed = try std.fmt.parseInt(u64, args[i], 0);
        }
    }

    var failure: ?fuzz.Failure = null;
    const report = fuzz.run(a, cfg, &failure) catch |e| {
        if (failure) |f| {
            const path = try std.fmt.allocPrint(a, "spec/fuzz/failures/failure_{x}_{d}.zsx", .{ f.seed, f.iteration });
            try std.Io.Dir.cwd().createDirPath(io, "spec/fuzz/failures");
            const file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
            defer file.close(io);
            try file.writeStreamingAll(io, f.input);
            std.debug.print("fuzz: wrote {s} ({s})\n", .{ path, f.reason });
        }
        return e;
    };
    std.debug.print("fuzz: ok — {d} valid + {d} mutated cases (seed 0x{x})\n", .{
        report.valid_cases, report.mutated_cases, cfg.seed,
    });
}
