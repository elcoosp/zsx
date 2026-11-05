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
            grow: bool = true,

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
                const opts = comptime textOpts(el);
                ui.text(ctx.c, text, opts);
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
            if (s.background) |bg| {
                d = d.bg(.{ .r = bg.r, .g = bg.g, .b = bg.b, .a = bg.a });
            }
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

        pub const TextOpts = struct {
            size: ?f32 = null,
            weight: ?style_mod.FontWeight = null,
            color: ?ui.Color = null,
        };

        fn textOpts(comptime el: ast.Element) TextOpts {
            const s = comptime style_mod.styleFrom(el);
            var opts = TextOpts{};
            if (s.foreground) |fg| {
                opts.color = .{ .r = fg.r, .g = fg.g, .b = fg.b, .a = fg.a };
            }
            if (s.font_size) |fs| opts.size = fs;
            if (s.font_weight) |fw| opts.weight = fw;
            return opts;
        }
    };
}

const StubNanoui = struct {
    pub const Context = struct {};

    pub const Color = struct {
        r: u8 = 0,
        g: u8 = 0,
        b: u8 = 0,
        a: u8 = 255,
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

    pub const ButtonResult = struct {
        clicked: bool = false,
    };

    pub fn div(c: *Context) Div {
        _ = c;
        return .{};
    }

    pub fn text(c: *Context, str: []const u8, opts: anytype) void {
        _ = c;
        _ = str;
        _ = opts;
    }

    pub fn button(c: *Context, label: []const u8, opts: anytype) ButtonResult {
        _ = c;
        _ = label;
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

test "nanoui backend capabilities report" {
    const caps = Backend(StubNanoui).Capabilities{};
    try std.testing.expect(caps.supports(.background));
    try std.testing.expect(caps.supports(.radius));
    try std.testing.expect(caps.supports(.gap));
    try std.testing.expect(!caps.supports(.margin));
    try std.testing.expect(!caps.supports(.border));
    try std.testing.expect(!caps.supports(.hover_background));
}
