const Feature = @import("feature.zig").Feature;

pub const Capabilities = struct {
    background: bool = false,
    hover_background: bool = false,
    foreground: bool = false,
    padding: bool = false,
    margin: bool = false,
    border: bool = false,
    radius: bool = false,
    gap: bool = false,
    flex_direction: bool = false,
    font: bool = false,
    shadow: bool = false,
    width: bool = false,
    height: bool = false,
    grow: bool = false,

    pub fn supports(self: Capabilities, feature: Feature) bool {
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
