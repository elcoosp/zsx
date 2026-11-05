const std = @import("std");
const ast = @import("../ast.zig");
const Feature = @import("../feature.zig").Feature;
const style_mod = @import("../style.zig");

pub fn Backend(comptime dvui: type) type {
    return struct {
        pub const Context = struct {};

        pub const Capabilities = struct {
            background: bool = true,
            hover_background: bool = true,
            foreground: bool = true,
            padding: bool = true,
            margin: bool = true,
            border: bool = true,
            radius: bool = false,
            gap: bool = false,
            flex_direction: bool = true,
            font: bool = true,
            shadow: bool = false,
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
            _ = ctx;
            emitElement(element);
        }

        fn emitElement(comptime el: ast.Element) void {
            const is_column = comptime std.mem.eql(u8, el.tag, "column");
            const is_row = comptime std.mem.eql(u8, el.tag, "row");
            const is_label = comptime std.mem.eql(u8, el.tag, "label");
            const is_button = comptime std.mem.eql(u8, el.tag, "button");

            if (is_column) {
                var box = dvui.box(@src(), .{ .dir = .vertical }, comptime optionsFrom(el));
                defer box.deinit();
                inline for (el.children) |c| emitChild(c);
            } else if (is_row) {
                var box = dvui.box(@src(), .{ .dir = .horizontal }, comptime optionsFrom(el));
                defer box.deinit();
                inline for (el.children) |c| emitChild(c);
            } else if (is_label) {
                const text = comptime style_mod.firstText(el) orelse @compileError("label element requires a text child");
                dvui.labelNoFmt(@src(), text, .{}, comptime optionsFrom(el));
            } else if (is_button) {
                const text = comptime style_mod.firstText(el) orelse @compileError("button element requires a text child");
                _ = dvui.button(@src(), text, .{}, comptime optionsFrom(el));
            } else {
                @compileError("dvui backend does not support tag '" ++ el.tag ++ "'");
            }
        }

        fn emitChild(comptime c: ast.Child) void {
            switch (c) {
                .element => |el| emitElement(el),
                .text => @compileError("text cannot be a direct child of a layout element"),
                .expression => @compileError("expression children not yet supported in dvui backend"),
            }
        }

        fn optionsFrom(comptime el: ast.Element) dvui.Options {
            const s = comptime style_mod.styleFrom(el);
            var opts = dvui.Options{};
            if (s.background) |bg| opts.color_fill = .{ .color = toDvuiColor(bg) };
            if (s.hover_background) |bg| opts.color_fill_hover = .{ .color = toDvuiColor(bg) };
            if (s.foreground) |fg| opts.color_text = .{ .color = toDvuiColor(fg) };
            if (s.padding) |p| opts.padding = .{ .x = p.x, .y = p.y, .w = p.w, .h = p.h };
            if (s.width) |w| {
                const h: f32 = if (opts.min_size_content) |sz| sz.h else 0;
                opts.min_size_content = .{ .w = w, .h = h };
            }
            if (s.height) |h| {
                const w: f32 = if (opts.min_size_content) |sz| sz.w else 0;
                opts.min_size_content = .{ .w = w, .h = h };
            }
            if (s.expand) |ex| {
                opts.expand = switch (ex) {
                    .none => .none,
                    .horizontal => .horizontal,
                    .vertical => .vertical,
                    .both => .both,
                };
            }
            return opts;
        }

        fn toDvuiColor(c: style_mod.Color) dvui.Color {
            return .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a };
        }
    };
}

const StubDvui = struct {
    pub const Color = struct {
        r: u8 = 0,
        g: u8 = 0,
        b: u8 = 0,
        a: u8 = 255,

        pub const white = Color{ .r = 255, .g = 255, .b = 255 };
        pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    };

    pub const ColorOrGradient = union(enum) {
        color: Color,
    };

    pub const Rect = struct {
        x: f32 = 0,
        y: f32 = 0,
        w: f32 = 0,
        h: f32 = 0,
    };

    pub const Size = struct {
        w: f32 = 0,
        h: f32 = 0,
    };

    pub const Expand = enum {
        none,
        horizontal,
        vertical,
        both,
        ratio,
    };

    pub const Font = struct {};

    pub const Options = struct {
        color_fill: ?ColorOrGradient = null,
        color_fill_hover: ?ColorOrGradient = null,
        color_text: ?ColorOrGradient = null,
        padding: ?Rect = null,
        margin: ?Rect = null,
        border: ?Rect = null,
        min_size_content: ?Size = null,
        expand: ?Expand = null,
        font: ?Font = null,
    };

    pub const BoxWidget = struct {
        pub fn deinit(self: *BoxWidget) void {
            _ = self;
        }
    };

    var _box_storage: BoxWidget = .{};

    pub fn box(src: anytype, init: anytype, opts: Options) *BoxWidget {
        _ = src;
        _ = init;
        _ = opts;
        return &_box_storage;
    }

    pub fn button(src: anytype, label: []const u8, init: anytype, opts: Options) bool {
        _ = src;
        _ = label;
        _ = init;
        _ = opts;
        return false;
    }

    pub fn labelNoFmt(src: anytype, text: []const u8, init: anytype, opts: Options) void {
        _ = src;
        _ = text;
        _ = init;
        _ = opts;
    }
};

const Attr = ast.Attribute;
const AttrVal = ast.AttributeValue;
const Child = ast.Child;
const Elem = ast.Element;

test "dvui backend instantiates against stub" {
    _ = Backend(StubDvui);
}

test "dvui backend emits label" {
    const el = comptime Elem{
        .tag = "label",
        .attributes = &[_]Attr{},
        .children = &[_]Child{Child{ .text = "hi" }},
    };
    const B = Backend(StubDvui);
    var ctx: B.Context = .{};
    B.emit(el, &ctx);
}

test "dvui backend emits column with label child" {
    const el = comptime Elem{
        .tag = "column",
        .attributes = &[_]Attr{},
        .children = &[_]Child{
            Child{ .element = Elem{
                .tag = "label",
                .attributes = &[_]Attr{},
                .children = &[_]Child{Child{ .text = "hello" }},
            } },
        },
    };
    const B = Backend(StubDvui);
    var ctx: B.Context = .{};
    B.emit(el, &ctx);
}

test "dvui backend emits button with classes" {
    const el = comptime Elem{
        .tag = "button",
        .attributes = &[_]Attr{
            Attr{ .name = "class", .value = AttrVal{ .string = "bg-blue-500 text-white px-4 py-2" } },
        },
        .children = &[_]Child{Child{ .text = "Save" }},
    };
    const B = Backend(StubDvui);
    var ctx: B.Context = .{};
    B.emit(el, &ctx);
}

test "dvui backend emits column with padding" {
    const el = comptime Elem{
        .tag = "column",
        .attributes = &[_]Attr{
            Attr{ .name = "padding", .value = AttrVal{ .expression = "16" } },
        },
        .children = &[_]Child{
            Child{ .element = Elem{
                .tag = "label",
                .attributes = &[_]Attr{},
                .children = &[_]Child{Child{ .text = "x" }},
            } },
        },
    };
    const B = Backend(StubDvui);
    var ctx: B.Context = .{};
    B.emit(el, &ctx);
}

test "dvui backend emits flex attribute" {
    const el = comptime Elem{
        .tag = "column",
        .attributes = &[_]Attr{
            Attr{ .name = "flex", .value = AttrVal{ .boolean = {} } },
        },
        .children = &[_]Child{},
    };
    const B = Backend(StubDvui);
    var ctx: B.Context = .{};
    B.emit(el, &ctx);
}

test "dvui backend shape matches contract" {
    const Impl = Backend(StubDvui);
    const ctx: Impl.Context = .{};
    _ = ctx;
    const caps: Impl.Capabilities = .{};
    try std.testing.expect(caps.supports(.background));
    try std.testing.expect(caps.supports(.padding));
    try std.testing.expect(!caps.supports(.radius));
}

test "dvui backend capabilities report" {
    const caps = Backend(StubDvui).Capabilities{};
    try std.testing.expect(caps.supports(.background));
    try std.testing.expect(caps.supports(.padding));
    try std.testing.expect(caps.supports(.flex_direction));
    try std.testing.expect(!caps.supports(.radius));
    try std.testing.expect(!caps.supports(.gap));
    try std.testing.expect(!caps.supports(.shadow));
}

test "dvui backend conforms to contract" {
    const contract = @import("../backend.zig");
    try std.testing.expect(contract.conforms(Backend(StubDvui)));
}
