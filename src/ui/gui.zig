//! Small helpers over Dear ImGui's C API for the rest of the editor: text from slices, strings made
//! for the frame, sizes in the design's pixels, fonts and colours pushed for a scope.

const std = @import("std");
const c = @import("c");

const fonts = @import("fonts.zig");
const theme = @import("theme.zig");
const Color = theme.Color;

pub const Vec2 = c.ImVec2;

/// The display's scale, which turns the design's pixels into ImGui's.
pub var scale: f32 = 1;

/// Memory for the strings made during a frame, freed as the next one starts.
var frame_arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);

pub fn frameAllocator() std.mem.Allocator {
    return frame_arena.allocator();
}

/// Frees the last frame's strings.
pub fn newFrame() void {
    _ = frame_arena.reset(.retain_capacity);
}

/// `value` design pixels in ImGui's.
pub fn px(value: f32) f32 {
    return value * scale;
}

pub fn vec2(x: f32, y: f32) Vec2 {
    return .{ .x = x, .y = y };
}

pub fn add(a: Vec2, b: Vec2) Vec2 {
    return .{ .x = a.x + b.x, .y = a.y + b.y };
}

/// A string for this frame, formatted, ending in a NUL for ImGui.
pub fn print(comptime format: []const u8, args: anytype) [:0]const u8 {
    return std.fmt.allocPrintSentinel(frame_arena.allocator(), format, args, 0) catch "";
}

/// `text` with a NUL after it, for ImGui, for this frame.
pub fn z(value: []const u8) [:0]const u8 {
    return frame_arena.allocator().dupeSentinel(u8, value, 0) catch "";
}

/// Shows `text`, which needs no NUL.
pub fn text(value: []const u8) void {
    c.ImGui_TextUnformattedEx(value.ptr, value.ptr + value.len);
}

pub fn textColored(color: Color, value: []const u8) void {
    c.ImGui_PushStyleColor(c.ImGuiCol_Text, color);
    text(value);
    c.ImGui_PopStyleColor();
}

/// The size `value` takes in the current font.
pub fn textSize(value: []const u8) Vec2 {
    return c.ImGui_CalcTextSizeEx(value.ptr, value.ptr + value.len, false, -1);
}

/// Where a line of text in the current font goes for it to sit in the middle of a box whose
/// middle is at `middle`, as a browser places the design's text: a line of the design's line
/// height centred on the middle, and the baseline in it on the nearest whole pixel.
pub fn textTop(middle: f32) f32 {
    return textTopIn(middle, null);
}

/// `textTop` for a line `line_pixels` design pixels high where the design sets one, such as a key
/// chip's, as high as its font.
pub fn textTopIn(middle: f32, line_pixels: ?f32) f32 {
    const face = fonts.current() orelse return middle - c.ImGui_GetFontSize() / 2;
    const size = px(face.size);
    const line_height = if (line_pixels) |pixels| px(pixels) else size * fonts.line_height;
    return @round(middle - line_height / 2 + face.family.metrics().baselineInLine(size, line_height)) - ascent();
}

/// How far below the top of a line of the current font its baseline is, as ImGui draws it.
pub fn ascent() f32 {
    return c.or_imgui_font_ascent();
}

/// Draws `value` at `at` in `color`, in the current font.
pub fn drawText(list: *c.ImDrawList, at: Vec2, color: Color, value: []const u8) void {
    c.ImDrawList_AddTextEx(list, at, color, value.ptr, value.ptr + value.len);
}

/// The lines of `value` wrapped at `width` in the current font, broken at spaces as ImGui wraps
/// text. Unlike ImGui's own wrapping, which keeps lines as high as the font, the caller places
/// each line, as high as the design's.
pub const Lines = struct {
    rest: []const u8,
    width: f32,

    pub fn next(lines: *Lines) ?[]const u8 {
        const left = std.mem.trimStart(u8, lines.rest, " \n");
        if (left.len == 0) return null;
        const start = left.ptr;
        const cut: [*]const u8 = c.ImFont_CalcWordWrapPosition(c.ImGui_GetFont(), c.ImGui_GetFontSize(), start, start + left.len, lines.width);
        // A word wider than the line goes on a line of its own.
        var length = cut - start;
        if (length == 0) length = std.mem.findAny(u8, left, " \n") orelse left.len;
        lines.rest = left[length..];
        return std.mem.trimEnd(u8, left[0..length], " \n");
    }

    /// How many lines there are.
    pub fn count(lines: Lines) usize {
        var copy = lines;
        var total: usize = 0;
        while (copy.next()) |_| total += 1;
        return total;
    }
};

pub fn wrap(value: []const u8, width: f32) Lines {
    return .{ .rest = value, .width = width };
}

/// Draws `value` at `at` with `spacing` design pixels after each of its characters, as the
/// design's letter spacing. Each character goes to the nearest whole pixel. Its width.
pub fn drawSpaced(list: *c.ImDrawList, at: Vec2, color: Color, value: []const u8, spacing: f32) f32 {
    const font = c.ImGui_GetFontBaked().?;
    var x = at.x;
    var view = std.unicode.Utf8View.initUnchecked(value).iterator();
    while (view.nextCodepointSlice()) |character| {
        drawText(list, .{ .x = @round(x), .y = at.y }, color, character);
        x += advance(font, character) + px(spacing);
    }
    return x - at.x;
}

/// The width `value` takes with `spacing` after each of its characters.
pub fn spacedWidth(value: []const u8, spacing: f32) f32 {
    const font = c.ImGui_GetFontBaked().?;
    var width: f32 = 0;
    var view = std.unicode.Utf8View.initUnchecked(value).iterator();
    while (view.nextCodepointSlice()) |character| width += advance(font, character) + px(spacing);
    return width;
}

/// How far `character` moves the pen in `font`. ImGui keeps characters to the first 65536, and
/// draws the others as the replacement character.
fn advance(font: *c.ImFontBaked, character: []const u8) f32 {
    const codepoint = std.unicode.utf8Decode(character) catch std.unicode.replacement_character;
    return c.ImFontBaked_GetCharAdvance(font, std.math.cast(c.ImWchar, codepoint) orelse std.unicode.replacement_character);
}

/// Pushes Newtown at `size` design pixels; `popFont` takes it off.
pub fn brand(size: f32) void {
    pushFace(fonts.face(.brand, .regular, size));
}

/// Pushes the interface's font at `size` design pixels.
pub fn sans(weight: fonts.Weight, size: f32) void {
    pushFace(fonts.face(.sans, weight, size));
}

/// Pushes the code font at `size` design pixels.
pub fn mono(weight: fonts.Weight, size: f32) void {
    pushFace(fonts.face(.mono, weight, size));
}

fn pushFace(face: *const fonts.Face) void {
    c.ImGui_PushFontFloat(face.font, face.imgui_size);
}

/// Pushes the font the icons are drawn in, so that an icon is `size` design pixels square: Lucide's
/// glyphs take the whole of its size.
pub fn iconFont(size: f32) void {
    c.ImGui_PushFontFloat(fonts.iconFont(), size);
}

pub fn popFont() void {
    c.ImGui_PopFont();
}

pub fn pushColor(which: c.ImGuiCol, color: Color) void {
    c.ImGui_PushStyleColor(which, color);
}

pub fn popColor(count: c_int) void {
    c.ImGui_PopStyleColorEx(count);
}

pub fn pushVar(which: c.ImGuiStyleVar, value: f32) void {
    c.ImGui_PushStyleVar(which, value);
}

pub fn pushVar2(which: c.ImGuiStyleVar, value: Vec2) void {
    c.ImGui_PushStyleVarImVec2(which, value);
}

pub fn popVar(count: c_int) void {
    c.ImGui_PopStyleVarEx(count);
}

pub fn cursor() Vec2 {
    return c.ImGui_GetCursorScreenPos();
}

pub fn setCursor(at: Vec2) void {
    c.ImGui_SetCursorScreenPos(at);
}

pub fn available() Vec2 {
    return c.ImGui_GetContentRegionAvail();
}

pub fn drawList() *c.ImDrawList {
    return c.ImGui_GetWindowDrawList();
}

pub fn rect(list: *c.ImDrawList, min: Vec2, max: Vec2, color: Color, rounding: f32) void {
    c.ImDrawList_AddRectFilledEx(list, min, max, color, px(rounding), 0);
}

pub fn outline(list: *c.ImDrawList, min: Vec2, max: Vec2, color: Color, rounding: f32) void {
    c.ImDrawList_AddRectEx(list, min, max, color, px(rounding), px(1), 0);
}

/// Draws the line a stylesheet's `inset 0 -thickness 0` shadow draws in a box from `min` to `max`
/// with corners of `rounding`: along the box's bottom, `thickness` pixels thick, and curving up
/// into its lower corners.
pub fn insetUnderline(list: *c.ImDrawList, min: Vec2, max: Vec2, rounding: f32, thickness: f32, color: Color) void {
    const radius = px(rounding);
    const width = px(thickness);
    const quarter: f32 = std.math.pi / 2.0;
    // The line's middle runs half its width inside the box's edge.
    const middle = radius - width / 2;
    arc(list, .{ .x = min.x + radius, .y = max.y - radius }, middle, 2 * quarter, quarter);
    arc(list, .{ .x = max.x - radius, .y = max.y - radius }, middle, quarter, 0);
    c.ImDrawList_PathStroke(list, color, width, 0);
}

/// Adds to the draw list's path the points of an arc around `center`, from angle `from` to `to`,
/// with y downwards.
fn arc(list: *c.ImDrawList, center: Vec2, radius: f32, from: f32, to: f32) void {
    const steps = 8;
    for (0..steps + 1) |step| {
        const angle = from + (to - from) * @as(f32, @floatFromInt(step)) / steps;
        c.ImDrawList_PathLineTo(list, .{ .x = center.x + @cos(angle) * radius, .y = center.y + @sin(angle) * radius });
    }
}

pub fn line(list: *c.ImDrawList, from: Vec2, to: Vec2, color: Color) void {
    c.ImDrawList_AddLineEx(list, from, to, color, px(1));
}

pub fn dot(list: *c.ImDrawList, center: Vec2, radius: f32, color: Color) void {
    c.ImDrawList_AddCircleFilled(list, center, px(radius), color, 0);
}

/// Whether the last item is under the pointer, shown as a hand for a clickable one.
pub fn hovered() bool {
    return c.ImGui_IsItemHovered(0);
}

/// A tooltip with `value`, after the usual delay.
pub fn tooltip(value: []const u8) void {
    if (!c.ImGui_IsItemHovered(c.ImGuiHoveredFlags_ForTooltip | c.ImGuiHoveredFlags_AllowWhenDisabled)) return;
    if (c.ImGui_BeginTooltip()) {
        sans(.regular, fonts.size.small);
        c.ImGui_PushTextWrapPos(px(360));
        text(value);
        c.ImGui_PopTextWrapPos();
        popFont();
        c.ImGui_EndTooltip();
    }
}

/// A tooltip with `value` now, whatever item is under the pointer.
pub fn tooltipNow(value: []const u8) void {
    if (c.ImGui_BeginTooltip()) {
        sans(.regular, fonts.size.small);
        text(value);
        popFont();
        c.ImGui_EndTooltip();
    }
}

/// Shows the pointer as a hand over the last item, for a clickable one.
pub fn handCursor() void {
    if (c.ImGui_IsItemHovered(0)) c.ImGui_SetMouseCursor(c.ImGuiMouseCursor_Hand);
}

/// Wraps the text that follows at the screen's `x`, until `c.ImGui_PopTextWrapPos`.
pub fn wrapAt(x: f32) void {
    c.ImGui_PushTextWrapPos(x - c.ImGui_GetWindowPos().x + c.ImGui_GetScrollX());
}

pub fn sameLine(spacing: f32) void {
    c.ImGui_SameLineEx(0, px(spacing));
}

pub fn space(height: f32) void {
    c.ImGui_Dummy(vec2(0, px(height)));
}

/// The ImGui ID of `value` in the current scope.
pub fn id(value: []const u8) c.ImGuiID {
    return c.ImGui_GetIDStr(value.ptr, value.ptr + value.len);
}

pub fn pushId(value: []const u8) void {
    c.ImGui_PushIDStr(value.ptr, value.ptr + value.len);
}

pub fn pushIdInt(value: usize) void {
    c.ImGui_PushIDInt(@intCast(value));
}

pub fn popId() void {
    c.ImGui_PopID();
}

test Lines {
    // An empty text, or one of spaces, has no lines. Wrapping words needs ImGui's fonts, which the
    // tests don't load.
    try std.testing.expectEqual(0, wrap("", 100).count());
    try std.testing.expectEqual(0, wrap(" \n ", 100).count());
}

test print {
    defer newFrame();
    try std.testing.expectEqualStrings("Ln 46, Col 5", print("Ln {d}, Col {d}", .{ 46, 5 }));
}
