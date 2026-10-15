//! The workspace's dockable panels. Each is an ImGui window the dock space holds; the source panel
//! is `views/script.zig`. The debugging panels show the game's script while the editor is linked
//! (`debug/session.zig`), and what they will hold until then.

const std = @import("std");
const c = @import("c");

const openreliant = @import("openreliant");
const State = openreliant.engine.link.State;

const app_mod = @import("app.zig");
const App = app_mod.App;
const Panel = app_mod.Panel;
const commands = @import("commands.zig");
const game = @import("game.zig");
const Document = @import("mission/document.zig").Document;
const forms = @import("forms.zig");
const script_view = @import("views/script.zig");
const ui = @import("ui.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const Icon = ui.icons.Icon;
const theme = ui.theme;
const widgets = ui.widgets;
const px = gui.px;

pub fn draw(app: *App) void {
    for (std.enums.values(Panel)) |panel| {
        if (!app.open_panels.get(panel)) continue;
        if (!begin(app, panel)) {
            c.ImGui_End();
            continue;
        }
        defer c.ImGui_End();
        defer frame(panel);
        switch (panel) {
            .mission => outline(app),
            .find => find(app),
            .source => script_view.draw(app),
            .threads => threads(app),
            .breakpoints => breakpoints(app),
            .output => output(app),
            .problems => problems(app),
            .variables => variables(app),
            .watch => watch(),
            .inspector => inspector(app),
            .reference => reference(app),
            .live_scene => liveScene(),
        }
    }
    addMenu(app);
}

/// The menu of records to add, next to the pointer, as + and Add a record open it, or Declare with
/// the name it declares.
fn addMenu(app: *App) void {
    if (app.add_menu) {
        _ = c.ImGui_OpenPopup("add record", 0);
        app.add_menu = false;
    }
    c.ImGui_SetNextWindowSizeConstraints(.{ .x = px(200), .y = 0 }, .{ .x = px(320), .y = px(400) }, null, null);
    if (!c.ImGui_BeginPopup("add record", 0)) return;
    defer c.ImGui_EndPopup();
    const name = app.declaring();
    widgets.caption(if (name) |given| gui.print("Declare {s} as", .{given}) else "Add", theme.text_dim, fonts.size.small, .regular);
    gui.space(4);
    for (app.profile.new_kinds, 0..) |kind, index| {
        if (name != null and !kind.named) continue;
        gui.pushIdInt(index);
        defer gui.popId();
        if (widgets.choiceRow(.{ .label = kind.label, .mark = .{ .icon = .{ .icon = sectionIcon(kind.section), .color = theme.text_dim } } })) {
            c.ImGui_CloseCurrentPopup();
            if (app.document) |document| document.queue(.{ .add = .{ .kind = kind, .name = name } });
        }
    }
}

/// Pushes the style ImGui lays out and draws a dock node's tab bar in: the design's 30 pixels
/// high, and the tabs side by side from the bar's left end, as wide as their titles
/// (`Panel.title`). ImGui's labels are hidden under the tabs the editor draws (`tab`).
/// `popTabBarStyle` takes it off.
pub fn pushTabBarStyle() void {
    gui.sans(.regular, fonts.size.ui);
    gui.pushVar2(c.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = (px(widgets.tab_bar_height) - c.ImGui_GetFontSize()) / 2 });
    gui.pushVar2(c.ImGuiStyleVar_ItemInnerSpacing, .{ .x = 0, .y = c.ImGui_GetStyle().*.ItemInnerSpacing.y });
    gui.pushVar(c.ImGuiStyleVar_WindowBorderSize, 0);
    gui.pushColor(c.ImGuiCol_Text, theme.fade(theme.text, 0));
}

pub fn popTabBarStyle() void {
    gui.popColor(1);
    gui.popVar(3);
    gui.popFont();
}

/// Begins `panel`'s window, and draws its tab. False when the window is hidden behind another tab.
/// A panel closes from the Window menu: its tab has no close button, as in the design.
fn begin(app: *App, panel: Panel) bool {
    if (panel == .source) {
        // The source panel draws its own tabs, for the open files.
        const class: c.ImGuiWindowClass = .{ .DockNodeFlagsOverrideSet = c.OR_DOCK_NODE_NO_TAB_BAR, .ParentViewportId = 0xffff_ffff, .DockingAllowUnclassed = true };
        c.ImGui_SetNextWindowClass(&class);
    }
    pushTabBarStyle();
    gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
    const flags: c.ImGuiWindowFlags = if (panel == .source) c.ImGuiWindowFlags_NoScrollbar | c.ImGuiWindowFlags_NoScrollWithMouse else 0;
    const visible = c.ImGui_Begin(panel.title(), null, flags);
    gui.popVar(1);
    popTabBarStyle();
    tab(app, panel);
    return visible;
}

/// Draws `panel`'s tab over ImGui's, where its dock node shows one, as the design's
/// (`widgets.PanelTab`).
fn tab(app: *App, panel: Panel) void {
    var rect: [4]f32 = undefined;
    var draw_list: ?*anyopaque = null;
    var selected = false;
    if (!c.or_imgui_window_tab(&rect, &draw_list, &selected)) return;
    const list: *c.ImDrawList = @ptrCast(@alignCast(draw_list.?));
    // The tab bar's line goes under the tabs (`frame`).
    const min = gui.vec2(rect[0], rect[1]);
    const max = gui.vec2(rect[2], rect[3] - px(1));
    const shown: widgets.PanelTab = .{ .label = panel.label(), .icon = panel.icon(), .pill = tabCount(app, panel), .on = selected };
    shown.draw(list, min, max, c.ImGui_IsMouseHoveringRectEx(min, max, false));
}

/// The count a panel's tab shows after its name.
fn tabCount(app: *App, panel: Panel) ?widgets.Pill {
    const document = app.document orelse return null;
    return switch (panel) {
        .problems => blk: {
            const found = document.problems().len;
            break :blk .{ .text = gui.print("{d}", .{found}), .style = if (found > 0) .err else .normal };
        },
        .breakpoints => blk: {
            var buffer: [@import("mission/document.zig").max_breakpoints]usize = undefined;
            break :blk .{ .text = gui.print("{d}", .{document.breakpoints(&buffer).len}) };
        },
        else => null,
    };
}

/// Draws the design's line around a panel, over the panel in front of its dock node: 1 pixel
/// outside the node, with corners of 3 and the ground past them, and under ImGui's tab bar, the
/// bar's line.
fn frame(panel: Panel) void {
    var node: [4]f32 = undefined;
    if (!c.or_imgui_window_dock_node(&node)) return;
    const line = px(theme.panel_line);
    const min = gui.vec2(node[0] - line, node[1] - line);
    const max = gui.vec2(node[2] + line, node[3] + line);
    const list = gui.drawList();
    c.ImDrawList_PushClipRect(list, min, max, false);
    defer c.ImDrawList_PopClipRect(list);
    // The source panel draws its own tab bar, with its line.
    if (panel != .source) {
        const bar_bottom = node[1] + px(widgets.tab_bar_height);
        gui.rect(list, .{ .x = node[0], .y = bar_bottom - px(1) }, .{ .x = node[2], .y = bar_bottom }, theme.tab_divider, 0);
    }
    // A stroke as wide as two corners, whose inner edge is the line's outer edge, puts the ground
    // past the corners.
    const radius = px(theme.panel_rounding);
    c.ImDrawList_AddRectEx(list, .{ .x = min.x - radius, .y = min.y - radius }, .{ .x = max.x + radius, .y = max.y + radius }, theme.ground, radius * 2, radius * 2, c.ImDrawFlags_RoundCornersAll);
    gui.outline(list, min, max, theme.divider, theme.panel_rounding);
}

/// The space the content starts at: the panel's inside, with the design's padding.
fn padded(x: f32, y: f32) void {
    gui.setCursor(gui.add(gui.cursor(), .{ .x = px(x), .y = px(y) }));
}

/// A line that says the panel needs something the editor doesn't have yet.
fn waiting(icon: Icon, text: []const u8, plan: ?commands.Plan) void {
    padded(12, 12);
    const at = gui.cursor();
    widgets.iconItem(icon, fonts.size.icon_small, theme.text_off);
    gui.setCursor(.{ .x = at.x + px(22), .y = at.y - px(1) });
    widgets.caption(text, theme.text_dim, fonts.size.small, .regular);
    if (plan) |planned| {
        gui.setCursor(.{ .x = at.x + px(22), .y = gui.cursor().y });
        widgets.caption(gui.print("Planned · {f}", .{planned}), theme.text_off, fonts.size.smaller, .regular);
    }
}

// The outline.

pub fn sectionIcon(section: game.Section) Icon {
    return switch (section) {
        .flight_groups => .layers,
        .ships => .navigation_2,
        .markers => .diamond,
        .squads => .boxes,
        .formations => .component,
        .curves => .route,
        .parts => .braces,
        .triggers => .zap,
        .globals => .hash,
    };
}

const Outline = struct {
    var filter: [128:0]u8 = @splat(0);
    var closed: std.EnumArray(game.Section, bool) = .initFill(false);
    var mission_closed: bool = false;
};

fn outline(app: *App) void {
    const document = app.document orelse return waiting(.flag, "No mission open", null);
    const known = document.outline();
    padded(8, 8);
    // The filter and the button that adds a record.
    const width = gui.available().x - px(8);
    const field_width = width - px(30) - px(6);
    const row_top = gui.cursor().y;
    widgets.searchField("##filter", &Outline.filter, "Filter records", field_width, 26, true);
    gui.sameLine(6);
    gui.setCursor(.{ .x = gui.cursor().x, .y = row_top - px(1) });
    if (widgets.toolButton("add record", .{ .icon = .plus, .icon_only = true, .disabled = app.unavailable(.add_record), .tooltip = "Add a record" })) app.run(.add_record);
    gui.setCursor(.{ .x = c.ImGui_GetWindowPos().x, .y = row_top + px(26) + px(8) });

    const filter = std.mem.sliceTo(&Outline.filter, 0);
    const footer = document.outline_stale;
    const footer_height: f32 = if (footer) px(40) else 0;
    _ = c.ImGui_BeginChild("outline", .{ .x = 0, .y = -footer_height }, 0, 0);
    defer {
        c.ImGui_EndChild();
        if (footer) {
            widgets.rule(theme.divider);
            padded(10, 10);
            widgets.caption("From the last good build", theme.text_dim, fonts.size.small, .regular);
        }
    }
    const root = widgets.row("mission", .{
        .label = known.name orelse if (document.number) |number| gui.print("Mission {d}", .{number}) else document.file,
        .indent = 6,
        .open = !Outline.mission_closed,
        .mark = .{ .icon = .{ .icon = .flag, .color = theme.accent, .size = fonts.size.icon_small } },
        .end = .{ .text = .{ .text = if (document.number) |number| gui.print("mission{d}", .{number}) else document.file, .mono = true } },
        .strong = true,
    });
    if (root.toggled) Outline.mission_closed = !Outline.mission_closed;
    if (Outline.mission_closed) return;
    const failed_line: ?u32 = if (document.problems().len > 0) document.problems()[0].at.line else null;
    for (std.enums.values(game.Section)) |section| {
        const count = known.count(section);
        if (count == 0 and !section.alwaysShown()) continue;
        const closed = Outline.closed.get(section);
        const header = widgets.row(@tagName(section), .{
            .label = section.label(),
            .indent = 20,
            .open = if (count > 0) !closed else false,
            .mark = .{ .icon = .{ .icon = sectionIcon(section), .color = theme.text_dim, .size = fonts.size.icon_small } },
            .end = .{ .text = .{ .text = gui.print("{d}", .{count}) } },
        });
        if (header.toggled and count > 0) Outline.closed.set(section, !closed);
        if (closed or count == 0) continue;
        for (known.records, 0..) |record, index| {
            if (record.section != section) continue;
            if (filter.len > 0 and std.ascii.findIgnoreCase(record.title, filter) == null and std.ascii.findIgnoreCase(record.name, filter) == null) continue;
            gui.pushIdInt(index);
            defer gui.popId();
            const selected = if (app.selection) |chosen| chosen.section == record.section and chosen.line == record.first_line else false;
            const failed = if (failed_line) |line| line >= record.first_line and line <= record.last_line else false;
            const result = widgets.row("record", recordRow(document, record, selected, failed));
            if (result.clicked) {
                app.select(record);
                app.goTo(record.first_line, record.column);
            }
        }
    }
}

/// How the outline shows `record`.
fn recordRow(document: *const Document, record: game.Record, selected: bool, failed: bool) widgets.Row {
    const group_color = if (record.group) |group| theme.groups[group % theme.groups.len] else theme.text_menu;
    var shown: widgets.Row = .{ .label = record.title, .indent = 52, .selected = selected, .failed = failed };
    shown.mark = switch (record.section) {
        .flight_groups => .{ .swatch = group_color },
        .ships => .{ .icon = .{ .icon = .navigation_2, .color = group_color } },
        .markers => .{ .icon = .{ .icon = .diamond, .color = group_color } },
        .parts => .{ .icon = .{ .icon = .braces, .color = theme.syntax.command } },
        .triggers => .{ .icon = .{ .icon = if (failed) .circle_alert else .zap, .color = if (failed) theme.error_outline_icon else if (selected) theme.accent else theme.text_dim } },
        .globals => .{ .icon = .{ .icon = .hash, .color = theme.text_dim } },
        else => .{ .icon = .{ .icon = sectionIcon(record.section), .color = theme.text_dim } },
    };
    if (record.section == .flight_groups) shown.indent = 54;
    if (failed) {
        shown.end = .{ .text = .{ .text = gui.print("line {d}", .{document.problems()[0].at.line + 1}), .color = theme.error_count } };
    } else if (holds(document, record)) {
        shown.end = .{ .badge = .{ .text = "held", .background = theme.accent, .foreground = theme.on_accent } };
    } else if (record.starts) {
        shown.end = .{ .badge = .{ .text = "start", .background = theme.teal_badge, .foreground = theme.teal_badge_text } };
    } else if (record.section == .triggers and hasBreakpointIn(document, record)) {
        shown.end = .{ .dot = theme.breakpoint };
    } else if (record.detail.len > 0) {
        shown.end = .{ .text = .{ .text = record.detail, .mono = record.section == .ships } };
    }
    return shown;
}

/// Whether the game holds the script on a line of `record`'s code.
fn holds(document: *const Document, record: game.Record) bool {
    const line = document.held_line orelse return false;
    return line >= record.first_line and line <= record.last_line;
}

fn hasBreakpointIn(document: *const Document, record: game.Record) bool {
    var line = record.first_line;
    while (line <= record.last_line) : (line += 1) {
        if (document.hasBreakpoint(line)) return true;
    }
    return false;
}

// Find: the lines of the mission that hold some text.

const Find = struct {
    var query: [128:0]u8 = @splat(0);
};

fn find(app: *App) void {
    const document = app.document orelse return waiting(.search, "No mission open", null);
    padded(8, 8);
    widgets.searchField("##find", &Find.query, "Find in the mission", gui.available().x - px(8), 26, true);
    gui.space(6);
    const query = std.mem.sliceTo(&Find.query, 0);
    if (query.len == 0) return;
    _ = c.ImGui_BeginChild("found", .{ .x = 0, .y = 0 }, 0, 0);
    defer c.ImGui_EndChild();
    var found: usize = 0;
    const count = document.editor.lineCount();
    var line: usize = 0;
    while (line < count) : (line += 1) {
        const text = document.editor.lineText(line);
        const column = std.ascii.findIgnoreCase(text, query) orelse continue;
        found += 1;
        gui.pushIdInt(line);
        defer gui.popId();
        const shown = std.mem.trim(u8, text, " \t");
        const result = widgets.row("line", .{
            .label = gui.z(shown[0..@min(shown.len, 60)]),
            .mono_label = true,
            .end = .{ .text = .{ .text = gui.print("{d}", .{line + 1}) } },
        });
        if (result.clicked) app.goTo(@intCast(line), @intCast(column));
        if (found >= 500) break;
    }
    if (found == 0) {
        padded(10, 6);
        widgets.caption("Not found", theme.text_dim, fonts.size.small, .regular);
    }
}

// The debugging panels, which need the game linked.

fn tableHeader(columns: []const []const u8, widths: []const f32) void {
    const at = gui.cursor();
    const width = gui.available().x;
    const height = px(27);
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.table_head, 0);
    gui.rect(list, .{ .x = at.x, .y = at.y + height - px(1) }, .{ .x = at.x + width, .y = at.y + height }, theme.table_head_line, 0);
    gui.sans(.medium, fonts.size.ui);
    var x = at.x + px(12);
    for (columns, widths) |column, column_width| {
        gui.drawText(list, .{ .x = x, .y = gui.textTop(at.y + height / 2) }, theme.text_dim, column);
        x += px(column_width);
    }
    gui.popFont();
    c.ImGui_Dummy(.{ .x = width, .y = height });
}

/// The threads' columns: their names and widths.
const thread_columns = [_][]const u8{ "Slot", "State", "Where", "Started by", "Depth", "Waits for" };
const thread_widths = [_]f32{ 46, 64, 136, 196, 58, 80 };

fn threads(app: *App) void {
    tableHeader(&thread_columns, &thread_widths);
    const session = &app.session;
    if (session.link_state != .linked) return waiting(.cable, "Threads show while linked", null);
    if (session.playing == null) return waiting(.cable, "No mission playing", null);
    const snapshot = session.state orelse return waiting(.cable, "Waiting for state", null);
    const state = snapshot.state;
    _ = c.ImGui_BeginChild("threads", .{ .x = 0, .y = -px(36) }, 0, 0);
    for (state.threads) |thread| {
        gui.pushIdInt(thread.slot);
        defer gui.popId();
        threadRow(app, state, thread);
    }
    c.ImGui_EndChild();
    padded(12, 10);
    widgets.caption(if (session.first_finished) "Start parts: done" else "Start parts: running", theme.text_dim, fonts.size.small, .regular);
}

/// A thread's row: its slot, whether the game holds it, where it is, what started it, its depth,
/// and what it waits for. A double click goes to its line.
fn threadRow(app: *App, state: State, thread: State.Thread) void {
    const session = &app.session;
    const at = gui.cursor();
    const width = gui.available().x;
    const height = px(27);
    _ = c.ImGui_InvisibleButton("thread", .{ .x = width, .y = height }, 0);
    const double_clicked = gui.hovered() and c.ImGui_IsMouseDoubleClicked(c.ImGuiMouseButton_Left);
    const list = gui.drawList();
    const held = if (session.held) |hold| thread.at == hold.offset else false;
    if (held) gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.held_row, 0) else if (gui.hovered()) gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.row_hover, 0);
    gui.rect(list, .{ .x = at.x, .y = at.y + height - px(1) }, .{ .x = at.x + width, .y = at.y + height }, theme.table_line, 0);
    const middle = at.y + height / 2;
    var x = at.x + px(12);
    gui.mono(.regular, fonts.size.ui);
    gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_row, gui.print("{d}", .{thread.slot}));
    gui.popFont();
    x += px(thread_widths[0]);
    if (held) {
        stateTag(list, x, middle, "Held");
    } else {
        const waits = thread.interrupted or thread.wake > state.clock;
        gui.sans(.regular, fonts.size.ui);
        gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_dim, if (waits) "Waiting" else "Ready");
        gui.popFont();
    }
    x += px(thread_widths[1]);
    // Where: its line, from the build's map, and its offset.
    const line = if (thread.at) |offset| session.lineOf(offset) else null;
    var where_x = x;
    if (line) |found| {
        gui.mono(.regular, fonts.size.ui);
        const text = gui.print("line {d}", .{found + 1});
        gui.drawText(list, .{ .x = where_x, .y = gui.textTop(middle) }, if (held) theme.held_text else theme.text_row, text);
        where_x += gui.textSize(text).x;
        gui.popFont();
    }
    gui.sans(.regular, fonts.size.ui);
    const offset_text = if (thread.at) |offset| gui.print("{s}offset {d}", .{ if (line != null) " · " else "", offset }) else "outside the script";
    gui.drawText(list, .{ .x = where_x, .y = gui.textTop(middle) }, theme.text_dim, offset_text);
    gui.popFont();
    x += px(thread_widths[2]);
    gui.mono(.regular, fonts.size.ui);
    gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_row, startedBy(app, thread, line));
    x += px(thread_widths[3]);
    gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_row, gui.print("{d}", .{thread.depth}));
    gui.popFont();
    x += px(thread_widths[4]);
    gui.sans(.regular, fonts.size.ui);
    const waits_for = if (thread.interrupted) "its trigger" else if (thread.wake != 0) gui.print("clock {d} s", .{thread.wake}) else "nothing";
    gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_dim, waits_for);
    gui.popFont();
    if (double_clicked) if (line) |found| app.goTo(found, 0);
}

/// The design's tag of the thread the game holds: the state on the accent, 7 pixels to each side.
fn stateTag(list: *c.ImDrawList, left: f32, middle: f32, text: []const u8) void {
    gui.sans(.semibold, 11);
    defer gui.popFont();
    const height = px(17);
    const max = gui.vec2(left + gui.textSize(text).x + px(7) * 2, middle + height / 2);
    gui.rect(list, .{ .x = left, .y = middle - height / 2 }, max, theme.accent, 3);
    gui.drawText(list, .{ .x = left + px(7), .y = gui.textTop(middle) }, theme.on_accent, text);
}

/// What started a thread, as the source writes it: its trigger, or the part whose code it runs.
fn startedBy(app: *App, thread: State.Thread, line: ?u32) []const u8 {
    const document = app.document orelse return "";
    const known = document.outline();
    if (thread.trigger) |index| {
        for (known.records) |record| {
            if (record.section == .triggers and record.index == index) return gui.print("on({s}, \"{s}\")", .{ record.subject, record.condition });
        }
        return gui.print("trigger {d}", .{index});
    }
    if (thread.depth == 0) if (line) |found| if (known.at(found)) |record| if (record.section == .parts) return record.title;
    return "a part";
}

fn breakpoints(app: *App) void {
    const document = app.document orelse return waiting(.circle_dot, "No mission open", null);
    var buffer: [@import("mission/document.zig").max_breakpoints]usize = undefined;
    const lines = document.breakpoints(&buffer);
    if (lines.len == 0) {
        waiting(.circle_dot, gui.print("No breakpoints · {s} or a click in the margin sets one", .{app.keyText(.toggle_breakpoint) orelse "F9"}), null);
        return;
    }
    tableHeader(&.{ "Line", "Statement", "In" }, &.{ 64, 330, 160 });
    const known = document.outline();
    for (lines) |line| {
        gui.pushIdInt(line);
        defer gui.popId();
        const statement = std.mem.trim(u8, document.editor.lineText(line), " \t");
        const record = known.at(@intCast(line));
        const at = gui.cursor();
        const width = gui.available().x;
        const height = px(26);
        const clicked = c.ImGui_InvisibleButton("breakpoint", .{ .x = width, .y = height }, 0);
        const list = gui.drawList();
        if (gui.hovered()) gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.row_hover, 0);
        gui.rect(list, .{ .x = at.x, .y = at.y + height - px(1) }, .{ .x = at.x + width, .y = at.y + height }, theme.table_line, 0);
        const middle = at.y + height / 2;
        if (app.session.mapped()) gui.dot(list, .{ .x = at.x + px(17), .y = middle }, 4.5, theme.breakpoint) else gui.ring(list, .{ .x = at.x + px(17), .y = middle }, 3.75, 1.5, theme.breakpoint);
        gui.mono(.regular, fonts.size.ui);
        gui.drawText(list, .{ .x = at.x + px(28), .y = gui.textTop(middle) }, theme.text_row, gui.print("{d}", .{line + 1}));
        gui.drawText(list, .{ .x = at.x + px(76), .y = gui.textTop(middle) }, theme.syntax.name, statement[0..@min(statement.len, 48)]);
        gui.popFont();
        if (record) |found| {
            gui.mono(.regular, fonts.size.ui);
            gui.drawText(list, .{ .x = at.x + px(406), .y = gui.textTop(middle) }, theme.text_dim, found.title);
            gui.popFont();
        }
        if (clicked) app.goTo(@intCast(line), 0);
    }
}

fn output(app: *App) void {
    if (app.output.items.len == 0) return waiting(.terminal, "Builds and saves show here", null);
    padded(0, 6);
    _ = c.ImGui_BeginChild("lines", .{ .x = 0, .y = 0 }, 0, 0);
    defer c.ImGui_EndChild();
    gui.mono(.regular, fonts.size.ui);
    defer gui.popFont();
    for (app.output.items) |line| {
        const at = gui.cursor();
        c.ImGui_Dummy(.{ .x = gui.available().x, .y = px(20) });
        const list = gui.drawList();
        gui.drawText(list, .{ .x = at.x + px(12), .y = at.y + px(2) }, theme.text_faint, &line.time);
        const color = switch (line.kind) {
            .info => theme.text_row,
            .success => theme.linked_text,
            .failure => theme.error_text,
        };
        gui.drawText(list, .{ .x = at.x + px(90), .y = at.y + px(2) }, color, line.text);
    }
    if (c.ImGui_GetScrollY() >= c.ImGui_GetScrollMaxY()) c.ImGui_SetScrollHereY(1);
}

fn problems(app: *App) void {
    const document = app.document orelse return waiting(.circle_alert, "No mission open", null);
    const found = document.problems();
    for (found, 0..) |problem, index| {
        gui.pushIdInt(index);
        defer gui.popId();
        problemCard(app, document, problem);
    }
    padded(12, 10);
    const at = gui.cursor();
    widgets.iconItem(.info, fonts.size.icon_small, theme.text_dim);
    gui.setCursor(.{ .x = at.x + px(24), .y = at.y });
    widgets.caption(if (found.len == 0) "No problems · checked as you type" else "Checked as you type", theme.text_dim, fonts.size.small, .regular);
}

/// A problem as the design shows it: what's wrong, the closest name for a name that isn't
/// declared, where it is, and the fixes.
fn problemCard(app: *App, document: *Document, problem: game.Problem) void {
    const at = gui.cursor();
    const width = gui.available().x;
    const list = gui.drawList();
    const start_y = at.y;
    // The content first, to know its height, then the background behind it.
    c.ImDrawList_ChannelsSplit(list, 2);
    c.ImDrawList_ChannelsSetCurrent(list, 1);
    gui.setCursor(.{ .x = at.x + px(12), .y = at.y + px(10) });
    widgets.iconItem(.circle_alert, fonts.size.icon, theme.error_icon);
    gui.setCursor(.{ .x = at.x + px(38), .y = at.y + px(9) });
    c.ImGui_BeginGroup();
    const closest = switch (problem.kind) {
        .not_declared => |name| document.outline().closest(name),
        .other => null,
    };
    switch (problem.kind) {
        .not_declared => |name| {
            widgets.caption("Not declared:", theme.text, fonts.size.body, .regular);
            gui.sameLine(5);
            widgets.monoCaption(name, theme.error_text, fonts.size.ui, .regular);
            if (closest) |record| {
                widgets.caption("Closest:", theme.error_dim, fonts.size.small, .regular);
                gui.sameLine(4);
                widgets.monoCaption(record.name, theme.text, fonts.size.small, .regular);
                gui.sameLine(4);
                widgets.caption(gui.print("· {s}, line {d}", .{ kindNoun(record.section), record.first_line + 1 }), theme.error_dim, fonts.size.small, .regular);
            }
        },
        .other => messageWithNames(problem.message),
    }
    widgets.monoCaption(gui.print("{s}:{d}:{d}", .{ document.file, problem.at.line + 1, problem.at.column + 1 }), theme.text_faint, fonts.size.smaller, .regular);
    c.ImGui_EndGroup();
    // The fixes, at the card's end.
    if (problem.kind == .not_declared) {
        const name = problem.kind.not_declared;
        const fix_y = at.y + px(10);
        var x = at.x + width - px(12);
        const declare_label = gui.print("Declare {s}", .{name});
        const declare_width = buttonWidth(declare_label);
        x -= declare_width;
        gui.setCursor(.{ .x = x, .y = fix_y });
        if (widgets.toolButton("declare", .{ .label = declare_label, .disabled = app.unavailable(.add_record) })) app.askToAdd(name);
        if (closest) |record| {
            const use_label = gui.print("Use {s}", .{record.name});
            x -= px(6) + buttonWidth(use_label);
            gui.setCursor(.{ .x = x, .y = fix_y });
            if (widgets.toolButton("use", .{ .label = use_label, .style = .primary, .weight = .semibold })) {
                const start: ui.text_editor.Pos = .{ .line = problem.at.line, .index = problem.at.column };
                document.queue(.{ .replace = .{ .start = start, .end = .{ .line = start.line, .index = start.index + name.len }, .text = record.name } });
            }
        }
    }
    const end_y = @max(gui.cursor().y, at.y + px(48)) + px(10);
    c.ImDrawList_ChannelsSetCurrent(list, 0);
    gui.rect(list, .{ .x = at.x, .y = start_y }, .{ .x = at.x + width, .y = end_y }, theme.error_row, 0);
    gui.rect(list, .{ .x = at.x, .y = end_y - px(1) }, .{ .x = at.x + width, .y = end_y }, theme.table_line, 0);
    c.ImDrawList_ChannelsMerge(list);
    gui.setCursor(.{ .x = at.x, .y = end_y });
    c.ImGui_Dummy(.{ .x = width, .y = 0 });
    // A click on the card goes to the problem.
    if (c.ImGui_IsMouseHoveringRect(.{ .x = at.x, .y = start_y }, .{ .x = at.x + width - px(240), .y = end_y }) and c.ImGui_IsMouseClicked(c.ImGuiMouseButton_Left)) {
        app.goTo(problem.at.line, problem.at.column);
    }
}

fn buttonWidth(label: []const u8) f32 {
    gui.sans(.semibold, fonts.size.ui);
    defer gui.popFont();
    return gui.textSize(label).x + px(20);
}

/// A message with its names, which OpenReliant writes in backticks, in the code font.
fn messageWithNames(message: []const u8) void {
    var parts = std.mem.splitScalar(u8, message, '`');
    var in_name = false;
    var first = true;
    while (parts.next()) |part| : (in_name = !in_name) {
        if (part.len == 0) continue;
        if (!first) gui.sameLine(0);
        first = false;
        if (in_name) widgets.monoCaption(part, theme.error_text, fonts.size.ui, .regular) else widgets.caption(part, theme.text, fonts.size.body, .regular);
    }
}

fn kindNoun(section: game.Section) []const u8 {
    return switch (section) {
        .flight_groups => "flight group",
        .ships => "ship",
        .markers => "marker",
        .squads => "squad",
        .formations => "formation",
        .curves => "curve",
        .parts => "part",
        .triggers => "trigger",
        .globals => "global",
    };
}

/// The game's variables the source uses, then the mission's globals, with their values from the
/// game's state while it's linked, in orange where they changed since the last hold.
fn variables(app: *App) void {
    padded(0, 4);
    const document = app.document;
    const session = &app.session;
    const state: ?State = if (session.mapped()) if (session.state) |snapshot| snapshot.state else null else null;
    _ = c.ImGui_BeginChild("variables", .{ .x = 0, .y = 0 }, 0, 0);
    defer c.ImGui_EndChild();
    _ = widgets.row("game", .{ .label = "Game", .indent = 12, .open = true, .strong = true });
    var shown: usize = 0;
    for (app.language.words) |word| {
        if (word.kind != .game_variable) continue;
        if (!usedIn(document, app.language.variables, word.name)) continue;
        const value = if (state) |known| gui.print("{d}", .{scriptWord(known.variable(word.name) orelse 0)}) else "";
        variableRow(word.name, value, theme.syntax.game, session.variableChanged(word.name));
        shown += 1;
    }
    if (shown == 0) variableRow("none used", "", theme.text_dim, false);
    _ = widgets.row("globals", .{ .label = "Globals", .indent = 12, .open = true, .strong = true });
    var globals: usize = 0;
    if (document) |open| for (open.outline().records) |record| {
        if (record.section != .globals) continue;
        // A global's value from the game, by its place among the globals; its first value from the
        // source until then.
        const value = if (state) |known| if (record.index < known.globals.len) gui.print("{d}", .{scriptWord(known.globals[record.index])}) else "" else record.detail;
        variableRow(record.title, value, theme.syntax.name, session.globalChanged(record.index));
        globals += 1;
    };
    if (globals == 0) variableRow("none", "", theme.text_dim, false);
    if (state == null) {
        padded(12, 8);
        widgets.caption("Values while this build plays", theme.text_off, fonts.size.smaller, .regular);
    }
}

/// One of the script's words, as the state gives it, unsigned, as a signed number: the scripts
/// count down past 0.
fn scriptWord(word: u32) i32 {
    return @bitCast(word);
}

/// Whether the source reads the game's variable `name` under the name `under`, as
/// `game.mission_over`.
fn usedIn(document: ?*Document, under: []const u8, name: []const u8) bool {
    const open = document orelse return false;
    const count = open.editor.lineCount();
    var line: usize = 0;
    while (line < count) : (line += 1) {
        const text = open.editor.lineText(line);
        var from: usize = 0;
        while (std.mem.findPos(u8, text, from, name)) |found| {
            from = found + 1;
            if (found < under.len + 1 or text[found - 1] != '.') continue;
            if (std.mem.eql(u8, text[found - 1 - under.len .. found - 1], under)) return true;
        }
    }
    return false;
}

/// A variable's line, as the design's `.vr`: its name in the code font, its value at the end, in
/// orange where it changed since the last hold.
fn variableRow(name: []const u8, value: []const u8, color: theme.Color, changed: bool) void {
    const at = gui.cursor();
    const width = gui.available().x;
    const height = px(22);
    c.ImGui_Dummy(.{ .x = width, .y = height });
    const list = gui.drawList();
    gui.mono(.regular, fonts.size.ui);
    const y = gui.textTop(at.y + height / 2);
    gui.drawText(list, .{ .x = at.x + px(34), .y = y }, color, name);
    gui.drawText(list, .{ .x = at.x + width - px(12) - gui.textSize(value).x, .y = y }, if (changed) theme.accent else theme.text_row, value);
    gui.popFont();
}

fn watch() void {
    waiting(.eye, "Watches show while linked", commands.plans.watches);
}

fn liveScene() void {
    waiting(.map, "Every object of the mission playing, with its order, target and range", commands.plans.live_scene);
}

// The inspector.

fn inspector(app: *App) void {
    const document = app.document orelse return waiting(.sliders_horizontal, "No mission open", null);
    const known = document.outline();
    const chosen = app.selection orelse blk: {
        // Without a selection, the record the cursor is in.
        const record = known.at(@intCast(document.editor.cursor().line)) orelse return waiting(.sliders_horizontal, "Select a record in the outline or the source", null);
        break :blk app_mod.Selection{ .section = record.section, .line = record.first_line };
    };
    const record = known.find(chosen.section, chosen.line) orelse return waiting(.sliders_horizontal, "Select a record in the outline or the source", null);
    gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = px(12), .y = px(14) });
    // The forms take the panel's whole width, as the design's do: it scrolls without a bar.
    _ = c.ImGui_BeginChild("inspector", .{ .x = 0, .y = 0 }, c.ImGuiChildFlags_AlwaysUseWindowPadding, c.ImGuiWindowFlags_NoScrollbar);
    gui.popVar(1);
    defer c.ImGui_EndChild();
    const left = gui.cursor().x;
    const content_width = gui.available().x;
    c.ImGui_PushItemWidth(content_width);
    defer c.ImGui_PopItemWidth();

    // The heading: an icon in a tile, the record, and where it is.
    const at = gui.cursor();
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + px(34), .y = at.y + px(34) }, theme.held, 6);
    widgets.drawIcon(list, .{ .x = at.x + px(9), .y = at.y + px(17) }, sectionIcon(record.section), fonts.size.icon, theme.accent);
    gui.setCursor(.{ .x = at.x + px(44), .y = at.y });
    c.ImGui_BeginGroup();
    const heading = switch (record.section) {
        .triggers => gui.print("on({s}, \"{s}\")", .{ record.subject, record.condition }),
        else => gui.z(record.title),
    };
    widgets.monoCaption(heading, theme.text_strong, 13.5, .semibold);
    const where = gui.print("{s} {d} · lines {d} to {d}", .{ capitalNoun(record.section), record.index, record.first_line + 1, record.last_line + 1 });
    widgets.caption(where, theme.text_dim, fonts.size.small, .regular);
    c.ImGui_EndGroup();
    gui.setCursor(.{ .x = left, .y = @max(gui.cursor().y, at.y + px(34)) + px(18) });
    if (holds(document, record.*)) {
        heldBar(app, document, record.*, content_width);
        gui.setCursor(.{ .x = left, .y = gui.cursor().y + px(18) });
    }

    // The forms write the source, which they can only do while it parses.
    const off: ?widgets.Disabled = if (document.outline_stale) .{ .reason = "Fix the source's problems first" } else null;
    switch (record.section) {
        .triggers => forms.trigger(app, document, known, record.*, off),
        else => forms.record(app, document, known, record.*, off),
    }

    // The code the declaration holds.
    gui.setCursor(.{ .x = left, .y = gui.cursor().y + px(18) });
    widgets.sectionHeading("Code");
    gui.space(9);
    codeExcerpt(document, record.*, content_width);
    gui.space(9);
    gui.setCursor(.{ .x = left, .y = gui.cursor().y });
    if (widgets.toolButton("go to code", .{ .label = "Go to code", .icon = .file, .size = fonts.size.ui })) app.goTo(record.first_line, record.column);

    gui.setCursor(.{ .x = left, .y = gui.cursor().y + px(18) });
    widgets.sectionHeading("Live");
    gui.space(9);
    widgets.caption(gui.print("While linked · planned {f}", .{commands.plans.live_scene}), theme.text_off, fonts.size.small, .regular);
}

/// The inspector's line for the thread the game holds in the record: its slot and statement, on
/// the held colours.
fn heldBar(app: *App, document: *Document, record: game.Record, width: f32) void {
    const at = gui.cursor();
    const height = px(32);
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.held, 4);
    const middle = at.y + height / 2;
    widgets.drawIcon(list, .{ .x = at.x + px(12), .y = middle }, .pause, fonts.size.icon_tiny, theme.accent);
    const slot = heldSlot(app);
    const statement = if (script_view.statementOf(document, record, document.held_line.?)) |found| found[0] else 1;
    const text = if (slot) |found| gui.print("Thread {d} · held · statement {d}", .{ found, statement }) else gui.print("Held · statement {d}", .{statement});
    gui.sans(.regular, fonts.size.ui);
    gui.drawText(list, .{ .x = at.x + px(32), .y = gui.textTop(middle) }, theme.held_text, text);
    gui.popFont();
    c.ImGui_Dummy(.{ .x = width, .y = height });
}

/// The slot of the thread the game holds, from the state.
fn heldSlot(app: *App) ?u32 {
    const held = app.session.held orelse return null;
    const snapshot = app.session.state orelse return null;
    for (snapshot.state.threads) |thread| if (thread.at == held.offset) return thread.slot;
    return null;
}

pub fn capitalNoun(section: game.Section) []const u8 {
    return switch (section) {
        .flight_groups => "Flight group",
        .ships => "Ship",
        .markers => "Marker",
        .squads => "Squad",
        .formations => "Formation",
        .curves => "Curve",
        .parts => "Part",
        .triggers => "Trigger",
        .globals => "Global",
    };
}

pub fn groupColor(record: game.Record) theme.Color {
    return if (record.group) |group| theme.groups[group % theme.groups.len] else theme.text_menu;
}

/// The first lines of a record's code, in a small code view with their numbers.
fn codeExcerpt(document: *Document, record: game.Record, width: f32) void {
    const first = if (record.section == .triggers or record.section == .parts) record.first_line + 1 else record.first_line;
    const last = @min(record.last_line, first + 4);
    const at = gui.cursor();
    const line_height = px(19);
    const lines: f32 = @floatFromInt(last - first + 1);
    const height = lines * line_height + px(12);
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.code, 4);
    gui.outline(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.table_head_line, 4);
    gui.mono(.regular, fonts.size.ui);
    defer gui.popFont();
    var y = at.y + px(6);
    var line = first;
    while (line <= last) : (line += 1) {
        const text = document.editor.lineText(line);
        const number = gui.print("{d}", .{line + 1});
        gui.drawText(list, .{ .x = at.x + px(34) - gui.textSize(number).x, .y = gui.textTop(y + line_height / 2) }, theme.text_faint, number);
        c.ImDrawList_PushClipRect(list, at, .{ .x = at.x + width - px(4), .y = at.y + height }, true);
        gui.drawText(list, .{ .x = at.x + px(44), .y = gui.textTop(y + line_height / 2) }, theme.syntax.name, std.mem.trimStart(u8, text, " \t"));
        c.ImDrawList_PopClipRect(list);
        y += line_height;
    }
    c.ImGui_Dummy(.{ .x = width, .y = height });
}

// The reference: what the word at the cursor is, from the game's catalogues.

fn reference(app: *App) void {
    const word_name = app.reference_word orelse return waiting(.book_open, "Put the cursor on a command or a word of mission source", null);
    const word = app.language.find(word_name) orelse return waiting(.book_open, "Put the cursor on a command or a word of mission source", null);
    gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = px(12), .y = px(12) });
    _ = c.ImGui_BeginChild("reference", .{ .x = 0, .y = 0 }, c.ImGuiChildFlags_AlwaysUseWindowPadding, 0);
    gui.popVar(1);
    defer c.ImGui_EndChild();
    const left = gui.cursor().x;
    const width = gui.available().x;
    widgets.monoCaption(word.name, theme.syntax.command, 13.5, .semibold);
    widgets.caption(if (word.source.len > 0) word.source else word.kind.label(), theme.text_dim, fonts.size.small, .regular);
    gui.space(10);
    if (word.signature.len > 0 and word.kind != .command) {
        gui.mono(.regular, fonts.size.small);
        gui.wrapAt(left + width);
        gui.textColored(theme.text_button, word.signature);
        c.ImGui_PopTextWrapPos();
        gui.popFont();
        gui.space(8);
    }
    if (word.about.len > 0) {
        gui.wrapAt(left + width);
        widgets.caption(word.about, theme.text, fonts.size.body, .regular);
        c.ImGui_PopTextWrapPos();
        gui.space(10);
    }
    if (word.parameters.len > 0) parameterTable(word.*, width);
    // Related: the commands whose names start the same.
    if (word.kind == .command) {
        gui.space(14);
        widgets.sectionHeading("Related");
        gui.space(6);
        var shown: usize = 0;
        const stem = word.name[0..@min(word.name.len, 8)];
        for (app.language.words) |other| {
            if (other.kind != .command or std.mem.eql(u8, other.name, word.name)) continue;
            if (!std.mem.startsWith(u8, other.name, stem)) continue;
            gui.pushIdInt(shown);
            defer gui.popId();
            const at = gui.cursor();
            gui.mono(.regular, fonts.size.ui);
            const name_width = gui.textSize(other.name).x;
            if (c.ImGui_InvisibleButton("related", .{ .x = name_width, .y = px(20) }, 0)) app.reference_word = other.name;
            gui.handCursor();
            gui.drawText(gui.drawList(), .{ .x = at.x, .y = at.y + px(2) }, theme.syntax.command, other.name);
            gui.popFont();
            shown += 1;
            if (shown == 4) break;
        }
        if (shown == 0) widgets.caption("None", theme.text_dim, fonts.size.small, .regular);
        gui.space(10);
        if (widgets.toolButton("browse speech", .{ .label = "Browse speech", .icon = .audio_waveform, .disabled = .{ .reason = gui.print("Planned · {f}", .{commands.plans.mod_mode}) } })) {}
        gui.sameLine(6);
        if (widgets.toolButton("as a block", .{ .label = "As a block", .disabled = .{ .reason = gui.print("Planned · {f}", .{commands.plans.blocks}) } })) {}
        gui.space(10);
        widgets.caption("From the game's command catalogue", theme.text_dim, fonts.size.small, .regular);
    }
}

/// A command's parameters, or a condition's values, as a table: the game's label and the type.
fn parameterTable(word: game.Word, width: f32) void {
    const at = gui.cursor();
    const list = gui.drawList();
    c.ImDrawList_ChannelsSplit(list, 2);
    c.ImDrawList_ChannelsSetCurrent(list, 1);
    const label_width = width * 0.4;
    gui.sans(.regular, fonts.size.small);
    var y = at.y;
    const head_height = px(28);
    gui.drawText(list, .{ .x = at.x + px(10), .y = gui.textTop(y + head_height / 2) }, theme.text_muted, if (word.kind == .condition) "Event value" else "Value");
    gui.drawText(list, .{ .x = at.x + label_width + px(10), .y = gui.textTop(y + head_height / 2) }, theme.text_muted, "Type");
    y += head_height;
    gui.popFont();
    for (word.parameters) |parameter| {
        gui.setCursor(.{ .x = at.x + px(10), .y = y + px(6) });
        gui.wrapAt(at.x + label_width);
        widgets.caption(parameter.label, theme.text_button, fonts.size.small, .regular);
        c.ImGui_PopTextWrapPos();
        const label_bottom = gui.cursor().y;
        gui.setCursor(.{ .x = at.x + label_width + px(10), .y = y + px(6) });
        gui.wrapAt(at.x + width - px(8));
        widgets.monoCaption(parameter.type, theme.syntax.keyword, fonts.size.small, .regular);
        c.ImGui_PopTextWrapPos();
        const bottom = @max(label_bottom, gui.cursor().y) + px(4);
        gui.rect(list, .{ .x = at.x, .y = y }, .{ .x = at.x + width, .y = y + px(1) }, theme.table_head_line, 0);
        y = bottom;
    }
    c.ImDrawList_ChannelsSetCurrent(list, 0);
    gui.rect(list, at, .{ .x = at.x + width, .y = y }, theme.code, 4);
    c.ImDrawList_ChannelsSetCurrent(list, 1);
    gui.outline(list, at, .{ .x = at.x + width, .y = y }, theme.table_head_line, 4);
    c.ImDrawList_ChannelsMerge(list);
    gui.setCursor(.{ .x = at.x, .y = y });
    c.ImGui_Dummy(.{ .x = width, .y = 0 });
}
