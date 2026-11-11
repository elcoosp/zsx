//! Code-frame renderer for ZSX diagnostics — the "show me the source" half
//! of the tooling front-end (master-plan M1 scope: "`ZSX0xxx` rendering with
//! code frames").
//!
//! `diag.zig` gives every diagnostic a stable code, severity and byte span;
//! this module turns one diagnostic plus the checked source into the annotated
//! snippet a developer actually reads:
//!
//!     views/bad.zsx:5:3: error[ZSX0004]: {/for} with no matching {if}/{for}/{switch}
//!       help: add `{/if}` or replace the closer
//!     3 |   <row>
//!     4 |     <label>x</label>
//!     5 |   {/for}
//!       |   ^^^^^^
//!
//! Layout contract (pinned by `src/tests/render.zig`):
//! - one line per source line in the window: `{num} | {content}`;
//! - the gutter right-aligns line numbers to the widest number shown;
//! - gutter-only rows (the caret row) print spaces instead of the number;
//! - the caret row points at the diagnostic span: `len` carets, clamped to
//!   the end of the line, minimum one; zero-length spans render one caret;
//! - the window is `line - context .. line + context`, clamped to the file;
//!   context defaults to 1;
//! - `render` prefixes the frame with the `path:line:col: severity[code]:
//!   message` header from `Diagnostic.renderHeader` and a `  help:` line when
//!   the diagnostic carries help text — byte-identical to what `zsx check`
//!   printed before frames existed, so existing output consumers keep working.
//!
//! Caret placement is derived from the diagnostic's byte `offset`, the same
//! value the checker wrote, so the caret can never disagree with the span;
//! `Diagnostic.line`/`col` are rendered verbatim in the header. Everything is
//! byte-based, matching the scanner and checker (no grapheme handling): the
//! frame is consumed by the same terminals that render the source itself.

const std = @import("std");
const diag = @import("diag.zig");

pub const Options = struct {
    /// Lines of source shown above and below the span's line.
    context: usize = 1,
};

/// Renders diagnostics against one fixed source. Build once per file (the
/// `LineIndex` scan is O(n)) and reuse it for every diagnostic of that file —
/// `zsx check` checks many files per run, so the index is never rebuilt.
pub const Renderer = struct {
    a: std.mem.Allocator,
    src: []const u8,
    idx: diag.LineIndex,

    /// Build a renderer for `src`. The source is borrowed, not copied: it
    /// must outlive every rendered frame (the caller's arena owns both).
    pub fn init(a: std.mem.Allocator, src: []const u8) !Renderer {
        return .{ .a = a, .src = src, .idx = try diag.LineIndex.build(a, src) };
    }

    /// Header + optional help + code frame, separated by newlines. No
    /// trailing newline; callers add one between diagnostics.
    pub fn render(self: *const Renderer, d: diag.Diagnostic, opts: Options) ![]const u8 {
        var out = std.array_list.Managed(u8).init(self.a);
        const header = try d.renderHeader(self.a);
        try out.appendSlice(header);
        try out.appendSlice("\n");
        if (d.help) |h| {
            try out.appendSlice("  help: ");
            try out.appendSlice(h);
            try out.appendSlice("\n");
        }
        try out.appendSlice(try self.renderFrame(d, opts));
        return out.items;
    }

    /// The annotated source snippet only (no header/help). Lines are joined
    /// with `\n`; no trailing newline.
    pub fn renderFrame(self: *const Renderer, d: diag.Diagnostic, opts: Options) ![]const u8 {
        // A source ending in '\n' has a phantom empty line at the end of the
        // index; clamp into the real lines so offsets past the end (and the
        // phantom itself) can never push the caret out of the frame.
        const total = self.effectiveLineCount();
        const span_line = @min(self.idx.lineCol(d.offset).line, total);

        const win_start = span_line -| (opts.context + 1) + 1;
        const win_end = @min(total, span_line + opts.context);
        const num_width = digits(win_end);

        var out = std.array_list.Managed(u8).init(self.a);
        var line = win_start;
        while (line <= win_end) : (line += 1) {
            const content = self.lineContent(line);
            try appendGutter(&out, num_width, try std.fmt.allocPrint(self.a, "{d}", .{line}));
            try out.appendSlice(content);
            try out.appendSlice("\n");
            if (line == span_line) {
                try appendGutter(&out, num_width, "");
                const col = caretCol(self.idx.starts[span_line - 1], content, d.offset);
                try appendNTimes(&out, ' ', col);
                try appendNTimes(&out, '^', caretCount(content, col, d.len));
                try out.appendSlice("\n");
            }
        }
        // Drop the final newline: frames end flush, no trailing blank line.
        _ = out.pop();
        return out.items;
    }

    /// Number of lines the frame may show: the phantom empty line a trailing
    /// '\n' produces in the index is excluded.
    fn effectiveLineCount(self: *const Renderer) usize {
        if (self.src.len != 0 and self.src[self.src.len - 1] == '\n') {
            return self.idx.starts.len - 1;
        }
        return self.idx.starts.len;
    }

    /// 1-based content of line `line`, newline (and a trailing '\r') stripped.
    fn lineContent(self: *const Renderer, line: usize) []const u8 {
        const i = line - 1;
        if (i >= self.idx.starts.len) return "";
        const start = self.idx.starts[i];
        if (start >= self.src.len) return "";
        const next: usize = if (i + 1 < self.idx.starts.len) self.idx.starts[i + 1] else self.src.len;
        var end = @min(next, self.src.len);
        if (end > start and self.src[end - 1] == '\n') end -= 1;
        if (end > start and self.src[end - 1] == '\r') end -= 1;
        return self.src[start..end];
    }
};

/// 0-based caret indent for `offset` on the line starting at `line_start`
/// with content `content`: clamped into the line so past-end offsets point at
/// the last byte instead of escaping the frame.
fn caretCol(line_start: usize, content: []const u8, offset: usize) usize {
    if (offset <= line_start) return 0;
    return @min(offset - line_start, content.len);
}

/// Caret run for a span displayed at 0-based indent `col`: clamped to what
/// the line actually holds, minimum 1 so a point span stays visible.
fn caretCount(content: []const u8, col: usize, len: usize) usize {
    const room = content.len - col;
    if (len == 0) return 1;
    return @max(1, @min(len, room));
}

fn appendGutter(out: *std.array_list.Managed(u8), num_width: usize, num: []const u8) !void {
    try appendNTimes(out, ' ', num_width -| num.len);
    try out.appendSlice(num);
    try out.appendSlice(" | ");
}

fn appendNTimes(out: *std.array_list.Managed(u8), c: u8, n: usize) !void {
    var i: usize = 0;
    while (i < n) : (i += 1) try out.append(c);
}

fn digits(n: usize) usize {
    var d: usize = 1;
    var v = n;
    while (v >= 10) : (v /= 10) d += 1;
    return d;
}

test "render: digits" {
    try testing.expectEqual(@as(usize, 1), digits(0));
    try testing.expectEqual(@as(usize, 1), digits(9));
    try testing.expectEqual(@as(usize, 2), digits(10));
    try testing.expectEqual(@as(usize, 3), digits(999));
}

const testing = std.testing;
