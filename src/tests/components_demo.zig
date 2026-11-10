const std = @import("std");

const ComponentsDemoCtx = struct {
    name: [64]u8 = @splat(0),
    active_tab: usize = 0,
    active_page: usize = 0,
};

test "components_demo: new components render" {
    const dvui_adapter = @import("../adapters/dvui.zig");
    const demo = @import("components_demo");
    const A = dvui_adapter.Adapter(dvui_adapter.StubDvui);
    var c: dvui_adapter.StubDvui.Context = .{};
    dvui_adapter.StubDvui.resetCounters();
    var ctx = ComponentsDemoCtx{};
    demo.view(A, &c, &ctx);
    // 3 tabs + 7 pagination buttons (< + 5 pages + >) = 10 buttons
    try std.testing.expectEqual(@as(usize, 10), dvui_adapter.StubDvui.buttonsRendered());
    // labels: Heading, Caption, Label, 4 alert titles, Breadcrumb (2 labels + 1 "/" = 3), Tabs caption = 11+
    try std.testing.expect(dvui_adapter.StubDvui.labelsRendered() >= 10);
}
