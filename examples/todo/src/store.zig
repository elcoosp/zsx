const std = @import("std");

pub const Item = struct {
    id: u32,
    done: bool = false,
    text: [128]u8 = @splat(0),
    text_len: u8 = 0,

    pub fn slice(self: *const Item) []const u8 {
        return self.text[0..self.text_len];
    }
};

pub const Store = struct {
    items: [64]Item = undefined,
    len: usize = 0,
    next_id: u32 = 1,

    pub fn add(self: *Store, text: []const u8) !void {
        if (self.len >= 64) return error.Full;
        if (text.len == 0) return error.EmptyText;
        if (text.len > 128) return error.TooLong;
        self.items[self.len] = .{ .id = self.next_id };
        @memcpy(self.items[self.len].text[0..text.len], text);
        self.items[self.len].text_len = @intCast(text.len);
        self.len += 1;
        self.next_id += 1;
    }

    pub fn findById(self: *const Store, id: u32) ?*const Item {
        for (self.items[0..self.len]) |*item| {
            if (item.id == id) return item;
        }
        return null;
    }

    pub fn clearDone(self: *Store) usize {
        var removed: usize = 0;
        var i: usize = 0;
        while (i < self.len) {
            if (self.items[i].done) {
                var j = i;
                while (j + 1 < self.len) : (j += 1) {
                    self.items[j] = self.items[j + 1];
                }
                self.len -= 1;
                removed += 1;
            } else {
                i += 1;
            }
        }
        return removed;
    }

    pub fn saveJson(self: *const Store, path: []const u8, io: std.Io) !void {
        var buf: [16 * 1024]u8 = undefined;
        var pos: usize = 0;
        const header = std.fmt.bufPrint(buf[pos..], "{{\"next_id\":{d},\"items\":[", .{self.next_id}) catch return error.BufferFull;
        pos += header.len;
        for (self.items[0..self.len], 0..) |item, i| {
            if (i > 0) {
                buf[pos] = ',';
                pos += 1;
            }
            const obj = std.fmt.bufPrint(buf[pos..], "{{\"id\":{d},\"done\":{s},\"text\":\"{s}\"}}", .{
                item.id,
                if (item.done) "true" else "false",
                item.slice(),
            }) catch return error.BufferFull;
            pos += obj.len;
        }
        buf[pos] = ']';
        pos += 1;
        buf[pos] = '}';
        pos += 1;
        const dir = std.Io.Dir.cwd();
        const f = try dir.createFile(io, path, .{ .truncate = true });
        defer f.close(io);
        try f.writeStreamingAll(io, buf[0..pos]);
    }

    pub fn loadJson(self: *Store, allocator: std.mem.Allocator, path: []const u8, io: std.Io) !void {
        const dir = std.Io.Dir.cwd();
        const data = dir.readFileAlloc(io, path, allocator, .limited(64 * 1024)) catch |e| {
            if (e == error.FileNotFound) return;
            return e;
        };
        defer allocator.free(data);
        const marker = "\"items\":[";
        const idx = std.mem.indexOf(u8, data, marker) orelse return;
        var pos: usize = idx + marker.len;
        while (pos < data.len) {
            while (pos < data.len and (data[pos] == ',' or data[pos] == ' ' or data[pos] == '\n')) pos += 1;
            if (pos >= data.len or data[pos] == ']') break;
            if (data[pos] != '{') return error.BadJson;
            pos += 1;
            var item = Item{ .id = 0 };
            while (pos < data.len and data[pos] != '}') {
                while (pos < data.len and (data[pos] == ',' or data[pos] == ' ' or data[pos] == '\n' or data[pos] == '"')) pos += 1;
                if (pos >= data.len) break;
                const kstart = pos;
                while (pos < data.len and data[pos] != '"') pos += 1;
                const key = data[kstart..pos];
                pos += 1;
                while (pos < data.len and data[pos] != ':') pos += 1;
                if (pos < data.len) pos += 1;
                if (std.mem.eql(u8, key, "id")) {
                    const numstart = pos;
                    while (pos < data.len and data[pos] != ',' and data[pos] != '}') pos += 1;
                    item.id = std.fmt.parseInt(u32, data[numstart..pos], 10) catch 0;
                } else if (std.mem.eql(u8, key, "done")) {
                    item.done = pos < data.len and data[pos] == 't';
                    while (pos < data.len and data[pos] != ',' and data[pos] != '}') pos += 1;
                } else if (std.mem.eql(u8, key, "text")) {
                    if (pos < data.len and data[pos] == '"') pos += 1;
                    const vstart = pos;
                    while (pos < data.len and data[pos] != '"') pos += 1;
                    const val = data[vstart..pos];
                    if (val.len <= 128) {
                        @memcpy(item.text[0..val.len], val);
                        item.text_len = @intCast(val.len);
                    }
                    if (pos < data.len) pos += 1;
                }
            }
            if (pos < data.len and data[pos] == '}') pos += 1;
            if (self.len < 64) {
                self.items[self.len] = item;
                self.len += 1;
                if (item.id >= self.next_id) self.next_id = item.id + 1;
            }
        }
    }
};
