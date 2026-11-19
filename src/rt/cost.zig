//! Static cost analysis for `zsx check --explain-cost` (master-plan WP 2.12).
//!
//! The generator has no expensive comptime machinery today, but WP 2.5/2.7
//! will add typed `Props` and capture tuples whose comptime cost grows with
//! markup size and component nesting. This module computes a deterministic
//! score from the actual tokens (never substrings) so CI can alarm before
//! compile times regress:
//!
//! * markup elements, attributes, expressions and component calls,
//! * maximum element/control-flow nesting,
//! * `@setEvalBranchQuota` occurrences (an explicit comptime red flag).
//!
//! The score is advisory; callers choose the budget
//! (`zsx check --explain-cost --cost-budget N`). The module is deliberately
//! allocation-light: tokens live in the caller's arena.

const std = @import("std");
const scan = @import("scan.zig");
const lossless = @import("lossless.zig");

pub const Report = struct {
    elements: usize = 0,
    components: usize = 0,
    attrs: usize = 0,
    expressions: usize = 0,
    events: usize = 0,
    max_depth: usize = 0,
    control_flow: usize = 0,
    max_control_depth: usize = 0,
    set_eval_branch_quota: usize = 0,

    /// Deterministic weighted score used for budgets. Weights are relative,
    /// not milliseconds: components and nesting are what make generated types
    /// large, expressions add type-checking work, and an explicit
    /// `@setEvalBranchQuota` is a strong signal of comptime pressure.
    pub fn score(self: Report) usize {
        return self.elements +
            self.attrs +
            2 * self.expressions +
            4 * self.components +
            8 * self.max_depth +
            16 * self.max_control_depth +
            20 * self.events +
            100 * self.set_eval_branch_quota;
    }

    pub fn merge(self: *Report, other: Report) void {
        self.elements += other.elements;
        self.components += other.components;
        self.attrs += other.attrs;
        self.expressions += other.expressions;
        self.events += other.events;
        self.max_depth = @max(self.max_depth, other.max_depth);
        self.control_flow += other.control_flow;
        self.max_control_depth = @max(self.max_control_depth, other.max_control_depth);
        self.set_eval_branch_quota += other.set_eval_branch_quota;
    }
};

pub fn analyze(a: std.mem.Allocator, source: []const u8) !Report {
    const doc = try lossless.Document.init(a, source);
    var report: Report = .{};

    for (doc.blocks) |blk| {
        const markup = doc.markup(blk);
        var scanner = scan.Scanner.init(a, markup, blk.markup_off);
        const toks = try scanner.run();

        var depth: usize = 0;
        var ctrl_depth: usize = 0;
        for (toks) |t| switch (t) {
            .open_tag => |ot| {
                report.elements += 1;
                if (isComponent(ot.tag)) report.components += 1;
                report.attrs += ot.attrs.len;
                for (ot.attrs) |attr| {
                    if (std.mem.startsWith(u8, attr.name, "on_") or std.mem.startsWith(u8, attr.name, "on:")) report.events += 1;
                }
                if (!ot.self_closing) {
                    depth += 1;
                    report.max_depth = @max(report.max_depth, depth);
                }
            },
            .close_tag => depth = depth -| 1,
            .ctrl_open => |co| {
                report.control_flow += 1;
                ctrl_depth += 1;
                report.max_control_depth = @max(report.max_control_depth, ctrl_depth);
                _ = co;
            },
            .ctrl_mid => {},
            .ctrl_close => ctrl_depth = ctrl_depth -| 1,
            .expression => report.expressions += 1,
            .text, .junk => {},
        };
    }

    // Token-based detection across the Zig parts (including markup
    // expressions is fine: `@setEvalBranchQuota` may legally appear there).
    report.set_eval_branch_quota = try countBuiltin(a, source, "@setEvalBranchQuota");
    return report;
}

fn isComponent(tag: []const u8) bool {
    if (tag.len == 0) return false;
    if (std.mem.indexOfScalar(u8, tag, '.') != null) return true;
    return std.ascii.isUpper(tag[0]);
}

fn countBuiltin(a: std.mem.Allocator, source: []const u8, name: []const u8) !usize {
    if (std.mem.indexOf(u8, source, name) == null) return 0;
    const z = try a.dupeSentinel(u8, source, 0);
    defer a.free(z);
    var tok = std.zig.Tokenizer.init(z);
    var n: usize = 0;
    while (true) {
        const t = tok.next();
        if (t.tag == .eof) break;
        if (t.tag == .builtin and std.mem.eql(u8, source[t.loc.start..t.loc.end], name)) n += 1;
    }
    return n;
}

test "cost: counts elements, components, attrs, expressions and depth" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src =
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    zsx!{
        \\        <column class="p-2">
        \\            {for ctx.items as item}
        \\                <Card><Button on:click={ctx.save(item)}>{item}</Button></Card>
        \\            {/for}
        \\        </column>
        \\    }
        \\}
        \\
    ;
    const r = try analyze(a, src);
    try std.testing.expectEqual(@as(usize, 3), r.elements);
    try std.testing.expectEqual(@as(usize, 2), r.components);
    try std.testing.expectEqual(@as(usize, 2), r.attrs);
    try std.testing.expectEqual(@as(usize, 1), r.expressions);
    try std.testing.expectEqual(@as(usize, 1), r.events);
    try std.testing.expectEqual(@as(usize, 3), r.max_depth);
    try std.testing.expectEqual(@as(usize, 1), r.control_flow);
    try std.testing.expectEqual(@as(usize, 1), r.max_control_depth);
    try std.testing.expect(r.score() > 0);
}

test "cost: @setEvalBranchQuota is detected token-wise" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src =
        \\pub fn view(ui: anytype, c: anytype, ctx: anytype) void {
        \\    @setEvalBranchQuota(10_000);
        \\    zsx!{
        \\        <label>x</label>
        \\    }
        \\}
        \\
    ;
    const r = try analyze(a, src);
    try std.testing.expectEqual(@as(usize, 1), r.set_eval_branch_quota);
}
