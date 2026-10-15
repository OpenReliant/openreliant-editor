//! How the Scene view's map draws its parts on the screen: the grid, the rings, the routes' legs,
//! the ships' and markers' marks, the names, and the notes over the map. Nothing here knows the
//! map's state; the view (`views/scene.zig`) says what goes where.

const std = @import("std");
const c = @import("c");

const game = @import("../../game.zig");
const ui = @import("../../ui.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const plot = ui.plot;
const theme = ui.theme;
const widgets = ui.widgets;
const Color = theme.Color;
const Icon = ui.icons.Icon;
const Vec2 = gui.Vec2;
const px = gui.px;

/// The least spacing of the grid's cells, in pixels: each is the smallest of 1, 2 or 5 times a
/// power of ten that is at least this wide. A line every `major_every` cells is brighter.
const least_cell = 40;
const major_every = 5;
/// A cluster's height, the size of its count, and the room around the count, in design pixels. A
/// cluster is the mark the map draws for several things that would overlap on the screen.
pub const cluster_size = 20;
const cluster_figures = fonts.size.tiny;
const cluster_padding = 4;
/// How long a leg to or from a place off the map is drawn, in pixels.
const stub_length = 56;

pub fn distanceTo(a: Vec2, b: Vec2) f32 {
    return @sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

/// The point `pixels` from `from` along the unit vector `way`.
pub fn along(from: Vec2, way: Vec2, pixels: f32) Vec2 {
    return .{ .x = from.x + way.x * pixels, .y = from.y + way.y * pixels };
}

/// Whether `point` is in the box between `corners`, edges included.
pub fn isInside(point: Vec2, corners: [2]Vec2) bool {
    return point.x >= corners[0].x and point.x <= corners[1].x and point.y >= corners[0].y and point.y <= corners[1].y;
}

/// The part of the line from `from` to `to` inside `corners`, as distances along it from `from`;
/// null where none of it is.
pub fn clipAlong(from: Vec2, to: Vec2, corners: [2]Vec2) ?[2]f32 {
    const length = distanceTo(from, to);
    if (length == 0) return null;
    const delta: Vec2 = .{ .x = to.x - from.x, .y = to.y - from.y };
    var first: f32 = 0;
    var last: f32 = 1;
    // Each edge cuts off the part of the line beyond it (Liang and Barsky's clipping).
    for ([_][2]f32{
        .{ -delta.x, from.x - corners[0].x },
        .{ delta.x, corners[1].x - from.x },
        .{ -delta.y, from.y - corners[0].y },
        .{ delta.y, corners[1].y - from.y },
    }) |edge| {
        const toward, const room = edge;
        if (toward == 0) {
            if (room < 0) return null;
            continue;
        }
        const cut = room / toward;
        if (toward < 0) first = @max(first, cut) else last = @min(last, cut);
    }
    if (first > last) return null;
    return .{ first * length, last * length };
}

/// How near and how far the map's area is from `middle`, in pixels: a ring shows on the map only
/// with a radius between the two.
pub fn reachOf(middle: Vec2, corners: [2]Vec2) [2]f32 {
    const nearest: Vec2 = .{ .x = std.math.clamp(middle.x, corners[0].x, corners[1].x), .y = std.math.clamp(middle.y, corners[0].y, corners[1].y) };
    var farthest: f32 = 0;
    for ([_]f32{ corners[0].x, corners[1].x }) |x| for ([_]f32{ corners[0].y, corners[1].y }) |y| {
        farthest = @max(farthest, distanceTo(middle, .{ .x = x, .y = y }));
    };
    return .{ distanceTo(middle, nearest), farthest };
}

/// The grid's cell for `scale` pixels to the game's unit: 1, 2 or 5 times a power of ten, the least
/// at least `least_cell` pixels wide.
pub fn cellOf(scale: f32) f64 {
    if (scale <= 0) return 1000;
    const least: f64 = least_cell / @as(f64, scale);
    var power = std.math.pow(f64, 10, @floor(std.math.log10(least)));
    while (true) : (power *= 10) {
        for ([_]f64{ 1, 2, 5 }) |step| if (step * power >= least) return step * power;
    }
}

/// The grid over the part of the map `shown`, a line every `cell` of the game's units.
pub fn grid(list: *c.ImDrawList, shown: plot.Rect, cell: f64) void {
    const corners = plot.area();
    var x = @ceil(shown.x_min / cell) * cell;
    while (x <= shown.x_max) : (x += cell) {
        const at = plot.toPixels(.{ x, 0 }).x;
        const color = if (isMajor(x, cell)) theme.map_grid else theme.map_grid_minor;
        c.ImDrawList_AddLineEx(list, .{ .x = at, .y = corners[0].y }, .{ .x = at, .y = corners[1].y }, color, px(1));
    }
    var y = @ceil(shown.y_min / cell) * cell;
    while (y <= shown.y_max) : (y += cell) {
        const at = plot.toPixels(.{ 0, y }).y;
        const color = if (isMajor(y, cell)) theme.map_grid else theme.map_grid_minor;
        c.ImDrawList_AddLineEx(list, .{ .x = corners[0].x, .y = at }, .{ .x = corners[1].x, .y = at }, color, px(1));
    }
}

fn isMajor(value: f64, cell: f64) bool {
    const cells = @round(value / cell);
    return @mod(cells, major_every) == 0;
}

/// A circle of dashes `dash` pixels long, `gap` pixels apart, drawn only where it can show on the
/// map, so that a ring far larger than the map costs no more than one that fits it.
pub fn dashedCircle(list: *c.ImDrawList, middle: Vec2, radius: f32, color: Color, dash: f32, gap: f32, corners: [2]Vec2) void {
    var from: f32 = 0;
    var to: f32 = 2 * std.math.pi;
    if (!isInside(middle, corners)) {
        // From outside the map, its corners lie within half a turn of the way to its middle.
        const towards = std.math.atan2((corners[0].y + corners[1].y) / 2 - middle.y, (corners[0].x + corners[1].x) / 2 - middle.x);
        var least: f32 = 0;
        var most: f32 = 0;
        for ([_]f32{ corners[0].x, corners[1].x }) |x| for ([_]f32{ corners[0].y, corners[1].y }) |y| {
            var turn = std.math.atan2(y - middle.y, x - middle.x) - towards;
            if (turn > std.math.pi) turn -= 2 * std.math.pi;
            if (turn < -std.math.pi) turn += 2 * std.math.pi;
            least = @min(least, turn);
            most = @max(most, turn);
        };
        from = towards + least;
        to = towards + most;
    }
    const step = px(dash + gap) / radius;
    const share = dash / (dash + gap);
    var angle = @floor(from / step) * step;
    while (angle < to) : (angle += step) {
        c.ImDrawList_PathArcTo(list, middle, radius, angle, angle + step * share, 2);
        c.ImDrawList_PathStroke(list, color, px(1), 0);
    }
}

/// The places taken on the map by its marks and the names placed so far, so that a name goes where
/// it covers neither, and the routes' legs, which a name keeps off where it can.
pub const Labels = struct {
    corners: [2]Vec2,
    taken: std.ArrayList([2]Vec2) = .empty,
    lines: []const [2]Vec2 = &.{},

    /// Takes the first of `spots` where a name `size` big fits, clear of the legs where one is,
    /// and returns it, if one does.
    pub fn place(labels: *Labels, spots: []const Vec2, size: Vec2) ?Vec2 {
        for ([_]bool{ true, false }) |clear_of_lines| for (spots) |spot| {
            const box: [2]Vec2 = .{ spot, .{ .x = spot.x + size.x, .y = spot.y + size.y } };
            if (!isInside(box[0], labels.corners) or !isInside(box[1], labels.corners) or labels.covers(box)) continue;
            if (clear_of_lines and labels.crossesLine(box)) continue;
            labels.take(box);
            return spot;
        };
        return null;
    }

    pub fn take(labels: *Labels, box: [2]Vec2) void {
        labels.taken.append(gui.frameAllocator(), box) catch {};
    }

    fn covers(labels: Labels, box: [2]Vec2) bool {
        for (labels.taken.items) |other| {
            if (box[0].x < other[1].x and box[1].x > other[0].x and box[0].y < other[1].y and box[1].y > other[0].y) return true;
        }
        return false;
    }

    fn crossesLine(labels: Labels, box: [2]Vec2) bool {
        for (labels.lines) |line| if (clipAlong(line[0], line[1], box) != null) return true;
        return false;
    }
};

/// A name on the map, `size` big at `at`, on a backing of the map's colour that the lines and rings
/// pass under, with a dark edge.
pub fn label(list: *c.ImDrawList, at: Vec2, size: Vec2, color: Color, text: []const u8) void {
    const pad: Vec2 = .{ .x = px(3), .y = px(1) };
    gui.rect(list, .{ .x = at.x - pad.x, .y = at.y - pad.y }, .{ .x = at.x + size.x + pad.x, .y = at.y + size.y + pad.y }, theme.fade(theme.map, 0.82), 3);
    for ([_][2]f32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } }) |offset| {
        gui.drawText(list, .{ .x = at.x + offset[0], .y = at.y + offset[1] }, theme.ground, text);
    }
    gui.drawText(list, at, color, text);
}

/// What the map draws for a thing at `middle`, `size` design pixels across: a ship's arrow,
/// pointing the way `heading` goes on the map, outlined in its group's colour on the map's ground,
/// as where it starts; a marker's diamond, filled; a camera point's small ring; or a planet's or
/// the sun's faint disc.
pub fn thing(list: *c.ImDrawList, middle: Vec2, kind: game.ThingKind, heading: ?[2]f64, size: f32, color: Color) void {
    const scale = px(size) / 24;
    switch (kind) {
        .ship => {
            // The design's arrow, in a box of 24 with its middle at 12, 12, pointing up.
            const shape = [_][2]f32{ .{ 0, -10 }, .{ 8, 9 }, .{ 0, 4.5 }, .{ -8, 9 } };
            const way = heading orelse .{ 0, 1 };
            const angle: f32 = if (@abs(way[0]) + @abs(way[1]) < 1e-6) 0 else @floatCast(std.math.atan2(way[0], way[1]));
            var points: [4]Vec2 = undefined;
            for (shape, &points) |point, *made| made.* = turned(middle, point, scale, angle);
            // Filled in two halves, since it isn't convex, then outlined.
            c.ImDrawList_AddTriangleFilled(list, points[0], points[1], points[2], theme.map);
            c.ImDrawList_AddTriangleFilled(list, points[0], points[2], points[3], theme.map);
            c.ImDrawList_AddPolyline(list, &points, points.len, color, px(1.8), c.ImDrawFlags_Closed);
        },
        .marker => {
            const shape = [_][2]f32{ .{ 0, -10 }, .{ 10, 0 }, .{ 0, 10 }, .{ -10, 0 } };
            var points: [4]Vec2 = undefined;
            for (shape, &points) |point, *made| made.* = turned(middle, point, scale, 0);
            c.ImDrawList_AddConvexPolyFilled(list, &points, points.len, color);
            c.ImDrawList_AddPolyline(list, &points, points.len, theme.ground, px(1.2), c.ImDrawFlags_Closed);
        },
        .camera => {
            c.ImDrawList_AddCircleFilled(list, middle, px(size) / 2, theme.map, 0);
            c.ImDrawList_AddCircleEx(list, middle, px(size) / 2, theme.curve, 0, px(1.4));
        },
        .scenery => {
            c.ImDrawList_AddCircleFilled(list, middle, px(size) / 2, theme.fade(theme.text_dim, 0.18), 0);
            c.ImDrawList_AddCircleEx(list, middle, px(size) / 2, theme.fade(theme.text_dim, 0.7), 0, px(1.2));
        },
    }
}

/// `point` of a shape around `middle`, scaled, and turned clockwise by `angle` radians.
fn turned(middle: Vec2, point: [2]f32, scale: f32, angle: f32) Vec2 {
    const x = point[0] * scale;
    const y = point[1] * scale;
    return .{ .x = middle.x + x * @cos(angle) - y * @sin(angle), .y = middle.y + x * @sin(angle) + y * @cos(angle) };
}

/// A cluster of `count` things: a ring in `color` with the count in its middle, or a pill where the
/// count is too wide for the ring (`clusterWidth`).
pub fn cluster(list: *c.ImDrawList, middle: Vec2, count: usize, color: Color) void {
    const width = clusterWidth(count);
    gui.sans(.semibold, cluster_figures);
    defer gui.popFont();
    const text = gui.print("{d}", .{count});
    const text_width = gui.textSize(text).x;
    // ImGui draws text from whole points, so the count goes there, and the ring around it.
    const at: Vec2 = .{ .x = @round(middle.x - text_width / 2), .y = gui.capitalsTop(middle.y) };
    const centre: Vec2 = .{ .x = at.x + text_width / 2, .y = at.y + gui.ascent() - gui.capitals() / 2 };
    const half: Vec2 = .{ .x = px(width) / 2, .y = px(cluster_size) / 2 };
    const line = px(1.6);
    if (width > cluster_size) {
        const min: Vec2 = .{ .x = centre.x - half.x, .y = centre.y - half.y };
        const max: Vec2 = .{ .x = centre.x + half.x, .y = centre.y + half.y };
        gui.rect(list, min, max, theme.map, cluster_size / 2);
        c.ImDrawList_AddRectEx(list, .{ .x = min.x + line / 2, .y = min.y + line / 2 }, .{ .x = max.x - line / 2, .y = max.y - line / 2 }, color, half.y - line / 2, line, 0);
    } else {
        c.ImDrawList_AddCircleFilled(list, centre, half.y, theme.map, 0);
        c.ImDrawList_AddCircleEx(list, centre, half.y - line / 2, color, 0, line);
    }
    gui.drawText(list, at, color, text);
}

/// How wide a cluster of `count` things is, in design pixels: a ring, or wider for a count of three
/// figures.
pub fn clusterWidth(count: usize) f32 {
    gui.sans(.semibold, cluster_figures);
    defer gui.popFont();
    const figures = gui.textSize(gui.print("{d}", .{count})).x / px(1);
    return @max(cluster_size, figures + 2 * cluster_padding);
}

/// The selection's corners around `middle`, `half` pixels out.
pub fn brackets(list: *c.ImDrawList, middle: Vec2, half: f32) void {
    const long = px(8);
    for ([_][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 } }) |corner| {
        const tip: Vec2 = .{ .x = middle.x + corner[0] * half, .y = middle.y + corner[1] * half };
        var points = [_]Vec2{
            .{ .x = tip.x, .y = tip.y - corner[1] * long },
            tip,
            .{ .x = tip.x - corner[0] * long, .y = tip.y },
        };
        c.ImDrawList_AddPolyline(list, &points, points.len, theme.accent, px(2), 0);
    }
}

/// The note by the selected thing: where it is on the map's axes, and how to move it.
pub const PlaceNote = struct {
    box: [2]Vec2,
    where: []const u8,

    const how = "Drag · Shift: snap 100";

    /// The note by the mark at `middle`, at `values` on the axes `names` across and up.
    pub fn at(middle: Vec2, names: [2][]const u8, values: [2]f64) PlaceNote {
        const where = gui.print("{s} {d} · {s} {d}", .{ names[0], @round(values[0]), names[1], @round(values[1]) });
        gui.mono(.regular, fonts.size.smaller);
        const where_width = gui.textSize(where).x;
        gui.popFont();
        gui.sans(.regular, fonts.size.smaller);
        const how_width = gui.textSize(how).x;
        gui.popFont();
        const width = @max(where_width, how_width) + px(18);
        const min: Vec2 = .{ .x = middle.x - px(14) - width, .y = middle.y + px(14) };
        return .{ .box = .{ min, .{ .x = min.x + width, .y = min.y + px(42) } }, .where = where };
    }
};

pub fn placeNote(list: *c.ImDrawList, note: PlaceNote) void {
    const min, const max = note.box;
    gui.rect(list, min, max, theme.fade(theme.panel, 0.94), 4);
    gui.outline(list, min, max, theme.border_strong, 4);
    gui.mono(.regular, fonts.size.smaller);
    gui.drawText(list, .{ .x = min.x + px(9), .y = gui.textTop(min.y + px(13)) }, theme.text_strong, note.where);
    gui.popFont();
    gui.sans(.regular, fonts.size.smaller);
    gui.drawText(list, .{ .x = min.x + px(9), .y = gui.textTop(min.y + px(29)) }, theme.text_muted, PlaceNote.how);
    gui.popFont();
}

/// Where a leg meets a thing on the screen: the middle of the mark it's in, and how far out from
/// it the mark reaches, or where it is where it's in no mark.
pub const End = struct {
    middle: Vec2,
    reach: f32 = 0,
    mark: ?usize = null,

    /// A number for the end: its mark's, or else its thing's, `thing_index`. The two never clash.
    pub fn key(end: End, thing_index: usize) usize {
        return if (end.mark) |mark| mark * 2 else thing_index * 2 + 1;
    }
};

pub const LegLook = struct {
    way: game.Way,
    starts: bool,
    color: Color,
};

/// A leg from `from` to `to`, clear of both marks: dots for a flight, dashes for a jump, an
/// arrowhead at its end, and a ring at its start where its route starts there. A leg to or from a
/// place the map doesn't show is a stub `stub_length` long that points the way, and one between
/// two such places shows nothing. Only the part inside `corners` is drawn. Returns the line drawn,
/// if any.
pub fn leg(list: *c.ImDrawList, from: End, to: End, look: LegLook, corners: [2]Vec2) ?[2]Vec2 {
    const from_shows = isInside(from.middle, corners);
    const to_shows = isInside(to.middle, corners);
    if (!from_shows and !to_shows) return null;
    const length = distanceTo(from.middle, to.middle);
    var start_at = from.reach + px(3);
    var end_at = length - to.reach - px(3);
    if (end_at - start_at < px(6)) return null;
    if (!to_shows) end_at = @min(end_at, start_at + px(stub_length));
    if (!from_shows) start_at = @max(start_at, end_at - px(stub_length));
    const way: Vec2 = .{ .x = (to.middle.x - from.middle.x) / length, .y = (to.middle.y - from.middle.y) / length };
    const start = along(from.middle, way, start_at);
    const end = along(from.middle, way, end_at);
    const shown = clipAlong(start, end, corners) orelse return null;
    const period = px(switch (look.way) {
        .fly => 5,
        .jump => 10,
    });
    var at = @floor(shown[0] / period) * period;
    while (at < shown[1]) : (at += period) {
        switch (look.way) {
            .fly => if (at >= shown[0]) c.ImDrawList_AddCircleFilled(list, along(start, way, at), px(1), look.color, 4),
            .jump => {
                const dash_start = @max(at, shown[0]);
                const dash_end = @min(at + px(6), shown[1]);
                if (dash_end > dash_start) c.ImDrawList_AddLineEx(list, along(start, way, dash_start), along(start, way, dash_end), look.color, px(1.5));
            },
        }
    }
    if (isInside(end, corners)) {
        const back = along(end, way, -px(7));
        const side: Vec2 = .{ .x = -way.y * px(3.5), .y = way.x * px(3.5) };
        c.ImDrawList_AddTriangleFilled(list, end, .{ .x = back.x + side.x, .y = back.y + side.y }, .{ .x = back.x - side.x, .y = back.y - side.y }, look.color);
    }
    if (look.starts and from_shows and isInside(start, corners)) gui.ring(list, along(start, way, px(3)), 3, 1.4, look.color);
    return .{ along(start, way, shown[0]), along(start, way, shown[1]) };
}

/// The legend's rows: where the ships start, and while the routes show, the legs ships fly and those
/// they jump.
const legend_rows = [_][]const u8{ "Start", "Flies", "Jumps" };
/// The legend's room for a row's sample, and its rows' height, in design pixels.
const legend_sample = 18;
const legend_row = 20;

/// Where the legend goes, in the map's top left corner `corner`.
pub fn legendBox(corner: Vec2, routes: bool) [2]Vec2 {
    const rows = legendRows(routes);
    gui.sans(.regular, fonts.size.smaller);
    defer gui.popFont();
    var widest: f32 = 0;
    for (rows) |text| widest = @max(widest, gui.textSize(text).x);
    const min: Vec2 = .{ .x = corner.x + px(10), .y = corner.y + px(10) };
    return .{ min, .{ .x = min.x + px(10 + 7 + 10 + legend_sample) + widest, .y = min.y + px(10 + legend_row * @as(f32, @floatFromInt(rows.len))) } };
}

fn legendRows(routes: bool) []const []const u8 {
    return legend_rows[0..if (routes) legend_rows.len else 1];
}

/// What the map's marks and lines are, in `box` (`legendBox`).
pub fn legend(list: *c.ImDrawList, box: [2]Vec2, routes: bool) void {
    const min, const max = box;
    gui.rect(list, min, max, theme.fade(theme.bar, 0.9), 4);
    gui.outline(list, min, max, theme.border_off, 4);
    gui.sans(.regular, fonts.size.smaller);
    defer gui.popFont();
    const sample = px(legend_sample);
    for (legendRows(routes), 0..) |text, index| {
        const middle = min.y + px(5) + px(legend_row) * (@as(f32, @floatFromInt(index)) + 0.5);
        const left = min.x + px(10);
        switch (index) {
            0 => thing(list, .{ .x = left + sample / 2, .y = middle }, .ship, null, fonts.size.icon_tiny, theme.text_menu),
            else => _ = leg(list, .{ .middle = .{ .x = left, .y = middle } }, .{ .middle = .{ .x = left + sample + px(4), .y = middle } }, .{
                .way = if (index == 1) .fly else .jump,
                .starts = false,
                .color = theme.text_menu,
            }, box),
        }
        gui.drawText(list, .{ .x = left + sample + px(7), .y = gui.textTop(middle) }, theme.text_menu, text);
    }
}

/// Where the scale goes, its left end at `corner` (`scaleBar`).
pub fn scaleBox(corner: Vec2, cell: f64, scale: f32) [2]Vec2 {
    gui.sans(.regular, 11);
    defer gui.popFont();
    const length = @as(f32, @floatCast(cell)) * scale;
    const top = corner.y - px(9) - c.ImGui_GetFontSize();
    return .{ .{ .x = corner.x, .y = top }, .{ .x = corner.x + @max(length, gui.textSize(distance(cell)).x), .y = corner.y } };
}

/// The scale, a cell of the grid long, its left end at `corner`, at `scale` pixels to the game's
/// unit.
pub fn scaleBar(list: *c.ImDrawList, corner: Vec2, cell: f64, scale: f32) void {
    const length = @as(f32, @floatCast(cell)) * scale;
    const bottom = corner.y;
    var points = [_]Vec2{ .{ .x = corner.x, .y = bottom - px(6) }, .{ .x = corner.x, .y = bottom }, .{ .x = corner.x + length, .y = bottom }, .{ .x = corner.x + length, .y = bottom - px(6) } };
    c.ImDrawList_AddPolyline(list, &points, points.len, theme.text_muted, px(1), 0);
    gui.sans(.regular, 11);
    defer gui.popFont();
    gui.drawText(list, .{ .x = corner.x, .y = bottom - px(9) - c.ImGui_GetFontSize() }, theme.text_muted, distance(cell));
}

/// Where the note that says which way the axes point goes, in the map's bottom right corner.
pub fn axesNoteBox(corners: [2]Vec2, text: []const u8) [2]Vec2 {
    gui.sans(.regular, 11);
    defer gui.popFont();
    const size = gui.textSize(text);
    const max: Vec2 = .{ .x = corners[1].x - px(12), .y = corners[1].y - px(12) };
    return .{ .{ .x = max.x - size.x, .y = max.y - c.ImGui_GetFontSize() }, max };
}

pub fn axesNote(list: *c.ImDrawList, box: [2]Vec2, text: []const u8) void {
    gui.sans(.regular, 11);
    defer gui.popFont();
    gui.drawText(list, box[0], theme.text_dim, text);
}

/// A note at the map's edge that points the way to something the map doesn't show, such as where
/// the player starts.
pub const Pill = struct {
    box: [2]Vec2,
    icon: Icon,
    color: Color,
    text: []const u8,

    /// The room before the icon, the icon's, and the room between it and the text and after the
    /// text, in design pixels.
    const inset = 9;
    const icon_room = 12;
    const gap = 6;

    /// How wide a pill with `text` is.
    pub fn width(text: []const u8) f32 {
        gui.sans(.regular, fonts.size.smaller);
        defer gui.popFont();
        return px(inset + icon_room + gap + inset) + gui.textSize(text).x;
    }
};

pub fn pill(list: *c.ImDrawList, shown: Pill) void {
    const min, const max = shown.box;
    const height = max.y - min.y;
    gui.rect(list, min, max, theme.fade(theme.bar, 0.9), height / 2 / px(1));
    gui.outline(list, min, max, theme.border_off, height / 2 / px(1));
    widgets.drawIconCentered(list, .{ .x = min.x + px(Pill.inset + Pill.icon_room / 2), .y = (min.y + max.y) / 2 }, shown.icon, fonts.size.icon_tiny, shown.color);
    gui.sans(.regular, fonts.size.smaller);
    defer gui.popFont();
    gui.drawText(list, .{ .x = min.x + px(Pill.inset + Pill.icon_room + Pill.gap), .y = gui.textTop((min.y + max.y) / 2) }, shown.color, shown.text);
}

/// The box `box`, `by` pixels larger each way.
pub fn grown(box: [2]Vec2, by: f32) [2]Vec2 {
    return .{ .{ .x = box[0].x - by, .y = box[0].y - by }, .{ .x = box[1].x + by, .y = box[1].y + by } };
}

/// A distance as the map writes it: `4k` for 4000, `1.5k`, `2.5M` for 2,500,000, or `500`.
pub fn distance(value: f64) []const u8 {
    const size = @abs(value);
    for ([_]struct { f64, []const u8 }{ .{ 1e6, "M" }, .{ 1e3, "k" } }) |unit| {
        if (size < unit[0]) continue;
        const count = value / unit[0];
        if (@round(count) == count or size >= 100 * unit[0]) return gui.print("{d}{s}", .{ @round(count), unit[1] });
        return gui.print("{d:.1}{s}", .{ count, unit[1] });
    }
    return gui.print("{d}", .{@round(value)});
}

test cellOf {
    // 54 pixels to a thousand: the cell is a thousand; zoomed out ten times, ten thousand.
    try std.testing.expectEqual(1000, cellOf(54.0 / 1000.0));
    try std.testing.expectEqual(10_000, cellOf(5.4 / 1000.0));
    try std.testing.expectEqual(2000, cellOf(30.0 / 1000.0));
}

test distance {
    try std.testing.expectEqualStrings("4k", distance(4000));
    try std.testing.expectEqualStrings("1.5k", distance(1500));
    try std.testing.expectEqualStrings("500", distance(500));
    try std.testing.expectEqualStrings("-2k", distance(-2000));
    try std.testing.expectEqualStrings("2.5M", distance(2_500_000));
    try std.testing.expectEqualStrings("150M", distance(150_000_000));
}

test clipAlong {
    const corners: [2]Vec2 = .{ .{ .x = 0, .y = 0 }, .{ .x = 100, .y = 100 } };
    // A line across the map from outside it on the left to outside it on the right shows inside
    // it, 50 to 150 pixels along.
    try std.testing.expectEqual([2]f32{ 50, 150 }, clipAlong(.{ .x = -50, .y = 50 }, .{ .x = 150, .y = 50 }, corners).?);
    // One wholly inside shows whole, and one beside the map not at all.
    try std.testing.expectEqual([2]f32{ 0, 10 }, clipAlong(.{ .x = 10, .y = 10 }, .{ .x = 20, .y = 10 }, corners).?);
    try std.testing.expectEqual(null, clipAlong(.{ .x = -50, .y = -10 }, .{ .x = 150, .y = -10 }, corners));
}

test Labels {
    defer gui.newFrame();
    const corners: [2]Vec2 = .{ .{ .x = 0, .y = 0 }, .{ .x = 200, .y = 200 } };
    // A leg leaves a mark at 100, 100 to the right.
    var labels: Labels = .{ .corners = corners, .lines = &.{.{ .{ .x = 110, .y = 100 }, .{ .x = 190, .y = 100 } }} };
    const size: Vec2 = .{ .x = 40, .y = 10 };
    const right: Vec2 = .{ .x = 110, .y = 95 };
    const left: Vec2 = .{ .x = 50, .y = 95 };
    // The name goes left, clear of the leg, though right comes first.
    try std.testing.expectEqual(left, labels.place(&.{ right, left }, size).?);
    // With the left taken, the next covers the leg rather than going without.
    try std.testing.expectEqual(right, labels.place(&.{ right, left }, size).?);
    // With both taken, the third goes without.
    try std.testing.expectEqual(null, labels.place(&.{ right, left }, size));
}

test grown {
    const box: [2]Vec2 = .{ .{ .x = 10, .y = 20 }, .{ .x = 30, .y = 40 } };
    try std.testing.expectEqual([2]Vec2{ .{ .x = 5, .y = 15 }, .{ .x = 35, .y = 45 } }, grown(box, 5));
}

test reachOf {
    const corners: [2]Vec2 = .{ .{ .x = 0, .y = 0 }, .{ .x = 300, .y = 400 } };
    // From inside the map, the nearest is its own place and the farthest the far corner.
    try std.testing.expectEqual([2]f32{ 0, 500 }, reachOf(.{ .x = 0, .y = 0 }, corners));
    // From 100 pixels left of the map's left edge.
    const reach = reachOf(.{ .x = -100, .y = 0 }, corners);
    try std.testing.expectEqual(100, reach[0]);
    try std.testing.expectApproxEqAbs(@sqrt(400.0 * 400.0 + 400.0 * 400.0), reach[1], 1e-3);
}
