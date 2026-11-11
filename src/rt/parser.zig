const std = @import("std");

pub const AttributeValue = union(enum) {
    boolean,
    string: []const u8,
    expression: []const u8,
};
pub const Attribute = struct { name: []const u8, value: AttributeValue };
pub const Child = union(enum) { element: Element, text: []const u8, expression: []const u8 };
pub const Element = struct {
    tag: []const u8,
    attributes: []Attribute,
    children: []Child,
};

const Parser = struct {
    arena: std.mem.Allocator,
    src: []const u8,
    src_name: []const u8,
    pos: usize = 0,

    fn loc(self: *const Parser) struct { line: usize, col: usize } {
        var line: usize = 1;
        var col: usize = 1;
        const end = @min(self.pos, self.src.len);
        for (self.src[0..end]) |c| {
            if (c == '\n') {
                line += 1;
                col = 1;
            } else col += 1;
        }
        return .{ .line = line, .col = col };
    }
    fn fail(self: *const Parser, msg: []const u8) error{ZsxParseError} {
        const l = self.loc();
        std.debug.print("{s}:{d}:{d}: zsx: {s}\n", .{ self.src_name, l.line, l.col, msg });
        return error.ZsxParseError;
    }

    fn parseElement(self: *Parser) anyerror!Element {
        if (self.pos >= self.src.len or self.src[self.pos] != '<') return self.fail("expected '<'");
        self.pos += 1;
        const tag_start = self.pos;
        while (self.pos < self.src.len and isTagChar(self.src[self.pos])) : (self.pos += 1) {}
        const tag = self.src[tag_start..self.pos];

        var attrs = std.array_list.Managed(Attribute).init(self.arena);
        var self_closing = false;
        while (true) {
            while (self.pos < self.src.len and self.src[self.pos] == ' ') : (self.pos += 1) {}
            if (self.pos >= self.src.len) return self.fail("unexpected EOF in opening tag");
            const c = self.src[self.pos];
            if (c == '>') {
                self.pos += 1;
                break;
            }
            if (c == '/') {
                self.pos += 1;
                if (self.pos >= self.src.len or self.src[self.pos] != '>') return self.fail("expected '>' after '/'");
                self.pos += 1;
                self_closing = true;
                break;
            }
            try attrs.append(try self.parseAttribute());
        }
        var children = std.array_list.Managed(Child).init(self.arena);
        if (!self_closing) {
            while (true) {
                if (self.pos >= self.src.len) return self.fail("unexpected EOF inside element");
                if (self.src[self.pos] == '<' and self.pos + 1 < self.src.len and self.src[self.pos + 1] == '/') {
                    self.pos += 2;
                    const close_start = self.pos;
                    while (self.pos < self.src.len and isTagChar(self.src[self.pos])) : (self.pos += 1) {}
                    const close_tag = self.src[close_start..self.pos];
                    if (!std.mem.eql(u8, close_tag, tag)) return self.fail("mismatched closing tag");
                    if (self.pos >= self.src.len or self.src[self.pos] != '>') return self.fail("expected '>' after closing tag");
                    self.pos += 1;
                    break;
                }
                try children.append(try self.parseChild());
            }
        }
        return .{ .tag = tag, .attributes = try attrs.toOwnedSlice(), .children = try children.toOwnedSlice() };
    }

    fn parseAttribute(self: *Parser) anyerror!Attribute {
        const name_start = self.pos;
        while (self.pos < self.src.len and isAttrNameChar(self.src[self.pos])) : (self.pos += 1) {}
        if (self.pos == name_start) return self.fail("expected attribute name");
        const name = self.src[name_start..self.pos];
        if (self.pos >= self.src.len or self.src[self.pos] != '=') return .{ .name = name, .value = .boolean };
        self.pos += 1;
        if (self.pos >= self.src.len) return self.fail("unexpected EOF in attribute value");
        const c = self.src[self.pos];
        if (c == '"') {
            self.pos += 1;
            const val_start = self.pos;
            while (self.pos < self.src.len and self.src[self.pos] != '"') : (self.pos += 1) {}
            if (self.pos >= self.src.len) return self.fail("unterminated string attribute");
            const val = self.src[val_start..self.pos];
            self.pos += 1;
            return .{ .name = name, .value = .{ .string = val } };
        }
        if (c == '{') {
            self.pos += 1;
            const val_start = self.pos;
            var depth: usize = 1;
            while (self.pos < self.src.len and depth > 0) {
                if (self.src[self.pos] == '{') depth += 1;
                if (self.src[self.pos] == '}') depth -= 1;
                if (depth > 0) self.pos += 1;
            }
            if (self.pos >= self.src.len) return self.fail("unterminated expression attribute");
            const val = self.src[val_start..self.pos];
            self.pos += 1;
            return .{ .name = name, .value = .{ .expression = val } };
        }
        return self.fail("expected quoted string or {expression}");
    }

    fn parseChild(self: *Parser) anyerror!Child {
        if (self.src[self.pos] == '<') return .{ .element = try self.parseElement() };
        if (self.src[self.pos] == '{') {
            self.pos += 1;
            const val_start = self.pos;
            var depth: usize = 1;
            while (self.pos < self.src.len and depth > 0) {
                if (self.src[self.pos] == '{') depth += 1;
                if (self.src[self.pos] == '}') depth -= 1;
                if (depth > 0) self.pos += 1;
            }
            if (self.pos >= self.src.len) return self.fail("unterminated expression child");
            const val = self.src[val_start..self.pos];
            self.pos += 1;
            return .{ .expression = val };
        }
        const start = self.pos;
        while (self.pos < self.src.len and self.src[self.pos] != '<' and self.src[self.pos] != '{') : (self.pos += 1) {}
        if (self.pos == start) return self.fail("expected text content");
        return .{ .text = self.src[start..self.pos] };
    }
};

pub fn parse(a: std.mem.Allocator, src: []const u8, src_name: []const u8) anyerror!Element {
    var p = Parser{ .arena = a, .src = src, .src_name = src_name };
    const el = try p.parseElement();
    if (p.pos != src.len) return p.fail("trailing input after root element");
    return el;
}

pub fn parseElement(a: std.mem.Allocator, src: []const u8, src_name: []const u8, pos: *usize) anyerror!Element {
    var p = Parser{ .arena = a, .src = src, .src_name = src_name, .pos = pos.* };
    const el = try p.parseElement();
    pos.* = p.pos;
    return el;
}

fn isTagChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-' or c == '.';
}
fn isAttrNameChar(c: u8) bool {
    return isTagChar(c) or c == ':' or c == '.';
}

test "rt parser: simple element" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parse(arena.allocator(), "<column></column>", "test.zsx");
    try std.testing.expectEqualStrings("column", el.tag);
    try std.testing.expectEqual(@as(usize, 0), el.attributes.len);
    try std.testing.expectEqual(@as(usize, 0), el.children.len);
}

test "rt parser: boolean attribute" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parse(arena.allocator(), "<column flex></column>", "test.zsx");
    try std.testing.expectEqual(@as(usize, 1), el.attributes.len);
    try std.testing.expectEqualStrings("flex", el.attributes[0].name);
    try std.testing.expect(el.attributes[0].value == .boolean);
}

test "rt parser: expression attribute" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parse(arena.allocator(), "<div gap={8}></div>", "test.zsx");
    try std.testing.expectEqualStrings("gap", el.attributes[0].name);
    switch (el.attributes[0].value) {
        .expression => |e| try std.testing.expectEqualStrings("8", e),
        else => return error.TestUnexpected,
    }
}

test "rt parser: string attribute" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parse(arena.allocator(), "<div class=\"p-4\"></div>", "test.zsx");
    switch (el.attributes[0].value) {
        .string => |s| try std.testing.expectEqualStrings("p-4", s),
        else => return error.TestUnexpected,
    }
}

test "rt parser: self-closing" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parse(arena.allocator(), "<input />", "test.zsx");
    try std.testing.expectEqualStrings("input", el.tag);
    try std.testing.expectEqual(@as(usize, 0), el.children.len);
}

test "rt parser: text child" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parse(arena.allocator(), "<label>Hello</label>", "test.zsx");
    switch (el.children[0]) {
        .text => |t| try std.testing.expectEqualStrings("Hello", t),
        else => return error.TestUnexpected,
    }
}

test "rt parser: expression child" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parse(arena.allocator(), "<label>{greeting}</label>", "test.zsx");
    switch (el.children[0]) {
        .expression => |e| try std.testing.expectEqualStrings("greeting", e),
        else => return error.TestUnexpected,
    }
}

test "rt parser: nested element" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parse(arena.allocator(), "<column><label>Hi</label></column>", "test.zsx");
    switch (el.children[0]) {
        .element => |child| try std.testing.expectEqualStrings("label", child.tag),
        else => return error.TestUnexpected,
    }
}

test "rt parser: path-qualified tag" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parse(arena.allocator(), "<shadcn.Button>Save</shadcn.Button>", "test.zsx");
    try std.testing.expectEqualStrings("shadcn.Button", el.tag);
}

test "rt parser: multiple attributes" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const el = try parse(arena.allocator(), "<button class=\"bg-blue-500\" on_click={save} disabled></button>", "test.zsx");
    try std.testing.expectEqual(@as(usize, 3), el.attributes.len);
}

test "rt parser: mismatched closing tag fails" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try std.testing.expectError(error.ZsxParseError, parse(arena.allocator(), "<column></row>", "test.zsx"));
}

test "rt parser: trailing input fails" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try std.testing.expectError(error.ZsxParseError, parse(arena.allocator(), "<column></column>extra", "test.zsx"));
}
