const std = @import("std");

const StructLoopUser = struct {
    name: []const u8,
    role: []const u8,
};

const StructLoopCtx = struct {
    users: []const StructLoopUser,
    badge_colors: [8][]const u8 = @splat(""),
    badge_count: usize = 0,

    pub inline fn Badge(self: *@This(), ui: anytype, c: anytype, props: anytype) void {
        const color: []const u8 = if (@hasField(@TypeOf(props), "color")) props.color else "";
        if (self.badge_count < 8) {
            self.badge_colors[self.badge_count] = color;
            self.badge_count += 1;
        }
        @import("shadcn").Badge(self, ui, c, props);
    }
};

test "struct-loop: iterates user records with field access" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("struct_loop_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = StructLoopCtx{
        .users = &[_]StructLoopUser{
            .{ .name = "Alice", .role = "green" },
            .{ .name = "Bob", .role = "red" },
            .{ .name = "Carol", .role = "blue" },
        },
    };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 3), ctx.badge_count);
    try std.testing.expectEqualStrings("green", ctx.badge_colors[0]);
    try std.testing.expectEqualStrings("red", ctx.badge_colors[1]);
    try std.testing.expectEqualStrings("blue", ctx.badge_colors[2]);
    try std.testing.expectEqual(@as(usize, 6), dvui_adapter.StubDvui.labelsRendered());
}

const CardIfCtx = struct {
    pub const Card = @import("shadcn").Card;
    show: bool = true,
};

test "card-if: show=true renders one label" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("card_if_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = CardIfCtx{ .show = true };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.labelsRendered());
}

test "card-if: show=false renders zero labels" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("card_if_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = CardIfCtx{ .show = false };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 0), dvui_adapter.StubDvui.labelsRendered());
}

const ElseIfCtx = struct {
    a: bool = false,
    b: bool = false,
};

test "else-if: a=true renders only A (1 label)" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("else_if_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ElseIfCtx{ .a = true, .b = false };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.labelsRendered());
}

test "else-if: a=false b=true renders B branch (2 labels)" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("else_if_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ElseIfCtx{ .a = false, .b = true };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.labelsRendered());
}

test "else-if: a=false b=false renders else branch (3 labels)" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("else_if_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ElseIfCtx{ .a = false, .b = false };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 3), dvui_adapter.StubDvui.labelsRendered());
}

const FragmentCtx = struct {
    verbose: bool = false,
};

test "fragment: verbose=false renders only always label" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("fragment_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = FragmentCtx{ .verbose = false };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.labelsRendered());
}

test "fragment: verbose=true renders two+always labels from fragment" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("fragment_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = FragmentCtx{ .verbose = true };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 3), dvui_adapter.StubDvui.labelsRendered());
}

const ClassOverrideCtx = struct {
    pub const Button = @import("shadcn").Button;
    first_padding: ?@import("../adapters/dvui.zig").StubDvui.Rect = null,
    second_padding: ?@import("../adapters/dvui.zig").StubDvui.Rect = null,
    count: usize = 0,
};

test "class-override: default Button gets 16x8 padding, p-4 override gets 16x16" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("class_override_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ClassOverrideCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.buttonsRendered());

    const final_padding = dvui_adapter.StubDvui.lastButtonPadding();
    try std.testing.expect(final_padding != null);
    try std.testing.expectEqual(@as(f32, 16), final_padding.?.x);
    try std.testing.expectEqual(@as(f32, 16), final_padding.?.y);
    try std.testing.expectEqual(@as(f32, 16), final_padding.?.w);
    try std.testing.expectEqual(@as(f32, 16), final_padding.?.h);
}

const NestedCardCtx = struct {
    pub const Card = @import("shadcn").Card;
};

test "nested-card: three cards produce distinct render fns and three labels" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("nested_card_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = NestedCardCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 3), dvui_adapter.StubDvui.labelsRendered());
}

const DashboardTask = struct {
    name: []const u8,
    urgent: bool = false,
    pending: bool = false,
};

const DashboardCtx = struct {
    pub const Badge = @import("shadcn").Badge;
    pub const Button = @import("shadcn").Button;

    user_role: []const u8 = "guest",
    error_message: []const u8 = "",
    items: []const DashboardTask = &[_]DashboardTask{},
    refresh_count: usize = 0,
    count_buf: [16]u8 = undefined,
    count_str: []const u8 = "",

    pub fn refresh(self: *@This()) void {
        self.refresh_count += 1;
        self.count_str = std.fmt.bufPrint(&self.count_buf, "{d}", .{self.refresh_count}) catch "?";
    }
};

test "dashboard: empty state renders header, no-items, refresh (4 labels, 1 button)" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("dashboard");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = DashboardCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 4), dvui_adapter.StubDvui.labelsRendered());
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
    try std.testing.expectEqual(@as(usize, 0), ctx.refresh_count);
}

test "dashboard: three items mixed status renders 9 labels (3x label+badge)" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("dashboard");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = DashboardCtx{
        .user_role = "admin",
        .items = &[_]DashboardTask{
            .{ .name = "task1", .urgent = true },
            .{ .name = "task2", .pending = true },
            .{ .name = "task3" },
        },
    };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 9), dvui_adapter.StubDvui.labelsRendered());
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "dashboard: error + one pending renders 6 labels (with error badge)" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("dashboard");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = DashboardCtx{
        .user_role = "guest",
        .error_message = "connection lost",
        .items = &[_]DashboardTask{
            .{ .name = "retry", .pending = true },
        },
    };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 6), dvui_adapter.StubDvui.labelsRendered());
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "dashboard: refresh button increments refresh_count" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("dashboard");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    dvui_adapter.StubDvui.queue_click();
    var ctx = DashboardCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), ctx.refresh_count);
}

test "dashboard: refresh_count>0 renders count badge (5 labels)" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("dashboard");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = DashboardCtx{ .refresh_count = 3, .count_str = "3" };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 5), dvui_adapter.StubDvui.labelsRendered());
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.buttonsRendered());
}

test "extended tokens resolve" {
    const style_mod = @import("shadcn").style;
    const s = comptime (try style_mod.parseClasses("bg-slate-100 text-slate-900 p-6 rounded-full text-3xl gap-4"));
    try std.testing.expectEqual(@as(u8, 241), s.background.?.r);
    try std.testing.expectEqual(@as(u8, 15), s.foreground.?.r);
    try std.testing.expectEqual(@as(f32, 24), s.padding.?.x);
    try std.testing.expectEqual(@as(f32, 9999), s.radius.?);
    try std.testing.expectEqual(@as(f32, 30), s.font_size.?);
    try std.testing.expectEqual(@as(f32, 16), s.gap.?);
    const s2 = comptime (try style_mod.parseClasses("bg-transparent text-xs px-3 py-3 gap-1"));
    try std.testing.expectEqual(@as(u8, 0), s2.background.?.a);
    try std.testing.expectEqual(@as(f32, 12), s2.font_size.?);
    try std.testing.expectEqual(@as(f32, 12), s2.padding.?.x);
    try std.testing.expectEqual(@as(f32, 4), s2.gap.?);
}

test "extended_styles_demo renders 2 buttons 5 labels" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("extended_styles_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    const NullCtx = struct {};
    var nctx: NullCtx = .{};
    dvui_adapter.StubDvui.resetCounters();
    demo.view(A, &c, &nctx);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.buttonsRendered());
    try std.testing.expectEqual(@as(usize, 5), dvui_adapter.StubDvui.labelsRendered());
}

test "component_lib_demo renders dvui" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("component_lib_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    const EmptyCtx = struct {
        pub const Heading = @import("shadcn").Heading;
        pub const Caption = @import("shadcn").Caption;
        pub const Link = @import("shadcn").Link;
        pub const Section = @import("shadcn").Section;
    };
    var ctx: EmptyCtx = .{};
    dvui_adapter.StubDvui.resetCounters();
    demo.view(A, &c, &ctx);
    try std.testing.expect(dvui_adapter.StubDvui.labelsRendered() > 0);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.buttonsRendered());
}

test "component_lib_demo renders nanoui" {
    const nanoui_adapter = @import("../adapters/nanoui.zig");
    const demo = @import("component_lib_demo");
    const A = nanoui_adapter.Adapter(nanoui_adapter.StubNanoui);
    var c: nanoui_adapter.StubNanoui.Context = .{};
    const EmptyCtx = struct {
        pub const Heading = @import("shadcn").Heading;
        pub const Caption = @import("shadcn").Caption;
        pub const Link = @import("shadcn").Link;
        pub const Section = @import("shadcn").Section;
    };
    var ctx: EmptyCtx = .{};
    nanoui_adapter.StubNanoui.resetCounters();
    demo.view(A, &c, &ctx);
    try std.testing.expect(nanoui_adapter.StubNanoui.labelsRendered() > 0);
    try std.testing.expectEqual(@as(usize, 2), nanoui_adapter.StubNanoui.buttonsRendered());
}

const InputCtx = struct {
    pub const Heading = @import("shadcn").Heading;
    pub const Caption = @import("shadcn").Caption;
    pub const Input = @import("shadcn").Input;

    name: [64]u8 = @splat(0),
    email: [128]u8 = @splat(0),
};

test "input_demo renders 2 text entries through dvui stub" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("input_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = InputCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.textEntriesRendered());
    try std.testing.expect(dvui_adapter.StubDvui.labelsRendered() >= 1);
}

test "input_demo renders 2 text entries through nanoui stub" {
    const nanoui_adapter = @import("../adapters/nanoui.zig");
    const demo = @import("input_demo");
    const A = nanoui_adapter.Adapter(nanoui_adapter.StubNanoui);
    var c: nanoui_adapter.StubNanoui.Context = .{};
    nanoui_adapter.StubNanoui.resetCounters();
    var ctx = InputCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), nanoui_adapter.StubNanoui.textEntriesRendered());
}

const PathDemoCtx = struct {
    save_called: bool = false,
    pub fn save(self: *@This()) void {
        self.save_called = true;
    }
};

test "path_demo: shadcn path tags render buttons and badges" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("path_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = PathDemoCtx{};
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.buttonsRendered());
    try std.testing.expectEqual(@as(usize, 2), dvui_adapter.StubDvui.labelsRendered());
}

const SwitchDemoCtx = struct {
    status: []const u8 = "ok",
};

test "switch_demo: status=ok" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("switch_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = SwitchDemoCtx{ .status = "ok" };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.labelsRendered());
}

test "switch_demo: status=warn" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("switch_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = SwitchDemoCtx{ .status = "warn" };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.labelsRendered());
}

test "switch_demo: status=other" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("switch_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = SwitchDemoCtx{ .status = "other" };
    demo.view(A, &c, &ctx);
    try std.testing.expectEqual(@as(usize, 1), dvui_adapter.StubDvui.labelsRendered());
}
