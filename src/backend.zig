const Feature = @import("feature.zig").Feature;

pub fn Backend(comptime Impl: type) type {
    return struct {
        pub const Capabilities = Impl.Capabilities;
        pub const Node = Impl.Node;

        pub fn emit(comptime element: anytype, ctx: *Impl.Context) Node {
            return Impl.emit(element, ctx);
        }

        pub fn supports(comptime feature: Feature) bool {
            return Impl.supports(feature);
        }
    };
}
