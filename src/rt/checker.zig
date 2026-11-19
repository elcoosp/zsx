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
/// Lossless front-end (M1 slice): one string-, char- and comment-aware pass
/// partitions a `.zsx` file into typed byte-exact segments, and
/// `lossless.Document.render` re-emits the source byte-for-byte (spikes S1 +
/// S2). The block scanner `preprocess.findBlocks` delegates to. Same barrel,
/// same one-file-one-module reason; see `lossless.zig`.
pub const lossless = @import("lossless.zig");
/// Code-frame renderer (M1 slice): turns a `diag.Diagnostic` plus the checked
/// source into the annotated snippet a developer reads. Same barrel, same
/// one-file-one-module reason; see `render.zig`.
pub const render = @import("render.zig");
const style = @import("style.zig");
const registry = @import("registry.zig");

pub const Options = struct {
    /// Warn on class tokens the built-in resolver does not know. Disable with
    /// `zsx check --no-class-check` (same flag the Python tool accepted).
    check_classes: bool = true,
    /// Error on props the built-in component registry does not accept (F7).
    /// Disable with `zsx check --no-prop-check`.
    check_props: bool = true,
    /// Enforce RFC-0001 S1: exactly one root element per block, with no text,
    /// expressions or control flow at the block top level. `checkSource`
    /// turns this on; `checkMarkup` leaves it off so callers can validate
    /// detached fragments (formatter previews, slot bodies, LSP ranges).
    require_single_root: bool = false,
    /// Run the lint pass (WP 1.7): unused loop bindings, empty loop bodies,
    /// text directly inside layout containers. Warnings only.
    check_lints: bool = true,
};

const TagFrame = struct {
    tag: []const u8,
    off: usize,
};

const CtrlFrame = struct {
    kind: scan.CtrlKind,
    off: usize,
    /// `{for … as name}` lint state (WP 1.7).
    binding: ?[]const u8 = null,
    binding_off: usize = 0,
    opener_len: usize = 0,
    used: bool = false,
    has_content: bool = false,
};

/// Check a whole `.zsx` source: find `zsx!{ }` blocks and validate the markup
/// in each. Diagnostics accumulate into `list` (callers own rendering).
pub fn checkSource(a: std.mem.Allocator, source: []const u8, src_name: []const u8, opts: Options, list: *diag.List) !void {
    const idx = try diag.LineIndex.build(a, source);
    const blocks = try preprocess.findBlocks(a, source);
    const first = list.count();
    for (blocks) |block| {
        if (!block.closed) {
            try list.err(idx, src_name, block.start, 5, .unterminated_block, "zsx!{{ block is never closed: no matching '}}' before end of file", .{});
            continue;
        }
        // markup body: between "zsx!{" (5 bytes) and the matching "}".
        const markup = source[block.start + 5 .. block.end - 1];
        var block_opts = opts;
        block_opts.require_single_root = true;
        try checkMarkup(a, markup, block.start + 5, idx, src_name, block_opts, list);
    }
    // `// zsx-ignore ZSX0020[, …]` on the line directly above `zsx!{`
    // suppresses matching warnings for that block.
    var i = first;
    while (i < list.count()) {
        const d = list.items.items[i];
        if (d.severity == .warning and ignoredByDirective(source, blocks, d.offset, d.code)) {
            _ = list.items.orderedRemove(i);
        } else i += 1;
    }
}

fn ignoredByDirective(source: []const u8, blocks: []const preprocess.Block, off: usize, code: diag.Code) bool {
    for (blocks) |b| {
        if (off < b.start or off >= b.end) continue;
        const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..b.start], '\n')) |nl| nl + 1 else 0;
        if (line_start == 0) return false;
        const prev_end = line_start - 1;
        const prev_start = if (std.mem.lastIndexOfScalar(u8, source[0..prev_end], '\n')) |nl| nl + 1 else 0;
        const line = std.mem.trim(u8, source[prev_start..prev_end], " \t\r");
        if (!std.mem.startsWith(u8, line, "// zsx-ignore")) return false;
        var it = std.mem.tokenizeAny(u8, line["// zsx-ignore".len..], " ,\t");
        while (it.next()) |tok| {
            if (std.mem.startsWith(u8, tok, "ZSX")) {
                const n = std.fmt.parseInt(u16, tok[3..], 10) catch continue;
                if (n == code.number()) return true;
            } else if (std.mem.eql(u8, tok, code.name())) return true;
        }
        return false;
    }
    return false;
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
    var roots: usize = 0;
    var saw_top_level = false;

    for (toks) |t| {
        const at_top = tags.items.len == 0 and ctrls.items.len == 0;
        switch (t) {
            .open_tag => |ot| {
                if (opts.require_single_root and at_top) {
                    roots += 1;
                    if (roots > 1) {
                        try list.err(idx, src_name, ot.off, ot.end - ot.off, .multiple_roots, "second root element; a zsx!{{ block has exactly one root (wrap siblings in a <> fragment)", .{});
                    }
                }
                if (opts.check_classes) try checkClasses(idx, src_name, ot, list);
                if (opts.check_props) try checkProps(a, idx, src_name, ot, list);
                if (opts.check_lints) {
                    markContent(ctrls.items);
                    for (ot.attrs) |attr| switch (attr.value) {
                        .expression => |v| markUses(a, ctrls.items, v),
                        else => {},
                    };
                }
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
                if (opts.check_lints) markContent(ctrls.items);
            },
            .ctrl_open => |co| {
                if (opts.check_lints) {
                    markContent(ctrls.items);
                    markUses(a, ctrls.items, markup[t.off() - base .. t.end() - base]);
                }
                var frame = CtrlFrame{ .kind = co.kind, .off = co.off, .opener_len = t.end() - t.off() };
                if (co.kind == .for_) {
                    if (forBinding(a, markup[t.off() - base .. t.end() - base])) |b| {
                        frame.binding = b.name;
                        frame.binding_off = t.off() + b.rel;
                    }
                }
                try ctrls.append(frame);
            },
            .ctrl_mid => |cm| {
                if (ctrls.items.len == 0) {
                    try list.err(idx, src_name, cm.off, cm.end - cm.off, switch (cm.kind) {
                        .else_ => .misplaced_else,
                        .case_ => .misplaced_case,
                    }, "{{:{s}}} at top level (no open {{{s}}})", .{ midName(cm.kind), "if/for/switch" });
                    continue;
                }
                if (opts.check_lints) {
                    markContent(ctrls.items);
                    markUses(a, ctrls.items, markup[t.off() - base .. t.end() - base]);
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
                } else if (opts.check_lints and frame.kind == .for_) {
                    try lintForFrame(idx, src_name, frame, list);
                }
            },
            .junk => |j| try list.err(idx, src_name, j.off, j.end - j.off, .junk_syntax, "{s}", .{j.msg}),
            .expression => |ex| {
                if (opts.check_lints) {
                    markContent(ctrls.items);
                    markUses(a, ctrls.items, ex.raw);
                }
                if (opts.require_single_root and at_top) {
                    saw_top_level = true;
                    try list.err(idx, src_name, ex.off, ex.end - ex.off, .stray_top_level, "expression at block top level; put it inside the root element", .{});
                }
            },
            .text => |tx| {
                if (std.mem.trim(u8, tx.raw, " \t\r\n").len != 0) {
                    if (opts.check_lints) {
                        markContent(ctrls.items);
                        if (tags.items.len != 0) {
                            const top_tag = tags.items[tags.items.len - 1];
                            if (std.mem.eql(u8, top_tag.tag, "column")) {
                                try list.warn(idx, src_name, tx.off, tx.end - tx.off, .text_in_layout_container, "text directly inside <column> is not rendered; wrap it in <label>", .{});
                            }
                        }
                    }
                    if (opts.require_single_root and at_top) {
                        saw_top_level = true;
                        try list.err(idx, src_name, tx.off, tx.end - tx.off, .stray_top_level, "text at block top level; put it inside the root element", .{});
                    }
                }
            },
        }
        if (opts.require_single_root and at_top and t == .ctrl_open) {
            saw_top_level = true;
            try list.err(idx, src_name, t.off(), t.end() - t.off(), .stray_top_level, "control flow at block top level; put it inside the root element", .{});
        }
    }

    if (opts.require_single_root and roots == 0 and !saw_top_level) {
        try list.err(idx, src_name, base, 0, .missing_root, "block has no root element", .{});
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

/// Unknown-prop errors for built-in components (F7): a typo such as
/// `varient="x"` becomes an error with a did-you-mean suggestion instead of a
/// silent no-op. User components are skipped (the registry only lists built-ins).
fn checkProps(a: std.mem.Allocator, idx: diag.LineIndex, src_name: []const u8, ot: scan.OpenTag, list: *diag.List) !void {
    const comp = registry.find(ot.tag) orelse return;
    for (ot.attrs) |attr| {
        if (registry.accepts(comp, attr.name)) continue;
        if (registry.suggest(comp, attr.name)) |suggestion| {
            const help = try std.fmt.allocPrint(a, "did you mean `{s}`?", .{suggestion});
            try list.errHelp(idx, src_name, attr.off, attr.name.len, .unknown_prop, "unknown prop '{s}' on <{s}>", .{ attr.name, ot.tag }, help);
        } else {
            try list.err(idx, src_name, attr.off, attr.name.len, .unknown_prop, "unknown prop '{s}' on <{s}>", .{ attr.name, ot.tag });
        }
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

const ForBinding = struct { name: []const u8, rel: usize };

/// First identifier bound by `as` in a `{for … as name}` opener.
fn forBinding(a: std.mem.Allocator, raw: []const u8) ?ForBinding {
    const z = a.allocSentinel(u8, raw.len, 0) catch return null;
    @memcpy(z, raw);
    var tk = std.zig.Tokenizer.init(z);
    var after_as = false;
    while (true) {
        const t = tk.next();
        if (t.tag == .eof) return null;
        if (after_as) {
            if (t.tag == .identifier) return .{ .name = raw[t.loc.start..t.loc.end], .rel = t.loc.start };
            return null;
        }
        if (t.tag == .identifier and std.mem.eql(u8, raw[t.loc.start..t.loc.end], "as")) after_as = true;
    }
}

fn markContent(frames: []CtrlFrame) void {
    for (frames) |*f| f.has_content = true;
}

fn markUses(a: std.mem.Allocator, frames: []CtrlFrame, hay: []const u8) void {
    if (frames.len == 0) return;
    const z = a.allocSentinel(u8, hay.len, 0) catch return;
    @memcpy(z, hay);
    var tk = std.zig.Tokenizer.init(z);
    while (true) {
        const t = tk.next();
        if (t.tag == .eof) return;
        if (t.tag != .identifier) continue;
        const id = hay[t.loc.start..t.loc.end];
        for (frames) |*f| {
            if (f.used) continue;
            if (f.binding) |name| {
                if (std.mem.eql(u8, id, name)) f.used = true;
            }
        }
    }
}

fn lintForFrame(idx: diag.LineIndex, src_name: []const u8, frame: CtrlFrame, list: *diag.List) !void {
    if (!frame.has_content) {
        try list.warn(idx, src_name, frame.off, frame.opener_len, .empty_for_body, "{{for}} has an empty body; add content or remove the loop", .{});
    }
    const name = frame.binding orelse return;
    if (name.len == 0 or name[0] == '_' or frame.used) return;
    try list.warn(idx, src_name, frame.binding_off, name.len, .unused_binding, "loop binding '{s}' is never used in the body", .{name});
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
