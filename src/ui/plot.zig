//! ImPlot through its C shim (`plot/plot_shim.h`): the plot the Scene view's map draws on, with
//! equal axes, which the pointer pans, and points it drags. The map zooms itself
//! (`views/scene.zig`).

const std = @import("std");
const c = @import("c");

const theme = @import("theme.zig");

pub const Vec2 = c.ImVec2;
pub const Rect = c.OrPlotRect;

/// Makes ImPlot's context, once Dear ImGui's is made, on the map's ground. The map draws its own
/// grid (`views/scene/drawing.zig`).
pub fn create() void {
    c.or_plot_create();
    c.or_plot_style(theme.map);
}

pub fn destroy() void {
    c.or_plot_destroy();
}

/// Begins a plot `size` pixels across and down. With `shown`, its axes show it from this frame
/// on. False where it isn't drawn; `end` ends it otherwise.
pub fn begin(id: [:0]const u8, size: Vec2, shown: ?Rect) bool {
    return c.or_plot_begin(id, size.x, size.y, shown != null, shown orelse std.mem.zeroes(Rect));
}

pub fn end() void {
    c.or_plot_end();
}

/// What the axes show.
pub fn limits() Rect {
    return c.or_plot_limits();
}

/// The plot's area on the screen: its top left and bottom right corners.
pub fn area() [2]Vec2 {
    var rect: [4]f32 = undefined;
    c.or_plot_area(&rect);
    return .{ .{ .x = rect[0], .y = rect[1] }, .{ .x = rect[2], .y = rect[3] } };
}

/// The place on the screen of `at` on the plot.
pub fn toPixels(at: [2]f64) Vec2 {
    var pixels: [2]f32 = undefined;
    c.or_plot_to_pixels(at[0], at[1], &pixels);
    return .{ .x = pixels[0], .y = pixels[1] };
}

/// The place on the plot of `at` on the screen.
pub fn fromPixels(at: Vec2) [2]f64 {
    var place: [2]f64 = undefined;
    c.or_plot_from_pixels(at.x, at.y, &place);
    return place;
}

/// The draw list over the plot, clipped to its area until `popClip`.
pub fn drawList() *c.ImDrawList {
    c.or_plot_push_clip();
    return @ptrCast(@alignCast(c.or_plot_draw_list().?));
}

pub fn popClip() void {
    c.or_plot_pop_clip();
}

/// What the pointer did to a point (`dragPoint`).
pub const Drag = struct {
    clicked: bool = false,
    hovered: bool = false,
    /// Whether the pointer holds it.
    held: bool = false,
};

/// A point `radius` pixels around `at`, which the pointer can click and drag; a drag moves `at`.
/// The caller draws it.
pub fn dragPoint(id: usize, at: *[2]f64, radius: f32) Drag {
    var drag: Drag = .{};
    _ = c.or_plot_drag_point(@intCast(id), &at[0], &at[1], radius, &drag.clicked, &drag.hovered, &drag.held);
    return drag;
}
