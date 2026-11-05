const std = @import("std");
const ast = @import("../ast.zig");
const Feature = @import("../feature.zig").Feature;
const style_mod = @import("../style.zig");

pub fn Backend(comptime ui: type) type {
    return struct {
        pub const Context = struct {
            c: *ui.Context,
        };

        pub const Capabilities = struct {
            background: bool = true,
            hover_background: bool = false,
            foreground: bool = true,
            padding: bool = true,
            margin: bool = false,
            border: bool = false,
            radius: bool = true,
            gap: bool = true,
            flex_direction: bool = true,
            font: bool = true,
            shadow: bool = true,
            width: bool = true,
            height: bool = true,
            grow: bool = false,

            pub fn supports(self: @This(), feature: Feature) bool {
                return switch (feature) {
                    .background => self.background,
                    .hover_background => self.hover_background,
                    .foreground => self.foreground,
                    .padding => self.padding,
                    .margin => self.margin,
                    .border => self.border,
                    .radius => self.radius,
                    .gap => self.gap,
                    .flex_direction => self.flex_direction,
                    .font => self.font,
                    .shadow => self.shadow,
                    .width => self.width,
                    .height => self.height,
                    .grow => self.grow,
                };
            }
        };

        pub fn emit(comptime element: ast.Element, ctx: *Context) void {
            emitElement(element, ctx);
        }

        fn emitElement(comptime el: ast.Element, ctx: *Context) void {
            if (comptime std.mem.eql(u8, el.tag, "column")) {
                var d = applyBox(ui.div(ctx.c), el);
                d = d.column();
                defer d.end();
                inline for (el.children) |c| emitChild(c, ctx);
            } else if (comptime std.mem.eql(u8, el.tag, "row")) {
                var d = applyBox(ui.div(ctx.c), el);
                d = d.row();
                defer d.end();
                inline for (el.children) |c| emitChild(c, ctx);
            } else if (comptime std.mem.eql(u8, el.tag, "label")) {
                const text = comptime style_mod.firstText(el) orelse @compileError("label requires text child");
                const style = comptime textStyle(el);
                ui.text(ctx.c, text, style);
            } else if (comptime std.mem.eql(u8, el.tag, "button")) {
                const text = comptime style_mod.firstText(el) orelse @compileError("button requires text child");
                _ = ui.button(ctx.c, text, .{});
            } else {
                @compileError("nanoui backend does not support tag '" ++ el.tag ++ "'");
            }
        }

        fn emitChild(comptime c: ast.Child, ctx: *Context) void {
            switch (c) {
                .element => |el| emitElement(el, ctx),
                .text => @compileError("text cannot be a direct child of a layout element"),
                .expression => @compileError("expression children not yet supported in nanoui backend"),
            }
        }

        fn applyBox(initial: anytype, comptime el: ast.Element) @TypeOf(initial) {
            const s = comptime style_mod.styleFrom(el);
            var d = initial;
            if (s.background) |bg| d = d.bg(toUiColor(bg));
            if (s.padding) |p| {
                if (p.x == p.y and p.x == p.w and p.x == p.h) {
                    d = d.p(p.x);
                } else {
                    if (p.x != 0 or p.w != 0) d = d.px(p.x);
                    if (p.y != 0 or p.h != 0) d = d.py(p.y);
                }
            }
            if (s.radius) |r| d = d.rounded(r);
            if (s.gap) |g| d = d.gap(g);
            if (s.width) |w| d = d.w(w);
            if (s.height) |h| d = d.h(h);
            return d;
        }

        fn textStyle(comptime el: ast.Element) ui.TextStyle {
            const s = comptime style_mod.styleFrom(el);
            var ts = ui.TextStyle{};
            if (s.foreground) |fg| ts.color = toUiColor(fg);
            if (s.font_size) |fs| ts.size = fs;
            if (s.font_weight) |fw| {
                ts.weight = switch (fw) {
                    .regular => .regular,
                    .semibold => .semibold,
                    .bold => .bold,
                };
            }
            return ts;
        }

        fn toUiColor(c: style_mod.Color) ui.Color {
            return .{
                .r = @as(f32, @floatFromInt(c.r)) / 255.0,
                .g = @as(f32, @floatFromInt(c.g)) / 255.0,
                .b = @as(f32, @floatFromInt(c.b)) / 255.0,
                .a = @as(f32, @floatFromInt(c.a)) / 255.0,
            };
        }
    };
}

const StubNanoui = struct {
    pub const Context = struct {};

    pub const Color = struct {
        r: f32 = 0,
        g: f32 = 0,
        b: f32 = 0,
        a: f32 = 1,
    };

    pub const Weight = enum { regular, medium, semibold, bold };

    pub const TextStyle = struct {
        size: f32 = 14,
        weight: Weight = .regular,
        color: ?Color = null,
        wrap: bool = false,
    };

    pub const Interaction = struct {
        clicked: bool = false,
        hovered: bool = false,
        pressed: bool = false,
        id: u32 = 0,
    };

    pub const ButtonVariant = enum { primary, secondary, ghost, danger };

    pub const ButtonOptions = struct {
        variant: ButtonVariant = .primary,
        size: f32 = 14,
        disabled: bool = false,
        icon: []const u8 = "",
        width: f32 = 0,
    };

    pub const Div = struct {
        pub fn column(self: Div) Div {
            return self;
        }
        pub fn row(self: Div) Div {
            return self;
        }
        pub fn gap(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn p(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn px(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn py(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn rounded(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn bg(self: Div, c: Color) Div {
            _ = c;
            return self;
        }
        pub fn w(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn h(self: Div, v: f32) Div {
            _ = v;
            return self;
        }
        pub fn end(self: Div) void {
            _ = self;
        }
    };

    pub fn div(c: *Context) Div {
        _ = c;
        return .{};
    }

    pub fn text(c: *Context, str: []const u8, style: TextStyle) void {
        _ = c;
        _ = str;
        _ = style;
    }

    pub fn button(c: *Context, title: []const u8, opts: ButtonOptions) Interaction {
        _ = c;
        _ = title;
        _ = opts;
        return .{};
    }
};

const Attr = ast.Attribute;
const AttrVal = ast.AttributeValue;
const Child = ast.Child;
const Elem = ast.Element;

test "nanoui backend instantiates against stub" {
    _ = Backend(StubNanoui);
}

test "nanoui backend emits label" {
    const el = comptime Elem{
        .tag = "label",
        .attributes = &[_]Attr{},
        .children = &[_]Child{Child{ .text = "hi" }},
    };
    var c: StubNanoui.Context = .{};
    var ctx = Backend(StubNanoui).Context{ .c = &c };
    Backend(StubNanoui).emit(el, &ctx);
}

test "nanoui backend emits column with classes" {
    const el = comptime Elem{
        .tag = "column",
        .attributes = &[_]Attr{
            Attr{ .name = "class", .value = AttrVal{ .string = "bg-blue-500 p-4 rounded-lg gap-2" } },
        },
        .children = &[_]Child{
            Child{ .element = Elem{
                .tag = "label",
                .attributes = &[_]Attr{},
                .children = &[_]Child{Child{ .text = "hello" }},
            } },
        },
    };
    var c: StubNanoui.Context = .{};
    var ctx = Backend(StubNanoui).Context{ .c = &c };
    Backend(StubNanoui).emit(el, &ctx);
}

test "nanoui backend emits row with gap" {
    const el = comptime Elem{
        .tag = "row",
        .attributes = &[_]Attr{
            Attr{ .name = "class", .value = AttrVal{ .string = "gap-2" } },
        },
        .children = &[_]Child{
            Child{ .element = Elem{
                .tag = "label",
                .attributes = &[_]Attr{},
                .children = &[_]Child{Child{ .text = "a" }},
            } },
        },
    };
    var c: StubNanoui.Context = .{};
    var ctx = Backend(StubNanoui).Context{ .c = &c };
    Backend(StubNanoui).emit(el, &ctx);
}

test "nanoui backend emits button" {
    const el = comptime Elem{
        .tag = "button",
        .attributes = &[_]Attr{},
        .children = &[_]Child{Child{ .text = "Save" }},
    };
    var c: StubNanoui.Context = .{};
    var ctx = Backend(StubNanoui).Context{ .c = &c };
    Backend(StubNanoui).emit(el, &ctx);
}

test "nanoui backend emits label with text classes" {
    const el = comptime Elem{
        .tag = "label",
        .attributes = &[_]Attr{
            Attr{ .name = "class", .value = AttrVal{ .string = "text-white text-lg font-bold" } },
        },
        .children = &[_]Child{Child{ .text = "Heading" }},
    };
    var c: StubNanoui.Context = .{};
    var ctx = Backend(StubNanoui).Context{ .c = &c };
    Backend(StubNanoui).emit(el, &ctx);
}

test "nanoui backend shape matches contract" {
    const Impl = Backend(StubNanoui);
    var inner: StubNanoui.Context = .{};
    const ctx: Impl.Context = .{ .c = &inner };
    _ = ctx;
    const caps: Impl.Capabilities = .{};
    try std.testing.expect(caps.supports(.background));
}

test "nanoui backend capabilities report" {
    const caps = Backend(StubNanoui).Capabilities{};
    try std.testing.expect(caps.supports(.background));
    try std.testing.expect(caps.supports(.radius));
    try std.testing.expect(caps.supports(.gap));
    try std.testing.expect(!caps.supports(.margin));
    try std.testing.expect(!caps.supports(.border));
    try std.testing.expect(!caps.supports(.hover_background));
    try std.testing.expect(!caps.supports(.grow));
}
