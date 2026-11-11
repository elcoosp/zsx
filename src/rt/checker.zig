//! Structural checker for `.zsx` files — the native replacement for
//! `scripts/zsx-check.py` (master-plan WP 1.7, first slice).
//!
//! The checker validates structure without compiling: balanced tags, matched
//! control flow, `{:else}`/`{:case}` placement, unknown-class warnings and
//! legacy-alias warnings. It never aborts on the first problem — the tolerant
//! scanner (`scan.zig`) recovers, so one bad element no longer hides every
//! later diagnostic, the way the fail-fast `parser.zig` used to.
//!
//! Diagnostics are `diag.Diagnostic` values with stable `ZSX0xxx` codes; the
//! CLI decides how to render them. The class table is not duplicated here:
//! `style.isKnownClass` asks the same resolver codegen uses, so a warning
//! from this checker is guaranteed to mean `error.ZsxUnknownClass` at build.
//!
//! Entry point:
//!
//!     var list = diag.List.init(arena);
//!     try checker.checkSource(arena, source, "src/views/x.zsx", .{}, &list);
//!     if (list.hasErrors()) { ... }
//!
//! Exit-code contract (mirrors the Python tool): 0 = clean or warnings only,
//! 1 = at least one error, 2 = the file could not be read at all (CLI maps
//! this; not represented here).

const std = @import("std");
/// Re-exported so downstream tools (bench, CLI) need only this module.
pub const diag = @import("diag.zig");
/// Re-exported so downstream tools (bench, CLI) need only this module.
///
/// Zig links each source file into exactly one module per compilation, so
/// every tooling consumer (bench, CLI, package root) reaches the front-end
/// through this barrel instead of importing sibling files as separate
/// modules — a second root over the same files would fail to compile.
pub const scan = @import("scan.zig");
/// Re-exported so downstream tools (bench, CLI) need only this module.
pub const preprocess = @import("preprocess.zig");
/// Native formatter (WP 1.6 slice). Lives on the same barrel for the same
/// one-file-one-module reason; see `fmt.zig`.
pub const fmt = @import("fmt.zig");
const style = @import("style.zig");

pub const Options = struct {
    /// Warn on class tokens the built-in resolver does not know. Disable with
    /// `zsx check --no-class-check` (same flag the Python tool accepted).
    check_classes: bool = true,
};

const TagFrame = struct {
    tag: []const u8,
    off: usize,
};

const CtrlFrame = struct {
    kind: scan.CtrlKind,
    off: usize,
};

/// Check a whole `.zsx` source: find `zsx!{ }` blocks and validate the markup
/// in each. Diagnostics accumulate into `list` (callers own rendering).
pub fn checkSource(a: std.mem.Allocator, source: []const u8, src_name: []const u8, opts: Options, list: *diag.List) !void {
    const idx = try diag.LineIndex.build(a, source);
    const blocks = try preprocess.findBlocks(a, source);
    for (blocks) |block| {
        if (!block.closed) {
            try list.err(idx, src_name, block.start, 5, .unterminated_block, "zsx!{{ block is never closed: no matching '}}' before end of file", .{});
            continue;
        }
        // markup body: between "zsx!{" (5 bytes) and the matching "}".
        const markup = source[block.start + 5 .. block.end - 1];
        try checkMarkup(a, markup, block.start + 5, idx, src_name, opts, list);
    }
}

/// Validate one block's markup fragment directly. `base` is the absolute file
/// offset of `markup[0]` (use 0 for standalone fragments) so diagnostics cite
/// file positions. Public for tooling that already holds a markup fragment
/// (for example a formatter preview or an LSP shadow document); the file-level
/// entry is `checkSource`.
pub fn checkMarkup(a: std.mem.Allocator, markup: []const u8, base: usize, idx: diag.LineIndex, src_name: []const u8, opts: Options, list: *diag.List) !void {
    var scanner = scan.Scanner.init(a, markup, base);
    const toks = try scanner.run();

    var tags = std.array_list.Managed(TagFrame).init(a);
    var ctrls = std.array_list.Managed(CtrlFrame).init(a);

    for (toks) |t| {
        switch (t) {
            .open_tag => |ot| {
                if (opts.check_classes) try checkClasses(idx, src_name, ot, list);
                if (!ot.self_closing) {
                    try tags.append(.{ .tag = ot.tag, .off = ot.off });
                }
            },
            .close_tag => |ct| {
                if (tags.items.len == 0) {
                    if (ct.tag.len == 0) {
                        try list.err(idx, src_name, ct.off, ct.end - ct.off, .stray_close_tag, "</> with no open fragment", .{});
                    } else {
                        try list.err(idx, src_name, ct.off, ct.end - ct.off, .stray_close_tag, "</{s}> with no open tag", .{ct.tag});
                    }
                    continue;
                }
                const frame = tags.pop().?;
                if (!std.mem.eql(u8, frame.tag, ct.tag)) {
                    const open_pos = idx.lineCol(frame.off);
                    try list.err(idx, src_name, ct.off, ct.end - ct.off, .tag_mismatch, "</{s}> closes <{s}> opened at line {d}", .{ ct.tag, frame.tag, open_pos.line });
                }
            },
            .ctrl_open => |co| try ctrls.append(.{ .kind = co.kind, .off = co.off }),
            .ctrl_mid => |cm| {
                if (ctrls.items.len == 0) {
                    try list.err(idx, src_name, cm.off, cm.end - cm.off, switch (cm.kind) {
                        .else_ => .misplaced_else,
                        .case_ => .misplaced_case,
                    }, "{{:{s}}} at top level (no open {{{s}}})", .{ midName(cm.kind), "if/for/switch" });
                    continue;
                }
                const top = ctrls.items[ctrls.items.len - 1];
                switch (cm.kind) {
                    .else_ => if (top.kind != .if_ and top.kind != .switch_) {
                        try list.err(idx, src_name, cm.off, cm.end - cm.off, .misplaced_else, "{{:else}} inside {{{s}}} (only valid in {{if}}/{{switch}})", .{scan.ctrlName(top.kind)});
                    },
                    .case_ => if (top.kind != .switch_) {
                        try list.err(idx, src_name, cm.off, cm.end - cm.off, .misplaced_case, "{{:case}} inside {{{s}}} (only valid in {{switch}})", .{scan.ctrlName(top.kind)});
                    },
                }
            },
            .ctrl_close => |cc| {
                if (cc.legacy) {
                    try list.warn(idx, src_name, cc.off, cc.end - cc.off, .legacy_alias, "{{{s}}} is a legacy alias; use {{/{s}}}", .{ legacyName(cc.kind), scan.ctrlName(cc.kind) });
                }
                if (ctrls.items.len == 0) {
                    try list.err(idx, src_name, cc.off, cc.end - cc.off, .stray_ctrl_close, "{{/{s}}} with no matching {{if}}/{{for}}/{{switch}}", .{scan.ctrlName(cc.kind)});
                    continue;
                }
                const frame = ctrls.pop().?;
                if (frame.kind != cc.kind) {
                    try list.err(idx, src_name, cc.off, cc.end - cc.off, .ctrl_mismatch, "{{/{s}}} closes {{{s}}}", .{ scan.ctrlName(cc.kind), scan.ctrlName(frame.kind) });
                }
            },
            .junk => |j| try list.err(idx, src_name, j.off, j.end - j.off, .junk_syntax, "{s}", .{j.msg}),
            .expression, .text => {},
        }
    }

    for (tags.items) |frame| {
        const pos = idx.lineCol(frame.off);
        if (frame.tag.len == 0) {
            try list.err(idx, src_name, frame.off, 2, .unclosed_tag, "<> fragment never closed at line {d}", .{pos.line});
        } else {
            try list.err(idx, src_name, frame.off, 1 + frame.tag.len, .unclosed_tag, "<{s}> never closed", .{frame.tag});
        }
    }
    for (ctrls.items) |frame| {
        try list.err(idx, src_name, frame.off, 1 + 1 + scan.ctrlName(frame.kind).len, .unclosed_ctrl, "{{{s}}} never closed", .{scan.ctrlName(frame.kind)});
    }
}

/// Class warnings, one per unknown token in a `class="..."` attribute.
fn checkClasses(idx: diag.LineIndex, src_name: []const u8, ot: scan.OpenTag, list: *diag.List) !void {
    for (ot.attrs) |attr| {
        if (!std.mem.eql(u8, attr.name, "class")) continue;
        switch (attr.value) {
            .string => |v| {
                var it = std.mem.tokenizeScalar(u8, v, ' ');
                while (it.next()) |cls| {
                    if (cls.len == 0) continue;
                    if (!style.isKnownClass(cls)) {
                        try list.warn(idx, src_name, attr.off, attr.name.len + 1 + v.len + 2, .unknown_class, "unknown class '{s}' (will error at build)", .{cls});
                    }
                }
            },
            else => {},
        }
    }
}

fn midName(k: scan.MidKind) []const u8 {
    return switch (k) {
        .else_ => "else",
        .case_ => "case",
    };
}

fn legacyName(k: scan.CtrlKind) []const u8 {
    return switch (k) {
        .if_ => "endif",
        .for_ => "endfor",
        .switch_ => "endswitch",
    };
}
