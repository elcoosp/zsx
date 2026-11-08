//! HTML adapter — emits plain semantic HTML with inline styles.
//!
//! Works with any writer type W that has:
//!     pub fn writeAll(self: *W, bytes: []const u8) !void

const std = @import("std");

pub fn Adapter(comptime W: type) type {
    return struct {
        pub const Box = struct {
            w: *W,
            pub fn end(self: Box) void {
                writeRaw(self.w, "</div>");
            }
        };

        pub fn column(c: *W, opts: anytype) Box {
            openBlock(c, "flex flex-col", opts);
            return .{ .w = c };
        }

        pub fn row(c: *W, opts: anytype) Box {
            openBlock(c, "flex flex-row", opts);
            return .{ .w = c };
        }

        pub fn text(c: *W, str: []const u8, opts: anytype) void {
            openInline(c, "span", opts);
            writeEscaped(c, str);
            writeRaw(c, "</span>");
        }

        pub fn button(c: *W, title: []const u8, opts: anytype) bool {
            openInline(c, "button", opts);
            writeEscaped(c, title);
            writeRaw(c, "</button>");
            return false;
        }

        pub fn textEntry(c: *W, buffer: []u8, opts: anytype) void {
            writeRaw(c, "<input type=\"text\"");
            writePlaceholder(c, opts);
            writeInputValue(c, buffer);
            writeRaw(c, ">");
        }

        pub fn textArea(c: *W, buffer: []u8, opts: anytype) void {
            writeRaw(c, "<textarea");
            writePlaceholder(c, opts);
            writeRaw(c, ">");
            const n = std.mem.indexOfScalar(u8, buffer, 0) orelse buffer.len;
            if (n > 0) writeEscaped(c, buffer[0..n]);
            writeRaw(c, "</textarea>");
        }

        pub fn checkbox(c: *W, title: []const u8, value: *bool, opts: anytype) bool {
            _ = opts;
            writeRaw(c, "<label><input type=\"checkbox\"");
            if (value.*) writeRaw(c, " checked");
            writeRaw(c, ">");
            writeEscaped(c, title);
            writeRaw(c, "</label>");
            return false;
        }

        pub fn progress(c: *W, value: f32, opts: anytype) void {
            _ = opts;
            const clamped: f32 = if (value < 0.0) 0.0 else if (value > 1.0) 1.0 else value;
            const pct: u32 = @intFromFloat(clamped * 100.0);
            var buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "<progress value=\"{d}\" max=\"100\"></progress>", .{pct}) catch return;
            writeRaw(c, s);
        }

        pub fn divider(c: *W, opts: anytype) void {
            _ = opts;
            writeRaw(c, "<hr>");
        }

        pub fn slider(c: *W, value: *f32, opts: anytype) bool {
            _ = opts;
            var buf: [96]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "<input type=\"range\" min=\"0\" max=\"1\" step=\"0.01\" value=\"{d:.2}\">", .{value.*}) catch return false;
            writeRaw(c, s);
            return false;
        }

        pub fn toggle(c: *W, label: []const u8, value: *bool, opts: anytype) bool {
            return checkbox(c, label, value, opts);
        }

        pub fn skeleton(c: *W, opts: anytype) void {
            writeRaw(c, "<div class=\"skeleton\"");
            var style_started = false;
            if (comptime @hasField(@TypeOf(opts), "width")) {
                const w_raw = opts.width;
                const w_f: f32 = comptime toFloat(@TypeOf(w_raw), w_raw);
                const w_px: u32 = @intFromFloat(w_f);
                var buf: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, " style=\"width:{d}px", .{w_px}) catch "";
                writeRaw(c, s);
                style_started = true;
            }
            if (comptime @hasField(@TypeOf(opts), "height")) {
                const h_raw = opts.height;
                const h_f: f32 = comptime toFloat(@TypeOf(h_raw), h_raw);
                const h_px: u32 = @intFromFloat(h_f);
                if (style_started) {
                    var buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, ";height:{d}px", .{h_px}) catch "";
                    writeRaw(c, s);
                }
            }
            if (style_started) writeRaw(c, "\"");
            writeRaw(c, "></div>");
        }

        fn openBlock(c: *W, comptime classes: []const u8, opts: anytype) void {
            writeRaw(c, "<div class=\"");
            writeRaw(c, classes);
            writeRaw(c, "\"");
            writeInlineStyle(c, opts);
            writeDataId(c, opts);
            writeRaw(c, ">");
        }

        fn openInline(c: *W, comptime tag: []const u8, opts: anytype) void {
            writeRaw(c, "<");
            writeRaw(c, tag);
            writeInlineStyle(c, opts);
            writeDataId(c, opts);
            writeRaw(c, ">");
        }

        // toFloat: comptime-coerce any numeric type to f32
        fn toFloat(comptime T: type, comptime v: T) f32 {
            return switch (@typeInfo(T)) {
                .int, .comptime_int => @floatFromInt(v),
                .float, .comptime_float => @floatCast(v),
                else => 0.0,
            };
        }

        fn writeInlineStyle(c: *W, opts: anytype) void {
            var buf: [256]u8 = undefined;
            var len: usize = 0;
            var started = false;

            if (comptime @hasField(@TypeOf(opts), "color_fill")) {
                const cf_type = @TypeOf(opts.color_fill);
                if (comptime @typeInfo(cf_type) == .optional) {
                    if (opts.color_fill) |cf| {
                        const s = std.fmt.bufPrint(buf[len..], "background:rgb({d},{d},{d});", .{ cf.r, cf.g, cf.b }) catch return;
                        len += s.len;
                        started = true;
                    }
                } else {
                    const cf = opts.color_fill;
                    const s = std.fmt.bufPrint(buf[len..], "background:rgb({d},{d},{d});", .{ cf.r, cf.g, cf.b }) catch return;
                    len += s.len;
                    started = true;
                }
            }
            if (comptime @hasField(@TypeOf(opts), "color_text")) {
                const ct_type = @TypeOf(opts.color_text);
                if (comptime @typeInfo(ct_type) == .optional) {
                    if (opts.color_text) |ct| {
                        const s = std.fmt.bufPrint(buf[len..], "color:rgb({d},{d},{d});", .{ ct.r, ct.g, ct.b }) catch return;
                        len += s.len;
                        started = true;
                    }
                } else {
                    const ct = opts.color_text;
                    const s = std.fmt.bufPrint(buf[len..], "color:rgb({d},{d},{d});", .{ ct.r, ct.g, ct.b }) catch return;
                    len += s.len;
                    started = true;
                }
            }
            if (comptime @hasField(@TypeOf(opts), "font_size")) {
                const fs_type = @TypeOf(opts.font_size);
                if (comptime @typeInfo(fs_type) == .optional) {
                    if (opts.font_size) |fs| {
                        const px: u32 = @intFromFloat(@as(f32, @floatCast(fs)));
                        const s = std.fmt.bufPrint(buf[len..], "font-size:{d}px;", .{px}) catch return;
                        len += s.len;
                        started = true;
                    }
                } else {
                    const fs: f32 = toFloat(fs_type, opts.font_size);
                    const px: u32 = @intFromFloat(fs);
                    const s = std.fmt.bufPrint(buf[len..], "font-size:{d}px;", .{px}) catch return;
                    len += s.len;
                    started = true;
                }
            }
            if (started) {
                writeRaw(c, " style=\"");
                writeRaw(c, buf[0..len]);
                writeRaw(c, "\"");
            }
        }

        fn writeDataId(c: *W, opts: anytype) void {
            if (comptime @hasField(@TypeOf(opts), "id_extra")) {
                const id_type = @TypeOf(opts.id_extra);
                if (comptime @typeInfo(id_type) == .optional) {
                    if (opts.id_extra) |id| {
                        writeId(c, id);
                    }
                } else {
                    writeId(c, opts.id_extra);
                }
            }
        }

        fn writeId(c: *W, id: anytype) void {
            var buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, " data-id=\"{d}\"", .{id}) catch return;
            writeRaw(c, s);
        }

        fn writePlaceholder(c: *W, opts: anytype) void {
            if (comptime @hasField(@TypeOf(opts), "placeholder")) {
                const p_type = @TypeOf(opts.placeholder);
                if (comptime @typeInfo(p_type) == .optional) {
                    if (opts.placeholder) |p| {
                        writeAttr(c, " placeholder=\"", p);
                    }
                } else {
                    writeAttr(c, " placeholder=\"", opts.placeholder);
                }
            }
        }

        fn writeAttr(c: *W, comptime prefix: []const u8, value: []const u8) void {
            writeRaw(c, prefix);
            writeEscaped(c, value);
            writeRaw(c, "\"");
        }

        fn writeInputValue(c: *W, buffer: []u8) void {
            const n = std.mem.indexOfScalar(u8, buffer, 0) orelse buffer.len;
            if (n > 0) {
                writeRaw(c, " value=\"");
                writeEscaped(c, buffer[0..n]);
                writeRaw(c, "\"");
            }
        }

        fn writeRaw(c: *W, s: []const u8) void {
            c.writeAll(s) catch {};
        }

        fn writeEscaped(c: *W, s: []const u8) void {
            for (s) |ch| {
                switch (ch) {
                    '<' => writeRaw(c, "&lt;"),
                    '>' => writeRaw(c, "&gt;"),
                    '&' => writeRaw(c, "&amp;"),
                    '"' => writeRaw(c, "&quot;"),
                    else => writeRaw(c, &[_]u8{ch}),
                }
            }
        }
    };
}

pub const TestWriter = struct {
    buf: [16384]u8 = undefined,
    len: usize = 0,

    pub fn writeAll(self: *@This(), s: []const u8) !void {
        if (self.len + s.len > self.buf.len) return error.NoSpace;
        @memcpy(self.buf[self.len..][0..s.len], s);
        self.len += s.len;
    }

    pub fn output(self: *@This()) []const u8 {
        return self.buf[0..self.len];
    }
};

test "html adapter: text escapes dangerous chars" {
    const A = Adapter(TestWriter);
    var c: TestWriter = .{};
    A.text(&c, "a<b>&c", .{});
    try std.testing.expect(std.mem.indexOf(u8, c.output(), "a&lt;b&gt;&amp;c") != null);
}

test "html adapter: button renders with closing tag" {
    const A = Adapter(TestWriter);
    var c: TestWriter = .{};
    _ = A.button(&c, "Save", .{});
    try std.testing.expect(std.mem.indexOf(u8, c.output(), "<button>Save</button>") != null);
}

test "html adapter: column wraps children in div" {
    const A = Adapter(TestWriter);
    var c: TestWriter = .{};
    const b = A.column(&c, .{});
    A.text(&c, "hi", .{});
    b.end();
    const out = c.output();
    try std.testing.expect(std.mem.indexOf(u8, out, "flex flex-col") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<span>hi</span>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "</div>") != null);
}
