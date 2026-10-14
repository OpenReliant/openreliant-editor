//! The workspace's frame around the panels: the menu bar with the editor's name, the search box
//! and the mode switch; the toolbar with the mission picker, the views, Build, Play and the
//! debugger's buttons; the dock space the panels live in; and the status bar.

const std = @import("std");
const c = @import("c");

const app_mod = @import("app.zig");
const App = app_mod.App;
const Panel = app_mod.Panel;
const commands = @import("commands.zig");
const Command = commands.Command;
const keys = @import("keys.zig");
const panels = @import("panels.zig");
const ui = @import("ui.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const theme = ui.theme;
const widgets = ui.widgets;
const px = gui.px;

/// The design's heights: the menu bar, the toolbar and the status bar.
const menu_bar_height = 34;
const toolbar_height = 43;
const status_bar_height = 24;

pub fn draw(app: *App) void {
    const viewport = c.ImGui_GetMainViewport();
    c.ImGui_SetNextWindowPos(viewport.*.WorkPos, 0);
    c.ImGui_SetNextWindowSize(viewport.*.WorkSize, 0);
    c.ImGui_SetNextWindowViewport(viewport.*.ID);
    gui.pushVar(c.ImGuiStyleVar_WindowRounding, 0);
    gui.pushVar(c.ImGuiStyleVar_WindowBorderSize, 0);
    gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
    // The menu bar's height comes from the frame padding and the font when the window begins.
    gui.pushVar2(c.ImGuiStyleVar_FramePadding, .{ .x = px(9), .y = (px(menu_bar_height) - px(fonts.size.ui * fonts.em.sans)) / 2 });
    gui.pushColor(c.ImGuiCol_WindowBg, theme.ground);
    gui.pushColor(c.ImGuiCol_MenuBarBg, theme.bar);
    gui.sans(.regular, fonts.size.ui);
    const flags = c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoResize | c.ImGuiWindowFlags_NoSavedSettings |
        c.ImGuiWindowFlags_NoBringToFrontOnFocus | c.ImGuiWindowFlags_NoNavFocus | c.ImGuiWindowFlags_NoDocking | c.ImGuiWindowFlags_MenuBar;
    _ = c.ImGui_Begin("workspace", null, flags);
    gui.popFont();
    gui.popColor(2);
    gui.popVar(4);

    app.shortcuts();
    menuBar(app, .full);
    toolbar(app);
    const dockspace = c.ImGui_GetID("dock");
    const space = gui.available();
    const dock_size = gui.vec2(space.x, space.y - px(status_bar_height));
    if (app.layout_due or !c.or_dock_builder_has_node(dockspace)) {
        fullLayout(dockspace, dock_size);
        app.layout_due = false;
        app.front_tabs_due = true;
    }
    // The dock space draws the panels' tab bars, in the design's font and height.
    gui.sans(.regular, fonts.size.ui);
    gui.pushVar2(c.ImGuiStyleVar_FramePadding, .{ .x = px(12), .y = (px(panels.tab_bar_height) - px(fonts.size.ui * fonts.em.sans)) / 2 });
    gui.pushVar2(c.ImGuiStyleVar_ItemInnerSpacing, .{ .x = px(7), .y = px(4) });
    gui.pushColor(c.ImGuiCol_Text, theme.text_muted);
    _ = c.ImGui_DockSpaceEx(dockspace, dock_size, c.OR_DOCK_NODE_NO_WINDOW_MENU_BUTTON | c.OR_DOCK_NODE_NO_CLOSE_BUTTON, null);
    gui.popColor(1);
    gui.popVar(2);
    gui.popFont();
    statusBar(app);
    c.ImGui_End();

    panels.draw(app);
    if (app.front_tabs_due) {
        // The panels the design shows in front of each group, the source last, which takes the
        // keyboard.
        for ([_]Panel{ .threads, .variables, .inspector, .mission, .source }) |panel| c.ImGui_SetWindowFocusStr(panel.title());
        app.front_tabs_due = false;
    }
}

pub const MenuSet = enum {
    /// Every menu, in the workspace.
    full,
    /// File, Game and Help, on the start screen.
    start,
    /// File, Edit, View, Window and Help, in the settings.
    settings,
};

/// The menu bar: the editor's name, the menus, the search box and, in the workspace, the mode
/// switch.
pub fn menuBar(app: *App, set: MenuSet) void {
    gui.sans(.regular, fonts.size.ui);
    defer gui.popFont();
    if (!c.ImGui_BeginMenuBar()) return;
    defer c.ImGui_EndMenuBar();
    const bar_min = gui.cursor();
    const bar_y = c.ImGui_GetWindowPos().y;
    // The line under the bar.
    gui.rect(c.ImGui_GetWindowDrawList(), .{ .x = c.ImGui_GetWindowPos().x, .y = bar_y + px(menu_bar_height) - px(1) }, .{ .x = c.ImGui_GetWindowPos().x + c.ImGui_GetWindowWidth(), .y = bar_y + px(menu_bar_height) }, theme.divider, 0);
    wordmark(.{ .x = bar_min.x + px(10), .y = bar_y + px(menu_bar_height) / 2 });
    gui.setCursor(.{ .x = bar_min.x + px(10) + wordmarkWidth() + px(18), .y = bar_min.y });

    gui.pushColor(c.ImGuiCol_Text, theme.text_menu);
    gui.pushColor(c.ImGuiCol_HeaderHovered, theme.divider);
    gui.pushColor(c.ImGuiCol_Header, theme.divider);
    gui.pushVar2(c.ImGuiStyleVar_ItemSpacing, .{ .x = px(9), .y = px(6) });
    for (std.enums.values(commands.Menu)) |menu| {
        if (!shown(menu, set)) continue;
        if (c.ImGui_BeginMenu(menu.label())) {
            gui.popColor(1);
            menuEntries(app, menu);
            gui.pushColor(c.ImGuiCol_Text, theme.text_menu);
            c.ImGui_EndMenu();
        }
    }
    gui.popVar(1);
    gui.popColor(3);

    // The search box and the mode switch, at the bar's end.
    const right = c.ImGui_GetWindowPos().x + c.ImGui_GetWindowWidth() - px(10);
    const mode_width: f32 = if (set == .full) modeSwitchWidth() + px(14) else 0;
    const search_width = px(if (set == .full) 340 else 300);
    const middle = bar_y + px(menu_bar_height) / 2;
    if (set != .settings) {
        gui.setCursor(.{ .x = right - mode_width - search_width, .y = middle - px(13) });
        if (searchBox(app, search_width, if (set == .full) "Search records and commands" else "Search commands")) app.palette.show(.commands);
    } else {
        gui.sans(.regular, fonts.size.ui);
        const text = "Settings";
        gui.drawText(gui.drawList(), .{ .x = right - gui.textSize(text).x, .y = middle - c.ImGui_GetFontSize() / 2 }, theme.text_muted, text);
        gui.popFont();
    }
    if (set == .full) {
        gui.setCursor(.{ .x = right - mode_width + px(14), .y = middle - px(14) });
        modeSwitch(app);
    }
}

fn shown(menu: commands.Menu, set: MenuSet) bool {
    return switch (set) {
        .full => true,
        .start => switch (menu) {
            .file, .game, .help => true,
            else => false,
        },
        .settings => switch (menu) {
            .file, .edit, .view, .window, .help => true,
            else => false,
        },
    };
}

/// A menu's items: each action with its icon, its keys, and greyed out with the reason when it
/// can't run.
fn menuEntries(app: *App, menu: commands.Menu) void {
    gui.pushVar2(c.ImGuiStyleVar_ItemSpacing, .{ .x = px(8), .y = px(6) });
    gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = px(6), .y = px(6) });
    defer gui.popVar(2);
    for (commands.entries(menu)) |entry| switch (entry) {
        .separator => c.ImGui_Separator(),
        .command => |command| {
            if (command == .view_4 and app.mode == .mission) continue;
            const known = commands.info(command);
            const off = app.unavailable(command);
            const icon = if (known.icon) |which| which.text() else "   ";
            const text = gui.print("{s}  {s}", .{ icon, app.label(command) });
            const key = app.keyText(command);
            const checked = isChecked(app, command);
            if (c.ImGui_MenuItemEx(text, if (key) |written| written.ptr else null, checked, off == null)) app.run(command);
            if (off) |why| gui.tooltip(why.reason);
        },
    };
}

/// Whether a menu item shows a check: the view shown, the panels open.
fn isChecked(app: *const App, command: Command) bool {
    return switch (command) {
        .view_1 => app.view == .script,
        .show_source => app.source_tab == .source,
        .show_listing => app.source_tab == .listing,
        else => for (std.enums.values(Panel)) |panel| {
            if (panel.command() == command) break app.open_panels.get(panel);
        } else false,
    };
}

/// "OpenReliant EDITOR": the name in Newtown, Reliant in orange, then EDITOR in small spaced
/// capitals.
pub fn wordmark(at: gui.Vec2) void {
    const list = gui.drawList();
    gui.brand(16);
    const open_width = gui.textSize("Open").x;
    const top = at.y - c.ImGui_GetFontSize() / 2;
    gui.drawText(list, .{ .x = at.x, .y = top }, theme.text, "Open");
    gui.drawText(list, .{ .x = at.x + open_width, .y = top }, theme.accent, "Reliant");
    const name_width = open_width + gui.textSize("Reliant").x;
    gui.popFont();
    gui.sans(.semibold, fonts.size.tiny);
    _ = gui.drawSpaced(list, .{ .x = at.x + name_width + px(8), .y = top + px(4.5) }, theme.text_dim, "EDITOR", 1.47);
    gui.popFont();
}

fn wordmarkWidth() f32 {
    gui.brand(16);
    const name = gui.textSize("OpenReliant").x;
    gui.popFont();
    gui.sans(.semibold, fonts.size.tiny);
    const editor = gui.spacedWidth("EDITOR", 1.47);
    gui.popFont();
    return name + px(8) + editor;
}

/// The search box that opens the command palette.
fn searchBox(app: *App, width: f32, placeholder: []const u8) bool {
    const at = gui.cursor();
    const height = px(26);
    const clicked = c.ImGui_InvisibleButton("search", .{ .x = width, .y = height }, 0);
    gui.handCursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    gui.rect(list, at, max, theme.field, 4);
    gui.outline(list, at, max, if (gui.hovered()) theme.border_strong else theme.border, 4);
    const middle = at.y + height / 2;
    widgets.drawIcon(list, .{ .x = at.x + px(8), .y = middle }, .search, fonts.size.icon_small, theme.text_dim);
    gui.sans(.regular, fonts.size.ui);
    gui.drawText(list, .{ .x = at.x + px(8) + px(14) + px(8), .y = middle - c.ImGui_GetFontSize() / 2 }, theme.text_dim, placeholder);
    gui.popFont();
    if (app.keyText(.palette)) |key| {
        const key_width = widgets.keyChipWidth(key);
        widgets.drawKeyChip(list, .{ .x = max.x - px(8) - key_width, .y = middle }, key, .normal);
    }
    return clicked;
}

fn modeSwitchWidth() f32 {
    gui.sans(.medium, fonts.size.ui);
    defer gui.popFont();
    return px(2) * 3 + (px(12) * 2 + px(14) + px(6)) * 2 + gui.textSize("Mod").x + gui.textSize("Mission").x;
}

/// The switch between Mod and Mission mode. Its buttons have IDs of their own, apart from the
/// menus of the same names beside them.
fn modeSwitch(app: *App) void {
    gui.pushId("mode");
    defer gui.popId();
    const width = modeSwitchWidth();
    const height = px(28);
    const at = gui.cursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    gui.rect(list, at, max, theme.field, 5);
    gui.outline(list, at, max, theme.border, 5);
    gui.sans(.medium, fonts.size.ui);
    defer gui.popFont();
    var x = at.x + px(2);
    const off = app.unavailable(.switch_mode);
    inline for (.{ .{ app_mod.Mode.mod, "Mod", ui.icons.Icon.box }, .{ app_mod.Mode.mission, "Mission", ui.icons.Icon.flag } }) |option| {
        const item_width = px(12) * 2 + px(14) + px(6) + gui.textSize(option[1]).x;
        gui.setCursor(.{ .x = x, .y = at.y + px(2) });
        const pressed = c.ImGui_InvisibleButton(option[1], .{ .x = item_width, .y = px(24) }, 0);
        const on = app.mode == option[0];
        const min = gui.vec2(x, at.y + px(2));
        if (on) gui.rect(list, min, .{ .x = x + item_width, .y = at.y + px(26) }, theme.border, 3);
        const disabled = !on and off != null;
        const foreground = if (on) theme.white else if (disabled) theme.text_off else theme.text_muted;
        const middle = at.y + height / 2;
        widgets.drawIcon(list, .{ .x = x + px(12), .y = middle }, option[2], fonts.size.icon_small, if (on and option[0] == .mission) theme.accent else foreground);
        gui.drawText(list, .{ .x = x + px(12) + px(14) + px(6), .y = middle - c.ImGui_GetFontSize() / 2 }, foreground, option[1]);
        if (disabled) gui.tooltip(off.?.reason);
        if (pressed and !disabled and !on) app.run(.switch_mode);
        x += item_width + px(2);
    }
    gui.setCursor(at);
    c.ImGui_Dummy(.{ .x = width, .y = height });
}

/// The toolbar: the mission picker, the views, Build, Play and the debugger's buttons, and the
/// chips that say the state of the build and of the game.
fn toolbar(app: *App) void {
    const window_pos = c.ImGui_GetWindowPos();
    const top = gui.cursor().y;
    const width = c.ImGui_GetWindowWidth();
    const list = gui.drawList();
    gui.rect(list, .{ .x = window_pos.x, .y = top }, .{ .x = window_pos.x + width, .y = top + px(toolbar_height) }, theme.toolbar, 0);
    gui.rect(list, .{ .x = window_pos.x, .y = top + px(toolbar_height) - px(1) }, .{ .x = window_pos.x + width, .y = top + px(toolbar_height) }, theme.divider, 0);
    gui.setCursor(.{ .x = window_pos.x + px(10), .y = top + px(6) });
    gui.pushVar2(c.ImGuiStyleVar_ItemSpacing, .{ .x = px(6), .y = px(6) });
    defer gui.popVar(1);

    const document = app.document;
    const title = if (document) |open| open.outline().name orelse if (open.number) |number| gui.print("Mission {d}", .{number}) else open.file else "No mission";
    const picker_tip = if (document) |open| gui.print("{s}, in the mod {s}", .{ open.file, if (app.project) |opened| opened.name else "" }) else null;
    if (widgets.picker("mission picker", title, theme.accent, picker_tip)) _ = c.ImGui_OpenPopup("missions", 0);
    missionMenu(app);
    gui.sameLine(6);

    const views = [_]widgets.ViewTab{
        .{ .label = "Script", .icon = .code, .tooltip = app.keyText(.view_1) },
        .{ .label = "Scene", .icon = .map, .disabled = app.unavailable(.view_2) },
        .{ .label = "Blocks", .icon = .blocks, .disabled = app.unavailable(.view_3) },
    };
    if (widgets.viewTabs("views", &views, @backingInt(app.view))) |chosen| app.run(switch (chosen) {
        0 => .view_1,
        1 => .view_2,
        else => .view_3,
    });
    gui.sameLine(6);
    widgets.toolbarDivider();
    gui.sameLine(6);

    const problem_count = if (document) |open| open.problems().len else 0;
    if (widgets.toolButton("build", .{
        .label = "Build",
        .icon = .hammer,
        .pill = if (problem_count > 0) .{ .text = gui.print("{d}", .{problem_count}), .style = .err } else null,
        .disabled = app.unavailable(.build),
        .tooltip = if (app.keyText(.build)) |key| gui.print("Build, {s}", .{key}) else "Build",
    })) app.run(.build);
    gui.sameLine(6);
    if (widgets.toolButton("play", .{ .label = "Play in game", .icon = .play, .corners = .left, .disabled = app.unavailable(.play) })) app.run(.play);
    gui.sameLine(0);
    if (widgets.toolButton("play from part", .{ .icon = .chevron_down, .icon_only = true, .corners = .right, .disabled = app.unavailable(.play_from_part), .tooltip = "Play from a part" })) app.run(.play_from_part);
    gui.sameLine(6);
    widgets.toolbarDivider();
    gui.sameLine(6);
    const held = app.held;
    if (widgets.toolButton("continue", .{
        .label = "Continue",
        .icon = .step_forward,
        .style = if (held) .primary else .normal,
        .weight = if (held) .semibold else .regular,
        .key = if (held) app.keyText(.@"continue") else null,
        .disabled = app.unavailable(.@"continue"),
    })) app.run(.@"continue");
    inline for (.{ .{ Command.step_over, ui.icons.Icon.redo_dot }, .{ Command.step_into, ui.icons.Icon.arrow_down_to_dot }, .{ Command.pause, ui.icons.Icon.pause }, .{ Command.let_go, ui.icons.Icon.square } }) |button| {
        gui.sameLine(6);
        const tip = if (app.keyText(button[0])) |key| gui.print("{s}, {s}", .{ commands.info(button[0]).label, key }) else commands.info(button[0]).label;
        if (widgets.toolButton(@tagName(button[0]), .{ .icon = button[1], .icon_only = true, .disabled = app.unavailable(button[0]), .tooltip = tip })) app.run(button[0]);
    }

    // The chips, at the toolbar's end.
    var chips: [2]widgets.Chip = undefined;
    var chip_count: usize = 0;
    if (document) |open| {
        const found = open.problems();
        if (found.len > 0) {
            chips[chip_count] = .{
                .style = .warning,
                .text = gui.print("{d} problem{s}", .{ found.len, if (found.len == 1) "" else "s" }),
                .extra = if (open.built) |built| gui.print("game: last build, {s}", .{built.time}) else "game: no build",
            };
            chip_count += 1;
        }
    }
    // The link is to OpenReliant, which names the game it plays once it answers.
    chips[chip_count] = if (app.linked_game) |name|
        .{ .style = .linked, .text = name }
    else
        .{ .style = .idle, .text = "OpenReliant", .extra = "not linked", .tooltip = gui.print("The editor link: planned · {f}", .{commands.plans.debugger}) };
    chip_count += 1;
    var total: f32 = 0;
    for (chips[0..chip_count]) |chip| total += widgets.chipWidth(chip) + px(8);
    gui.sameLine(0);
    const right = window_pos.x + width - px(10);
    const start = @max(gui.cursor().x + px(8), right - total + px(8));
    gui.setCursor(.{ .x = start, .y = top + px(8.5) });
    for (chips[0..chip_count], 0..) |chip, index| {
        if (index > 0) gui.sameLine(8);
        widgets.chip(chip);
    }
    gui.setCursor(.{ .x = window_pos.x, .y = top + px(toolbar_height) });
}

/// The mod's missions, which the picker opens.
fn missionMenu(app: *App) void {
    gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = px(6), .y = px(6) });
    defer gui.popVar(1);
    if (!c.ImGui_BeginPopup("missions", 0)) return;
    defer c.ImGui_EndPopup();
    const opened = app.project orelse {
        gui.text("No mod open");
        return;
    };
    widgets.sectionHeading(gui.print("Missions of {s}", .{opened.name}));
    for (opened.missions, 0..) |mission, index| {
        const current = if (app.document) |document| std.mem.eql(u8, document.file, mission.file) else false;
        if (c.ImGui_MenuItemEx(gui.z(mission.file), null, current, true) and !current) app.openMission(index);
    }
    c.ImGui_Separator();
    if (c.ImGui_MenuItemEx(gui.print("{s}  New mission", .{ui.icons.Icon.file_plus.text()}), null, false, false)) {}
    if (app.unavailable(.new_mission)) |off| gui.tooltip(off.reason);
}

/// The status bar: the state, the file and the cursor, the keys that matter now, and the last
/// build.
fn statusBar(app: *App) void {
    const window_pos = c.ImGui_GetWindowPos();
    const width = c.ImGui_GetWindowWidth();
    const top = window_pos.y + c.ImGui_GetWindowHeight() - px(status_bar_height);
    const list = gui.drawList();
    gui.rect(list, .{ .x = window_pos.x, .y = top }, .{ .x = window_pos.x + width, .y = top + px(status_bar_height) }, theme.bar, 0);
    gui.rect(list, .{ .x = window_pos.x, .y = top }, .{ .x = window_pos.x + width, .y = top + px(1) }, theme.divider, 0);
    gui.sans(.regular, fonts.size.smaller);
    defer gui.popFont();
    const middle = top + px(status_bar_height) / 2;
    const text_y = middle - c.ImGui_GetFontSize() / 2;
    var x = window_pos.x + px(10);
    const gap = px(16);

    const document = app.document orelse return;
    const found = document.problems();
    if (found.len > 0) {
        widgets.drawIcon(list, .{ .x = x, .y = middle }, .circle_alert, fonts.size.icon_tiny, theme.error_icon);
        x += px(12) + px(6);
        const text = gui.print("{d} problem{s}", .{ found.len, if (found.len == 1) "" else "s" });
        gui.drawText(list, .{ .x = x, .y = text_y }, theme.error_text, text);
        x += gui.textSize(text).x + gap;
    } else if (app.held) {
        gui.dot(list, .{ .x = x + px(3.5), .y = middle }, 3.5, theme.accent);
        x += px(7) + px(6);
        gui.drawText(list, .{ .x = x, .y = text_y }, theme.held_text, "Held");
        x += gui.textSize("Held").x + gap;
    }
    const cursor = document.editor.cursor();
    for ([_][]const u8{ document.file, gui.print("Ln {d}, Col {d}", .{ cursor.line + 1, cursor.index + 1 }), keyHints(app) }) |part| {
        gui.drawText(list, .{ .x = x, .y = text_y }, theme.text_muted, part);
        x += gui.textSize(part).x + gap;
    }

    // At the end: the last build, and live changes.
    var right = window_pos.x + width - px(10);
    const live = if (found.len > 0) "Live changes paused" else "Live changes: not linked";
    right -= gui.textSize(live).x;
    gui.drawText(list, .{ .x = right, .y = text_y }, theme.text_muted, live);
    right -= gap;
    if (document.built) |built| {
        const text = gui.print("Built {s} · {s}", .{ built.time, built.file });
        right -= gui.textSize(text).x;
        gui.drawText(list, .{ .x = right, .y = text_y }, theme.text_muted, text);
        right -= px(12) + px(6);
        widgets.drawIcon(list, .{ .x = right, .y = middle }, .check, fonts.size.icon_tiny, theme.linked);
    }
}

/// The keys that matter now, as the status bar lists them.
fn keyHints(app: *App) []const u8 {
    const system = keys.System.current;
    const views = app.settings.keymap.chords(.view_1, system);
    const view_key = if (views.len > 0) gui.print("{f}", .{views[0].written(system)}) else "";
    const views_hint = if (view_key.len > 0) gui.print("{s} to 3 switch views", .{view_key}) else "";
    if (app.held) {
        return gui.print("{s} continue · {s} step over · {s} step into · {s}", .{ app.keyText(.@"continue") orelse "", app.keyText(.step_over) orelse "", app.keyText(.step_into) orelse "", views_hint });
    }
    return gui.print("{s} build · {s} breakpoint · {s}", .{ app.keyText(.build) orelse "", app.keyText(.toggle_breakpoint) orelse "", views_hint });
}

/// The full layout: the outline on the left, the source in the middle with the debugging panels
/// under it, and the inspector on the right, as the design shows them.
pub fn fullLayout(dockspace: c.ImGuiID, size: gui.Vec2) void {
    c.or_dock_builder_reset(dockspace, size.x, size.y);
    var left: c.ImGuiID = 0;
    var rest: c.ImGuiID = 0;
    _ = c.or_dock_builder_split(dockspace, c.ImGuiDir_Left, px(250) / size.x, &left, &rest);
    var right: c.ImGuiID = 0;
    var middle: c.ImGuiID = 0;
    _ = c.or_dock_builder_split(rest, c.ImGuiDir_Right, px(310) / (size.x - px(250)), &right, &middle);
    var bottom: c.ImGuiID = 0;
    var source: c.ImGuiID = 0;
    _ = c.or_dock_builder_split(middle, c.ImGuiDir_Down, px(250) / size.y, &bottom, &source);
    var bottom_right: c.ImGuiID = 0;
    var bottom_left: c.ImGuiID = 0;
    _ = c.or_dock_builder_split(bottom, c.ImGuiDir_Right, 0.42, &bottom_right, &bottom_left);
    for ([_]Panel{ .mission, .find }) |panel| c.or_dock_builder_dock_window(panel.title(), left);
    c.or_dock_builder_dock_window(Panel.source.title(), source);
    for ([_]Panel{ .threads, .breakpoints, .output, .problems }) |panel| c.or_dock_builder_dock_window(panel.title(), bottom_left);
    for ([_]Panel{ .variables, .watch }) |panel| c.or_dock_builder_dock_window(panel.title(), bottom_right);
    for ([_]Panel{ .inspector, .reference, .live_scene }) |panel| c.or_dock_builder_dock_window(panel.title(), right);
    c.or_dock_builder_finish(dockspace);
}
