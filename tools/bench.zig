//! `zig build bench` — deterministic-ish benchmark skeleton.
//!
//! M0 measures wall-clock generator throughput on synthetic views and writes a
//! baseline JSON. M1 adds `check_1k`: checker throughput over the same
//! synthetic file, against the master-plan WP 1.7 acceptance target (< 20 ms
//! per 1k lines). `render_1k` covers the code-frame renderer (M1): check plus
//! render of every diagnostic against a synthetic broken view, the full
//! pipeline `zsx check` runs on a failing file. `lossless_1k` covers the
//! lossless front-end (M1): segment the synthetic file and re-emit it
//! byte-for-byte (S1 + S2), the round-trip every lossless consumer relies on.
//! Instruction counts and per-backend frame costs land in M10.

const std = @import("std");
const checker = @import("zsx_checker");
const diag = checker.diag;
const preprocess = checker.preprocess;
const lossless = checker.lossless;

const Kind = enum { gen, check, fmt, render, lossless };

const Case = struct {
    name: []const u8,
    kind: Kind,
    lines: usize,
    iterations: usize,
    result: ?Metrics = null,
};

const Metrics = struct {
    input_bytes: usize,
    output_bytes: usize = 0,
    diagnostics: usize = 0,
    ns: u64,
    mb_per_s: f64,
};

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    const dir = std.Io.Dir.cwd();

    var out_path: ?[]const u8 = null;
    var smoke = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--out")) {
            i += 1;
            out_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--smoke")) {
            smoke = true;
        }
    }

    var cases = std.array_list.Managed(Case).init(a);
    if (smoke) {
        try cases.append(.{ .name = "gen_1k", .kind = .gen, .lines = 1000, .iterations = 3 });
        try cases.append(.{ .name = "check_1k", .kind = .check, .lines = 1000, .iterations = 3 });
        try cases.append(.{ .name = "fmt_1k", .kind = .fmt, .lines = 1000, .iterations = 3 });
        try cases.append(.{ .name = "render_1k", .kind = .render, .lines = 1000, .iterations = 3 });
        try cases.append(.{ .name = "lossless_1k", .kind = .lossless, .lines = 1000, .iterations = 3 });
    } else {
        try cases.append(.{ .name = "gen_1k", .kind = .gen, .lines = 1000, .iterations = 10 });
        try cases.append(.{ .name = "gen_10k", .kind = .gen, .lines = 10_000, .iterations = 5 });
        try cases.append(.{ .name = "check_1k", .kind = .check, .lines = 1000, .iterations = 10 });
        try cases.append(.{ .name = "fmt_1k", .kind = .fmt, .lines = 1000, .iterations = 10 });
        try cases.append(.{ .name = "render_1k", .kind = .render, .lines = 1000, .iterations = 10 });
        try cases.append(.{ .name = "lossless_1k", .kind = .lossless, .lines = 1000, .iterations = 10 });
    }
    const case_slice = cases.items;

    var json = std.array_list.Managed(u8).init(a);
    try json.appendSlice("{\n  \"schema\": 1,\n  \"metric\": \"wall_ns\",\n  \"cases\": {\n");
    for (case_slice, 0..) |*c, idx| {
        const src = if (c.kind == .render) try syntheticBroken(a, c.lines) else try synthetic(a, c.lines);
        var best: u64 = std.math.maxInt(u64);
        var out_len: usize = 0;
        var diag_count: usize = 0;
        var iter: usize = 0;
        while (iter < c.iterations) : (iter += 1) {
            var work: usize = 0;
            const t0 = std.Io.Clock.Timestamp.now(io, .awake);
            switch (c.kind) {
                .gen => {
                    const body = try preprocess.preprocess(a, src, "synthetic.zsx", 0);
                    work = body.len;
                },
                .check => {
                    var list = diag.List.init(a);
                    try checker.checkSource(a, src, "synthetic.zsx", .{}, &list);
                    work = list.count();
                },
                .fmt => {
                    const body = try checker.fmt.formatSource(a, src, .{});
                    work = body.len;
                },
                .render => {
                    var list = diag.List.init(a);
                    try checker.checkSource(a, src, "synthetic-broken.zsx", .{}, &list);
                    const r = try checker.render.Renderer.init(a, src);
                    var bytes: usize = 0;
                    for (list.items.items) |d| {
                        bytes += (try r.render(d, .{})).len;
                    }
                    work = bytes;
                },
                .lossless => {
                    const doc = try lossless.Document.init(a, src);
                    const rendered = try doc.render(a);
                    if (!std.mem.eql(u8, rendered, src)) return error.BenchFailed;
                    work = doc.blocks.len;
                },
            }
            const t1 = std.Io.Clock.Timestamp.now(io, .awake);
            const ns: u64 = @intCast(@max(0, t0.durationTo(t1).raw.nanoseconds));
            if (ns < best) best = ns;
            switch (c.kind) {
                .gen => out_len = work,
                .check => diag_count = work,
                .lossless => out_len = src.len,
                .fmt, .render => out_len = work,
            }
        }
        // `gen` is validated inside the timing loop above (`try preprocess`),
        // so a generator failure already aborts the bench run with the real
        // error; no redundant re-run needed here.
        const mb_per_s = if (best == 0) 0.0 else (@as(f64, @floatFromInt(src.len)) / (1024.0 * 1024.0)) / (@as(f64, @floatFromInt(best)) / 1e9);
        c.result = .{ .input_bytes = src.len, .output_bytes = out_len, .diagnostics = diag_count, .ns = best, .mb_per_s = mb_per_s };

        try json.appendSlice(if (idx == 0) "" else ",\n");
        const line = switch (c.kind) {
            .gen, .fmt, .render, .lossless => try std.fmt.allocPrint(
                a,
                "    \"{s}\": {{ \"input_lines\": {d}, \"input_bytes\": {d}, \"output_bytes\": {d}, \"ns\": {d}, \"mb_per_s\": {d:.2} }}",
                .{ c.name, c.lines, src.len, out_len, best, mb_per_s },
            ),
            .check => try std.fmt.allocPrint(
                a,
                "    \"{s}\": {{ \"input_lines\": {d}, \"input_bytes\": {d}, \"diagnostics\": {d}, \"ns\": {d}, \"mb_per_s\": {d:.2} }}",
                .{ c.name, c.lines, src.len, diag_count, best, mb_per_s },
            ),
        };
        try json.appendSlice(line);
        const label = switch (c.kind) {
            .gen => "gen",
            .check => "check",
            .fmt => "fmt",
            .render => "render",
            .lossless => "lossless",
        };
        std.debug.print("bench: {s}  {s}  {d} lines  {d} ns  {d:.2} MB/s\n", .{ c.name, label, c.lines, best, mb_per_s });
    }
    try json.appendSlice("\n  }\n}\n");

    if (out_path) |p| {
        if (std.fs.path.dirname(p)) |d| dir.createDirPath(io, d) catch {};
        const f = try dir.createFile(io, p, .{ .truncate = true });
        defer f.close(io);
        try f.writeStreamingAll(io, json.items);
        std.debug.print("bench: wrote {s}\n", .{p});
    } else {
        try std.Io.File.stdout().writeStreamingAll(io, json.items);
    }
}

fn synthetic(a: std.mem.Allocator, lines: usize) ![]const u8 {
    var out = std.array_list.Managed(u8).init(a);
    try out.appendSlice("const std = @import(\"std\");\n\npub fn view(ui: anytype, c: anytype, ctx: anytype) void {\n    zsx!{\n        <column class=\"gap-2 p-4\">\n");
    var i: usize = 0;
    while (i < lines) : (i += 1) {
        try out.appendSlice("            <label class=\"text-sm text-slate-900\">row</label>\n");
    }
    try out.appendSlice("        </column>\n    }\n}\n");
    return out.toOwnedSlice();
}

/// Same shape as `synthetic`, but every fifth label is never closed: the
/// checker reports one `ZSX0003` per fifth row, giving the renderer a
/// deterministic, sizeable diagnostic list to frame.
fn syntheticBroken(a: std.mem.Allocator, lines: usize) ![]const u8 {
    var out = std.array_list.Managed(u8).init(a);
    try out.appendSlice("const std = @import(\"std\");\n\npub fn view(ui: anytype, c: anytype, ctx: anytype) void {\n    zsx!{\n        <column class=\"gap-2 p-4\">\n");
    var i: usize = 0;
    while (i < lines) : (i += 1) {
        if (i % 5 == 0) {
            try out.appendSlice("            <label class=\"text-sm text-slate-900\">row\n");
        } else {
            try out.appendSlice("            <label class=\"text-sm text-slate-900\">row</label>\n");
        }
    }
    try out.appendSlice("        </column>\n    }\n}\n");
    return out.toOwnedSlice();
}
