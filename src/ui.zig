//! The editor's interface kit on Dear ImGui: the design's colours, fonts and icons, the widgets
//! the screens are made of, the text editor, and the map's plot.

const std = @import("std");

pub const fonts = @import("ui/fonts.zig");
pub const gui = @import("ui/gui.zig");
pub const icons = @import("ui/icons.zig");
pub const plot = @import("ui/plot.zig");
pub const text_editor = @import("ui/text_editor.zig");
pub const theme = @import("ui/theme.zig");
pub const widgets = @import("ui/widgets.zig");

test {
    std.testing.refAllDecls(@This());
}
