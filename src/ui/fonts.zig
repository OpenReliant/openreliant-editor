//! The fonts the editor carries and draws with: IBM Plex Sans for the interface, with Lucide's
//! icons merged into it, JetBrains Mono for code and values, and Newtown, OpenReliant's own, for
//! the editor's name. ImGui draws each at any size, so a size is given where a font is pushed.

const std = @import("std");
const c = @import("c");

const icons = @import("icons.zig");

pub const Weight = enum { regular, medium, semibold };

/// The design's text sizes, in its pixels.
pub const size = struct {
    /// Body text: the start screen and the mission picker.
    pub const body: f32 = 13;
    /// Most of the interface: menus, tabs, rows, buttons and code.
    pub const ui: f32 = 12.5;
    /// Labels, chips and secondary lines.
    pub const small: f32 = 12;
    /// The status bar, counts and file paths.
    pub const smaller: f32 = 11.5;
    /// Key chips, pills, badges and section headings.
    pub const tiny: f32 = 10.5;
    /// Icons in buttons, and the larger icons beside text.
    pub const icon: f32 = 16;
    pub const icon_small: f32 = 14;
    pub const icon_tiny: f32 = 12;
};

const Loaded = struct {
    sans: std.EnumArray(Weight, *c.ImFont),
    mono: std.EnumArray(Weight, *c.ImFont),
    brand: *c.ImFont,
};

/// How much larger ImGui's size of a font is than the design's: ImGui sizes a font by its ascent
/// and descent, a stylesheet by its em, so a font pushed at the design's size times this draws as
/// large as in the design.
pub const em = struct {
    pub const sans = emFactor(@embedFile("IBMPlexSans-Regular.ttf"));
    pub const mono = emFactor(@embedFile("JetBrainsMono-Regular.ttf"));
    pub const brand = emFactor(@embedFile("Newtown.ttf"));
    pub const icons = emFactor(@embedFile("lucide.ttf"));
};

/// A TrueType font's ascent less its descent in ems, from its `hhea` and `head` tables, as
/// stb_truetype reads them.
fn emFactor(comptime data: []const u8) f32 {
    @setEvalBranchQuota(10_000);
    const tables = std.mem.readInt(u16, data[4..6], .big);
    var units: u16 = 0;
    var ascent: i16 = 0;
    var descent: i16 = 0;
    for (0..tables) |index| {
        const record = 12 + index * 16;
        const offset = std.mem.readInt(u32, data[record + 8 ..][0..4], .big);
        if (std.mem.eql(u8, data[record..][0..4], "head")) units = std.mem.readInt(u16, data[offset + 18 ..][0..2], .big);
        if (std.mem.eql(u8, data[record..][0..4], "hhea")) {
            ascent = std.mem.readInt(i16, data[offset + 4 ..][0..2], .big);
            descent = std.mem.readInt(i16, data[offset + 6 ..][0..2], .big);
        }
    }
    return @as(f32, @floatFromInt(@as(i32, ascent) - descent)) / @as(f32, @floatFromInt(units));
}

test emFactor {
    // The text fonts are taller than their em, Newtown much shorter, and the icons as tall.
    try std.testing.expectApproxEqAbs(1.3, em.sans, 0.01);
    try std.testing.expectApproxEqAbs(1.32, em.mono, 0.01);
    try std.testing.expect(em.brand < 0.6);
    try std.testing.expectEqual(1, em.icons);
}

var loaded: Loaded = undefined;

pub fn sans(weight: Weight) *c.ImFont {
    return loaded.sans.get(weight);
}

pub fn mono(weight: Weight) *c.ImFont {
    return loaded.mono.get(weight);
}

/// Newtown, for the editor's name.
pub fn brand() *c.ImFont {
    return loaded.brand;
}

const sans_files = std.EnumArray(Weight, []const u8).init(.{
    .regular = @embedFile("IBMPlexSans-Regular.ttf"),
    .medium = @embedFile("IBMPlexSans-Medium.ttf"),
    .semibold = @embedFile("IBMPlexSans-SemiBold.ttf"),
});
const mono_files = std.EnumArray(Weight, []const u8).init(.{
    .regular = @embedFile("JetBrainsMono-Regular.ttf"),
    .medium = @embedFile("JetBrainsMono-Medium.ttf"),
    .semibold = @embedFile("JetBrainsMono-SemiBold.ttf"),
});
const newtown = @embedFile("Newtown.ttf");
const lucide = @embedFile("lucide.ttf");

/// The range of codepoints the icons take, which the icon font gives the interface's fonts.
const icon_range = [_]c.ImWchar{ icons.Icon.first, icons.Icon.last, 0 };

/// Adds the fonts to ImGui's atlas, the first sans font as the default.
pub fn load() void {
    const atlas = c.ImGui_GetIO().*.Fonts;
    for (std.enums.values(Weight)) |weight| {
        loaded.sans.set(weight, add(atlas, sans_files.get(weight), false, null));
        // Lucide's glyphs sit on the baseline, a little low beside the text, and each icon takes
        // the same width, so that a column of icons lines up.
        _ = add(atlas, lucide, true, &icon_range);
    }
    for (std.enums.values(Weight)) |weight| loaded.mono.set(weight, add(atlas, mono_files.get(weight), false, null));
    loaded.brand = add(atlas, newtown, false, null);
}

fn add(atlas: *c.ImFontAtlas, data: []const u8, merge: bool, range: ?[*]const c.ImWchar) *c.ImFont {
    var config: c.ImFontConfig = .{
        // The data is the executable's own, which the atlas must not free.
        .FontDataOwnedByAtlas = false,
        .MergeMode = merge,
        .GlyphMaxAdvanceX = std.math.floatMax(f32),
        .RasterizerMultiply = 1,
        .RasterizerDensity = 1,
        .ExtraSizeScale = 1,
    };
    if (merge) {
        config.GlyphOffset = .{ .x = 0, .y = 2 };
        config.GlyphMinAdvanceX = size.ui * 1.25;
    }
    return c.ImFontAtlas_AddFontFromMemoryTTF(atlas, @constCast(data.ptr), @intCast(data.len), size.ui, &config, range).?;
}
