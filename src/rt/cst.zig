//! Markup CST parser with error recovery (master-plan WP 1.3, first slice).
//!
//! Unlike `parser.zig` (fail-fast, one root, no diagnostics), this parser
//! consumes the tolerant scanner's tokens and always returns a tree plus
//! diagnostics. It is the shape the formatter, checker and LSP will share:
//! every token lands in a node, spans stay absolute, and a bad construct
//! yields an `error_token` node while parsing continues.
//!
//! The tree is intentionally structural, not semantic: attributes stay on
//! their open-tag node, `{:else}`/`{:case}` are branch markers inside their
//! control node, and a mismatch unwinds to the nearest matching opener,
//! reporting every opener it implicitly closes. Semantic rules (unknown
//! props, classes, root shape) remain in `checker.zig` for now.

const std = @import("std");
const diag = @import("diag.zig");
const scan = @import("scan.zig");
const ast = @import("parser.zig");

pub const Span = struct { off: usize, end: usize };

pub const Kind = enum {
    block,
    element,
    fragment,
    text,
    expression,
    control_if,
    control_for,
    control_switch,
    branch,
    control_close,
    error_token,
};

pub const Node = struct {
    kind: Kind,
    span: Span,
    /// Element tag (`""` for fragments, `""` for non-elements).
    tag: []const u8 = "",
    attrs: []const scan.Attr = &.{},
    children: []const Node = &.{},
    /// Original token bytes (braces included) for leaves/control markers.
    raw: []const u8 = "",
};

const Frame = struct {
    kind: Kind,
    tag: []const u8 = "",
    attrs: []const scan.Attr = &.{},
    raw: []const u8 = "",
    start: usize,
    children: std.array_list.Managed(Node),
};

fn frameKind(t: scan.Token) ?Kind {
    return switch (t) {
        .open_tag => |ot| if (ot.tag.len == 0) .fragment else .element,
        .ctrl_open => |co| switch (co.kind) {
            .if_ => .control_if,
            .for_ => .control_for,
            .switch_ => .control_switch,
        },
        else => null,
    };
}

fn ctrlFrameKind(k: scan.CtrlKind) Kind {
    return switch (k) {
        .if_ => .control_if,
        .for_ => .control_for,
        .switch_ => .control_switch,
    };
}

fn ctrlKindOf(k: Kind) scan.CtrlKind {
    return switch (k) {
        .control_if => .if_,
        .control_for => .for_,
        .control_switch => .switch_,
        else => unreachable,
    };
}

const Parser = struct {
    a: std.mem.Allocator,
    src_name: []const u8,
    idx: diag.LineIndex,
    list: *diag.List,
    toks: []const scan.Token,
    stack: std.array_list.Managed(Frame),
    src: []const u8,
    base: usize,

    fn err(self: *Parser, span: Span, code: diag.Code, comptime fmt: []const u8, args: anytype) !void {
        try self.list.err(self.idx, self.src_name, span.off, span.end - span.off, code, fmt, args);
    }

    fn finish(f: *Frame, end: usize) !Node {
        return .{
            .kind = f.kind,
            .span = .{ .off = f.start, .end = end },
            .tag = f.tag,
            .attrs = f.attrs,
            .children = try f.children.toOwnedSlice(),
            .raw = f.raw,
        };
    }

    /// Pop frames down to (and including) `target`. Returns the finalized
    /// target; every frame above it is reported as unclosed.
    fn lastChildEnd(f: *const Frame) usize {
        var end = f.start;
        for (f.children.items) |c| end = @max(end, c.span.end);
        return end;
    }

    fn unwindTo(self: *Parser, target: usize, close_end: usize) !Node {
        return self.closeFrame(target, close_end, null);
    }

    fn closeFrame(self: *Parser, target: usize, close_end: usize, extra: ?Node) !Node {
        while (self.stack.items.len - 1 > target) {
            var f = self.stack.pop().?;
            try self.reportUnclosed(&f);
            const node = try finish(&f, lastChildEnd(&f));
            try self.appendToTop(node);
        }
        var f = self.stack.pop().?;
        if (extra) |e| try f.children.append(e);
        return finish(&f, close_end);
    }

    fn reportUnclosed(self: *Parser, f: *const Frame) !void {
        const span = Span{ .off = f.start, .end = f.start };
        switch (f.kind) {
            .element => try self.err(span, .unclosed_tag, "<{s}> never closed", .{f.tag}),
            .fragment => try self.err(span, .unclosed_tag, "<> fragment never closed", .{}),
            .control_if => try self.err(span, .unclosed_ctrl, "{{if}} never closed", .{}),
            .control_for => try self.err(span, .unclosed_ctrl, "{{for}} never closed", .{}),
            .control_switch => try self.err(span, .unclosed_ctrl, "{{switch}} never closed", .{}),
            else => {},
        }
    }

    fn appendToTop(self: *Parser, node: Node) !void {
        try self.stack.items[self.stack.items.len - 1].children.append(node);
    }

    fn rawOf(self: *Parser, t: scan.Token) []const u8 {
        return self.src[t.off() - self.base .. t.end() - self.base];
    }

    fn push(self: *Parser, kind: Kind, tag: []const u8, attrs: []const scan.Attr, raw: []const u8, start: usize) !void {
        try self.stack.append(.{
            .kind = kind,
            .tag = tag,
            .attrs = attrs,
            .raw = raw,
            .start = start,
            .children = std.array_list.Managed(Node).init(self.a),
        });
    }

    fn run(self: *Parser) !Node {
        for (self.toks) |t| {
            switch (t) {
                .open_tag => |ot| {
                    const kind: Kind = if (ot.tag.len == 0) .fragment else .element;
                    if (ot.self_closing) {
                        try self.appendToTop(.{
                            .kind = kind,
                            .span = .{ .off = ot.off, .end = ot.end },
                            .tag = ot.tag,
                            .attrs = ot.attrs,
                        });
                    } else {
                        try self.push(kind, ot.tag, ot.attrs, self.rawOf(t), ot.off);
                    }
                },
                .close_tag => |ct| {
                    var match: ?usize = null;
                    var i: usize = self.stack.items.len;
                    while (i > 1) {
                        i -= 1;
                        const f = self.stack.items[i];
                        if (f.kind == .element or f.kind == .fragment) {
                            if (std.mem.eql(u8, f.tag, ct.tag)) {
                                match = i;
                                break;
                            }
                        }
                    }
                    if (match) |m| {
                        const node = try self.unwindTo(m, ct.end);
                        try self.appendToTop(node);
                    } else {
                        try self.err(.{ .off = ct.off, .end = ct.end }, .stray_close_tag, "</{s}> with no open tag", .{ct.tag});
                        try self.appendToTop(.{ .kind = .error_token, .span = .{ .off = ct.off, .end = ct.end }, .raw = self.rawOf(t) });
                    }
                },
                .ctrl_open => |co| {
                    try self.push(ctrlFrameKind(co.kind), "", &.{}, self.rawOf(t), co.off);
                },
                .ctrl_mid => |cm| {
                    var top_ctrl: ?usize = null;
                    var i: usize = self.stack.items.len;
                    while (i > 1) {
                        i -= 1;
                        const k = self.stack.items[i].kind;
                        if (k == .control_if or k == .control_for or k == .control_switch) {
                            top_ctrl = i;
                            break;
                        }
                    }
                    if (top_ctrl == null) {
                        try self.err(.{ .off = cm.off, .end = cm.end }, switch (cm.kind) {
                            .else_ => .misplaced_else,
                            .case_ => .misplaced_case,
                        }, "{{:{s}}} at top level (no open {{if}}/{{for}}/{{switch}})", .{switch (cm.kind) {
                            .else_ => "else",
                            .case_ => "case",
                        }});
                    } else {
                        const k = self.stack.items[top_ctrl.?].kind;
                        switch (cm.kind) {
                            .else_ => if (k != .control_if and k != .control_switch) {
                                try self.err(.{ .off = cm.off, .end = cm.end }, .misplaced_else, "{{:else}} inside {{{s}}}", .{switch (k) {
                                    .control_for => "for",
                                    else => "?",
                                }});
                            },
                            .case_ => if (k != .control_switch) {
                                try self.err(.{ .off = cm.off, .end = cm.end }, .misplaced_case, "{{:case}} outside {{switch}}", .{});
                            },
                        }
                    }
                    try self.appendToTop(.{ .kind = .branch, .span = .{ .off = cm.off, .end = cm.end }, .raw = self.rawOf(t) });
                },
                .ctrl_close => |cc| {
                    const want = ctrlFrameKind(cc.kind);
                    var match: ?usize = null;
                    var i: usize = self.stack.items.len;
                    while (i > 1) {
                        i -= 1;
                        const k = self.stack.items[i].kind;
                        if (k == .control_if or k == .control_for or k == .control_switch) {
                            match = i;
                            break;
                        }
                    }
                    if (match) |m| {
                        if (self.stack.items[m].kind != want) {
                            try self.err(.{ .off = cc.off, .end = cc.end }, .ctrl_mismatch, "{{/{s}}} closes {{{s}}}", .{
                                scan.ctrlName(cc.kind), scan.ctrlName(ctrlKindOf(self.stack.items[m].kind)),
                            });
                        }
                        const node = try self.closeFrame(m, cc.end, .{
                            .kind = .control_close,
                            .span = .{ .off = cc.off, .end = cc.end },
                            .raw = self.rawOf(t),
                        });
                        try self.appendToTop(node);
                    } else {
                        try self.err(.{ .off = cc.off, .end = cc.end }, .stray_ctrl_close, "{{/{s}}} with no matching opener", .{scan.ctrlName(cc.kind)});
                        try self.appendToTop(.{ .kind = .error_token, .span = .{ .off = cc.off, .end = cc.end }, .raw = self.rawOf(t) });
                    }
                },
                .expression => |ex| try self.appendToTop(.{ .kind = .expression, .span = .{ .off = ex.off, .end = ex.end }, .raw = self.rawOf(t) }),
                .text => |tx| try self.appendToTop(.{ .kind = .text, .span = .{ .off = tx.off, .end = tx.end }, .raw = tx.raw }),
                .junk => |j| {
                    try self.err(.{ .off = j.off, .end = j.end }, .junk_syntax, "{s}", .{j.msg});
                    try self.appendToTop(.{ .kind = .error_token, .span = .{ .off = j.off, .end = j.end }, .raw = self.rawOf(t) });
                },
            }
        }

        // Close whatever is still open, innermost first; the block frame is
        // index 0 and gets no diagnostic.
        const block_end = self.stack.items[0].start;
        while (self.stack.items.len > 1) {
            var f = self.stack.pop().?;
            try self.reportUnclosed(&f);
            const node = try finish(&f, lastChildEnd(&f));
            try self.appendToTop(node);
        }
        var block = self.stack.pop().?;
        return finish(&block, block_end);
    }
};

/// Parse one markup block. `base` is the absolute file offset of `markup[0]`.
/// Always returns a `block` root; diagnostics accumulate in `list`.
pub fn parse(a: std.mem.Allocator, markup: []const u8, base: usize, src_name: []const u8, idx: diag.LineIndex, list: *diag.List) !Node {
    var scanner = scan.Scanner.init(a, markup, base);
    const toks = try scanner.run();
    var stack = std.array_list.Managed(Frame).init(a);
    try stack.append(.{
        .kind = .block,
        .start = base,
        .children = std.array_list.Managed(Node).init(a),
    });
    var p = Parser{
        .a = a,
        .src_name = src_name,
        .idx = idx,
        .list = list,
        .toks = toks,
        .stack = stack,
        .src = markup,
        .base = base,
    };
    // `finish` needs the block end before the frame is popped.
    p.stack.items[0].start = base;
    var root = try p.run();
    root.span.end = base + markup.len;
    return root;
}

/// Structural invariant for tests/tools: children are ordered, non-overlapping
/// and contained in their parent (tag delimiters are not children).
pub fn spansAreOrdered(node: Node) bool {
    var cursor = node.span.off;
    for (node.children) |c| {
        if (c.span.off < cursor or c.span.end > node.span.end or c.span.end < c.span.off) return false;
        cursor = c.span.end;
    }
    return true;
}

/// Recursive form of `spansAreOrdered`, used by corpus tests.
pub fn treeIsOrdered(node: Node) bool {
    if (!spansAreOrdered(node)) return false;
    for (node.children) |c| if (!treeIsOrdered(c)) return false;
    return true;
}

pub const LowerError = error{
    NoRoot,
    MultipleRoots,
    StrayTopLevel,
    ErrorToken,
    OutOfMemory,
};

fn inner(raw: []const u8) []const u8 {
    if (raw.len >= 2 and raw[0] == '{' and raw[raw.len - 1] == '}') return raw[1 .. raw.len - 1];
    return raw;
}

/// Lower a parsed block to the AST codegen consumes (M1 WP 1.5 slice).
///
/// The compiler path calls this after `parse`; recovery/error nodes are
/// rejected here because codegen cannot emit them. Whitespace-only top-level
/// text is ignored; exactly one element or fragment root is required.
pub fn lowerBlock(a: std.mem.Allocator, block: Node) LowerError!ast.Element {
    if (block.kind != .block) return error.ErrorToken;
    var found: ?Node = null;
    for (block.children) |c| switch (c.kind) {
        .text => if (std.mem.trim(u8, c.raw, " \t\r\n").len != 0) return error.StrayTopLevel,
        .element, .fragment => {
            if (found != null) return error.MultipleRoots;
            found = c;
        },
        else => return error.StrayTopLevel,
    };
    const root = found orelse return error.NoRoot;
    return lowerElement(a, root);
}

fn lowerElement(a: std.mem.Allocator, node: Node) LowerError!ast.Element {
    var attrs = std.array_list.Managed(ast.Attribute).init(a);
    try attrs.ensureTotalCapacity(node.attrs.len);
    for (node.attrs) |at| {
        attrs.appendAssumeCapacity(.{
            .name = at.name,
            .value = switch (at.value) {
                .boolean => .boolean,
                .string => |v| .{ .string = v },
                .expression => |v| .{ .expression = v },
            },
        });
    }

    var children = std.array_list.Managed(ast.Child).init(a);
    for (node.children) |c| try appendChild(a, &children, c);
    return .{ .tag = node.tag, .attributes = try attrs.toOwnedSlice(), .children = try children.toOwnedSlice() };
}

/// Flatten control-flow nodes into the marker/content stream codegen expects:
/// opener expression, children, branch/close markers — all as siblings.
fn appendChild(a: std.mem.Allocator, out: *std.array_list.Managed(ast.Child), node: Node) LowerError!void {
    switch (node.kind) {
        .element, .fragment => try out.append(.{ .element = try lowerElement(a, node) }),
        .text => try out.append(.{ .text = node.raw }),
        .expression, .branch, .control_close => try out.append(.{ .expression = inner(node.raw) }),
        .control_if, .control_for, .control_switch => {
            try out.append(.{ .expression = inner(node.raw) });
            for (node.children) |c| try appendChild(a, out, c);
        },
        .error_token, .block => return error.ErrorToken,
    }
}

test "cst: nested elements, attributes and text keep spans" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "<column class=\"gap-2\"><label>Hi</label></column>";
    const idx = try diag.LineIndex.build(a, src);
    var list = diag.List.init(a);
    const root = try parse(a, src, 0, "t.zsx", idx, &list);
    try std.testing.expectEqual(@as(usize, 0), list.count());
    try std.testing.expectEqual(Kind.block, root.kind);
    try std.testing.expectEqual(@as(usize, 1), root.children.len);
    const column = root.children[0];
    try std.testing.expectEqualStrings("column", column.tag);
    try std.testing.expectEqual(@as(usize, 1), column.attrs.len);
    try std.testing.expectEqual(@as(usize, 1), column.children.len);
    try std.testing.expectEqualStrings("label", column.children[0].tag);
    try std.testing.expect(spansAreOrdered(root));
    try std.testing.expect(spansAreOrdered(column));
}

test "cst: mismatch unwinds and reports both ends" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "<column><row>x</row></column>";
    const idx = try diag.LineIndex.build(a, src);
    var list = diag.List.init(a);
    const root = try parse(a, src, 0, "t.zsx", idx, &list);
    try std.testing.expectEqual(@as(usize, 0), list.count());
    try std.testing.expectEqual(@as(usize, 1), root.children.len);
}

test "cst: recovery keeps later siblings parseable" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "<column></row><label>after</label></column>";
    const idx = try diag.LineIndex.build(a, src);
    var list = diag.List.init(a);
    const root = try parse(a, src, 0, "t.zsx", idx, &list);
    try std.testing.expect(list.count() >= 1);
    try std.testing.expectEqual(diag.Code.stray_close_tag, list.items.items[0].code);
    const column = root.children[0];
    var saw_label = false;
    for (column.children) |c| {
        if (c.kind == .element and std.mem.eql(u8, c.tag, "label")) saw_label = true;
    }
    try std.testing.expect(saw_label);
}

test "cst: control flow becomes nested frames and branches" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "<>{if ctx.a}<label>A</label>{:else}<label>B</label>{/if}</>";
    const idx = try diag.LineIndex.build(a, src);
    var list = diag.List.init(a);
    const root = try parse(a, src, 0, "t.zsx", idx, &list);
    try std.testing.expectEqual(@as(usize, 0), list.count());
    const frag = root.children[0];
    try std.testing.expectEqual(Kind.fragment, frag.kind);
    try std.testing.expectEqual(@as(usize, 1), frag.children.len);
    const ifnode = frag.children[0];
    try std.testing.expectEqual(Kind.control_if, ifnode.kind);
    var branches: usize = 0;
    for (ifnode.children) |c| if (c.kind == .branch) {
        branches += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), branches);
}

test "cst: junk token becomes an error node and parsing continues" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "< label>x</label>";
    const idx = try diag.LineIndex.build(a, src);
    var list = diag.List.init(a);
    const root = try parse(a, src, 0, "t.zsx", idx, &list);
    try std.testing.expect(list.count() >= 1);
    try std.testing.expectEqual(diag.Code.junk_syntax, list.items.items[0].code);
    var saw_error = false;
    for (root.children) |c| if (c.kind == .error_token) {
        saw_error = true;
    };
    try std.testing.expect(saw_error);
}

test "cst: lowering produces the AST codegen expects" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "<>{for items as item}<label>{item}</label>{/for}</>";
    const idx = try diag.LineIndex.build(a, src);
    var list = diag.List.init(a);
    const root = try parse(a, src, 0, "t.zsx", idx, &list);
    const el = try lowerBlock(a, root);
    try std.testing.expectEqualStrings("", el.tag);
    try std.testing.expectEqual(@as(usize, 3), el.children.len);
    try std.testing.expect(el.children[0] == .expression);
    try std.testing.expectEqualStrings("for items as item", el.children[0].expression);
    try std.testing.expect(el.children[1] == .element);
    try std.testing.expectEqualStrings("/for", el.children[2].expression);
}

test "cst: unclosed frames end at their last child and stay ordered" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "<Card>{for ctx.items as item}<label>x</labl>{/for}</Card>";
    const idx = try diag.LineIndex.build(a, src);
    var list = diag.List.init(a);
    const root = try parse(a, src, 0, "t.zsx", idx, &list);
    try std.testing.expect(treeIsOrdered(root));
}

test "cst: control closer is ordered after unwinding inner frames" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = "<Card>{for ctx.items as item}<label>{item}</labl>{/for}</Card>";
    const idx = try diag.LineIndex.build(a, src);
    var list = diag.List.init(a);
    const root = try parse(a, src, 0, "t.zsx", idx, &list);
    try std.testing.expect(treeIsOrdered(root));
}
