const std = @import("std");

pub const AttributeValue = union(enum) {
    boolean,
    string: []const u8,
    expression: []const u8,
};

pub const Attribute = struct {
    name: []const u8,
    value: AttributeValue,
};

pub const Child = union(enum) {
    element: Element,
    text: []const u8,
    expression: []const u8,
};

pub const Element = struct {
    tag: []const u8,
    attributes: []const Attribute,
    children: []const Child,
};

test "ast types construct" {
    const el = Element{
        .tag = "div",
        .attributes = &.{},
        .children = &.{},
    };
    try std.testing.expectEqualStrings("div", el.tag);
    try std.testing.expectEqual(@as(usize, 0), el.attributes.len);
    try std.testing.expectEqual(@as(usize, 0), el.children.len);
}
