//! Built-in component prop registry (master-plan WP 2.5, F7 slice).
//!
//! The generator cannot inspect Zig types, so the set of props a built-in
//! component accepts is declared here once and consumed by the checker (and
//! later by `zsx-gen`). A misspelled prop on `<Button>`/`<shadcn.Button>` is a
//! check error with a did-you-mean suggestion instead of a silent no-op.
//!
//! User components are *not* validated: their props are only known once Zig
//! type-checks the generated file, and inventing a validation rule for them
//! would reject legitimate names. The registry is therefore a closed list of
//! the components shipped in `src/lib/shadcn.zig`.

const std = @import("std");

pub const Component = struct {
    /// Name without a namespace (`shadcn.Button` → `Button`).
    name: []const u8,
    /// Non-event, non-common props accepted by the component.
    props: []const []const u8,
    /// Slot fields the component renders (`content`, `header`, …).
    slots: []const []const u8 = &.{},
};

/// Props every generated component call may carry.
pub const common_props = [_][]const u8{ "class", "id_extra" };

pub const components = [_]Component{
    .{ .name = "Alert", .props = &.{ "variant", "title", "text" }, .slots = &.{"content"} },
    .{ .name = "Badge", .props = &.{ "text", "color" } },
    .{ .name = "Breadcrumb", .props = &.{"path"} },
    .{ .name = "Button", .props = &.{ "text", "variant" } },
    .{ .name = "Caption", .props = &.{"text"} },
    .{ .name = "Card", .props = &.{}, .slots = &.{ "content", "header", "body", "footer" } },
    .{ .name = "Checkbox", .props = &.{ "text", "checked" } },
    .{ .name = "Divider", .props = &.{} },
    .{ .name = "Heading", .props = &.{ "text", "size", "color" } },
    .{ .name = "Input", .props = &.{ "buffer", "placeholder" } },
    .{ .name = "Label", .props = &.{"text"} },
    .{ .name = "Link", .props = &.{"text"} },
    .{ .name = "Pagination", .props = &.{ "total", "selected" } },
    .{ .name = "Progress", .props = &.{"value"} },
    .{ .name = "Section", .props = &.{"title"}, .slots = &.{ "content", "header", "body", "footer" } },
    .{ .name = "Skeleton", .props = &.{ "width", "height", "radius" } },
    .{ .name = "Slider", .props = &.{"value"} },
    .{ .name = "Switch", .props = &.{ "checked", "text" } },
    .{ .name = "Tabs", .props = &.{ "labels", "selected" }, .slots = &.{"content"} },
    .{ .name = "Textarea", .props = &.{ "buffer", "placeholder" } },
};

/// Look up a component by tag: `Button` and `shadcn.Button` both map to
/// `Button`. Only dotted tags in the `shadcn`/`ui` namespaces are resolved;
/// unknown namespaces return `null` so user components are not second-guessed.
pub fn find(tag: []const u8) ?Component {
    if (tag.len == 0) return null;
    var name = tag;
    if (std.mem.lastIndexOfScalar(u8, tag, '.')) |dot| {
        const ns = tag[0..dot];
        if (!std.mem.eql(u8, ns, "shadcn") and !std.mem.eql(u8, ns, "ui")) return null;
        name = tag[dot + 1 ..];
    } else if (!std.ascii.isUpper(tag[0])) {
        return null;
    }
    if (name.len == 0 or !std.ascii.isUpper(name[0])) return null;
    for (components) |c| {
        if (std.mem.eql(u8, c.name, name)) return c;
    }
    return null;
}

/// True when `name` is an attribute a component call may carry.
pub fn accepts(comp: Component, name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "on_") or std.mem.startsWith(u8, name, "on:")) return true;
    for (common_props) |p| {
        if (std.mem.eql(u8, p, name)) return true;
    }
    for (comp.props) |p| {
        if (std.mem.eql(u8, p, name)) return true;
    }
    for (comp.slots) |p| {
        if (std.mem.eql(u8, p, name)) return true;
    }
    return false;
}

/// Nearest accepted prop within edit distance 2, for a did-you-mean hint.
pub fn suggest(comp: Component, name: []const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_d: usize = 3;
    for (comp.props) |p| {
        const d = editDistance(name, p);
        if (d < best_d) {
            best_d = d;
            best = p;
        }
    }
    for (common_props) |p| {
        const d = editDistance(name, p);
        if (d < best_d) {
            best_d = d;
            best = p;
        }
    }
    return best;
}

fn editDistance(a: []const u8, b: []const u8) usize {
    var prev: [64]usize = undefined;
    var cur: [64]usize = undefined;
    if (a.len >= prev.len or b.len >= prev.len) return 99;
    for (0..b.len + 1) |j| prev[j] = j;
    for (a, 0..) |ca, i| {
        cur[0] = i + 1;
        for (b, 0..) |cb, j| {
            const cost: usize = if (ca == cb) 0 else 1;
            cur[j + 1] = @min(@min(cur[j] + 1, prev[j + 1] + 1), prev[j] + cost);
        }
        @memcpy(prev[0 .. b.len + 1], cur[0 .. b.len + 1]);
    }
    return prev[b.len];
}

test "registry: only built-in namespaces resolve" {
    try std.testing.expect(find("Button") != null);
    try std.testing.expect(find("shadcn.Button") != null);
    try std.testing.expect(find("ui.Card") != null);
    try std.testing.expect(find("myapp.Button") == null);
    try std.testing.expect(find("column") == null);
}

test "registry: accepts common, props, slots and events" {
    const b = find("Button").?;
    try std.testing.expect(accepts(b, "class"));
    try std.testing.expect(accepts(b, "variant"));
    try std.testing.expect(accepts(b, "on:click"));
    try std.testing.expect(accepts(b, "on_click"));
    try std.testing.expect(!accepts(b, "varient"));
    const card = find("Card").?;
    try std.testing.expect(accepts(card, "body"));
}

test "registry: suggests the nearest prop" {
    const s = suggest(find("Button").?, "varient");
    try std.testing.expectEqualStrings("variant", s.?);
}
