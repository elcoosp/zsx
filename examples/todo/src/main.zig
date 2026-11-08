const std = @import("std");
const store_mod = @import("store.zig");
const stub = @import("stub.zig");
const todo = @import("todo");

const Ctx = struct {
    store: store_mod.Store = .{},
    new_text: [128]u8 = @splat(0),
    last_error: [64]u8 = @splat(0),
    last_error_len: u8 = 0,
    io: ?std.Io = null,

    pub fn setText(self: *@This(), s: []const u8) void {
        @memset(&self.new_text, 0);
        const n = @min(s.len, 127);
        @memcpy(self.new_text[0..n], s[0..n]);
    }

    pub fn add(self: *@This()) void {
        self.last_error_len = 0;
        const n = std.mem.indexOfScalar(u8, &self.new_text, 0) orelse self.new_text.len;
        self.store.add(self.new_text[0..n]) catch |e| {
            const msg: []const u8 = switch (e) {
                error.EmptyText => "empty text",
                error.TooLong => "text too long (max 128)",
                error.Full => "list full (max 64)",
            };
            self.setError(msg);
            return;
        };
        @memset(&self.new_text, 0);
    }

    pub fn clearDone(self: *@This()) void {
        _ = self.store.clearDone();
    }

    pub fn save(self: *@This()) void {
        const io = self.io orelse {
            self.setError("no io");
            return;
        };
        self.store.saveJson("todos.json", io) catch |e| {
            const msg = std.fmt.bufPrint(&self.last_error, "save: {s}", .{@errorName(e)}) catch "save failed";
            self.last_error_len = @intCast(@min(msg.len, 64));
        };
    }

    pub fn errorText(self: *@This()) []const u8 {
        return self.last_error[0..self.last_error_len];
    }

    pub fn itemText(self: *@This(), item: store_mod.Item) []const u8 {
        _ = self;
        return item.slice();
    }

    pub fn itemColor(self: *@This(), item: store_mod.Item) []const u8 {
        _ = self;
        return if (item.done) "green" else "blue";
    }

    fn setError(self: *@This(), msg: []const u8) void {
        self.last_error_len = @intCast(@min(msg.len, 64));
        @memcpy(self.last_error[0..self.last_error_len], msg[0..self.last_error_len]);
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var ctx = Ctx{ .io = io };

    ctx.store.loadJson(std.heap.page_allocator, "todos.json", io) catch |e| {
        std.debug.print("load failed: {any}\n", .{e});
    };
    std.debug.print("loaded: {d} items\n\n", .{ctx.store.len});

    var c: stub.Context = .{};

    std.debug.print("=== Step 1: render empty ===\n", .{});
    stub.resetCounters();
    todo.view(stub.Adapter, &c, &ctx);
    std.debug.print("labels={d} buttons={d} dividers={d}\n\n", .{
        stub.labelsRendered(), stub.buttonsRendered(), stub.dividersRendered(),
    });

    std.debug.print("=== Step 2: add empty (error) ===\n", .{});
    ctx.setText("");
    ctx.add();
    std.debug.print("error: {s}\n", .{ctx.errorText()});
    stub.resetCounters();
    todo.view(stub.Adapter, &c, &ctx);
    std.debug.print("labels={d} (error badge adds 1)\n\n", .{stub.labelsRendered()});

    std.debug.print("=== Step 3: add items ===\n", .{});
    ctx.setText("Buy milk");
    ctx.add();
    ctx.setText("Walk dog");
    ctx.add();
    ctx.setText("Write tests");
    ctx.add();
    std.debug.print("store.len={d}, next_id={d}\n", .{ ctx.store.len, ctx.store.next_id });

    stub.resetCounters();
    todo.view(stub.Adapter, &c, &ctx);
    std.debug.print("rendered: labels={d} buttons={d}\n\n", .{
        stub.labelsRendered(), stub.buttonsRendered(),
    });

    std.debug.print("=== Step 4: UI click on Add ===\n", .{});
    ctx.setText("Read book");
    stub.resetCounters();
    stub.clickButtonByLabel("Add");
    todo.view(stub.Adapter, &c, &ctx);
    std.debug.print("after click: store.len={d} buttons={d}\n\n", .{
        ctx.store.len, stub.buttonsRendered(),
    });

    std.debug.print("=== Step 5: save ===\n", .{});
    ctx.save();
    if (ctx.last_error_len > 0) {
        std.debug.print("save error: {s}\n", .{ctx.errorText()});
    } else {
        std.debug.print("saved to todos.json\n", .{});
    }

    std.debug.print("\n=== Step 6: reload from disk ===\n", .{});
    var ctx2 = Ctx{ .io = io };
    ctx2.store.loadJson(std.heap.page_allocator, "todos.json", io) catch |e| {
        std.debug.print("reload failed: {any}\n", .{e});
        return;
    };
    std.debug.print("reloaded: {d} items\n", .{ctx2.store.len});
    for (ctx2.store.items[0..ctx2.store.len]) |item| {
        std.debug.print("  [{d}] {s} done={}\n", .{ item.id, item.slice(), item.done });
    }

    std.debug.print("\n=== All steps complete ===\n", .{});
}

test "add rejects empty" {
    var s = store_mod.Store{};
    try std.testing.expectError(error.EmptyText, s.add(""));
    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "add appends items" {
    var s = store_mod.Store{};
    try s.add("a");
    try s.add("b");
    try std.testing.expectEqual(@as(usize, 2), s.len);
    try std.testing.expectEqualStrings("a", s.items[0].slice());
    try std.testing.expectEqualStrings("b", s.items[1].slice());
    try std.testing.expectEqual(@as(u32, 3), s.next_id);
}

test "findById returns item or null" {
    var s = store_mod.Store{};
    try s.add("x");
    try std.testing.expect(s.findById(1) != null);
    try std.testing.expect(s.findById(999) == null);
}

test "clearDone removes only done items" {
    var s = store_mod.Store{};
    try s.add("a");
    try s.add("b");
    try s.add("c");
    s.items[1].done = true;
    const removed = s.clearDone();
    try std.testing.expectEqual(@as(usize, 1), removed);
    try std.testing.expectEqual(@as(usize, 2), s.len);
    try std.testing.expectEqualStrings("a", s.items[0].slice());
    try std.testing.expectEqualStrings("c", s.items[1].slice());
}

test "todo view renders empty state" {
    var ctx = Ctx{};
    var c: stub.Context = .{};
    stub.resetCounters();
    todo.view(stub.Adapter, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), stub.textEntriesRendered());
    try std.testing.expectEqual(@as(usize, 2), stub.dividersRendered());
    try std.testing.expectEqual(@as(usize, 3), stub.buttonsRendered());
}

test "todo view renders items" {
    var ctx = Ctx{};
    try ctx.store.add("alpha");
    try ctx.store.add("beta");
    var c: stub.Context = .{};
    stub.resetCounters();
    todo.view(stub.Adapter, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 3), stub.buttonsRendered());
}
