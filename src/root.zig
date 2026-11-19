const std = @import("std");

pub const style = @import("shadcn").style;

test {
    _ = @import("tests/modules.zig");
}
test {
    _ = @import("tests/demos.zig");
}
test {
    _ = @import("tests/shadcn.zig");
}
test {
    _ = @import("tests/views.zig");
}
test {
    _ = @import("tests/html.zig");
}
test {
    _ = @import("tests/components_demo.zig");
}
test {
    _ = @import("tests/reproducers.zig");
}
test {
    _ = @import("tests/checker.zig");
}
test {
    _ = @import("tests/fmt.zig");
}
test {
    _ = @import("tests/render.zig");
}
test {
    _ = @import("tests/compat.zig");
}
test {
    _ = @import("tests/lossless.zig");
}
test {
    _ = @import("tests/cost.zig");
}
test {
    _ = @import("tests/migrate.zig");
}
test {
    _ = @import("tests/grammar.zig");
}
test {
    _ = @import("tests/cst.zig");
    // M1 WP 1.5: CST -> AST lowering dumps.
    _ = @import("tests/ast_lowering.zig");
    // M1 WP 1.8: rendered diagnostic snapshots.
    _ = @import("tests/diagnostics_snapshot.zig");
    // M1 WP 1.9: property/mutation fuzz smoke.
    _ = @import("tests/fuzz.zig");
}
