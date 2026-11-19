const std = @import("std");
const ast = @import("parser.zig");
const style = @import("style.zig");

/// A generator-introduced loop scope. `value` is the binding name
/// (`{for items as item}` → `item`), `index` is the loop counter emitted by
/// the generator (`idx_0`, `idx_1`, …). Both are ordinary Zig locals, so a
/// component body emitted inside the loop has to capture them (F3).
const Loop = struct { value: []const u8, index: []const u8 };

fn writeFmt(a: std.mem.Allocator, out: *std.array_list.Managed(u8), comptime fmt: []const u8, args: anytype) !void {
    try out.appendSlice(try std.fmt.allocPrint(a, fmt, args));
}

/// True when `name` occurs in `code` as a whole identifier (token-ish scan, not
/// a substring match: `items` does not mention `item`). Capture analysis is the
/// one place the master plan permits identifier scanning (WP 2.3).
fn mentionsIdentifier(code: []const u8, name: []const u8) bool {
    if (name.len == 0) return false;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, code, i, name)) |pos| {
        const before_ok = pos == 0 or !isIdentChar(code[pos - 1]);
        const after = pos + name.len;
        const after_ok = after >= code.len or !isIdentChar(code[after]);
        if (before_ok and after_ok) return true;
        i = pos + 1;
    }
    return false;
}

fn isIdentChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

/// `_ = param;` lines for the parameters a generated body never references.
/// Discarding a parameter that *is* used is a Zig compile error ("pointless
/// discard"), so this must be decided from the emitted body (F4: no
/// substring/`indexOf("ui.")` guessing).
fn discardLines(a: std.mem.Allocator, code: []const u8, self_used: bool, ui: []const u8, c: []const u8, ctx: []const u8) ![]const u8 {
    var out = std.array_list.Managed(u8).init(a);
    if (!mentionsIdentifier(code, ui)) try writeFmt(a, &out, "    _ = {s};\n", .{ui});
    if (!mentionsIdentifier(code, c)) try writeFmt(a, &out, "    _ = {s};\n", .{c});
    if (!mentionsIdentifier(code, ctx)) try writeFmt(a, &out, "    _ = {s};\n", .{ctx});
    if (!self_used) try out.appendSlice("    _ = self;\n");
    return out.toOwnedSlice();
}

/// Stable widget ID for a node: `hash64(src_key, block_index, structural_path)`.
///
/// `src_key` is the source's stable name (its path relative to the project),
/// *not* its index in the build list — reordering `.paths` must not rename
/// widget identities (F1). Hashing also removes the old
/// `file_index * 10_000_000_000_000 + base` overflow at ~184 files.
pub fn stableNodeId(src_key: []const u8, block_index: usize, path_index: usize) u64 {
    var idx_buf: [64]u8 = undefined;
    const idx_key = std.fmt.bufPrint(&idx_buf, "{d}:{d}", .{ block_index, path_index }) catch unreachable;
    var h = std.hash.Wyhash.init(0);
    h.update(src_key);
    h.update(":");
    h.update(idx_key);
    return h.final();
}

const EmitResult = struct {
    code: []const u8,
    preamble: []const u8,
    next_id: usize,
};

const BodyValue = struct {
    /// Declarations the caller must emit before the component call (empty for
    /// hoisted bodies).
    pre: []const u8,
    /// Expression to store in the slot/content field.
    value: []const u8,
    next_id: usize,
};

const Emitter = struct {
    a: std.mem.Allocator,
    src_key: []const u8,
    block_index: usize,
    preamble: std.array_list.Managed(u8),
    // Parameter names used for emitted builder calls. Hoisted helpers and the
    // top-level view use `ui`/`c`/`ctx`; capture structs are declared *inside*
    // the view, where those names would shadow the view's own parameters, so
    // their methods use underscored names instead.
    ui_name: []const u8 = "ui",
    c_name: []const u8 = "c",
    ctx_name: []const u8 = "ctx",

    fn init(a: std.mem.Allocator, src_key: []const u8, block_index: usize) Emitter {
        return .{
            .a = a,
            .src_key = src_key,
            .block_index = block_index,
            .preamble = std.array_list.Managed(u8).init(a),
        };
    }
    fn deinit(self: *Emitter) void {
        self.preamble.deinit();
    }

    fn nodeId(self: *const Emitter, base: usize) u64 {
        return stableNodeId(self.src_key, self.block_index, base);
    }

    /// Emit an ID expression. Loop indices are mixed in with wrapping
    /// arithmetic so arbitrarily deep loops cannot overflow; the final value is
    /// truncated to `usize` so 32-bit targets (wasm) still compile.
    fn idExpr(self: *Emitter, base: usize, loops: []const Loop) ![]const u8 {
        const id = self.nodeId(base);
        if (loops.len == 0) return std.fmt.allocPrint(self.a, "@as(usize, @truncate(@as(u64, {d})))", .{id});

        var out = std.array_list.Managed(u8).init(self.a);
        try writeFmt(self.a, &out, "@as(usize, @truncate(@as(u64, {d})", .{id});
        for (loops, 0..) |lp, depth| {
            const stride: u64 = 1_000_003 + @as(u64, depth) * 7_919;
            try writeFmt(self.a, &out, " +% @as(u64, {s}) *% {d}", .{ lp.index, stride });
        }
        try out.appendSlice("))");
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

    fn isWs(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r';
    }
    fn isWhitespaceOnly(s: []const u8) bool {
        for (s) |c| if (!isWs(c)) return false;
        return true;
    }
    fn isUpper(c: u8) bool {
        return c >= 'A' and c <= 'Z';
    }

    fn hasElementChildren(el: ast.Element) bool {
        for (el.children) |c| switch (c) {
            .element => return true,
            else => continue,
        };
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
            if (std.mem.eql(u8, attr.name, "name")) return switch (attr.value) {
                .string => |s| s,
                else => error.ZsxParseError,
            };
        }
        return error.ZsxParseError;
    }
    fn sanitizeTag(a: std.mem.Allocator, tag: []const u8) ![]const u8 {
        var out = std.array_list.Managed(u8).init(a);
        for (tag) |ch| {
            if (ch == '.') try out.append('_') else try out.append(ch);
        }
        return try out.toOwnedSlice();
    }

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
            if (!std.mem.eql(u8, attr.name, name)) continue;
            return switch (attr.value) {
                .expression => |e| e,
                else => null,
            };
        }
        return null;
    }

    fn findEventExpr(el: ast.Element, event: []const u8) ?[]const u8 {
        for (el.attributes) |attr| {
            const match = attr.name.len == event.len + 3 and
                (std.mem.startsWith(u8, attr.name, "on_") or std.mem.startsWith(u8, attr.name, "on:")) and
                std.mem.eql(u8, attr.name[3..], event);
            if (!match) continue;
            return switch (attr.value) {
                .expression => |e| e,
                else => null,
            };
        }
        return null;
    }

    fn isEventAttr(name: []const u8) bool {
        return std.mem.startsWith(u8, name, "on_") or std.mem.startsWith(u8, name, "on:");
    }

    fn attrFieldName(self: *Emitter, name: []const u8) ![]const u8 {
        if (std.mem.indexOfScalar(u8, name, ':') == null) return name;
        const buf = try self.a.dupe(u8, name);
        for (buf) |*ch| {
            if (ch.* == ':') ch.* = '_';
        }
        return buf;
    }

    /// Build a zero-return event handler callable `call(ctx)` for a component
    /// prop. Loop locals referenced by the expression are captured on a
    /// container-level factory; expressions without captures become a hoisted
    /// `inline fn`. Arbitrary Zig expressions are accepted, so
    /// `on:click={ctx.remove(item)}` works and handler-in-loop is safe.
    fn buildHandler(self: *Emitter, expr: []const u8, base: usize, slot: usize, loops: []const Loop) ![]const u8 {
        const trimmed = std.mem.trim(u8, expr, " \t\n\r");

        var caps = std.array_list.Managed([]const u8).init(self.a);
        for (loops) |lp| {
            for ([_][]const u8{ lp.value, lp.index }) |cap| {
                if (!mentionsIdentifier(trimmed, cap)) continue;
                var dup = false;
                for (caps.items) |seen| if (std.mem.eql(u8, seen, cap)) {
                    dup = true;
                };
                if (!dup) try caps.append(cap);
            }
        }

        const ctx_discard = if (mentionsIdentifier(trimmed, "ctx")) "" else "_ = ctx;\n";

        if (caps.items.len == 0) {
            const name = try std.fmt.allocPrint(self.a, "render_handler_{d}_{d}", .{ base, slot });
            var decl = std.array_list.Managed(u8).init(self.a);
            try writeFmt(self.a, &decl, "inline fn {s}(ctx: anytype) void {{\n{s}{s};\n}}\n\n", .{ name, ctx_discard, trimmed });
            try self.preamble.appendSlice(decl.items);
            return name;
        }

        var params = std.array_list.Managed(u8).init(self.a);
        var fields = std.array_list.Managed(u8).init(self.a);
        var aliases = std.array_list.Managed(u8).init(self.a);
        var inits = std.array_list.Managed(u8).init(self.a);
        var args = std.array_list.Managed(u8).init(self.a);
        var sep: []const u8 = "";
        var psep: []const u8 = "";
        for (caps.items, 0..) |cap, n| {
            try writeFmt(self.a, &params, "{s}T{d}: type", .{ psep, n });
            try writeFmt(self.a, &fields, "        {s}: T{d},\n", .{ cap, n });
            try writeFmt(self.a, &aliases, "            const {s} = self.{s};\n", .{ cap, cap });
            try writeFmt(self.a, &inits, "{s}.{s} = {s}", .{ sep, cap, cap });
            try writeFmt(self.a, &args, "{s}@TypeOf({s})", .{ psep, cap });
            sep = ", ";
            psep = ", ";
        }
        const ty = try std.fmt.allocPrint(self.a, "ZsxHandler_{d}_{d}", .{ base, slot });
        var decl = std.array_list.Managed(u8).init(self.a);
        try writeFmt(
            self.a,
            &decl,
            "fn {s}(comptime {s}) type {{\n    return struct {{\n{s}        pub inline fn call(self: @This(), ctx: anytype) void {{\n{s}{s}{s};\n        }}\n    }};\n}}\n\n",
            .{ ty, params.items, fields.items, ctx_discard, aliases.items, trimmed },
        );
        try self.preamble.appendSlice(decl.items);
        return std.fmt.allocPrint(self.a, "{s}({s}){{ {s} }}", .{ ty, args.items, inits.items });
    }

    fn optsLiteral(self: *Emitter, el: ast.Element, base: usize, loops: []const Loop) ![]const u8 {
        const s = try style.styleFrom(el);
        var out = std.array_list.Managed(u8).init(self.a);
        try writeFmt(self.a, &out, ".{{.id_extra = {s}", .{try self.idExpr(base, loops)});
        if (s.background) |c| try writeFmt(self.a, &out, ", .color_fill = .{{ .r = {d}, .g = {d}, .b = {d}, .a = {d} }}", .{ c.r, c.g, c.b, c.a });
        if (s.foreground) |c| try writeFmt(self.a, &out, ", .color_text = .{{ .r = {d}, .g = {d}, .b = {d}, .a = {d} }}", .{ c.r, c.g, c.b, c.a });
        if (s.padding) |p| try writeFmt(self.a, &out, ", .padding = .{{ .x = {d}, .y = {d}, .w = {d}, .h = {d} }}", .{ @as(u32, @intFromFloat(p.x)), @as(u32, @intFromFloat(p.y)), @as(u32, @intFromFloat(p.w)), @as(u32, @intFromFloat(p.h)) });
        if (s.radius) |r| try writeFmt(self.a, &out, ", .radius = {d}", .{@as(u32, @intFromFloat(r))});
        if (s.gap) |g| try writeFmt(self.a, &out, ", .gap = {d}", .{@as(u32, @intFromFloat(g))});
        if (s.expand) |ex| try writeFmt(self.a, &out, ", .expand = .{s}", .{@tagName(ex)});
        if (s.font_size) |fs| try writeFmt(self.a, &out, ", .font_size = {d}", .{@as(u32, @intFromFloat(fs))});
        if (s.font_weight) |fw| {
            const w: u32 = switch (fw) {
                .regular => 400,
                .semibold => 600,
                .bold => 700,
            };
            try writeFmt(self.a, &out, ", .font_weight = {d}", .{w});
        }
        try out.append('}');
        return out.toOwnedSlice();
    }

    const Field = struct { name: []const u8, value: []const u8 };

    fn propsLiteral(self: *Emitter, el: ast.Element, include_text: bool, base: usize, loops: []const Loop, extra: []const Field) ![]const u8 {
        var out = std.array_list.Managed(u8).init(self.a);
        try writeFmt(self.a, &out, ".{{.id_extra = {s}", .{try self.idExpr(base, loops)});
        for (el.attributes, 0..) |attr, ai| {
            try writeFmt(self.a, &out, ", .{s} = ", .{try self.attrFieldName(attr.name)});
            if (isEventAttr(attr.name)) {
                switch (attr.value) {
                    .expression => |e| try out.appendSlice(try self.buildHandler(e, base, ai, loops)),
                    else => try out.appendSlice("undefined"),
                }
            } else switch (attr.value) {
                .boolean => try out.appendSlice("true"),
                .string => |s| {
                    try out.append('"');
                    try out.appendSlice(try self.escapeString(s));
                    try out.append('"');
                },
                .expression => |e| try out.appendSlice(e),
            }
        }
        for (extra) |f| try writeFmt(self.a, &out, ", .{s} = {s}", .{ f.name, f.value });
        if (include_text and hasTextChild(el)) {
            const text = try self.firstTextLiteral(el);
            if (text.len > 2) try writeFmt(self.a, &out, ", .text = {s}", .{text});
        }
        try out.append('}');
        return out.toOwnedSlice();
    }

    /// Build the callable value for a content/slot body.
    ///
    /// * No surrounding loop locals → a hoisted `inline fn render_*`.
    /// * Surrounding loop locals → a container-level generic *capture struct*
    ///   factory `fn ZsxBody_N(T0, …) type` whose `call` method aliases the
    ///   captured locals from `self`. The value is constructed at the call site
    ///   (`ZsxBody_N(@TypeOf(item), …){ .item = item, … }`), so the body sees
    ///   `item` (F3) without a nested struct shadowing the view's parameters.
    ///   Only captures actually referenced by the body are stored.
    fn buildBody(self: *Emitter, children: []const ast.Child, base: usize, loops: []const Loop, name_hint: []const u8) anyerror!BodyValue {
        const inner = try self.emitChildren(children, 1, base, loops, .render);
        const my_id = inner.next_id;

        // Collect the captures this body actually mentions (identifier-token
        // scan over the emitted body — WP 2.3 permits this for captures).
        var caps = std.array_list.Managed([]const u8).init(self.a);
        for (loops) |lp| {
            for ([_][]const u8{ lp.value, lp.index }) |cap| {
                if (!mentionsIdentifier(inner.code, cap)) continue;
                var dup = false;
                for (caps.items) |seen| if (std.mem.eql(u8, seen, cap)) {
                    dup = true;
                };
                if (!dup) try caps.append(cap);
            }
        }

        // Nothing to capture (including a static body inside a loop): hoist.
        if (caps.items.len == 0) {
            const render_name = try std.fmt.allocPrint(self.a, "render_{s}_{d}", .{ try sanitizeTag(self.a, name_hint), my_id });
            const discards = try discardLines(self.a, inner.code, true, "ui", "c", "ctx");
            var decl = std.array_list.Managed(u8).init(self.a);
            try writeFmt(self.a, &decl, "inline fn {s}(ui: anytype, c: anytype, ctx: anytype) void {{\n{s}{s}}}\n\n", .{ render_name, discards, inner.code });
            try self.preamble.appendSlice(inner.preamble);
            try self.preamble.appendSlice(decl.items);
            return .{ .pre = "", .value = render_name, .next_id = my_id + 1 };
        }

        var params = std.array_list.Managed(u8).init(self.a);
        var fields = std.array_list.Managed(u8).init(self.a);
        var aliases = std.array_list.Managed(u8).init(self.a);
        var inits = std.array_list.Managed(u8).init(self.a);
        var args = std.array_list.Managed(u8).init(self.a);
        var sep: []const u8 = "";
        var psep: []const u8 = "";
        for (caps.items, 0..) |cap, n| {
            try writeFmt(self.a, &params, "{s}T{d}: type", .{ psep, n });
            try writeFmt(self.a, &fields, "        {s}: T{d},\n", .{ cap, n });
            try writeFmt(self.a, &aliases, "        const {s} = self.{s};\n", .{ cap, cap });
            try writeFmt(self.a, &inits, "{s}.{s} = {s}", .{ sep, cap, cap });
            try writeFmt(self.a, &args, "{s}@TypeOf({s})", .{ psep, cap });
            sep = ", ";
            psep = ", ";
        }

        const ty = try std.fmt.allocPrint(self.a, "ZsxBody_{d}", .{my_id});
        const discards = try discardLines(self.a, inner.code, true, "ui", "c", "ctx");
        var decl = std.array_list.Managed(u8).init(self.a);
        try writeFmt(
            self.a,
            &decl,
            "fn {s}(comptime {s}) type {{\n    return struct {{\n{s}        pub inline fn call(self: @This(), ui: anytype, c: anytype, ctx: anytype) void {{\n{s}{s}{s}        }}\n    }};\n}}\n\n",
            .{ ty, params.items, fields.items, discards, aliases.items, inner.code },
        );
        const value = try std.fmt.allocPrint(self.a, "{s}({s}){{ {s} }}", .{ ty, args.items, inits.items });
        try self.preamble.appendSlice(inner.preamble);
        try self.preamble.appendSlice(decl.items);
        return .{ .pre = "", .value = value, .next_id = my_id + 1 };
    }

    fn emitElement(self: *Emitter, el: ast.Element, level: usize, base: usize, loops: []const Loop) anyerror!EmitResult {
        if (std.mem.eql(u8, el.tag, "Slot")) return error.ZsxParseError;
        if (el.tag.len == 0) return self.emitChildren(el.children, level, base, loops, .reject);
        const indent = try self.makeIndent(level);

        if (std.mem.eql(u8, el.tag, "column") or std.mem.eql(u8, el.tag, "row")) {
            const dir = if (std.mem.eql(u8, el.tag, "column")) "column" else "row";
            const inner = try self.emitChildren(el.children, level + 1, base + 1, loops, .reject);
            var out = std.array_list.Managed(u8).init(self.a);
            try writeFmt(self.a, &out, "{s}{{\n{s}    var b_{d} = {s}.{s}({s}, {s});\n{s}    defer b_{d}.end();\n{s}{s}{s}}}\n", .{ indent, indent, base, self.ui_name, dir, self.c_name, try self.optsLiteral(el, base, loops), indent, base, indent, inner.code, indent });
            try self.preamble.appendSlice(inner.preamble);
            return .{ .code = try out.toOwnedSlice(), .preamble = "", .next_id = inner.next_id };
        } else if (std.mem.eql(u8, el.tag, "label")) {
            const text = try self.firstTextLiteral(el);
            return .{ .code = try std.fmt.allocPrint(self.a, "{s}{s}.text({s}, {s}, {s});\n", .{ indent, self.ui_name, self.c_name, text, try self.optsLiteral(el, base, loops) }), .preamble = "", .next_id = base + 1 };
        } else if (std.mem.eql(u8, el.tag, "button")) {
            const text = try self.firstTextLiteral(el);
            const opts = try self.optsLiteral(el, base, loops);
            if (findEventExpr(el, "click")) |h| {
                return .{ .code = try std.fmt.allocPrint(self.a, "{s}if ({s}.button({s}, {s}, {s})) {s};\n", .{ indent, self.ui_name, self.c_name, text, opts, h }), .preamble = "", .next_id = base + 1 };
            }
            return .{ .code = try std.fmt.allocPrint(self.a, "{s}_ = {s}.button({s}, {s}, {s});\n", .{ indent, self.ui_name, self.c_name, text, opts }), .preamble = "", .next_id = base + 1 };
        } else if (std.mem.indexOf(u8, el.tag, ".") != null) {
            return self.emitComponent(el, level, base, loops, true);
        } else if (isUpper(el.tag[0])) {
            return self.emitComponent(el, level, base, loops, false);
        }
        return error.ZsxParseError;
    }

    fn emitComponent(self: *Emitter, el: ast.Element, level: usize, base: usize, loops: []const Loop, is_path: bool) anyerror!EmitResult {
        const indent = try self.makeIndent(level);

        if (hasSlotChildren(el)) {
            var pre = std.array_list.Managed(u8).init(self.a);
            var fields = std.array_list.Managed(Field).init(self.a);
            var id = base + 1;
            for (el.children) |c| switch (c) {
                .element => |slot| {
                    if (!std.mem.eql(u8, slot.tag, "Slot")) return error.ZsxParseError;
                    const name = try getSlotName(slot);
                    const hint = try std.fmt.allocPrint(self.a, "{s}_{s}", .{ el.tag, name });
                    const body = try self.buildBody(slot.children, id, loops, hint);
                    if (body.pre.len != 0) try pre.appendSlice(body.pre);
                    try fields.append(.{ .name = name, .value = body.value });
                    id = body.next_id;
                },
                .text => |t| if (!isWhitespaceOnly(t)) return error.ZsxParseError,
                .expression => return error.ZsxParseError,
            };
            const props = try self.propsLiteral(el, false, base, loops, fields.items);
            const call = if (is_path)
                try std.fmt.allocPrint(self.a, "{s}({s}, {s}, {s}, {s})", .{ el.tag, self.ctx_name, self.ui_name, self.c_name, props })
            else
                try std.fmt.allocPrint(self.a, "{s}.{s}({s}, {s}, {s})", .{ self.ctx_name, el.tag, self.ui_name, self.c_name, props });
            return .{ .code = try std.fmt.allocPrint(self.a, "{s}{s}{s};\n", .{ pre.items, indent, call }), .preamble = "", .next_id = id };
        }

        if (hasElementChildren(el)) {
            const body = try self.buildBody(el.children, base + 1, loops, el.tag);
            const fields = [_]Field{.{ .name = "content", .value = body.value }};
            const props = try self.propsLiteral(el, false, base, loops, &fields);
            const call = if (is_path)
                try std.fmt.allocPrint(self.a, "{s}({s}, {s}, {s}, {s})", .{ el.tag, self.ctx_name, self.ui_name, self.c_name, props })
            else
                try std.fmt.allocPrint(self.a, "{s}.{s}({s}, {s}, {s})", .{ self.ctx_name, el.tag, self.ui_name, self.c_name, props });
            return .{ .code = try std.fmt.allocPrint(self.a, "{s}{s}{s};\n", .{ body.pre, indent, call }), .preamble = "", .next_id = body.next_id };
        }

        const props = try self.propsLiteral(el, true, base, loops, &.{});
        const call = if (is_path)
            try std.fmt.allocPrint(self.a, "{s}({s}, {s}, {s}, {s})", .{ el.tag, self.ctx_name, self.ui_name, self.c_name, props })
        else
            try std.fmt.allocPrint(self.a, "{s}.{s}({s}, {s}, {s})", .{ self.ctx_name, el.tag, self.ui_name, self.c_name, props });
        return .{ .code = try std.fmt.allocPrint(self.a, "{s}{s};\n", .{ indent, call }), .preamble = "", .next_id = base + 1 };
    }

    const TextMode = enum { reject, render };

    /// The single control-flow lowering used by element bodies *and* slot /
    /// content bodies (F2). Loop depth is unbounded; each `{for}` pushes a
    /// `Loop`, so nested loops get distinct `idx_N` names and distinct IDs.
    fn emitChildren(self: *Emitter, children: []const ast.Child, start_level: usize, start_id: usize, incoming_loops: []const Loop, text_mode: TextMode) anyerror!EmitResult {
        var code = std.array_list.Managed(u8).init(self.a);
        var level = start_level;
        var id = start_id;
        var loops = std.array_list.Managed(Loop).init(self.a);
        try loops.appendSlice(incoming_loops);
        var stack: [64]u8 = undefined;
        var stack_depth: usize = 0;
        var switch_exprs: [32][]const u8 = undefined;
        var switch_depth: usize = 0;

        for (children) |child| switch (child) {
            .element => |el| {
                const r = try self.emitElement(el, level, id, loops.items);
                try code.appendSlice(r.code);
                try self.preamble.appendSlice(r.preamble);
                id = r.next_id;
            },
            .text => |t| if (!isWhitespaceOnly(t)) {
                if (text_mode == .reject) return error.ZsxParseError;
                try code.appendSlice(try std.fmt.allocPrint(self.a, "{s}{s}.text({s}, \"{s}\", .{{}});\n", .{ try self.makeIndent(level), self.ui_name, self.c_name, try self.escapeString(t) }));
            },
            .expression => |raw| {
                const e = std.mem.trim(u8, raw, " \t\n\r");
                if (stack_depth >= stack.len) return error.ZsxParseError;
                if (std.mem.startsWith(u8, e, "if ")) {
                    const cond = std.mem.trim(u8, e[3..], " \t\n\r");
                    if (cond.len == 0) return error.ZsxParseError;
                    try writeFmt(self.a, &code, "{s}if ({s}) {{\n", .{ try self.makeIndent(level), cond });
                    stack[stack_depth] = 'i';
                    stack_depth += 1;
                    level += 1;
                } else if (std.mem.startsWith(u8, e, "for ") and std.mem.indexOf(u8, e, " as ") != null) {
                    const body = std.mem.trim(u8, e[4..], " \t\n\r");
                    const as_idx = std.mem.indexOf(u8, body, " as ").?;
                    const items = std.mem.trim(u8, body[0..as_idx], " \t\n\r");
                    const binding = std.mem.trim(u8, body[as_idx + 4 ..], " \t\n\r");
                    if (items.len == 0 or binding.len == 0) return error.ZsxParseError;
                    const idx_name = try std.fmt.allocPrint(self.a, "idx_{d}", .{loops.items.len});
                    try writeFmt(self.a, &code, "{s}for ({s}, 0..) |{s}, {s}| {{\n", .{ try self.makeIndent(level), items, binding, idx_name });
                    try loops.append(.{ .value = binding, .index = idx_name });
                    stack[stack_depth] = 'f';
                    stack_depth += 1;
                    level += 1;
                } else if (std.mem.startsWith(u8, e, "switch ")) {
                    const expr = std.mem.trim(u8, e[7..], " \t\n\r");
                    if (expr.len == 0 or switch_depth >= switch_exprs.len) return error.ZsxParseError;
                    switch_exprs[switch_depth] = expr;
                    switch_depth += 1;
                    stack[stack_depth] = 'S';
                    stack_depth += 1;
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
                        level += 1;
                        stack[stack_depth] = 'c';
                        stack_depth += 1;
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
                    if (top == 'i' or top == 'c') {
                        stack[stack_depth - 1] = if (top == 'i') 'e' else 'E';
                        level -= 1;
                        try writeFmt(self.a, &code, "{s}}} else {{\n", .{try self.makeIndent(level)});
                        level += 1;
                    } else return error.ZsxParseError;
                } else if (std.mem.eql(u8, e, "/if") or std.mem.eql(u8, e, "endif")) {
                    if (stack_depth == 0) return error.ZsxParseError;
                    const top = stack[stack_depth - 1];
                    if (top != 'i' and top != 'e') return error.ZsxParseError;
                    stack_depth -= 1;
                    level -= 1;
                    try writeFmt(self.a, &code, "{s}}}\n", .{try self.makeIndent(level)});
                } else if (std.mem.eql(u8, e, "/for") or std.mem.eql(u8, e, "endfor")) {
                    if (stack_depth == 0 or stack[stack_depth - 1] != 'f') return error.ZsxParseError;
                    stack_depth -= 1;
                    level -= 1;
                    if (loops.items.len == incoming_loops.len) return error.ZsxParseError;
                    _ = loops.pop();
                    try writeFmt(self.a, &code, "{s}}}\n", .{try self.makeIndent(level)});
                } else if (std.mem.eql(u8, e, "/switch") or std.mem.eql(u8, e, "endswitch")) {
                    if (stack_depth == 0) return error.ZsxParseError;
                    const top = stack[stack_depth - 1];
                    if (top == 'S') return error.ZsxParseError;
                    if (top != 'c' and top != 'E') return error.ZsxParseError;
                    stack_depth -= 1;
                    level -= 1;
                    try writeFmt(self.a, &code, "{s}}}\n", .{try self.makeIndent(level)});
                    if (stack_depth == 0 or stack[stack_depth - 1] != 'S') return error.ZsxParseError;
                    stack_depth -= 1;
                    switch_depth -= 1;
                } else return error.ZsxParseError;
            },
        };
        if (stack_depth != 0) return error.ZsxParseError;
        return .{ .code = try code.toOwnedSlice(), .preamble = "", .next_id = id };
    }
};

pub const BlockOutput = struct { preamble: []const u8, code: []const u8 };

pub fn emitBlock(a: std.mem.Allocator, root: ast.Element, src_key: []const u8, block_index: usize) !BlockOutput {
    var em = Emitter.init(a, src_key, block_index);
    defer em.deinit();
    const result = try em.emitElement(root, 1, 0, &.{});
    const preamble = try em.preamble.toOwnedSlice();
    return .{ .preamble = preamble, .code = result.code };
}

pub fn emitBlockJoined(a: std.mem.Allocator, root: ast.Element, src_key: []const u8, block_index: usize) ![]const u8 {
    const split = try emitBlock(a, root, src_key, block_index);
    return std.fmt.allocPrint(a, "{s}{s}", .{ split.preamble, split.code });
}
