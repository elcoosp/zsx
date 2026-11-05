//! Backend contract for ZSX.
//!
//! Every backend exposes `pub fn Backend(comptime X: type) type` returning
//! a struct with three required declarations:
//!
//!   pub const Context = ...;         // any struct type
//!   pub const Capabilities = ...;    // struct with pub fn supports(Feature) bool
//!   pub fn emit(comptime ast.Element, *Context) void;
//!
//! `conforms(Impl)` returns true if a backend's return type has the shape.
//! Each backend's test suite calls it. There is no wrapper struct: each
//! backend's own `Backend(comptime X: type) type` IS the contract.
//!
//! Backends are side-effecting: DVUI calls widget functions, Nanoui calls
//! `.end()` on builder chains. Neither returns a node. The original
//! `Node`-returning shape was aspirational and was removed in Phase 3.5.

const std = @import("std");
const ast = @import("ast.zig");
const Feature = @import("feature.zig").Feature;

pub fn conforms(comptime Impl: type) bool {
    if (!@hasDecl(Impl, "Context")) return false;
    if (!@hasDecl(Impl, "Capabilities")) return false;
    if (!@hasDecl(Impl, "emit")) return false;
    if (@TypeOf(Impl.Capabilities) != type) return false;
    if (!@hasDecl(Impl.Capabilities, "supports")) return false;
    return true;
}

const DummyCtx = struct {};

const GoodImpl = struct {
    pub const Context = struct {};
    pub const Capabilities = struct {
        pub fn supports(feature: Feature) bool {
            _ = feature;
            return false;
        }
    };
    pub fn emit(comptime el: ast.Element, ctx: *Context) void {
        _ = el;
        _ = ctx;
    }
};

test "conforms accepts valid backend" {
    try std.testing.expect(conforms(GoodImpl));
}

test "conforms rejects missing Context" {
    const Bad = struct {
        pub const Capabilities = GoodImpl.Capabilities;
        pub fn emit(comptime el: ast.Element, ctx: *DummyCtx) void {
            _ = el;
            _ = ctx;
        }
    };
    try std.testing.expect(!conforms(Bad));
}

test "conforms rejects missing Capabilities" {
    const Bad = struct {
        pub const Context = struct {};
        pub fn emit(comptime el: ast.Element, ctx: *Context) void {
            _ = el;
            _ = ctx;
        }
    };
    try std.testing.expect(!conforms(Bad));
}

test "conforms rejects missing emit" {
    const Bad = struct {
        pub const Context = struct {};
        pub const Capabilities = GoodImpl.Capabilities;
    };
    try std.testing.expect(!conforms(Bad));
}

test "conforms rejects Capabilities without supports" {
    const Bad = struct {
        pub const Context = struct {};
        pub const Capabilities = struct {};
        pub fn emit(comptime el: ast.Element, ctx: *Context) void {
            _ = el;
            _ = ctx;
        }
    };
    try std.testing.expect(!conforms(Bad));
}
