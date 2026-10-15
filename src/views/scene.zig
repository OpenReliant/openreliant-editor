//! The Scene view: the mission's map, from above, from the side or from the front, with its ships
//! and markers where they start in their flight groups' colours, the ranges its triggers watch, its
//! curves, and the routes its script sends ships along (`game.Scene`). Things that would overlap on
//! the screen show as one mark, a cluster, which opens with a click, so that a mission spread over
//! areas far apart shows whole. The pointer pans and zooms the map. A ship or a marker dragged
//! moves where it starts, which rewrites its place in the source as one step of Undo, and what the
//! map selects is what the outline and the inspector show. `scene/drawing.zig` draws the map's
//! parts.

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("c");

const app_mod = @import("../app.zig");
const App = app_mod.App;
const commands = @import("../commands.zig");
const drawing = @import("scene/drawing.zig");
const Document = @import("../mission/document.zig").Document;
const game = @import("../game.zig");
const source_edit = @import("../mission/edit.zig");
const panels = @import("../panels.zig");
const ui = @import("../ui.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const plot = ui.plot;
const theme = ui.theme;
const widgets = ui.widgets;
const Color = theme.Color;
const Icon = ui.icons.Icon;
const Vec2 = gui.Vec2;
const px = gui.px;

/// How the map looks at the mission.
pub const Projection = enum {
    top,
    side,
    front,

    /// The map's place of `place`, in the game's coordinates, where Y points down: its horizontal
    /// coordinate, then its vertical one, which points up.
    pub fn project(projection: Projection, place: [3]f64) [2]f64 {
        return switch (projection) {
            .top => .{ place[0], place[2] },
            .side => .{ place[2], -place[1] },
            .front => .{ place[0], -place[1] },
        };
    }

    /// The game's place of `at` on the map, with the coordinate the map doesn't show kept from
    /// `kept`.
    pub fn unproject(projection: Projection, at: [2]f64, kept: [3]f64) [3]f64 {
        return switch (projection) {
            .top => .{ at[0], kept[1], at[1] },
            .side => .{ kept[0], -at[1], at[0] },
            .front => .{ at[0], -at[1], kept[2] },
        };
    }

    /// The game's coordinates the map shows, across and up, by their index in a place.
    fn axes(projection: Projection) [2]usize {
        return switch (projection) {
            .top => .{ 0, 2 },
            .side => .{ 2, 1 },
            .front => .{ 0, 1 },
        };
    }

    /// The note in the map's corner, which says which way its axes point.
    fn note(projection: Projection) []const u8 {
        return switch (projection) {
            .top => "X right · Z up",
            .side => "Z right · Y down",
            .front => "X right · Y down",
        };
    }

    fn label(projection: Projection) []const u8 {
        return switch (projection) {
            .top => "Top",
            .side => "Side",
            .front => "Front",
        };
    }
};

/// A record the map places, by its section and its place among the section's.
const Ref = struct {
    section: game.Section,
    index: usize,

    fn of(thing: game.Thing) Ref {
        return .{ .section = thing.section, .index = thing.index };
    }

    fn eql(ref: Ref, other: Ref) bool {
        return ref.section == other.section and ref.index == other.index;
    }
};

/// What the map keeps from one frame to the next.
const Map = struct {
    var projection: Projection = .top;
    var ranges: bool = true;
    var routes: bool = true;
    var curves: bool = false;
    /// Whether the axes fit the mission on the next frame: as the map first shows, as Fit asks,
    /// and as the projection changes.
    var fit: bool = true;
    /// The record the map keeps in its middle.
    var follow: ?Ref = null;
    /// The record being dragged, and where it is now.
    var dragging: ?struct { ref: Ref, place: [3]f64 } = null;
    /// What the axes showed last, whose size Follow keeps, and where the map was on the screen.
    var shown: ?plot.Rect = null;
    var area: ?[2]Vec2 = null;
    /// The mission the map last fitted, by its path: one opened anew shows whole.
    var fitted_for: u64 = 0;
    /// The places a click on a cluster opens on the next frame, and when the last one did, so that
    /// the second click of a double click doesn't fit the mission again.
    var zoom_to: ?[2][2]f64 = null;
    var zoomed_at: f64 = -1;
    /// The first thing of the cluster whose list is open.
    var listed: ?Ref = null;
    /// The place on the map under the pointer, for the status bar.
    var pointer: ?[2]f64 = null;
};

/// The pixels around a marker's middle that the pointer takes it by, and how far past a selected
/// marker its brackets reach.
const grab_radius = 11;
const bracket_reach = 5;
/// The marks' sizes, in design pixels: a ship's or a marker's, the player's, a camera point's and a
/// planet's (a cluster's is `drawing.cluster_size`).
const marker_size = 18;
const player_size = 20;
const camera_size = 8;
const scenery_size = 14;
/// How close on the screen, in pixels, things draw as one cluster.
const cluster_radius = 14;
/// The least the map shows across, in the game's units, as it fits the mission and as it opens a
/// cluster.
const least_fit = 4000;
const least_opened = 400;
/// How many of a cluster's things its tooltip names, and the least width, in design pixels, of the
/// list of things too close together to show apart.
const most_listed = 12;
const list_width = 200;
/// How much lighter than its group's colour the player's name is.
const player_tint = 0.47;
/// How much a notch of the wheel zooms, and how far in and out the map goes, in the game's
/// units across.
const zoom_step = 1.25;
const least_across = 200;
const most_across = 1e9;
/// The places a drag with Shift held snaps to, in the game's units.
const snap = 100;

pub fn draw(app: *App) void {
    const document = app.document orelse return;
    if (widgets.panelTabs(&.{
        .{ .label = "Map", .icon = .map, .icon_color = theme.accent, .on = true },
        .{ .label = document.file, .icon = .file_code, .dot = document.dirty() },
    })) |index| if (index == 1) app.run(.view_1);
    const scene = document.scene() catch return;
    toolbar(document, scene);
    map(app, document, scene);
}

/// The status bar's part while the map shows: the projection, and the place under the pointer.
pub fn status() []const u8 {
    const projection = Map.projection;
    const at = Map.pointer orelse return gui.print("Map · {s}", .{lower(projection.label())});
    const names = axisNames(projection);
    return gui.print("Map · {s} · {s} {s} · {s} {s}", .{ lower(projection.label()), names[0], drawing.distance(at[0]), names[1], drawing.distance(projectedValue(projection, at, 1)) });
}

/// The names of the game's coordinates across and up the map: `x` and `z` from above.
fn axisNames(projection: Projection) [2][]const u8 {
    const names = [_][]const u8{ "x", "y", "z" };
    const axes = projection.axes();
    return .{ names[axes[0]], names[axes[1]] };
}

/// The game's coordinate `which` of a place on the map, 0 across and 1 up: up is Y's opposite on
/// the side and the front.
fn projectedValue(projection: Projection, at: [2]f64, which: usize) f64 {
    if (which == 1 and projection != .top) return -at[1];
    return at[which];
}

fn lower(text: []const u8) []const u8 {
    return std.ascii.lowerString(gui.frameAllocator().alloc(u8, text.len) catch return text, text);
}

/// The map's toolbar: the projection, what it shows, the record it follows, and Fit.
fn toolbar(document: *Document, scene: game.Scene) void {
    const at = gui.cursor();
    const width = gui.available().x;
    const height = px(36);
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.toolbar, 0);
    gui.rect(list, .{ .x = at.x, .y = at.y + height - px(1) }, .{ .x = at.x + width, .y = at.y + height }, theme.divider, 0);
    const middle = at.y + height / 2;
    var x = at.x + px(10);

    gui.setCursor(.{ .x = x, .y = middle - px(13) });
    const projections = [_][]const u8{ Projection.top.label(), Projection.side.label(), Projection.front.label() };
    if (widgets.choice("projection", &projections, @backingInt(Map.projection), .{ .height = 26, .padding = 9, .font = fonts.size.small, .rounding = 4 })) |chosen| {
        if (chosen != @backingInt(Map.projection)) {
            Map.projection = @fromBackingInt(@as(u2, @intCast(chosen)));
            Map.fit = true;
        }
    }
    x = gui.lastItemRight() + px(8);
    gui.rect(list, .{ .x = x, .y = middle - px(9) }, .{ .x = x + px(1), .y = middle + px(9) }, theme.border, 0);
    x += px(9);
    const live_planned: widgets.Disabled = .{ .reason = gui.print("Planned · {f}", .{commands.plans.live_scene}) };
    const chips = [_]struct { []const u8, []const u8, Icon, ?*bool }{
        .{ "live", "Live", .radio, null },
        .{ "ranges", "Ranges", .circle_dashed, &Map.ranges },
        .{ "routes", "Routes", .route, &Map.routes },
        .{ "orders", "Orders", .arrow_up_right, null },
        .{ "curves", "Curves", .spline, &Map.curves },
    };
    for (chips) |chip| {
        gui.setCursor(.{ .x = x, .y = middle - px(12) });
        if (widgets.toggleChip(chip[0], chip[1], chip[2], if (chip[3]) |on| on.* else false, if (chip[3] == null) live_planned else null)) {
            if (chip[3]) |on| on.* = !on.*;
        }
        x = gui.lastItemRight() + px(6);
    }

    // At the end: Follow, and Fit.
    const fit_width = px(30);
    const follow_width = px(120);
    var right = at.x + width - px(10) - fit_width;
    gui.setCursor(.{ .x = right, .y = middle - px(13) });
    if (widgets.toolButton("fit", .{ .icon = .scan, .icon_only = true, .height = 26, .tooltip = "Zoom to fit the mission" })) Map.fit = true;
    right -= px(6) + follow_width;
    gui.setCursor(.{ .x = right, .y = middle - px(13) });
    followPick(document, scene, follow_width);
    gui.sans(.regular, fonts.size.small);
    const follow_label = "Follow";
    gui.drawText(list, .{ .x = right - px(6) - gui.textSize(follow_label).x, .y = gui.textTop(middle) }, theme.text_dim, follow_label);
    gui.popFont();
    gui.setCursor(.{ .x = at.x, .y = at.y + height });
}

/// Follow's list: none, or a ship, which the map then keeps in its middle.
fn followPick(document: *Document, scene: game.Scene, width: f32) void {
    const known = document.outline();
    const allocator = gui.frameAllocator();
    var choices: std.ArrayList(widgets.Choice) = .empty;
    var refs: std.ArrayList(?Ref) = .empty;
    choices.append(allocator, .{ .label = "none", .dim = true }) catch return;
    refs.append(allocator, null) catch return;
    var current: ?*const game.Record = null;
    for (scene.things) |thing| {
        if (thing.section != .ships) continue;
        const record = known.nth(thing.section, thing.index) orelse continue;
        choices.append(allocator, .{ .label = record.title, .mark = .{ .icon = .{ .icon = .navigation_2, .color = panels.groupColor(record.*) } } }) catch return;
        refs.append(allocator, Ref.of(thing)) catch return;
        if (Map.follow) |followed| if (followed.eql(Ref.of(thing))) {
            current = record;
        };
    }
    const frame: widgets.Frame = if (current) |record|
        .{ .label = record.title, .mark = .{ .icon = .{ .icon = .navigation_2, .color = panels.groupColor(record.*) } }, .width = width }
    else
        .{ .label = "none", .dim_label = true, .width = width };
    if (widgets.pick("follow", frame, choices.items)) |index| Map.follow = refs.items[index];
}

/// The map: the grid, the ranges and the curves, then the ships and markers, gathered into one
/// mark where they would overlap, each named where its name has room, and over them the legend,
/// the scale and the axes' note. The pointer pans the map and zooms it with the wheel, selects and
/// drags a thing, and opens a cluster with a click; a double click fits the mission.
fn map(app: *App, document: *Document, scene: game.Scene) void {
    const size = gui.available();
    if (size.x < 1 or size.y < 1) return;
    const known = document.outline();
    const projection = Map.projection;
    const opened = std.hash.Wyhash.hash(0, document.path);
    if (Map.fitted_for != opened) {
        Map.fitted_for = opened;
        Map.fit = true;
    }
    var wanted: ?plot.Rect = if (Map.fit) fitted(scene, projection, size) else if (Map.zoom_to) |bounds| framed(bounds, size, least_opened) else wheeled();
    Map.fit = false;
    Map.zoom_to = null;
    if (Map.follow) |followed| if (thingOf(scene, followed)) |thing| if (wanted orelse Map.shown) |around| {
        wanted = centredOn(around, projection.project(placeOf(thing)));
    };
    if (!plot.begin("##map", size, wanted)) return;
    defer plot.end();
    Map.shown = plot.limits();
    Map.area = plot.area();
    const list = plot.drawList();
    defer plot.popClip();
    const corners = Map.area.?;
    const shown = Map.shown.?;
    const scale = (corners[1].x - corners[0].x) / @as(f32, @floatCast(shown.x_max - shown.x_min));
    const cell = drawing.cellOf(scale);
    drawing.grid(list, shown, cell);
    const rings: []const Ring = if (Map.ranges) drawRanges(list, scene, projection, scale, corners) else &.{};
    if (Map.curves) for (scene.curves) |path| drawCurve(list, projection, path);

    const inspected = app.inspected();
    const selected: ?Ref = if (inspected) |record| refOf(scene, record.*) else null;
    const gathered = gather(scene, projection, selected) catch return;
    const lines: []const [2]Vec2 = if (Map.routes) drawRoutes(list, scene, gathered, projection, if (inspected) |record| record.* else null, corners) else &.{};
    const pointer = pointerOnMap();
    var hovered: ?usize = null;
    for (gathered.marks, 0..) |*mark, which| {
        const thing = scene.things[mark.first];
        const record = known.nth(thing.section, thing.index) orelse continue;
        const color = panels.groupColor(record.*);
        if (mark.count > 1) {
            drawing.cluster(list, mark.middle, mark.count, color);
            if (pointer) |at| if (drawing.isInside(at, mark.box())) {
                hovered = which;
            };
            continue;
        }
        const ref = Ref.of(thing);
        const dragged = if (Map.dragging) |drag| drag.ref.eql(ref) else false;
        var at = projection.project(placeOf(thing));
        const drag = plot.dragPoint(mark.first, &at, px(grab_radius));
        if (drag.hovered or drag.held) hovered = which;
        if (drag.clicked) app.select(record.*);
        if (drag.held) {
            if (c.ImGui_GetIO().*.KeyShift) at = .{ @round(at[0] / snap) * snap, @round(at[1] / snap) * snap };
            Map.dragging = .{ .ref = ref, .place = projection.unproject(at, thing.place) };
        } else if (dragged) {
            // Let go: the place goes into the source, where it moved.
            const moved = Map.dragging.?.place;
            Map.dragging = null;
            if (!std.meta.eql(moved, thing.place)) moveTo(document, scene, record.*, moved);
        }
        mark.middle = plot.toPixels(at);
        if (drag.hovered or drag.held) gui.dot(list, mark.middle, mark.size / 2 + 6, theme.fade(theme.text, 0.08));
        drawing.thing(list, mark.middle, thing.kind, if (thing.heading) |heading| projection.project(heading) else null, mark.size, color);
    }

    // The notes over the map, which the names keep off: the legend, the scale, the axes' note, the
    // player's start where the map doesn't show it, and the selection's brackets and place.
    const routes_shown = Map.routes and scene.routes.len > 0;
    const legend_box = drawing.legendBox(corners[0], routes_shown);
    const scale_at: Vec2 = .{ .x = corners[0].x + px(12), .y = corners[1].y - px(12) };
    const note = projection.note();
    const note_box = drawing.axesNoteBox(corners, note);
    const start: ?drawing.Pill = if (scene.player) |player| startPill(corners, shown, projection, scene.things[player], known) else null;
    const chosen: ?Mark = for (gathered.marks) |mark| {
        if (mark.count == 1 and selected != null and selected.?.eql(Ref.of(scene.things[mark.first]))) break mark;
    } else null;
    const place_note: ?drawing.PlaceNote = if (chosen) |mark| placeNoteOf(scene, projection, mark) else null;
    var labels: drawing.Labels = .{ .corners = corners, .lines = lines };
    for (gathered.marks) |mark| labels.take(mark.box());
    for ([_]?[2]Vec2{
        legend_box,
        drawing.scaleBox(scale_at, cell, scale),
        note_box,
        if (start) |pill| pill.box else null,
        if (chosen) |mark| drawing.grown(mark.box(), px(bracket_reach)) else null,
        if (place_note) |placed| placed.box else null,
    }) |taken| if (taken) |box| labels.take(box);
    const named = nameMarks(list, &labels, scene, known, gathered.marks);
    for (rings) |ring| nameRing(list, &labels, ring);
    if (chosen) |mark| {
        drawing.brackets(list, mark.middle, px(mark.size) / 2 + px(bracket_reach));
        drawing.placeNote(list, place_note.?);
    }
    if (hovered) |which| {
        const mark = gathered.marks[which];
        if (mark.count > 1) {
            c.ImGui_SetMouseCursor(c.ImGuiMouseCursor_Hand);
            gui.tooltipNow(memberNames(scene, known, gathered, which, size));
            if (isClick(mark.middle, px(drawing.cluster_size) / 2)) openMark(scene, mark, size);
        } else if (!named[which]) {
            if (known.nth(scene.things[mark.first].section, scene.things[mark.first].index)) |record| gui.tooltipNow(record.title);
        }
    }
    listMembers(app, scene, known, gathered);
    // A click on an empty part of the map clears the selection.
    if (hovered == null) if (pointer) |at| if (isClick(at, px(4))) {
        app.selection = null;
    };
    // A double click away from the things fits the mission again.
    const settled = c.ImGui_GetTime() - Map.zoomed_at > c.ImGui_GetIO().*.MouseDoubleClickTime;
    if (pointer != null and hovered == null and settled and c.ImGui_IsMouseDoubleClicked(0)) Map.fit = true;

    drawing.legend(list, legend_box, routes_shown);
    drawing.scaleBar(list, scale_at, cell, scale);
    drawing.axesNote(list, note_box, note);
    if (start) |pill| drawing.pill(list, pill);
    Map.pointer = if (pointer) |at| plot.fromPixels(at) else null;
}

/// Where the pointer is, while it's over the map and not over something in front of it.
fn pointerOnMap() ?Vec2 {
    if (!c.ImGui_IsWindowHovered(0)) return null;
    const mouse = c.ImGui_GetMousePos();
    return if (drawing.isInside(mouse, Map.area orelse return null)) mouse else null;
}

/// Whether the left button has just been let go after a press within `radius` of `middle`, with
/// no drag between.
fn isClick(middle: Vec2, radius: f32) bool {
    if (!c.ImGui_IsMouseReleased(0)) return false;
    const io = c.ImGui_GetIO();
    const delta = c.ImGui_GetMouseDragDelta(0, -1);
    return delta.x == 0 and delta.y == 0 and drawing.distanceTo(io.*.MouseClickedPos[0], middle) <= radius;
}

/// Whether zooming in to a cluster's things, on a map `size` big, shows them apart.
fn opensApart(mark: Mark, size: Vec2) bool {
    const opened = framed(.{ mark.low, mark.high }, size, least_opened);
    const scale = size.x / (opened.x_max - opened.x_min);
    return @max(mark.high[0] - mark.low[0], mark.high[1] - mark.low[1]) * scale >= px(cluster_radius);
}

/// Opens a cluster: zooms in to its things where that shows them apart, or lists them where they
/// lie too close together.
fn openMark(scene: game.Scene, mark: Mark, size: Vec2) void {
    if (opensApart(mark, size)) {
        Map.zoom_to = .{ mark.low, mark.high };
        Map.zoomed_at = c.ImGui_GetTime();
    } else {
        Map.listed = Ref.of(scene.things[mark.first]);
        _ = c.ImGui_OpenPopup("members", 0);
    }
}

/// The list of a cluster's things that lie too close together to show apart. A click on one
/// selects it.
fn listMembers(app: *App, scene: game.Scene, known: game.Outline, gathered: Gathered) void {
    if (!c.ImGui_BeginPopup("members", c.ImGuiWindowFlags_NoMove)) return;
    defer c.ImGui_EndPopup();
    const listed = Map.listed orelse return c.ImGui_CloseCurrentPopup();
    const which = for (gathered.marks, 0..) |mark, index| {
        if (Ref.of(scene.things[mark.first]).eql(listed)) break index;
    } else return c.ImGui_CloseCurrentPopup();
    c.ImGui_Dummy(.{ .x = px(list_width), .y = 0 });
    for (scene.things, gathered.owners, 0..) |thing, owner, index| {
        if (owner != which) continue;
        const record = known.nth(thing.section, thing.index) orelse continue;
        gui.pushIdInt(index);
        defer gui.popId();
        const mark: widgets.RowMark = .{ .icon = .{ .icon = kindIcon(thing.kind), .color = panels.groupColor(record.*) } };
        if (widgets.choiceRow(.{ .label = record.title, .mark = mark })) {
            app.select(record.*);
            c.ImGui_CloseCurrentPopup();
        }
    }
}

fn kindIcon(kind: game.ThingKind) Icon {
    return switch (kind) {
        .ship => .navigation_2,
        .marker => .diamond,
        .camera => .circle_dot,
        .scenery => .circle,
    };
}

/// The names of a cluster's things, for its tooltip: the first `most_listed`, how many
/// more, and what a click does on a map `size` big.
fn memberNames(scene: game.Scene, known: game.Outline, gathered: Gathered, which: usize, size: Vec2) []const u8 {
    var text: std.Io.Writer.Allocating = .init(gui.frameAllocator());
    const writer = &text.writer;
    var count: usize = 0;
    for (scene.things, gathered.owners) |thing, owner| {
        if (owner != which) continue;
        count += 1;
        if (count > most_listed) continue;
        const record = known.nth(thing.section, thing.index) orelse continue;
        writer.print("{s}{s}", .{ if (count > 1) "\n" else "", record.title }) catch return "";
    }
    if (count > most_listed) writer.print("\n{d} more", .{count - most_listed}) catch return "";
    writer.writeAll(if (opensApart(gathered.marks[which], size)) "\nClick to zoom in" else "\nClick to choose one") catch return "";
    return text.written();
}

/// What the map draws for a thing, or for several that would overlap on the screen.
const Mark = struct {
    /// The thing it's for, the most important where it's for several, by its place in the scene.
    first: usize,
    count: usize,
    middle: Vec2,
    /// The map's places its things span, which a click on a cluster opens.
    low: [2]f64,
    high: [2]f64,
    /// Its marker's height and width, in design pixels: a cluster is wider for a count of
    /// three figures.
    size: f32,
    width: f32,

    /// Where its marker covers the map.
    fn box(mark: Mark) [2]Vec2 {
        const half: Vec2 = .{ .x = px(mark.width) / 2, .y = px(mark.size) / 2 };
        return .{ .{ .x = mark.middle.x - half.x, .y = mark.middle.y - half.y }, .{ .x = mark.middle.x + half.x, .y = mark.middle.y + half.y } };
    }
};

/// The map's marks, and the mark each thing of the scene is in, by its place among the marks; a
/// camera point, while the curves are hidden, is in none.
const Gathered = struct {
    marks: []Mark,
    owners: []const usize,
};

/// The things the map shows as marks, the most important first: the selected thing, the player,
/// the ships, the markers, the camera's points where the curves show, and the scenery. A thing
/// within `cluster_radius` of a mark on the screen joins it, but for the selected thing and the
/// one being dragged, which stay apart.
fn gather(scene: game.Scene, projection: Projection, selected: ?Ref) Allocator.Error!Gathered {
    const allocator = gui.frameAllocator();
    var order: std.ArrayList(usize) = .empty;
    for (scene.things, 0..) |thing, index| {
        if (thing.kind == .camera and !Map.curves) continue;
        try order.append(allocator, index);
    }
    const Order = struct {
        scene: game.Scene,
        selected: ?Ref,
        fn lessThan(context: @This(), a: usize, b: usize) bool {
            const first = importance(context.scene, a, context.selected);
            const second = importance(context.scene, b, context.selected);
            return if (first != second) first < second else a < b;
        }
    };
    std.mem.sort(usize, order.items, Order{ .scene = scene, .selected = selected }, Order.lessThan);
    const owners = try allocator.alloc(usize, scene.things.len);
    @memset(owners, std.math.maxInt(usize));
    var marks: std.ArrayList(Mark) = .empty;
    things: for (order.items) |index| {
        const thing = scene.things[index];
        const at = projection.project(placeOf(thing));
        const middle = plot.toPixels(at);
        if (!isApart(Ref.of(thing), selected)) for (marks.items, 0..) |*mark, which| {
            if (isApart(Ref.of(scene.things[mark.first]), selected)) continue;
            if (drawing.distanceTo(mark.middle, middle) > px(cluster_radius)) continue;
            mark.count += 1;
            mark.size = drawing.cluster_size;
            mark.width = drawing.clusterWidth(mark.count);
            const point: @Vector(2, f64) = at;
            const low: @Vector(2, f64) = mark.low;
            const high: @Vector(2, f64) = mark.high;
            mark.low = @min(low, point);
            mark.high = @max(high, point);
            owners[index] = which;
            continue :things;
        };
        owners[index] = marks.items.len;
        const size = sizeOf(scene, index);
        try marks.append(allocator, .{ .first = index, .count = 1, .middle = middle, .low = at, .high = at, .size = size, .width = size });
    }
    return .{ .marks = marks.items, .owners = owners };
}

/// How important the thing at `index` in the scene is to the map: 0 is the most important.
fn importance(scene: game.Scene, index: usize, selected: ?Ref) u8 {
    const thing = scene.things[index];
    if (isApart(Ref.of(thing), selected)) return 0;
    if (scene.player == index) return 1;
    return switch (thing.kind) {
        .ship => 2,
        .marker => 3,
        .camera => 4,
        .scenery => 5,
    };
}

/// Whether a thing stays apart from the others: it's selected, or being dragged.
fn isApart(ref: Ref, selected: ?Ref) bool {
    if (selected) |chosen| if (chosen.eql(ref)) return true;
    if (Map.dragging) |drag| if (drag.ref.eql(ref)) return true;
    return false;
}

fn sizeOf(scene: game.Scene, index: usize) f32 {
    if (scene.player == index) return player_size;
    return switch (scene.things[index].kind) {
        .ship, .marker => marker_size,
        .camera => camera_size,
        .scenery => scenery_size,
    };
}

/// The scene's thing for `record`, where the map places it.
fn refOf(scene: game.Scene, record: game.Record) ?Ref {
    const ref: Ref = .{ .section = record.section, .index = record.index };
    return if (thingOf(scene, ref) != null) ref else null;
}

/// The axes the wheel asks for, zoomed by `zoom_step` a notch around the place under the pointer,
/// where the pointer is over the map; null otherwise.
fn wheeled() ?plot.Rect {
    const wheel = c.ImGui_GetIO().*.MouseWheel;
    if (wheel == 0) return null;
    const mouse = pointerOnMap() orelse return null;
    const area = Map.area.?;
    const last = Map.shown orelse return null;
    const across: f64 = (mouse.x - area[0].x) / (area[1].x - area[0].x);
    const down: f64 = (mouse.y - area[0].y) / (area[1].y - area[0].y);
    const at: [2]f64 = .{ last.x_min + across * (last.x_max - last.x_min), last.y_max - down * (last.y_max - last.y_min) };
    const width = last.x_max - last.x_min;
    const factor = std.math.clamp(std.math.pow(f64, zoom_step, -wheel), least_across / width, most_across / width);
    return .{
        .x_min = at[0] + (last.x_min - at[0]) * factor,
        .x_max = at[0] + (last.x_max - at[0]) * factor,
        .y_min = at[1] + (last.y_min - at[1]) * factor,
        .y_max = at[1] + (last.y_max - at[1]) * factor,
    };
}

/// Puts where `record` starts at `place`, in its table's place field, as one step of Undo, once
/// the frame is drawn.
fn moveTo(document: *Document, scene: game.Scene, record: game.Record, place: [3]f64) void {
    const value = source_edit.vector(gui.frameAllocator(), &place) catch return;
    document.queue(.{ .edit = .{ .section = record.section, .index = record.index, .edit = .{ .field = .{ .name = scene.place_field, .value = value } } } });
}

/// The scene's thing for a record.
fn thingOf(scene: game.Scene, ref: Ref) ?game.Thing {
    return scene.things[indexOf(scene, ref) orelse return null];
}

/// Where the scene lists a record's thing.
fn indexOf(scene: game.Scene, ref: Ref) ?usize {
    for (scene.things, 0..) |thing, index| if (Ref.of(thing).eql(ref)) return index;
    return null;
}

/// Where a thing is now: where a drag has it, or where it starts.
fn placeOf(thing: game.Thing) [3]f64 {
    if (Map.dragging) |drag| if (drag.ref.eql(Ref.of(thing))) return drag.place;
    return thing.place;
}

/// The axes that show the mission: its ships and markers, and the camera's points where the
/// curves show, but not its scenery, which lies far off; every thing where that's all it has.
fn fitted(scene: game.Scene, projection: Projection, size: Vec2) plot.Rect {
    var low: @Vector(2, f64) = @splat(std.math.inf(f64));
    var high: @Vector(2, f64) = @splat(-std.math.inf(f64));
    for ([_]bool{ false, true }) |everything| {
        for (scene.things) |thing| {
            if (!everything and (thing.kind == .scenery or (thing.kind == .camera and !Map.curves))) continue;
            const at: @Vector(2, f64) = projection.project(thing.place);
            low = @min(low, at);
            high = @max(high, at);
        }
        if (low[0] <= high[0]) break;
    }
    if (low[0] > high[0]) return framed(.{ @splat(0), @splat(0) }, size, least_fit);
    return framed(.{ low, high }, size, least_fit);
}

/// The axes that show `bounds`, with a margin of a tenth each side and at least `least` across and
/// up, at the map's aspect.
fn framed(bounds: [2][2]f64, size: Vec2, least: f64) plot.Rect {
    const across = @max(bounds[1][0] - bounds[0][0], least) * 1.2;
    const up = @max(bounds[1][1] - bounds[0][1], least) * 1.2;
    const middle: [2]f64 = .{ (bounds[0][0] + bounds[1][0]) / 2, (bounds[0][1] + bounds[1][1]) / 2 };
    // Equal axes: the side that's too short for the map's shape grows.
    const aspect: f64 = size.x / size.y;
    const width = @max(across, up * aspect);
    const height = width / aspect;
    return .{ .x_min = middle[0] - width / 2, .x_max = middle[0] + width / 2, .y_min = middle[1] - height / 2, .y_max = middle[1] + height / 2 };
}

/// `last` moved to have `middle` in its middle.
fn centredOn(last: plot.Rect, middle: [2]f64) plot.Rect {
    const half_across = (last.x_max - last.x_min) / 2;
    const half_up = (last.y_max - last.y_min) / 2;
    return .{ .x_min = middle[0] - half_across, .x_max = middle[0] + half_across, .y_min = middle[1] - half_up, .y_max = middle[1] + half_up };
}

/// Each mark's name, the most important first: right of its marker, else left, below or above,
/// wherever it covers no mark and no name placed before it. Returns which marks have their name
/// shown; the others show it as the pointer comes over them.
fn nameMarks(list: *c.ImDrawList, labels: *drawing.Labels, scene: game.Scene, known: game.Outline, marks: []const Mark) []const bool {
    const named = gui.frameAllocator().alloc(bool, marks.len) catch return &.{};
    @memset(named, false);
    gui.sans(.regular, fonts.size.smaller);
    defer gui.popFont();
    const height = c.ImGui_GetFontSize();
    for (marks, named) |mark, *shown| {
        const thing = scene.things[mark.first];
        const record = known.nth(thing.section, thing.index) orelse continue;
        const text = if (mark.count > 1) gui.print("{s} +{d}", .{ record.title, mark.count - 1 }) else record.title;
        const color = if (scene.player == mark.first)
            theme.lighten(panels.groupColor(record.*), player_tint)
        else switch (thing.kind) {
            .ship, .marker => theme.text,
            .camera, .scenery => theme.text_dim,
        };
        const width = gui.textSize(text).x;
        const box = mark.box();
        const gap = px(5);
        const spots = [_]Vec2{
            .{ .x = box[1].x + gap, .y = mark.middle.y - height / 2 },
            .{ .x = box[0].x - gap - width, .y = mark.middle.y - height / 2 },
            .{ .x = mark.middle.x - width / 2, .y = box[1].y + px(2) },
            .{ .x = mark.middle.x - width / 2, .y = box[0].y - px(2) - height },
        };
        const at = labels.place(&spots, .{ .x = width, .y = height }) orelse continue;
        drawing.label(list, at, .{ .x = width, .y = height }, color, text);
        shown.* = true;
    }
    return named;
}

/// A ring the map draws, for its label.
const Ring = struct {
    middle: Vec2,
    radius: f32,
    range: game.Range,
};

/// The ranges, each ring once however many triggers watch it: a trigger's as a dashed ring with a
/// faint fill, a hint's as a dotted one. Returns the rings drawn, for their labels.
fn drawRanges(list: *c.ImDrawList, scene: game.Scene, projection: Projection, scale: f32, corners: [2]Vec2) []const Ring {
    var rings: std.ArrayList(Ring) = .empty;
    ranges: for (scene.ranges, 0..) |range, index| {
        for (scene.ranges[0..index]) |before| {
            if (before.section == range.section and before.index == range.index and before.radius == range.radius and before.style == range.style) continue :ranges;
        }
        const subject = thingOf(scene, .{ .section = range.section, .index = range.index }) orelse continue;
        const middle = plot.toPixels(projection.project(placeOf(subject)));
        const radius = @as(f32, @floatCast(range.radius)) * scale;
        const reach = drawing.reachOf(middle, corners);
        // A ring smaller than a few pixels, or one the map lies outside, shows nothing; one the
        // map lies inside shows only its fill.
        if (radius < px(4) or radius < reach[0]) continue;
        const shows = radius <= reach[1];
        switch (range.style) {
            .trigger => {
                const fill = theme.fade(theme.accent, 0.035);
                if (shows) c.ImDrawList_AddCircleFilled(list, middle, radius, fill, 0) else gui.rect(list, corners[0], corners[1], fill, 0);
                if (shows) drawing.dashedCircle(list, middle, radius, theme.fade(theme.accent, 0.55), 5, 4, corners);
            },
            .hint => if (shows) drawing.dashedCircle(list, middle, radius, theme.fade(theme.text_menu, 0.3), 1.5, 3, corners),
        }
        if (shows) rings.append(gui.frameAllocator(), .{ .middle = middle, .radius = radius, .range = range }) catch break;
    }
    return rings.items;
}

/// A ring's label, inside it at its top or else at its bottom, where the ring is wide enough to
/// hold it and the label covers no mark and no name.
fn nameRing(list: *c.ImDrawList, labels: *drawing.Labels, ring: Ring) void {
    gui.sans(.regular, 11);
    defer gui.popFont();
    const text = gui.print("{s} · {s}", .{ ring.range.label, drawing.distance(ring.range.radius) });
    const size = gui.textSize(text);
    if (size.x + px(40) > ring.radius * 2) return;
    const left = ring.middle.x - size.x / 2;
    const spots = [_]Vec2{
        .{ .x = left, .y = ring.middle.y - ring.radius + px(6) },
        .{ .x = left, .y = ring.middle.y + ring.radius - px(6) - size.y },
    };
    const at = labels.place(&spots, size) orelse return;
    const color = switch (ring.range.style) {
        .trigger => theme.range_text,
        .hint => theme.text_muted,
    };
    drawing.label(list, at, size, color, text);
}

fn drawCurve(list: *c.ImDrawList, projection: Projection, path: []const [3]f64) void {
    for (path) |place| c.ImDrawList_PathLineTo(list, plot.toPixels(projection.project(place)));
    c.ImDrawList_PathStroke(list, theme.curve, px(1.4), 0);
}

/// The routes, under the marks: each leg from mark to mark, dotted where the ship flies and dashed
/// where it jumps, in its group's colour, with an arrowhead where it goes and a ring where its
/// route starts. A leg within one cluster shows nothing, and a leg several routes share shows once.
/// With a ship, a group or a marker selected, the routes it's on show brighter and the others
/// faint. Returns the legs drawn, as lines on the screen.
fn drawRoutes(list: *c.ImDrawList, scene: game.Scene, gathered: Gathered, projection: Projection, inspected: ?game.Record, corners: [2]Vec2) []const [2]Vec2 {
    var lines: std.ArrayList([2]Vec2) = .empty;
    const selected: ?usize = if (inspected) |record| indexOf(scene, .{ .section = record.section, .index = record.index }) else null;
    // A ship's group, or a group itself: the routes of the group show too.
    const selected_group: ?usize = if (inspected) |record| switch (record.section) {
        .ships, .flight_groups => record.group,
        else => null,
    } else null;
    // The selection's routes stand out where it's on any; otherwise every route shows alike.
    const focused = isOnAnyRoute(scene.routes, selected, selected_group);
    const Drawn = struct { from: usize, to: usize, way: game.Way, color: Color };
    var drawn: std.AutoHashMapUnmanaged(Drawn, void) = .empty;
    for (scene.routes) |route| {
        const base = if (route.group) |group| theme.groups[group % theme.groups.len] else theme.text_dim;
        for (route.legs) |leg| {
            const from = endOf(scene, gathered, projection, leg.from);
            const to = endOf(scene, gathered, projection, leg.to);
            if (from.mark != null and from.mark == to.mark) continue;
            const focus: f32 = if (!focused) 0.75 else if (isOnRoute(route, leg, selected, selected_group)) 1 else 0.3;
            const color = theme.fade(base, focus);
            const key: Drawn = .{ .from = from.key(leg.from), .to = to.key(leg.to), .way = leg.way, .color = color };
            const seen = drawn.getOrPut(gui.frameAllocator(), key) catch return lines.items;
            if (seen.found_existing) continue;
            const line = drawing.leg(list, from, to, .{ .way = leg.way, .starts = leg.starts, .color = color }, corners) orelse continue;
            lines.append(gui.frameAllocator(), line) catch return lines.items;
        }
    }
    return lines.items;
}

/// Whether any leg of `routes` is on the selection (`isOnRoute`).
fn isOnAnyRoute(routes: []const game.Route, selected: ?usize, selected_group: ?usize) bool {
    for (routes) |route| for (route.legs) |leg| if (isOnRoute(route, leg, selected, selected_group)) return true;
    return false;
}

/// Whether a leg of `route` is on the selection: the selected ship's route, its group's, or a leg
/// to or from the selected marker.
fn isOnRoute(route: game.Route, leg: game.Leg, selected: ?usize, selected_group: ?usize) bool {
    if (selected) |thing| {
        if (route.ship == thing or leg.from == thing or leg.to == thing) return true;
    }
    if (route.ship == null) if (route.group) |group| if (selected_group == group) return true;
    return false;
}

/// Where a leg meets the thing at `thing` in the scene: the mark it's in, or where it is.
fn endOf(scene: game.Scene, gathered: Gathered, projection: Projection, thing: usize) drawing.End {
    const owner = gathered.owners[thing];
    if (owner < gathered.marks.len) {
        const mark = gathered.marks[owner];
        return .{ .middle = mark.middle, .reach = px(@max(mark.size, mark.width)) / 2, .mark = owner };
    }
    return .{ .middle = plot.toPixels(projection.project(placeOf(scene.things[thing]))) };
}

/// The note at the map's edge that points the way to where the player starts, where the map
/// doesn't show it, with how far that is from the map's middle.
fn startPill(corners: [2]Vec2, shown: plot.Rect, projection: Projection, player: game.Thing, known: game.Outline) ?drawing.Pill {
    const record = known.nth(player.section, player.index) orelse return null;
    const at = projection.project(placeOf(player));
    if (at[0] >= shown.x_min and at[0] <= shown.x_max and at[1] >= shown.y_min and at[1] <= shown.y_max) return null;
    const middle: [2]f64 = .{ (shown.x_min + shown.x_max) / 2, (shown.y_min + shown.y_max) / 2 };
    const across = at[0] - middle[0];
    const up = at[1] - middle[1];
    const far = @sqrt(across * across + up * up);
    // The edge the player is beyond, by which way it is most.
    const ratio = (shown.x_max - shown.x_min) / (shown.y_max - shown.y_min);
    const sideways = @abs(across) > @abs(up) * ratio;
    const text = gui.print("{s} start · {s}", .{ record.title, drawing.distance(far) });
    const width = drawing.Pill.width(text);
    const height = px(24);
    const centre: Vec2 = .{ .x = (corners[0].x + corners[1].x) / 2, .y = (corners[0].y + corners[1].y) / 2 };
    const min: Vec2 = if (sideways)
        .{ .x = if (across > 0) corners[1].x - px(10) - width else corners[0].x + px(10), .y = centre.y - height / 2 }
    else
        .{ .x = centre.x - width / 2, .y = if (up > 0) corners[0].y + px(10) else corners[1].y - px(10) - height };
    return .{
        .box = .{ min, .{ .x = min.x + width, .y = min.y + height } },
        .icon = if (sideways) (if (across > 0) .arrow_right else .arrow_left) else (if (up > 0) .arrow_up else .arrow_down),
        .color = theme.lighten(panels.groupColor(record.*), player_tint),
        .text = text,
    };
}

/// The note by the selected mark: where its thing is on the map's axes.
fn placeNoteOf(scene: game.Scene, projection: Projection, mark: Mark) drawing.PlaceNote {
    const place = placeOf(scene.things[mark.first]);
    const axes = projection.axes();
    return .at(mark.middle, axisNames(projection), .{ place[axes[0]], place[axes[1]] });
}

test isOnAnyRoute {
    const legs = [_]game.Leg{.{ .from = 0, .to = 1, .way = .fly }};
    const routes = [_]game.Route{
        .{ .ship = 2, .group = 0, .legs = &legs },
        .{ .ship = null, .group = 3, .legs = &legs },
    };
    // With nothing selected, or a record no route takes, the routes show alike.
    try std.testing.expect(!isOnAnyRoute(&routes, null, null));
    try std.testing.expect(!isOnAnyRoute(&routes, 5, 4));
    // A route's ship, a marker a route passes, or a group with a route of its own.
    try std.testing.expect(isOnAnyRoute(&routes, 2, null));
    try std.testing.expect(isOnAnyRoute(&routes, 1, null));
    try std.testing.expect(isOnAnyRoute(&routes, null, 3));
}

test Projection {
    const place: [3]f64 = .{ 1, 2, 3 };
    for (std.enums.values(Projection)) |projection| {
        const at = projection.project(place);
        try std.testing.expectEqual(place, projection.unproject(at, place));
    }
    // From above, X runs across and Z up; from the side and the front, up is Y's opposite.
    try std.testing.expectEqual([2]f64{ 1, 3 }, Projection.top.project(place));
    try std.testing.expectEqual([2]f64{ 3, -2 }, Projection.side.project(place));
}
