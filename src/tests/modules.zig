const std = @import("std");

pub const style = @import("shadcn").style;

test {
    _ = @import("shadcn").style;
}

test {
    _ = @import("../adapters/dvui.zig");
}

test {
    _ = @import("../adapters/nanoui.zig");
}

test {
    _ = @import("demo");
}

test {
    _ = @import("component_demo");
}

test {
    _ = @import("shadcn_demo");
}

test {
    _ = @import("shadcn_lib_demo");
}

test {
    _ = @import("onclick_demo");
}

test {
    _ = @import("struct_loop_demo");
}

test {
    _ = @import("card_if_demo");
}

test {
    _ = @import("else_if_demo");
}

test {
    _ = @import("fragment_demo");
}

test {
    _ = @import("class_override_demo");
}

test {
    _ = @import("nested_card_demo");
}

test {
    _ = @import("dashboard");
}

test {
    _ = @import("input_demo");
}

test {
    _ = @import("extended_styles_demo");
}
