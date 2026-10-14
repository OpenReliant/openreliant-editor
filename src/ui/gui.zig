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

/// Draws `value` at `at` in `color`, in the current font.
pub fn drawText(list: *c.ImDrawList, at: Vec2, color: Color, value: []const u8) void {
    c.ImDrawList_AddTextEx(list, at, color, value.ptr, value.ptr + value.len);
}

/// Draws `value` at `at` with `spacing` design pixels between its characters, as the design's
/// uppercase headings are.
pub fn drawSpaced(list: *c.ImDrawList, at: Vec2, color: Color, value: []const u8, spacing: f32) f32 {
    var x = at.x;
    var view = std.unicode.Utf8View.initUnchecked(value).iterator();
    while (view.nextCodepointSlice()) |character| {
        drawText(list, .{ .x = x, .y = at.y }, color, character);
        x += textSize(character).x + px(spacing);
    }
    return x - at.x;
}

/// The width `value` takes with `spacing` between its characters.
pub fn spacedWidth(value: []const u8, spacing: f32) f32 {
    var width: f32 = 0;
    var view = std.unicode.Utf8View.initUnchecked(value).iterator();
    while (view.nextCodepointSlice()) |character| width += textSize(character).x + px(spacing);
    return width;
}

/// Pushes Newtown at `size` design pixels; `popFont` takes it off.
pub fn brand(size: f32) void {
    c.ImGui_PushFontFloat(fonts.brand(), size * fonts.em.brand);
}

/// Pushes the interface's font at `size` design pixels.
pub fn sans(weight: fonts.Weight, size: f32) void {
    c.ImGui_PushFontFloat(fonts.sans(weight), size * fonts.em.sans);
}

/// Pushes the code font at `size` design pixels.
pub fn mono(weight: fonts.Weight, size: f32) void {
    c.ImGui_PushFontFloat(fonts.mono(weight), size * fonts.em.mono);
}

/// Pushes the font the icons are drawn in, so that an icon is `size` design pixels square.
pub fn iconFont(size: f32) void {
    c.ImGui_PushFontFloat(fonts.sans(.regular), size * fonts.em.icons);
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

test print {
    defer newFrame();
    try std.testing.expectEqualStrings("Ln 46, Col 5", print("Ln {d}, Col {d}", .{ 46, 5 }));
}
