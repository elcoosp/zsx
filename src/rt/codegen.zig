const std = @import("std");
const ast = @import("parser.zig");
const style = @import("style.zig");

fn writeFmt(a: std.mem.Allocator, out: *std.array_list.Managed(u8), comptime fmt: []const u8, args: anytype) !void {
    try out.appendSlice(try std.fmt.allocPrint(a, fmt, args));
}
fn usesParam(code: []const u8, name: []const u8) bool {
    if (std.mem.indexOf(u8, code, name ++ ".") != null) return true;
    if (std.mem.indexOf(u8, code, name ++ ",") != null) return true;
    if (std.mem.indexOf(u8, code, name ++ ")") != null) return true;
    if (std.mem.indexOf(u8, code, name ++ " ") != null) return true;
    if (std.mem.indexOf(u8, code, "(" ++ name) != null) return true;
    if (std.mem.indexOf(u8, code, "," ++ name) != null) return true;
    return false;
}

fn discardPrefix(a: std.mem.Allocator, code: []const u8) ![]const u8 {
    var out = std.array_list.Managed(u8).init(a);
    if (!usesParam(code, "ui")) try out.appendSlice("    _ = ui;\n");
    if (!usesParam(code, "c")) try out.appendSlice("    _ = c;\n");
    if (!usesParam(code, "ctx")) try out.appendSlice("    _ = ctx;\n");
    return try out.toOwnedSlice();
}


pub const FILE_STRIDE: usize = 10_000_000_000_000;
pub const LOOP_STRIDE_0: usize = 1_000_000;
pub const LOOP_STRIDE_1: usize = 1_000_000_000;
pub const BLOCK_STRIDE: usize = 10_000;

const EmitResult = struct {
    code: []const u8,
    preamble: []const u8,
    next_id: usize,
};

const Emitter = struct {
    a: std.mem.Allocator,
    file_index: usize,
    block_index: usize,
    preamble: std.array_list.Managed(u8),

    fn init(a: std.mem.Allocator, file_index: usize, block_index: usize) Emitter {
        return .{ .a = a, .file_index = file_index, .block_index = block_index, .preamble = std.array_list.Managed(u8).init(a) };
    }
    fn deinit(self: *Emitter) void { self.preamble.deinit(); }

    fn fileBase(self: *const Emitter) usize {
        return self.file_index * BLOCK_STRIDE + self.block_index;
    }

    fn idExpr(self: *Emitter, base: usize, loop_depth: usize) ![]const u8 {
        const real = self.fileBase() * FILE_STRIDE + base;
        if (loop_depth == 0) return std.fmt.allocPrint(self.a, "{d}", .{real});
        var out = std.array_list.Managed(u8).init(self.a);
        try writeFmt(self.a, &out, "{d} + idx_0 * {d}", .{ real, LOOP_STRIDE_0 });
        var j: usize = 1;
        var stride: usize = LOOP_STRIDE_1;
        while (j < loop_depth) : (j += 1) {
            try writeFmt(self.a, &out, " + idx_{d} * {d}", .{ j, stride });
            stride *= 1000;
        }
        return out.toOwnedSlice();
    }

    fn escapeString(self: *Emitter, s: []const u8) ![]const u8 {
        var out = std.array_list.Managed(u8).init(self.a);
        for (s) |ch| {
            switch (ch) {
                '"' => try out.appendSlice("\\\""),
                '\\' => try out.appendSlice("\\\\"),
                '\n' => try out.appendSlice("\\n"),
                '\r' => try out.appendSlice("\\r"),
                '\t' => try out.appendSlice("\\t"),
                else => if (ch >= 0x20 and ch < 0x7f) try out.append(ch) else {
                    try writeFmt(self.a, &out, "\\x{x:0>2}", .{ch});
                },
            }
        }
        return out.toOwnedSlice();
    }

    fn isWs(c: u8) bool { return c == ' ' or c == '\t' or c == '\n' or c == '\r'; }
    fn isWhitespaceOnly(s: []const u8) bool { for (s) |c| if (!isWs(c)) return false; return true; }
    fn isUpper(c: u8) bool { return c >= 'A' and c <= 'Z'; }

    fn hasElementChildren(el: ast.Element) bool {
        for (el.children) |c| switch (c) { .element => return true, else => continue };
        return false;
    }
    fn hasTextChild(el: ast.Element) bool {
        for (el.children) |c| switch (c) {
            .text => |t| if (!isWhitespaceOnly(t)) return true,
            .expression => return true,
            .element => continue,
        };
        return false;
    }
    fn hasSlotChildren(el: ast.Element) bool {
        for (el.children) |c| switch (c) {
            .element => |e| if (std.mem.eql(u8, e.tag, "Slot")) return true,
            else => continue,
        };
        return false;
    }
    fn getSlotName(el: ast.Element) ![]const u8 {
        for (el.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, "name")) return switch (attr.value) { .string => |s| s, else => error.ZsxParseError };
        }
        return error.ZsxParseError;
    }
    fn sanitizeTag(a: std.mem.Allocator, tag: []const u8) ![]const u8 {
    var out = std.array_list.Managed(u8).init(a);
    for (tag) |ch| {
        if (ch == '.') try out.append('_') else try out.append(ch);
    }
    return try out.toOwnedSlice();
} // dots preserved in fn names via valid Zig idents

    fn makeIndent(self: *Emitter, level: usize) ![]const u8 {
        const n = level * 4;
        const buf = try self.a.alloc(u8, n);
        @memset(buf, ' ');
        return buf;
    }

    fn firstTextLiteral(self: *Emitter, el: ast.Element) ![]const u8 {
        for (el.children) |c| switch (c) {
            .text => |t| if (!isWhitespaceOnly(t)) return std.fmt.allocPrint(self.a, "\"{s}\"", .{try self.escapeString(t)}),
            .expression => |e| return e,
            .element => continue,
        };
        return "\"\"";
    }

    fn findAttrExpr(el: ast.Element, name: []const u8) ?[]const u8 {
        for (el.attributes) |attr| {
            if (std.mem.eql(u8, attr.name, name)) return switch (attr.value) { .expression => |e| e, else => null };
        }
        return null;
    }

    fn normalizeClickHandler(self: *Emitter, expr: []const u8) ![]const u8 {
        const trimmed = std.mem.trim(u8, expr, " \t\n\r");
        if (!std.mem.startsWith(u8, trimmed, "ctx.") or !std.mem.endsWith(u8, trimmed, "()")) return error.ZsxParseError;
        const method = trimmed[4 .. trimmed.len - 2];
        return std.fmt.allocPrint(self.a, "@field(@TypeOf(ctx.*), \"{s}\")", .{method});
    }

    fn optsLiteral(self: *Emitter, el: ast.Element, start_id: usize, loop_depth: usize) ![]const u8 {
        const s = try style.styleFrom(el);
        var out = std.array_list.Managed(u8).init(self.a);
        try writeFmt(self.a, &out, ".{{.id_extra = {s}", .{try self.idExpr(start_id, loop_depth)});
        if (s.background) |c| try writeFmt(self.a, &out, ", .color_fill = .{{ .r = {d}, .g = {d}, .b = {d}, .a = {d} }}", .{ c.r, c.g, c.b, c.a });
        if (s.foreground) |c| try writeFmt(self.a, &out, ", .color_text = .{{ .r = {d}, .g = {d}, .b = {d}, .a = {d} }}", .{ c.r, c.g, c.b, c.a });
        if (s.padding) |p| try writeFmt(self.a, &out, ", .padding = .{{ .x = {d}, .y = {d}, .w = {d}, .h = {d} }}", .{ @as(u32, @intFromFloat(p.x)), @as(u32, @intFromFloat(p.y)), @as(u32, @intFromFloat(p.w)), @as(u32, @intFromFloat(p.h)) });
        if (s.radius) |r| try writeFmt(self.a, &out, ", .radius = {d}", .{@as(u32, @intFromFloat(r))});
        if (s.gap) |g| try writeFmt(self.a, &out, ", .gap = {d}", .{@as(u32, @intFromFloat(g))});
        if (s.expand) |ex| try writeFmt(self.a, &out, ", .expand = .{s}", .{@tagName(ex)});
        if (s.font_size) |fs| try writeFmt(self.a, &out, ", .font_size = {d}", .{@as(u32, @intFromFloat(fs))});
        if (s.font_weight) |fw| {
            const w: u32 = switch (fw) { .regular => 400, .semibold => 600, .bold => 700 };
            try writeFmt(self.a, &out, ", .font_weight = {d}", .{w});
        }
        try out.append('}');
        return out.toOwnedSlice();
    }

    fn componentPropsLiteral(self: *Emitter, el: ast.Element, include_text: bool, start_id: usize, loop_depth: usize) ![]const u8 {
        var out = std.array_list.Managed(u8).init(self.a);
        try writeFmt(self.a, &out, ".{{.id_extra = {s}", .{try self.idExpr(start_id, loop_depth)});
        for (el.attributes) |attr| {
            try writeFmt(self.a, &out, ", .{s} = ", .{attr.name});
            if (std.mem.eql(u8, attr.name, "on_click")) {
                switch (attr.value) { .expression => |e| try out.appendSlice(try self.normalizeClickHandler(e)), else => try out.appendSlice("undefined") }
            } else switch (attr.value) {
                .boolean => try out.appendSlice("true"),
                .string => |s| { try out.append('"'); try out.appendSlice(try self.escapeString(s)); try out.append('"'); },
                .expression => |e| try out.appendSlice(e),
            }
        }
        if (include_text and hasTextChild(el)) {
            const text = try self.firstTextLiteral(el);
            if (text.len > 2) try writeFmt(self.a, &out, ", .text = {s}", .{text});
        }
        try out.append('}');
        return out.toOwnedSlice();
    }

    fn insertContentField(self: *Emitter, props: []const u8, content_name: []const u8) ![]const u8 {
        if (props.len < 2 or props[props.len - 1] != '}') return error.ZsxParseError;
        var trimmed = props[0 .. props.len - 1];
        while (trimmed.len > 0 and trimmed[trimmed.len - 1] == ' ') trimmed = trimmed[0 .. trimmed.len - 1];
        if (std.mem.eql(u8, trimmed, ".{")) return std.fmt.allocPrint(self.a, ".{{ .content = {s} }}", .{content_name});
        return std.fmt.allocPrint(self.a, "{s}, .content = {s} }}", .{ trimmed, content_name });
    }

    fn emitElement(self: *Emitter, el: ast.Element, level: usize, start_id: usize, loop_depth: usize) anyerror!EmitResult {
        if (std.mem.eql(u8, el.tag, "Slot")) return error.ZsxParseError;
        if (el.tag.len == 0) return self.emitChildren(el.children, level, start_id, loop_depth);
        const indent = try self.makeIndent(level);

        if (std.mem.eql(u8, el.tag, "column") or std.mem.eql(u8, el.tag, "row")) {
            const dir = if (std.mem.eql(u8, el.tag, "column")) "column" else "row";
            const inner = try self.emitChildren(el.children, level + 1, start_id + 1, loop_depth);
            var out = std.array_list.Managed(u8).init(self.a);
            try writeFmt(self.a, &out, "{s}{{\n{s}    var b_{d} = ui.{s}(c, {s});\n{s}    defer b_{d}.end();\n{s}{s}{s}}}\n", .{ indent, indent, start_id, dir, try self.optsLiteral(el, start_id, loop_depth), indent, start_id, indent, inner.code, indent });
            return .{ .code = try out.toOwnedSlice(), .preamble = inner.preamble, .next_id = inner.next_id };
        } else if (std.mem.eql(u8, el.tag, "label")) {
            const text = try self.firstTextLiteral(el);
            return .{ .code = try std.fmt.allocPrint(self.a, "{s}ui.text(c, {s}, {s});\n", .{ indent, text, try self.optsLiteral(el, start_id, loop_depth) }), .preamble = "", .next_id = start_id + 1 };
        } else if (std.mem.eql(u8, el.tag, "button")) {
            const text = try self.firstTextLiteral(el);
            const opts = try self.optsLiteral(el, start_id, loop_depth);
            if (findAttrExpr(el, "on_click")) |h| {
                return .{ .code = try std.fmt.allocPrint(self.a, "{s}if (ui.button(c, {s}, {s})) {s};\n", .{ indent, text, opts, h }), .preamble = "", .next_id = start_id + 1 };
            }
            return .{ .code = try std.fmt.allocPrint(self.a, "{s}_ = ui.button(c, {s}, {s});\n", .{ indent, text, opts }), .preamble = "", .next_id = start_id + 1 };
        } else if (std.mem.indexOf(u8, el.tag, ".") != null) {
            return self.emitPathComponent(el, level, start_id, loop_depth);
        } else if (isUpper(el.tag[0])) {
            if (hasSlotChildren(el)) return self.emitSlotComponent(el, level, start_id, loop_depth);
            if (hasElementChildren(el)) {
                const inner = try self.emitContentChildren(el.children, 1, start_id + 1);
                const my_id = inner.next_id;
                const render_name = try std.fmt.allocPrint(self.a, "render_{s}_{d}", .{ try sanitizeTag(self.a, el.tag), my_id });
                var decl = std.array_list.Managed(u8).init(self.a);
                try writeFmt(self.a, &decl, "inline fn {s}(ui: anytype, c: anytype, ctx: anytype) void {{\n    _ = ui; _ = c; _ = ctx;\n{s}}}\n\n", .{ render_name, inner.code });
                try self.preamble.appendSlice(inner.preamble);
                try self.preamble.appendSlice(decl.items);
                const props = try self.insertContentField(try self.componentPropsLiteral(el, false, start_id, loop_depth), render_name);
                return .{ .code = try std.fmt.allocPrint(self.a, "{s}ctx.{s}(ui, c, {s});\n", .{ indent, el.tag, props }), .preamble = "", .next_id = my_id + 1 };
            }
            return .{ .code = try std.fmt.allocPrint(self.a, "{s}ctx.{s}(ui, c, {s});\n", .{ indent, el.tag, try self.componentPropsLiteral(el, true, start_id, loop_depth) }), .preamble = "", .next_id = start_id + 1 };
        }
        return error.ZsxParseError;
    }

    fn emitPathComponent(self: *Emitter, el: ast.Element, level: usize, start_id: usize, loop_depth: usize) anyerror!EmitResult {
        const indent = try self.makeIndent(level);
        if (hasSlotChildren(el)) return self.emitSlotComponent(el, level, start_id, loop_depth);
        if (hasElementChildren(el)) {
            const inner = try self.emitContentChildren(el.children, 1, start_id + 1);
            const my_id = inner.next_id;
            const render_name = try std.fmt.allocPrint(self.a, "render_{s}_{d}", .{ try sanitizeTag(self.a, el.tag), my_id });
            var decl = std.array_list.Managed(u8).init(self.a);
            try writeFmt(self.a, &decl, "inline fn {s}(ui: anytype, c: anytype, ctx: anytype) void {{\n    _ = ui; _ = c; _ = ctx;\n{s}}}\n\n", .{ render_name, inner.code });
            try self.preamble.appendSlice(inner.preamble);
            try self.preamble.appendSlice(decl.items);
            const props = try self.insertContentField(try self.componentPropsLiteral(el, false, start_id, loop_depth), render_name);
            return .{ .code = try std.fmt.allocPrint(self.a, "{s}{s}(ctx, ui, c, {s});\n", .{ indent, el.tag, props }), .preamble = "", .next_id = my_id + 1 };
        }
        return .{ .code = try std.fmt.allocPrint(self.a, "{s}{s}(ctx, ui, c, {s});\n", .{ indent, el.tag, try self.componentPropsLiteral(el, true, start_id, loop_depth) }), .preamble = "", .next_id = start_id + 1 };
    }

    fn emitSlotComponent(self: *Emitter, el: ast.Element, level: usize, start_id: usize, loop_depth: usize) anyerror!EmitResult {
        const indent = try self.makeIndent(level);
        var id = start_id + 1;
        var props = std.array_list.Managed(u8).init(self.a);
        try props.appendSlice(".{");
        var sep: []const u8 = "";
        for (el.children) |c| switch (c) {
            .element => |slot| {
                if (!std.mem.eql(u8, slot.tag, "Slot")) return error.ZsxParseError;
                const name = try getSlotName(slot);
                const inner = try self.emitContentChildren(slot.children, 1, id);
                const my_id = inner.next_id;
                const fn_name = try std.fmt.allocPrint(self.a, "render_{s}_{s}_{d}", .{ try sanitizeTag(self.a, el.tag), name, my_id });
                var decl = std.array_list.Managed(u8).init(self.a);
                try writeFmt(self.a, &decl, "inline fn {s}(ui: anytype, c: anytype, ctx: anytype) void {{\n    _ = ui; _ = c; _ = ctx;\n{s}}}\n\n", .{ fn_name, inner.code });
                try self.preamble.appendSlice(inner.preamble);
                try self.preamble.appendSlice(decl.items);
                try writeFmt(self.a, &props, "{s}.{s} = {s}", .{ sep, name, fn_name });
                sep = ", ";
                id = my_id + 1;
            },
            .text => |t| if (!isWhitespaceOnly(t)) return error.ZsxParseError,
            .expression => return error.ZsxParseError,
        };
        try writeFmt(self.a, &props, "{s}.id_extra = {s}", .{ sep, try self.idExpr(start_id, loop_depth) });
        for (el.attributes) |attr| {
            try writeFmt(self.a, &props, ", .{s} = ", .{attr.name});
            if (std.mem.eql(u8, attr.name, "on_click")) {
                switch (attr.value) { .expression => |e| try props.appendSlice(try self.normalizeClickHandler(e)), else => try props.appendSlice("undefined") }
            } else switch (attr.value) {
                .boolean => try props.appendSlice("true"),
                .string => |s| { try props.append('"'); try props.appendSlice(try self.escapeString(s)); try props.append('"'); },
                .expression => |e| try props.appendSlice(e),
            }
        }
        try props.append('}');
        const is_path = std.mem.indexOf(u8, el.tag, ".") != null;
        const call = if (is_path)
            try std.fmt.allocPrint(self.a, "{s}(ctx, ui, c, {s})", .{ el.tag, props.items })
        else
            try std.fmt.allocPrint(self.a, "ctx.{s}(ui, c, {s})", .{ el.tag, props.items });
        return .{ .code = try std.fmt.allocPrint(self.a, "{s}{s};\n", .{ indent, call }), .preamble = "", .next_id = id };
    }

    fn emitChildren(self: *Emitter, children: []const ast.Child, start_level: usize, start_id: usize, incoming_loop_depth: usize) anyerror!EmitResult {
        var code = std.array_list.Managed(u8).init(self.a);
        var level = start_level;
        var id = start_id;
        var cur_depth = incoming_loop_depth;
        var stack: [32]u8 = undefined;
        var stack_depth: usize = 0;
        var switch_exprs: [16][]const u8 = undefined;
        var switch_depth: usize = 0;

        for (children) |child| switch (child) {
            .element => |el| {
                const r = try self.emitElement(el, level, id, cur_depth);
                try code.appendSlice(r.code);
                try self.preamble.appendSlice(r.preamble);
                id = r.next_id;
            },
            .text => |t| if (!isWhitespaceOnly(t)) return error.ZsxParseError,
            .expression => |e| {
                if (std.mem.startsWith(u8, e, "if ")) {
                    const cond = std.mem.trim(u8, e[3..], " \t\n\r");
                    if (cond.len == 0) return error.ZsxParseError;
                    try writeFmt(self.a, &code, "{s}if ({s}) {{\n", .{ try self.makeIndent(level), cond });
                    stack[stack_depth] = 'i'; stack_depth += 1; level += 1;
                } else if (std.mem.startsWith(u8, e, "for ") and std.mem.indexOf(u8, e, " as ") != null) {
                    const body = std.mem.trim(u8, e[4..], " \t\n\r");
                    const as_idx = std.mem.indexOf(u8, body, " as ").?;
                    const items = std.mem.trim(u8, body[0..as_idx], " \t\n\r");
                    const binding = std.mem.trim(u8, body[as_idx + 4 ..], " \t\n\r");
                    if (items.len == 0 or binding.len == 0 or cur_depth >= 3) return error.ZsxParseError;
                    try writeFmt(self.a, &code, "{s}for ({s}, 0..) |{s}, idx_{d}| {{\n", .{ try self.makeIndent(level), items, binding, cur_depth });
                    stack[stack_depth] = 'f'; stack_depth += 1; level += 1; cur_depth += 1;
                } else if (std.mem.startsWith(u8, e, "switch ")) {
                    const expr = std.mem.trim(u8, e[7..], " \t\n\r");
                    if (expr.len == 0 or switch_depth >= 16) return error.ZsxParseError;
                    switch_exprs[switch_depth] = expr; switch_depth += 1;
                    stack[stack_depth] = 'S'; stack_depth += 1;
                } else if (std.mem.startsWith(u8, e, ":case ") or std.mem.startsWith(u8, e, "case ")) {
                    const pat = std.mem.trim(u8, if (std.mem.startsWith(u8, e, ":case ")) e[6..] else e[5..], " \t\n\r");
                    if (pat.len == 0 or stack_depth == 0) return error.ZsxParseError;
                    const top = stack[stack_depth - 1];
                    if (top != 'S' and top != 'c') return error.ZsxParseError;
                    const expr = switch_exprs[switch_depth - 1];
                    const predicate = if (pat[0] == '"')
                        try std.fmt.allocPrint(self.a, "std.mem.eql(u8, {s}, {s})", .{ expr, pat })
                    else
                        try std.fmt.allocPrint(self.a, "{s} == {s}", .{ expr, pat });
                    if (top == 'S') {
                        try writeFmt(self.a, &code, "{s}if ({s}) {{\n", .{ try self.makeIndent(level), predicate });
                        level += 1; stack[stack_depth] = 'c'; stack_depth += 1;
                    } else {
                        level -= 1;
                        try writeFmt(self.a, &code, "{s}}} else if ({s}) {{\n", .{ try self.makeIndent(level), predicate });
                        level += 1;
                    }
                } else if (std.mem.startsWith(u8, e, ":else if ") or std.mem.startsWith(u8, e, "else if ")) {
                    const cond = std.mem.trim(u8, if (std.mem.startsWith(u8, e, ":else if ")) e[9..] else e[8..], " \t\n\r");
                    if (cond.len == 0 or stack_depth == 0 or stack[stack_depth - 1] != 'i') return error.ZsxParseError;
                    level -= 1;
                    try writeFmt(self.a, &code, "{s}}} else if ({s}) {{\n", .{ try self.makeIndent(level), cond });
                    level += 1;
                } else if (std.mem.eql(u8, e, ":else") or std.mem.eql(u8, e, "else")) {
                    if (stack_depth == 0) return error.ZsxParseError;
                    const top = stack[stack_depth - 1];
                    if (top == 'i') {
                        stack[stack_depth - 1] = 'e';
                        level -= 1;
                        try writeFmt(self.a, &code, "{s}}} else {{\n", .{try self.makeIndent(level)});
                        level += 1;
                    } else if (top == 'c') {
                        stack[stack_depth - 1] = 'E';
                        level -= 1;
                        try writeFmt(self.a, &code, "{s}}} else {{\n", .{try self.makeIndent(level)});
                        level += 1;
                    } else return error.ZsxParseError;
                } else if (std.mem.eql(u8, e, "/if") or std.mem.eql(u8, e, "endif")) {
                    if (stack_depth == 0) return error.ZsxParseError;
                    const top = stack[stack_depth - 1];
                    if (top != 'i' and top != 'e') return error.ZsxParseError;
                    stack_depth -= 1; level -= 1;
                    try writeFmt(self.a, &code, "{s}}}\n", .{try self.makeIndent(level)});
                } else if (std.mem.eql(u8, e, "/for") or std.mem.eql(u8, e, "endfor")) {
                    if (stack_depth == 0 or stack[stack_depth - 1] != 'f') return error.ZsxParseError;
                    stack_depth -= 1; level -= 1; cur_depth -= 1;
                    try writeFmt(self.a, &code, "{s}}}\n", .{try self.makeIndent(level)});
                } else if (std.mem.eql(u8, e, "/switch") or std.mem.eql(u8, e, "endswitch")) {
                    if (stack_depth == 0) return error.ZsxParseError;
                    const top = stack[stack_depth - 1];
                    if (top == 'S') return error.ZsxParseError;
                    if (top != 'c' and top != 'E') return error.ZsxParseError;
                    stack_depth -= 1; level -= 1;
                    try writeFmt(self.a, &code, "{s}}}\n", .{try self.makeIndent(level)});
                    if (stack_depth == 0 or stack[stack_depth - 1] != 'S') return error.ZsxParseError;
                    stack_depth -= 1; switch_depth -= 1;
                } else return error.ZsxParseError;
            },
        };
        if (stack_depth != 0) return error.ZsxParseError;
        return .{ .code = try code.toOwnedSlice(), .preamble = "", .next_id = id };
    }

        fn emitContentChildren(self: *Emitter, children: []const ast.Child, start_level: usize, start_id: usize) anyerror!EmitResult {
        // emitContentChildrenCF-v1
        var code = std.array_list.Managed(u8).init(self.a);
        var level = start_level;
        var id = start_id;
        var stack: [32]u8 = undefined;
        var stack_depth: usize = 0;
        var switch_exprs: [16][]const u8 = undefined;
        var switch_depth: usize = 0;
        for (children) |child| switch (child) {
            .element => |el| {
                const r = try self.emitElement(el, level, id, 0);
                try code.appendSlice(r.code);
                try self.preamble.appendSlice(r.preamble);
                id = r.next_id;
            },
            .text => |t| if (!isWhitespaceOnly(t)) {
                try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}ui.text(c, \"{s}\", .{{}});\n", .{ try self.makeIndent(level), try self.escapeString(t) }));
            },
            .expression => |e| {
                if (std.mem.startsWith(u8, e, "if ")) {
                    const cond = std.mem.trim(u8, e[3..], " \t\n\r");
                    if (cond.len == 0) return error.ZsxParseError;
                    try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}if ({s}) {{\n", .{ try self.makeIndent(level), cond }));
                    stack[stack_depth] = 'i'; stack_depth += 1; level += 1;
                } else if (std.mem.startsWith(u8, e, "for ") and std.mem.indexOf(u8, e, " as ") != null) {
                    const body = std.mem.trim(u8, e[4..], " \t\n\r");
                    const as_idx = std.mem.indexOf(u8, body, " as ").?;
                    const items = std.mem.trim(u8, body[0..as_idx], " \t\n\r");
                    const binding = std.mem.trim(u8, body[as_idx + 4 ..], " \t\n\r");
                    if (items.len == 0 or binding.len == 0) return error.ZsxParseError;
                    try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}for ({s}, 0..) |{s}, idx_0| {{\n", .{ try self.makeIndent(level), items, binding }));
                    stack[stack_depth] = 'f'; stack_depth += 1; level += 1;
                } else if (std.mem.startsWith(u8, e, "switch ")) {
                    const expr = std.mem.trim(u8, e[7..], " \t\n\r");
                    if (expr.len == 0 or switch_depth >= 16) return error.ZsxParseError;
                    switch_exprs[switch_depth] = expr; switch_depth += 1;
                    stack[stack_depth] = 'S'; stack_depth += 1;
                } else if (std.mem.startsWith(u8, e, ":case ") or std.mem.startsWith(u8, e, "case ")) {
                    const pat = std.mem.trim(u8, if (std.mem.startsWith(u8, e, ":case ")) e[6..] else e[5..], " \t\n\r");
                    if (pat.len == 0 or stack_depth == 0) return error.ZsxParseError;
                    const top = stack[stack_depth - 1];
                    if (top != 'S' and top != 'c') return error.ZsxParseError;
                    const expr = switch_exprs[switch_depth - 1];
                    const predicate = if (pat[0] == '"')
                        try std.fmt.allocPrint(self.a, "std.mem.eql(u8, {s}, {s})", .{ expr, pat })
                    else
                        try std.fmt.allocPrint(self.a, "{s} == {s}", .{ expr, pat });
                    if (top == 'S') {
                        try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}if ({s}) {{\n", .{ try self.makeIndent(level), predicate }));
                        level += 1; stack[stack_depth] = 'c'; stack_depth += 1;
                    } else {
                        level -= 1;
                        try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}}} else if ({s}) {{\n", .{ try self.makeIndent(level), predicate }));
                        level += 1;
                    }
                } else if (std.mem.startsWith(u8, e, ":else if ") or std.mem.startsWith(u8, e, "else if ")) {
                    const cond = std.mem.trim(u8, if (std.mem.startsWith(u8, e, ":else if ")) e[9..] else e[8..], " \t\n\r");
                    if (cond.len == 0 or stack_depth == 0 or stack[stack_depth - 1] != 'i') return error.ZsxParseError;
                    level -= 1;
                    try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}}} else if ({s}) {{\n", .{ try self.makeIndent(level), cond }));
                    level += 1;
                } else if (std.mem.eql(u8, e, ":else") or std.mem.eql(u8, e, "else")) {
                    if (stack_depth == 0) return error.ZsxParseError;
                    const top = stack[stack_depth - 1];
                    if (top == 'i') {
                        stack[stack_depth - 1] = 'e';
                        level -= 1;
                        try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}}} else {{\n", .{try self.makeIndent(level)}));
                        level += 1;
                    } else if (top == 'c') {
                        stack[stack_depth - 1] = 'E';
                        level -= 1;
                        try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}}} else {{\n", .{try self.makeIndent(level)}));
                        level += 1;
                    } else return error.ZsxParseError;
                } else if (std.mem.eql(u8, e, "/if") or std.mem.eql(u8, e, "endif")) {
                    if (stack_depth == 0) return error.ZsxParseError;
                    const top = stack[stack_depth - 1];
                    if (top != 'i' and top != 'e') return error.ZsxParseError;
                    stack_depth -= 1; level -= 1;
                    try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}}}\n", .{try self.makeIndent(level)}));
                } else if (std.mem.eql(u8, e, "/for") or std.mem.eql(u8, e, "endfor")) {
                    if (stack_depth == 0 or stack[stack_depth - 1] != 'f') return error.ZsxParseError;
                    stack_depth -= 1; level -= 1;
                    try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}}}\n", .{try self.makeIndent(level)}));
                } else if (std.mem.eql(u8, e, "/switch") or std.mem.eql(u8, e, "endswitch")) {
                    if (stack_depth == 0) return error.ZsxParseError;
                    const top = stack[stack_depth - 1];
                    if (top == 'S') return error.ZsxParseError;
                    if (top != 'c' and top != 'E') return error.ZsxParseError;
                    stack_depth -= 1; level -= 1;
                    try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}}}\n", .{try self.makeIndent(level)}));
                    if (stack_depth == 0 or stack[stack_depth - 1] != 'S') return error.ZsxParseError;
                    stack_depth -= 1; switch_depth -= 1;
                } else return error.ZsxParseError;
            },
        };
        return .{ .code = try code.toOwnedSlice(), .preamble = "", .next_id = id };
    }
};


fn fixDiscardPrefixes(a: std.mem.Allocator, preamble: []const u8) ![]const u8 {
    var out = std.array_list.Managed(u8).init(a);
    var pos: usize = 0;
    while (pos < preamble.len) {
        if (std.mem.startsWith(u8, preamble[pos..], "inline fn render_")) {
            const brace = std.mem.indexOfScalarPos(u8, preamble, pos, '{') orelse {
                try out.append(preamble[pos]);
                pos += 1;
                continue;
            };
            const fn_end_marker = std.mem.indexOfPos(u8, preamble, brace, "\n}\n\n") orelse {
                try out.appendSlice(preamble[pos..]);
                break;
            };
            const body = preamble[brace + 1 .. fn_end_marker];
            try out.appendSlice(preamble[pos..brace + 1]);

            // Strip existing discard lines, compute which are needed
            var body_iter: []const u8 = body;
            body_iter = std.mem.trimStart(u8, body_iter, " \n");
            for ([_][]const u8{ "_ = ui;", "_ = c;", "_ = ctx;" }) |disc| {
                while (std.mem.startsWith(u8, body_iter, disc)) {
                    const nl = std.mem.indexOfScalar(u8, body_iter, '\n') orelse body_iter.len;
                    body_iter = std.mem.trimStart(u8, body_iter[nl + 1 ..], " \n");
                }
            }

            const uses_ui = std.mem.indexOf(u8, body_iter, "ui.") != null or
                std.mem.indexOf(u8, body_iter, "ui,") != null or
                std.mem.indexOf(u8, body_iter, "ui)") != null;
            const uses_c = std.mem.indexOf(u8, body_iter, "(c,") != null or
                std.mem.indexOf(u8, body_iter, ", c,") != null or
                std.mem.indexOf(u8, body_iter, "(c)") != null;
            const uses_ctx = std.mem.indexOf(u8, body_iter, "ctx.") != null;

            if (!uses_ui) try out.appendSlice("\n    _ = ui;");
            if (!uses_c) try out.appendSlice("\n    _ = c;");
            if (!uses_ctx) try out.appendSlice("\n    _ = ctx;");
            if (body_iter.len > 0) {
                try out.append('\n');
                try out.appendSlice(body_iter);
            }
            try out.appendSlice("\n}\n\n");
            pos = fn_end_marker + 4;
        } else {
            try out.append(preamble[pos]);
            pos += 1;
        }
    }
    return try out.toOwnedSlice();
}

pub const BlockOutput = struct { preamble: []const u8, code: []const u8 };

pub fn emitBlock(a: std.mem.Allocator, root: ast.Element, file_index: usize, block_index: usize) !BlockOutput {
    var em = Emitter.init(a, file_index, block_index);
    const result = try em.emitElement(root, 1, 0, 0);
    const raw_preamble = try em.preamble.toOwnedSlice();
    return .{ .preamble = try fixDiscardPrefixes(a, raw_preamble), .code = result.code };
}

pub fn emitBlockJoined(a: std.mem.Allocator, root: ast.Element, file_index: usize, block_index: usize) ![]const u8 {
    const split = try emitBlock(a, root, file_index, block_index);
    return std.fmt.allocPrint(a, "{s}{s}", .{ split.preamble, split.code });
}
