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
            if (c == '\n') { line += 1; col = 1; } else col += 1;
        }
        return .{ .line = line, .col = col };
    }
    fn fail(self: *const Parser, msg: []const u8) error{ZsxParseError} {
        const l = self.loc();
        std.log.err("{s}:{d}:{d}: zsx: {s}", .{ self.src_name, l.line, l.col, msg });
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
            if (c == '>') { self.pos += 1; break; }
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
fn isAttrNameChar(c: u8) bool { return isTagChar(c) or c == ':' or c == '.'; }
