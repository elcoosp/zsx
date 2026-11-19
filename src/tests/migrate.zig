//! Aggregates the codemod's unit tests into the root test run.
test {
    _ = @import("../rt/migrate.zig");
}
