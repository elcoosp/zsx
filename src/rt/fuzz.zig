//! Property/fuzz harness for the front-end (M1 WP 1.9 slice).
//!
//! Two inputs per iteration: a grammar-shaped valid markup block from the
//! generator, then a byte-mutated copy. Every input must survive the scanner,
//! CST parser and checker without crashing; token spans must tile the source,
//! CST spans must stay ordered, clean CSTs must lower, and formatting must be
//! idempotent. Failures return the exact input plus seed/iteration so the
//! `tools/fuzz.zig` runner can save a minimized reproducer.

const std = @import("std");
const checker = @import("checker.zig");
const cst = @import("cst.zig");
const diag = @import("diag.zig");
const fmt = @import("fmt.zig");
const scan = @import("scan.zig");

pub const Config = struct {
    iterations: usize = 5_000,
    seed: u64 = 0x5eed_2a17,
    max_depth: usize = 3,
};

pub const Kind = enum { valid, mutated };

pub const Failure = struct {
    seed: u64,
    iteration: usize,
    kind: Kind,
    input: []const u8,
    reason: []const u8,
};

pub const Report = struct {
    valid_cases: usize = 0,
    mutated_cases: usize = 0,
};

pub fn run(a: std.mem.Allocator, cfg: Config, failure: *?Failure) !Report {
    var prng = std.Random.DefaultPrng.init(cfg.seed);
    const random = prng.random();
    var report: Report = .{};
    for (0..cfg.iterations) |iteration| {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        const valid = try genValid(aa, random, cfg.max_depth);
        try checkCase(a, aa, cfg.seed, iteration, .valid, valid, failure);
        report.valid_cases += 1;

        const mutated = try mutate(aa, random, valid);
        try checkCase(a, aa, cfg.seed, iteration, .mutated, mutated, failure);
        report.mutated_cases += 1;
    }
    return report;
}

fn checkCase(
    out_a: std.mem.Allocator,
    a: std.mem.Allocator,
    seed: u64,
    iteration: usize,
    kind: Kind,
    input: []const u8,
    failure: *?Failure,
) !void {
    const idx = diag.LineIndex.build(a, input) catch |e| return fail(out_a, failure, seed, iteration, kind, input, @errorName(e));

    var scanner = scan.Scanner.init(a, input, 0);
    const toks = scanner.run() catch |e| return fail(out_a, failure, seed, iteration, kind, input, @errorName(e));
    if (!scan.coversSource(toks, input, 0)) return fail(out_a, failure, seed, iteration, kind, input, "tokens do not tile source");

    var cst_list = diag.List.init(a);
    const root = cst.parse(a, input, 0, "fuzz.zsx", idx, &cst_list) catch |e| return fail(out_a, failure, seed, iteration, kind, input, @errorName(e));
    if (!cst.spansAreOrdered(root) or !cst.treeIsOrdered(root)) {
        return fail(out_a, failure, seed, iteration, kind, input, "CST spans are not ordered");
    }

    var check_list = diag.List.init(a);
    checker.checkMarkup(a, input, 0, idx, "fuzz.zsx", .{}, &check_list) catch |e| {
        return fail(out_a, failure, seed, iteration, kind, input, @errorName(e));
    };

    if (cst_list.count() == 0) {
        // A clean CST can still be an invalid block (top-level text/multiple
        // roots); lowering is expected to reject those, not crash.
        _ = cst.lowerBlock(a, root) catch |e| switch (e) {
            error.NoRoot, error.MultipleRoots, error.StrayTopLevel => {},
            else => return fail(out_a, failure, seed, iteration, kind, input, @errorName(e)),
        };
        const once = fmt.formatMarkup(a, input, 0, .{}) catch |e| return fail(out_a, failure, seed, iteration, kind, input, @errorName(e));
        const twice = fmt.formatMarkup(a, once, 0, .{}) catch |e| return fail(out_a, failure, seed, iteration, kind, input, @errorName(e));
        if (!std.mem.eql(u8, once, twice)) return fail(out_a, failure, seed, iteration, kind, input, "fmt is not idempotent");
    }
}

fn fail(
    out_a: std.mem.Allocator,
    failure: *?Failure,
    seed: u64,
    iteration: usize,
    kind: Kind,
    input: []const u8,
    reason: []const u8,
) anyerror!void {
    std.debug.print("fuzz: {s} case {d} (seed 0x{x}) failed: {s}\n--- input ---\n{s}\n---\n", .{
        @tagName(kind), iteration, seed, reason, input,
    });
    failure.* = .{
        .seed = seed,
        .iteration = iteration,
        .kind = kind,
        .input = try out_a.dupe(u8, input),
        .reason = reason,
    };
    return error.FuzzFailure;
}

const tags = [_][]const u8{ "column", "row", "label", "Button", "Card" };
const text_alphabet = "abc XYZ 0123";
const mutation_alphabet = "<>{}/=\"' :\n\tab019_-";

fn genValid(a: std.mem.Allocator, random: std.Random, max_depth: usize) ![]u8 {
    var out = std.array_list.Managed(u8).init(a);
    // A block root must be an element or fragment (RFC-0001 S1).
    if (random.boolean()) {
        try genElement(&out, a, random, max_depth);
    } else {
        try out.appendSlice("<>");
        try genChildren(&out, a, random, max_depth);
        try out.appendSlice("</>");
    }
    return out.toOwnedSlice();
}

fn genChildren(out: *std.array_list.Managed(u8), a: std.mem.Allocator, random: std.Random, depth: usize) anyerror!void {
    const count = random.intRangeAtMost(usize, 0, 3);
    for (0..count) |_| try genNode(out, a, random, depth);
}

fn genNode(out: *std.array_list.Managed(u8), a: std.mem.Allocator, random: std.Random, depth: usize) anyerror!void {
    const choice = if (depth == 0) random.intRangeAtMost(usize, 0, 3) else random.intRangeAtMost(usize, 0, 6);
    switch (choice) {
        0 => try genText(out, random),
        1 => try out.appendSlice("{ctx.value}"),
        2 => try genElement(out, a, random, depth),
        3 => try out.appendSlice("<Input buffer={&ctx.name} />"),
        4 => try genIf(out, a, random, depth - 1),
        5 => try genFor(out, a, random, depth - 1),
        else => try genSwitch(out, a, random, depth - 1),
    }
}

fn genText(out: *std.array_list.Managed(u8), random: std.Random) anyerror!void {
    const len = random.intRangeAtMost(usize, 1, 8);
    for (0..len) |_| try out.append(text_alphabet[random.intRangeLessThan(usize, 0, text_alphabet.len)]);
}

fn genElement(out: *std.array_list.Managed(u8), a: std.mem.Allocator, random: std.Random, depth: usize) anyerror!void {
    const tag = tags[random.intRangeLessThan(usize, 0, tags.len)];
    try out.append('<');
    try out.appendSlice(tag);
    if (std.mem.eql(u8, tag, "column") or std.mem.eql(u8, tag, "row")) try out.appendSlice(" class=\"gap-2\"");
    if (std.mem.eql(u8, tag, "Button")) try out.appendSlice(" variant=\"primary\"");
    try out.append('>');
    if (depth == 0) {
        if (std.mem.eql(u8, tag, "label")) try genText(out, random) else try out.appendSlice("{ctx.value}");
    } else {
        try genChildren(out, a, random, depth - 1);
    }
    try out.appendSlice("</");
    try out.appendSlice(tag);
    try out.append('>');
}

fn genIf(out: *std.array_list.Managed(u8), a: std.mem.Allocator, random: std.Random, depth: usize) anyerror!void {
    try out.appendSlice("{if ctx.flag}");
    try genChildren(out, a, random, depth);
    if (random.boolean()) {
        try out.appendSlice("{:else}");
        try genChildren(out, a, random, depth);
    }
    try out.appendSlice("{/if}");
}

fn genFor(out: *std.array_list.Managed(u8), a: std.mem.Allocator, random: std.Random, depth: usize) anyerror!void {
    try out.appendSlice("{for ctx.items as item}");
    if (random.boolean()) {
        try out.appendSlice("<label>{item}</label>");
    } else {
        try genChildren(out, a, random, depth);
    }
    try out.appendSlice("{/for}");
}

fn genSwitch(out: *std.array_list.Managed(u8), a: std.mem.Allocator, random: std.Random, depth: usize) anyerror!void {
    try out.appendSlice("{switch ctx.mode}{:case 1}");
    try genChildren(out, a, random, depth);
    try out.appendSlice("{:else}");
    try genChildren(out, a, random, depth);
    try out.appendSlice("{/switch}");
}

fn mutate(a: std.mem.Allocator, random: std.Random, src: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(a);
    try out.appendSlice(src);
    const ops = random.intRangeAtMost(usize, 1, 4);
    for (0..ops) |_| {
        switch (random.intRangeAtMost(usize, 0, 2)) {
            0 => if (out.items.len != 0) {
                out.items[random.intRangeLessThan(usize, 0, out.items.len)] = mutation_alphabet[random.intRangeLessThan(usize, 0, mutation_alphabet.len)];
            },
            1 => {
                const pos = random.intRangeAtMost(usize, 0, out.items.len);
                try out.insert(pos, mutation_alphabet[random.intRangeLessThan(usize, 0, mutation_alphabet.len)]);
            },
            else => if (out.items.len > 1) {
                _ = out.orderedRemove(random.intRangeLessThan(usize, 0, out.items.len));
            },
        }
    }
    return out.toOwnedSlice();
}

test "fuzz: generator and mutation invariants hold" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var failure: ?Failure = null;
    const report = try run(arena.allocator(), .{ .iterations = 500, .seed = 0xabc123 }, &failure);
    try std.testing.expect(failure == null);
    try std.testing.expectEqual(@as(usize, 500), report.valid_cases);
    try std.testing.expectEqual(@as(usize, 500), report.mutated_cases);
}
