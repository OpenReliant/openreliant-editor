//! The fonts the editor carries and draws with: IBM Plex Sans for the interface, with Lucide's
//! icons merged into it, JetBrains Mono for code and values, and Newtown, OpenReliant's own, for
//! the editor's name.
//!
//! ImGui draws a font only at a whole number of its pixels, which for Plex at the design's 12.5
//! pixels is 16.25. So each size the design uses is a font of its own, a face, which ImGui draws at
//! the nearest whole number and scales to the exact size (`ImFontConfig.ExtraSizeScale`).

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

/// The design's line height, in ems: a line of text is this much higher than its font's size.
pub const line_height: f32 = 1.45;

pub const Family = enum {
    /// IBM Plex Sans, with Lucide's icons.
    sans,
    /// JetBrains Mono.
    mono,
    /// Newtown, for the editor's name.
    brand,

    fn file(family: Family, weight: Weight) []const u8 {
        return switch (family) {
            .sans => sans_files.get(weight),
            .mono => mono_files.get(weight),
            .brand => newtown,
        };
    }

    /// The family's metrics, the same in each of its weights.
    pub fn metrics(family: Family) Metrics {
        return switch (family) {
            inline else => |which| comptime Metrics.read(which.file(.regular)),
        };
    }
};

/// The sizes the design draws each family at, with the weights of each. A face for every one is
/// in the atlas.
const sizes = std.EnumArray(Family, []const f32).init(.{
    .sans = &.{ size.tiny, 11, size.smaller, size.small, size.ui, size.body, 13.5, 16 },
    .mono = &.{ size.tiny, size.smaller, size.small, size.ui },
    .brand = &.{ 16, 60 },
});

/// A family in one weight at one of the design's sizes, as a font of ImGui's atlas.
pub const Face = struct {
    family: Family,
    weight: Weight,
    /// The size in the design's pixels.
    size: f32,
    font: *c.ImFont = undefined,
    /// The size ImGui draws the font at, a whole number of its pixels.
    imgui_size: f32 = undefined,
};

/// Every face, in the order of `sizes`, the weights of each size together.
var faces: [face_count]Face = blk: {
    var all: [face_count]Face = undefined;
    var index: usize = 0;
    for (std.enums.values(Family)) |family| for (sizes.get(family)) |design_size| for (weightsOf(family)) |weight| {
        all[index] = .{ .family = family, .weight = weight, .size = design_size };
        index += 1;
    };
    break :blk all;
};

const face_count = count: {
    var total: usize = 0;
    for (std.enums.values(Family)) |family| total += sizes.get(family).len * weightsOf(family).len;
    break :count total;
};

/// Newtown has one weight.
fn weightsOf(family: Family) []const Weight {
    return switch (family) {
        .sans, .mono => std.enums.values(Weight),
        .brand => &.{.regular},
    };
}

/// The face of `family` in `weight` at `design_size`, or at the nearest size the design has.
pub fn face(family: Family, weight: Weight, design_size: f32) *const Face {
    var best: ?*const Face = null;
    for (&faces) |*each| {
        if (each.family != family or (family != .brand and each.weight != weight)) continue;
        if (best == null or @abs(each.size - design_size) < @abs(best.?.size - design_size)) best = each;
    }
    return best.?;
}

/// The face ImGui draws text in now, if it's one of the faces.
pub fn current() ?*const Face {
    const font: *c.ImFont = c.ImGui_GetFont();
    for (&faces) |*each| if (each.font == font) return each;
    return null;
}

/// The font the icons are drawn with, at a whole number of pixels: Plex at the interface's size,
/// with Lucide merged into it.
pub fn iconFont() *c.ImFont {
    return icon_font;
}

var icon_font: *c.ImFont = undefined;

/// A font's height above and below its baseline, and its capitals' height, in ems, from its `hhea`,
/// `head` and `OS/2` tables.
pub const Metrics = struct {
    /// The height above the baseline and below it, as a stylesheet lays out a line of text.
    ascent: f32,
    descent: f32,
    /// The capitals' height above the baseline, which the figures share in the editor's fonts; 0
    /// where the font doesn't give it.
    cap_height: f32,
    /// How much larger ImGui's size of the font is than its em. ImGui sizes a font by its ascent
    /// less its descent as the file gives them, a stylesheet by its em, so a font pushed at the
    /// design's size times this draws as large as in the design.
    em: f32,

    fn read(comptime data: []const u8) Metrics {
        @setEvalBranchQuota(10_000);
        const tables = std.mem.readInt(u16, data[4..6], .big);
        var units: u16 = 0;
        var ascent: i16 = 0;
        var descent: i16 = 0;
        var cap_height: i16 = 0;
        for (0..tables) |index| {
            const record = 12 + index * 16;
            const offset = std.mem.readInt(u32, data[record + 8 ..][0..4], .big);
            if (std.mem.eql(u8, data[record..][0..4], "head")) units = std.mem.readInt(u16, data[offset + 18 ..][0..2], .big);
            if (std.mem.eql(u8, data[record..][0..4], "hhea")) {
                ascent = std.mem.readInt(i16, data[offset + 4 ..][0..2], .big);
                descent = std.mem.readInt(i16, data[offset + 6 ..][0..2], .big);
            }
            // `sCapHeight` came in the table's second version.
            if (std.mem.eql(u8, data[record..][0..4], "OS/2") and std.mem.readInt(u16, data[offset..][0..2], .big) >= 2) {
                cap_height = std.mem.readInt(i16, data[offset + 88 ..][0..2], .big);
            }
        }
        const em_units: f32 = @floatFromInt(units);
        return .{
            .ascent = @as(f32, @floatFromInt(ascent)) / em_units,
            // Newtown gives its descent as a positive number; browsers take it as below the
            // baseline all the same.
            .descent = @as(f32, @floatFromInt(@abs(descent))) / em_units,
            .cap_height = @as(f32, @floatFromInt(cap_height)) / em_units,
            .em = @as(f32, @floatFromInt(@as(i32, ascent) - descent)) / em_units,
        };
    }

    /// How far below the top of a line `line` pixels high a browser puts the baseline of text
    /// `pixels` high: with the ascent and descent each rounded to whole pixels, and half the
    /// leading, rounded down, above the text (Blink's `FontHeight::AddLeading`).
    pub fn baselineInLine(font: Metrics, pixels: f32, line: f32) f32 {
        const ascent = @round(font.ascent * pixels);
        const descent = @round(font.descent * pixels);
        return @floor((line - ascent - descent) / 2) + ascent;
    }
};

test Metrics {
    // The text fonts are taller than their em in ImGui's sizes, Newtown much shorter, and the
    // icons as tall.
    try std.testing.expectApproxEqAbs(1.3, Family.sans.metrics().em, 0.01);
    try std.testing.expectApproxEqAbs(1.32, Family.mono.metrics().em, 0.01);
    try std.testing.expect(Family.brand.metrics().em < 0.6);
    try std.testing.expectEqual(1, comptime Metrics.read(lucide).em);
    // In the design's lines, Plex at 12.5 pixels has 13 pixels of ascent and a pixel of leading
    // above it, at 13 pixels no leading, and Newtown at 16 pixels, whose descent counts below the
    // baseline, 12 and 4.
    try std.testing.expectEqual(14, Family.sans.metrics().baselineInLine(12.5, 12.5 * line_height));
    try std.testing.expectEqual(13, Family.sans.metrics().baselineInLine(13, 13 * line_height));
    try std.testing.expectApproxEqAbs(0.19, Family.brand.metrics().descent, 1e-6);
    try std.testing.expectEqual(16, Family.brand.metrics().baselineInLine(16, 16 * line_height));
    // Plex's capitals and figures are 0.698 of its em high, JetBrains Mono's 0.73.
    try std.testing.expectApproxEqAbs(0.698, Family.sans.metrics().cap_height, 1e-6);
    try std.testing.expectApproxEqAbs(0.73, Family.mono.metrics().cap_height, 1e-6);
}

test face {
    // Each size the design gives has a face of its own, in each weight; another size takes the
    // nearest.
    try std.testing.expectEqual(12.5, face(.sans, .medium, size.ui).size);
    try std.testing.expectEqual(Weight.medium, face(.sans, .medium, size.ui).weight);
    try std.testing.expectEqual(13.5, face(.sans, .semibold, 13.4).size);
    try std.testing.expectEqual(60, face(.brand, .semibold, 60).size);
    try std.testing.expectEqual(10.5, face(.mono, .regular, 9).size);
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

/// Adds the fonts to ImGui's atlas: the icons' font first, as the default, then every face.
pub fn load() void {
    const atlas = c.ImGui_GetIO().*.Fonts;
    icon_font = add(atlas, sans_files.get(.regular), size.ui, 1);
    mergeIcons(atlas, size.ui);
    for (&faces) |*each| {
        // ImGui's size of the face, and the scale from the nearest whole number to it.
        const exact = each.size * each.family.metrics().em;
        each.imgui_size = @max(1, @round(exact));
        each.font = add(atlas, each.family.file(each.weight), each.imgui_size, exact / each.imgui_size);
        if (each.family == .sans) mergeIcons(atlas, each.imgui_size);
    }
}

fn add(atlas: *c.ImFontAtlas, data: []const u8, imgui_size: f32, scale: f32) *c.ImFont {
    var config: c.ImFontConfig = .{
        // The data is the executable's own, which the atlas must not free.
        .FontDataOwnedByAtlas = false,
        .GlyphMaxAdvanceX = std.math.floatMax(f32),
        .RasterizerMultiply = 1,
        .RasterizerDensity = 1,
        .ExtraSizeScale = scale,
    };
    return c.ImFontAtlas_AddFontFromMemoryTTF(atlas, @constCast(data.ptr), @intCast(data.len), imgui_size, &config, null).?;
}

/// Merges Lucide's icons into the font just added, which ImGui draws at `imgui_size`. At the
/// interface's size, each icon moves 2 pixels down to sit on the line of text beside it, and takes
/// the same width, so that a column of icons lines up; both scale with the font's size.
fn mergeIcons(atlas: *c.ImFontAtlas, imgui_size: f32) void {
    const scale = imgui_size / size.ui;
    var config: c.ImFontConfig = .{
        .FontDataOwnedByAtlas = false,
        .MergeMode = true,
        .GlyphOffset = .{ .x = 0, .y = 2 * scale },
        .GlyphMinAdvanceX = size.ui * 1.25 * scale,
        .GlyphMaxAdvanceX = std.math.floatMax(f32),
        .RasterizerMultiply = 1,
        .RasterizerDensity = 1,
        .ExtraSizeScale = 1,
    };
    _ = c.ImFontAtlas_AddFontFromMemoryTTF(atlas, @constCast(lucide.ptr), @intCast(lucide.len), 0, &config, &icon_range).?;
}
