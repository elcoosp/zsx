const std = @import("std");
const ast = @import("../ast.zig");
const Feature = @import("../feature.zig").Feature;

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

        pub fn emit(comptime element: ast.Element) void {
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
                const text = comptime firstText(el) orelse @compileError("label element requires a text child");
                dvui.labelNoFmt(@src(), text, .{}, comptime optionsFrom(el));
            } else if (is_button) {
                const text = comptime firstText(el) orelse @compileError("button element requires a text child");
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

        fn firstText(comptime el: ast.Element) ?[]const u8 {
            inline for (el.children) |c| {
                switch (c) {
                    .text => |t| return t,
                    .expression => return null,
                    .element => continue,
                }
            }
            return null;
        }

        fn optionsFrom(comptime el: ast.Element) dvui.Options {
            var opts = dvui.Options{};
            inline for (el.attributes) |attr| {
                if (comptime std.mem.eql(u8, attr.name, "class")) {
                    switch (attr.value) {
                        .string => |s| applyClasses(&opts, s),
                        else => @compileError("class attribute must be a string"),
                    }
                } else if (comptime std.mem.eql(u8, attr.name, "padding")) {
                    switch (attr.value) {
                        .expression => |e| {
                            const v = comptime parseNumeric(e);
                            opts.padding = .{ .x = v, .y = v, .w = v, .h = v };
                        },
                        else => @compileError("padding attribute must be an expression"),
                    }
                } else if (comptime std.mem.eql(u8, attr.name, "width")) {
                    switch (attr.value) {
                        .expression => |e| {
                            const v = comptime parseNumeric(e);
                            const h: f32 = if (opts.min_size_content) |s| s.h else 0;
                            opts.min_size_content = .{ .w = v, .h = h };
                        },
                        else => @compileError("width attribute must be an expression"),
                    }
                } else if (comptime std.mem.eql(u8, attr.name, "height")) {
                    switch (attr.value) {
                        .expression => |e| {
                            const v = comptime parseNumeric(e);
                            const w: f32 = if (opts.min_size_content) |s| s.w else 0;
                            opts.min_size_content = .{ .w = w, .h = v };
                        },
                        else => @compileError("height attribute must be an expression"),
                    }
                } else if (comptime std.mem.eql(u8, attr.name, "flex")) {
                    switch (attr.value) {
                        .boolean => opts.expand = .horizontal,
                        else => @compileError("flex attribute must be boolean"),
                    }
                }
            }
            return opts;
        }

        fn applyClasses(opts: *dvui.Options, comptime class: []const u8) void {
            comptime var i: usize = 0;
            inline while (i < class.len) {
                while (i < class.len and class[i] == ' ') i += 1;
                if (i >= class.len) break;
                const start = i;
                while (i < class.len and class[i] != ' ') i += 1;
                const token = class[start..i];
                if (std.mem.eql(u8, token, "bg-blue-500")) {
                    opts.color_fill = .{ .color = .{ .r = 59, .g = 130, .b = 246 } };
                } else if (std.mem.eql(u8, token, "bg-blue-600")) {
                    opts.color_fill_hover = .{ .color = .{ .r = 37, .g = 99, .b = 235 } };
                } else if (std.mem.eql(u8, token, "bg-gray-100")) {
                    opts.color_fill = .{ .color = .{ .r = 243, .g = 244, .b = 246 } };
                } else if (std.mem.eql(u8, token, "text-white")) {
                    opts.color_text = .{ .color = dvui.Color.white };
                } else if (std.mem.eql(u8, token, "text-black")) {
                    opts.color_text = .{ .color = dvui.Color.black };
                } else if (std.mem.eql(u8, token, "p-4")) {
                    opts.padding = .{ .x = 16, .y = 16, .w = 16, .h = 16 };
                } else if (std.mem.eql(u8, token, "p-2")) {
                    opts.padding = .{ .x = 8, .y = 8, .w = 8, .h = 8 };
                } else if (std.mem.eql(u8, token, "px-4")) {
                    const cur: dvui.Rect = opts.padding orelse dvui.Rect{};
                    opts.padding = .{ .x = 16, .y = cur.y, .w = 16, .h = cur.h };
                } else if (std.mem.eql(u8, token, "py-2")) {
                    const cur: dvui.Rect = opts.padding orelse dvui.Rect{};
                    opts.padding = .{ .x = cur.x, .y = 8, .w = cur.w, .h = 8 };
                } else {
                    @compileError("dvui backend does not recognize tailwind class '" ++ token ++ "'");
                }
            }
        }

        fn parseNumeric(comptime s: []const u8) f32 {
            if (s.len == 0) @compileError("empty numeric attribute value");
            var result: f32 = 0;
            inline for (s) |ch| {
                if (ch < '0' or ch > '9') @compileError("non-numeric attribute value: '" ++ s ++ "'");
                result = result * 10.0 + @as(f32, @floatFromInt(ch - '0'));
            }
            return result;
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
        .children = &[_]Child{
            Child{ .text = "hi" },
        },
    };
    const B = Backend(StubDvui);
    B.emit(el);
}

test "dvui backend emits column with label child" {
    const el = comptime Elem{
        .tag = "column",
        .attributes = &[_]Attr{},
        .children = &[_]Child{
            Child{ .element = Elem{
                .tag = "label",
                .attributes = &[_]Attr{},
                .children = &[_]Child{
                    Child{ .text = "hello" },
                },
            } },
        },
    };
    const B = Backend(StubDvui);
    B.emit(el);
}

test "dvui backend emits button with classes" {
    const el = comptime Elem{
        .tag = "button",
        .attributes = &[_]Attr{
            Attr{ .name = "class", .value = AttrVal{ .string = "bg-blue-500 text-white px-4 py-2" } },
        },
        .children = &[_]Child{
            Child{ .text = "Save" },
        },
    };
    const B = Backend(StubDvui);
    B.emit(el);
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
                .children = &[_]Child{
                    Child{ .text = "x" },
                },
            } },
        },
    };
    const B = Backend(StubDvui);
    B.emit(el);
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
