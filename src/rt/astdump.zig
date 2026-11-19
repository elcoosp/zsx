//! Reviewable dump of the lowered AST (M1 WP 1.5).
//!
//! The CST keeps spans and recovery nodes; codegen consumes a flat `ast`
//! tree with control-flow markers as siblings. These dumps pin that flat
//! shape for `spec/ast/*.txt` and let the formatter prove
//! `parse(fmt(x)) ≅ parse(x)` without comparing raw whitespace.

const std = @import("std");
const ast = @import("parser.zig");

/// Full dump: every child, including whitespace-only text.
pub fn dump(a: std.mem.Allocator, el: ast.Element) ![]u8 {
    return dumpOpt(a, el, false);
}

/// Structural dump: whitespace-only text children are dropped. Formatter
/// indentation changes only those, so equality means formatting preserved
/// the tree.
pub fn dumpNormalized(a: std.mem.Allocator, el: ast.Element) ![]u8 {
    return dumpOpt(a, el, true);
}

fn dumpOpt(a: std.mem.Allocator, el: ast.Element, skip_ws: bool) ![]u8 {
    var out = std.array_list.Managed(u8).init(a);
    try dumpElement(a, &out, el, 0, skip_ws);
    return out.toOwnedSlice();
}

fn indent(out: *std.array_list.Managed(u8), depth: usize) !void {
    for (0..depth) |_| try out.appendSlice("  ");
}

fn escape(out: *std.array_list.Managed(u8), s: []const u8) !void {
    for (s) |c| switch (c) {
        '\n' => try out.appendSlice("\\n"),
        '\r' => try out.appendSlice("\\r"),
        '\t' => try out.appendSlice("\\t"),
        '"' => try out.appendSlice("\\\""),
        '\\' => try out.appendSlice("\\\\"),
        else => try out.append(c),
    };
}

fn dumpElement(
    a: std.mem.Allocator,
    out: *std.array_list.Managed(u8),
    el: ast.Element,
    depth: usize,
    skip_ws: bool,
) !void {
    try indent(out, depth);
    if (el.tag.len == 0) {
        try out.appendSlice("fragment\n");
    } else {
        try out.appendSlice(try std.fmt.allocPrint(a, "element {s}\n", .{el.tag}));
    }
    for (el.attributes) |at| {
        try indent(out, depth + 1);
        switch (at.value) {
            .boolean => try out.appendSlice(try std.fmt.allocPrint(a, "attr {s} boolean\n", .{at.name})),
            .string => |v| {
                try out.appendSlice(try std.fmt.allocPrint(a, "attr {s} string ", .{at.name}));
                try escape(out, v);
                try out.append('\n');
            },
            .expression => |v| try out.appendSlice(try std.fmt.allocPrint(a, "attr {s} expr {s}\n", .{ at.name, v })),
        }
    }
    for (el.children) |c| switch (c) {
        .element => |child| try dumpElement(a, out, child, depth + 1, skip_ws),
        .expression => |e| {
            try indent(out, depth + 1);
            try out.appendSlice(try std.fmt.allocPrint(a, "expr {s}\n", .{e}));
        },
        .text => |t| {
            if (skip_ws and std.mem.trim(u8, t, " \t\r\n").len == 0) continue;
            try indent(out, depth + 1);
            try out.appendSlice("text \"");
            try escape(out, t);
            try out.appendSlice("\"\n");
        },
    };
}
