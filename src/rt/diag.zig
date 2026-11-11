//! Structured diagnostics shared by ZSX tooling.
//!
//! Until M1, tooling diagnostics were printed ad hoc: `parser.zig` wrote
//! `std.debug.print` lines and returned a bare `error.ZsxParseError`, so
//! callers could never inspect file/line/col programmatically. This module is
//! the seam that replaces that: every check produces `Diagnostic` values with
//! a stable code, severity, source span and help text; the caller decides how
//! to render them (CLI stderr, JSON, future LSP).
//!
//! Codes follow the `ZSX0xxx` numbering reserved by `docs/ZSX_MASTER_PLAN.md`
//! (WP 1.3: "each error has code `ZSX0xxx`, span, help text"). Rendering keeps
//! the repo's existing `path:line:col` convention, e.g.
//!
//!     src/views/dashboard.zsx:14:8: error[ZSX0003]: <row> never closed
//!       help: add `</row>` or make the element self-closing
//!
//! Diagnostics must not abort a check: tooling collects as many as possible
//! per file (error recovery), then reports. Warnings never change the exit
//! code — only `severity == .err` does.

const std = @import("std");

/// Stable diagnostic identifiers. Numbers are part of the public contract:
/// never renumber a code, only add new ones at the end.
pub const Code = enum(u16) {
    /// `</tag>` appeared with no matching open tag on the stack.
    stray_close_tag = 1,
    /// `</tag>` closed a different element than the one opened.
    tag_mismatch = 2,
    /// An open tag was never closed before end of block.
    unclosed_tag = 3,
    /// `{/if}`-style closer with no matching control-flow opener.
    stray_ctrl_close = 4,
    /// `{/for}`-style closer whose kind does not match the opener.
    ctrl_mismatch = 5,
    /// `{if}`/`{for}`/`{switch}` was never closed before end of block.
    unclosed_ctrl = 6,
    /// `{:else}` outside an `{if}` or `{switch}` body.
    misplaced_else = 7,
    /// `{:case}` outside a `{switch}` body.
    misplaced_case = 8,
    /// Class token that does not resolve in the built-in table
    /// (`src/rt/style.zig`). Warning: codegen turns it into
    /// `error.ZsxUnknownClass` at build time.
    unknown_class = 9,
    /// Legacy `{endif}`/`{endfor}`/`{endswitch}` alias. Warning: still
    /// supported, slated for removal per RFC-0001.
    legacy_alias = 10,
    /// `zsx!{` block whose matching `}` was never found.
    unterminated_block = 11,
    /// Markup the tolerant scanner could not make sense of (stray `<`,
    /// unterminated tag or attribute). Errors, not warnings: AGENTS.md
    /// forbids silently ignoring malformed input.
    junk_syntax = 12,

    /// `ZSX0xxx` string form, zero-padded to four digits.
    pub fn number(self: Code) u16 {
        return @backingInt(self);
    }

    /// Short machine-readable name (used by tests and future JSON output).
    pub fn name(self: Code) []const u8 {
        return switch (self) {
            .stray_close_tag => "stray-close-tag",
            .tag_mismatch => "tag-mismatch",
            .unclosed_tag => "unclosed-tag",
            .stray_ctrl_close => "stray-ctrl-close",
            .ctrl_mismatch => "ctrl-mismatch",
            .unclosed_ctrl => "unclosed-ctrl",
            .misplaced_else => "misplaced-else",
            .misplaced_case => "misplaced-case",
            .unknown_class => "unknown-class",
            .legacy_alias => "legacy-alias",
            .unterminated_block => "unterminated-block",
            .junk_syntax => "junk-syntax",
        };
    }
};

pub const Severity = enum { err, warning };

/// One reported issue. `line`/`col` are 1-based; `offset`/`len` are byte
/// spans into the checked source (len 0 = point). All slices are allocated
/// in the caller-provided arena and share its lifetime.
pub const Diagnostic = struct {
    code: Code,
    severity: Severity,
    message: []const u8,
    help: ?[]const u8 = null,
    file: []const u8,
    line: usize,
    col: usize,
    offset: usize,
    len: usize = 0,

    /// Render one line of `path:line:col: severity[code]: message` text,
    /// matching the repo's existing source-span convention.
    pub fn renderHeader(self: Diagnostic, a: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(a, "{s}:{d}:{d}: {s}[ZSX{d:0>4}]: {s}", .{
            self.file,
            self.line,
            self.col,
            switch (self.severity) {
                .err => "error",
                .warning => "warning",
            },
            self.code.number(),
            self.message,
        });
    }
};

/// Byte-offset → (line, column) index. Built once per file with a O(n) scan,
/// then queried in O(log n) — replaces the O(offset) rescan in
/// `parser.zig`'s `loc()` for tooling callers.
pub const LineIndex = struct {
    /// Byte offset of the first byte of each line; starts[0] == 0.
    starts: []const usize,

    pub fn build(a: std.mem.Allocator, src: []const u8) !LineIndex {
        var starts = std.array_list.Managed(usize).init(a);
        try starts.append(0);
        for (src, 0..) |c, i| {
            if (c == '\n') try starts.append(i + 1);
        }
        return .{ .starts = try starts.toOwnedSlice() };
    }

    /// 1-based line and column for a byte offset (clamped to the source end).
    pub fn lineCol(self: LineIndex, offset: usize) struct { line: usize, col: usize } {
        const off = @min(offset, if (self.starts.len == 0) 0 else self.starts[self.starts.len - 1]);
        var lo: usize = 0;
        var hi: usize = self.starts.len;
        while (lo + 1 < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.starts[mid] <= off) lo = mid else hi = mid;
        }
        return .{ .line = lo + 1, .col = off - self.starts[lo] + 1 };
    }
};

/// Accumulates diagnostics for one or more files. Allocator is expected to be
/// an arena owned by the caller; `deinit` only frees the list bookkeeping.
pub const List = struct {
    items: std.array_list.Managed(Diagnostic),
    a: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) List {
        return .{ .items = std.array_list.Managed(Diagnostic).init(a), .a = a };
    }

    pub fn deinit(self: *List) void {
        self.items.deinit();
    }

    /// Append a pre-built diagnostic.
    pub fn add(self: *List, d: Diagnostic) !void {
        try self.items.append(d);
    }

    /// Append an error at a source position.
    pub fn err(self: *List, idx: LineIndex, file: []const u8, offset: usize, len: usize, code: Code, comptime fmt: []const u8, args: anytype) !void {
        try self.appendAt(.err, idx, file, offset, len, code, fmt, args);
    }

    /// Append a warning at a source position.
    pub fn warn(self: *List, idx: LineIndex, file: []const u8, offset: usize, len: usize, code: Code, comptime fmt: []const u8, args: anytype) !void {
        try self.appendAt(.warning, idx, file, offset, len, code, fmt, args);
    }

    fn appendAt(self: *List, severity: Severity, idx: LineIndex, file: []const u8, offset: usize, len: usize, code: Code, comptime fmt: []const u8, args: anytype) !void {
        const pos = idx.lineCol(offset);
        const lc = pos.line;
        const cc = pos.col;
        try self.items.append(.{
            .code = code,
            .severity = severity,
            .message = try std.fmt.allocPrint(self.a, fmt, args),
            .file = file,
            .line = lc,
            .col = cc,
            .offset = offset,
            .len = len,
        });
    }

    pub fn count(self: *const List) usize {
        return self.items.items.len;
    }

    pub fn errorCount(self: *const List) usize {
        var n: usize = 0;
        for (self.items.items) |d| {
            if (d.severity == .err) n += 1;
        }
        return n;
    }

    pub fn warningCount(self: *const List) usize {
        return self.count() - self.errorCount();
    }

    pub fn hasErrors(self: *const List) bool {
        return self.errorCount() != 0;
    }
};

test "diag: line index maps offsets to 1-based line/col" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const idx = try LineIndex.build(a, "abc\ndef\n");
    try std.testing.expectEqual(@as(usize, 1), idx.lineCol(0).line);
    try std.testing.expectEqual(@as(usize, 1), idx.lineCol(0).col);
    try std.testing.expectEqual(@as(usize, 1), idx.lineCol(3).line);
    try std.testing.expectEqual(@as(usize, 4), idx.lineCol(3).col);
    try std.testing.expectEqual(@as(usize, 2), idx.lineCol(4).line);
    try std.testing.expectEqual(@as(usize, 1), idx.lineCol(4).col);
    try std.testing.expectEqual(@as(usize, 2), idx.lineCol(6).line);
    try std.testing.expectEqual(@as(usize, 3), idx.lineCol(6).col);
}

test "diag: render header uses path:line:col and code" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = Diagnostic{
        .code = .unclosed_tag,
        .severity = .err,
        .message = "<row> never closed",
        .file = "src/views/demo.zsx",
        .line = 14,
        .col = 8,
        .offset = 100,
    };
    const s = try d.renderHeader(a);
    try std.testing.expectEqualStrings(
        "src/views/demo.zsx:14:8: error[ZSX0003]: <row> never closed",
        s,
    );
}

test "diag: list counts errors and warnings separately" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const idx = try LineIndex.build(a, "x\ny\n");
    var list = List.init(a);
    defer list.deinit();
    try list.err(idx, "f.zsx", 0, 1, .stray_close_tag, "boom", .{});
    try list.warn(idx, "f.zsx", 2, 1, .unknown_class, "meh", .{});
    try std.testing.expectEqual(@as(usize, 2), list.count());
    try std.testing.expectEqual(@as(usize, 1), list.errorCount());
    try std.testing.expectEqual(@as(usize, 1), list.warningCount());
    try std.testing.expect(list.hasErrors());
}
