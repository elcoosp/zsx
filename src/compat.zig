//! Compatibility shims for the supported Zig versions.
//!
//! Policy: `docs/adr/0002-zig-version-policy.md`. A ZSX minor release supports
//! the latest stable Zig release (`current`) and the previous one (`current-1`).
//! Put every API difference here so runtime and compiler code stays
//! version-neutral. Each shim carries the verbatim error that motivated it in
//! `docs/zig-skill.md`.

const std = @import("std");
const builtin = @import("builtin");

pub const zig_version = builtin.zig_version;

pub const is_current = zig_version.major == 0 and zig_version.minor == 17;

/// True when running on the newest release advertised by `build.zig.zon`.
pub fn onCurrent() bool {
    return is_current;
}

/// `std.fs.path.join` replacement whose error set is stable across the two
/// supported releases. Callers pass a small slice of path components.
pub fn joinPath(a: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return std.fs.path.join(a, parts);
}
