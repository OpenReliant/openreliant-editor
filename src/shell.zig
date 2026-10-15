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
const scene_view = @import("views/scene.zig");
const ui = @import("ui.zig");
const version = @import("version.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const theme = ui.theme;
const widgets = ui.widgets;
const px = gui.px;

/// The design's menu bar: 3 pixels of padding above and below its controls, at least 34 pixels
/// high with its line at the bottom.
const menu_bar_padding = 3;
const menu_bar_least_height = 34;
/// The mode switch's height, which makes the workspace's menu bar higher than the others.
const mode_switch_height = 30;

/// The toolbar: 6 pixels of padding above and below a row of controls as high as the view tabs,
/// which the others are centred on, and its line.
const toolbar_padding = 6;
const toolbar_row = widgets.view_tabs_height;
const toolbar_height = toolbar_padding * 2 + toolbar_row + 1;

const status_bar_height = 24;

/// The dock space's ID, which names the layout's version: a layout saved with other panels or other
/// sizes gives way to the full layout once.
const dock_id = "dock 2";

pub fn draw(app: *App) void {
    beginScreen("workspace", .full, theme.bar);
    app.shortcuts();
    menuBar(app, .full);
    toolbar(app);
    const dockspace = c.ImGui_GetID(dock_id);
    // The panels fill the area above the status bar, 3 pixels in from its edges. The dock nodes are
    // the panels' insides, within their lines.
    const inset = px(theme.panel_gap + theme.panel_line);
    const space = gui.available();
    gui.setCursor(gui.add(gui.cursor(), .{ .x = inset, .y = inset }));
    const dock_size = gui.vec2(space.x - inset * 2, space.y - px(status_bar_height) - inset * 2);
    if (app.layout_due or !c.or_dock_builder_has_node(dockspace)) {
        fullLayout(dockspace, dock_size);
        app.layout_due = false;
        app.front_tabs_due = true;
    }
    // The dock space draws the panels' tab bars, and the gaps between the panels in the border's
    // colour, which shows the ground there.
    panels.pushTabBarStyle();
    gui.pushColor(c.ImGuiCol_Border, theme.ground);
    _ = c.ImGui_DockSpaceEx(dockspace, dock_size, c.OR_DOCK_NODE_NO_WINDOW_MENU_BUTTON | c.OR_DOCK_NODE_NO_CLOSE_BUTTON, null);
    gui.popColor(1);
    panels.popTabBarStyle();
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

    /// The menu bar's height: the workspace's holds the mode switch.
    pub fn height(set: MenuSet) f32 {
        return switch (set) {
            .full => @max(menu_bar_least_height, menu_bar_padding * 2 + mode_switch_height + 1),
            .start, .settings => menu_bar_least_height,
        };
    }
};

/// Begins a screen: a window over the whole of the main viewport, with `set`'s menu bar on a
/// background of `bar`. `c.ImGui_End` ends it.
pub fn beginScreen(name: [:0]const u8, set: MenuSet, bar: theme.Color) void {
    const viewport = c.ImGui_GetMainViewport();
    c.ImGui_SetNextWindowPos(viewport.*.WorkPos, 0);
    c.ImGui_SetNextWindowSize(viewport.*.WorkSize, 0);
    c.ImGui_SetNextWindowViewport(viewport.*.ID);
    gui.pushVar(c.ImGuiStyleVar_WindowRounding, 0);
    gui.pushVar(c.ImGuiStyleVar_WindowBorderSize, 0);
    gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
    // ImGui makes the menu bar as high as the font with the frame padding above and below it.
    gui.sans(.regular, fonts.size.ui);
    gui.pushVar2(c.ImGuiStyleVar_FramePadding, .{ .x = px(9), .y = (px(set.height()) - c.ImGui_GetFontSize()) / 2 });
    // The bar draws its line inside its height (`menuBar`); with a frame border, ImGui would draw
    // one below it as well, and keep the content from it.
    gui.pushVar(c.ImGuiStyleVar_FrameBorderSize, 0);
    gui.pushColor(c.ImGuiCol_WindowBg, theme.ground);
    gui.pushColor(c.ImGuiCol_MenuBarBg, bar);
    const flags = c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoSavedSettings | c.ImGuiWindowFlags_NoBringToFrontOnFocus |
        c.ImGuiWindowFlags_NoNavFocus | c.ImGuiWindowFlags_NoDocking | c.ImGuiWindowFlags_MenuBar;
    _ = c.ImGui_Begin(name, null, flags);
    gui.popColor(2);
    gui.popVar(5);
    gui.popFont();
}

/// The menu bar: the editor's name, the menus, the search box and, in the workspace, the mode
/// switch.
pub fn menuBar(app: *App, set: MenuSet) void {
    gui.sans(.regular, fonts.size.ui);
    defer gui.popFont();
    const window_pos = c.ImGui_GetWindowPos();
    const width = c.ImGui_GetWindowWidth();
    const height = px(set.height());
    // The bar's controls are centred between its padding, above its line.
    const middle = window_pos.y + (height - px(1)) / 2;
    // ImGui puts the menus' labels the frame padding below the bar's top, which it reads as the
    // bar begins: there they sit in the middle, as the design's menu buttons.
    gui.pushVar2(c.ImGuiStyleVar_FramePadding, .{ .x = px(9), .y = gui.textTop(middle) - window_pos.y });
    const open = c.ImGui_BeginMenuBar();
    gui.popVar(1);
    if (!open) return;
    defer c.ImGui_EndMenuBar();
    const bar_top = gui.cursor().y;
    gui.rect(gui.drawList(), .{ .x = window_pos.x, .y = window_pos.y + height - px(1) }, .{ .x = window_pos.x + width, .y = window_pos.y + height }, theme.divider, 0);
    const name_end = wordmark(window_pos.x + px(10), middle);

    // A menu's label goes half the item spacing after the cursor, and its highlight reaches the
    // spacing to each side and half the spacing above and below, as far as the design's menu
    // buttons. The buttons start after the name's padding of 4 and the bar's gap of 14, and have
    // 2 pixels between them. Each label goes where its button puts it, to the nearest pixel: ImGui
    // would round each label's width up.
    const spacing = gui.vec2(px(9), px(10));
    var label_x = name_end + px(4) + px(14) + spacing.x;
    gui.pushColor(c.ImGuiCol_Text, theme.text_menu);
    gui.pushColor(c.ImGuiCol_HeaderHovered, theme.divider);
    gui.pushColor(c.ImGuiCol_Header, theme.divider);
    gui.pushVar2(c.ImGuiStyleVar_ItemSpacing, spacing);
    for (std.enums.values(commands.Menu)) |menu| {
        if (!shown(menu, set)) continue;
        gui.setCursor(.{ .x = @round(label_x) - @trunc(spacing.x / 2), .y = bar_top });
        label_x += gui.spacedWidth(menu.label(), 0) + spacing.x * 2 + px(2);
        if (c.ImGui_BeginMenu(menu.label())) {
            gui.popColor(1);
            menuEntries(app, menu);
            gui.pushColor(c.ImGuiCol_Text, theme.text_menu);
            c.ImGui_EndMenu();
        }
    }
    gui.popVar(1);
    gui.popColor(3);

    // The search box and the mode switch, at the bar's end, 14 pixels apart.
    const right = window_pos.x + width - px(10);
    const mode_width: f32 = if (set == .full) modeSwitchWidth(app.mode) + px(14) else 0;
    const search_width = px(if (set == .full) 340 else 300);
    if (set != .settings) {
        gui.setCursor(.{ .x = right - mode_width - search_width, .y = middle - px(search_box_height) / 2 });
        if (searchBox(app, search_width, if (set == .full) "Search records and commands" else "Search commands")) app.palette.show(.commands);
    } else {
        const text = "Settings";
        gui.drawText(gui.drawList(), .{ .x = right - gui.textSize(text).x, .y = gui.textTop(middle) }, theme.text_muted, text);
    }
    if (set == .full) {
        gui.setCursor(.{ .x = right - mode_width + px(14), .y = middle - px(mode_switch_height) / 2 });
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
        .version => _ = c.ImGui_MenuItemEx(gui.print("{s}  Version {s}", .{ no_icon, version.string }), null, false, false),
        .command => |command| {
            if (command == .view_4 and app.mode == .mission) continue;
            const known = commands.info(command);
            const off = app.unavailable(command);
            const icon = if (known.icon) |which| which.text() else no_icon;
            const text = gui.print("{s}  {s}", .{ icon, app.label(command) });
            const key = app.keyText(command);
            const checked = isChecked(app, command);
            if (c.ImGui_MenuItemEx(text, if (key) |written| written.ptr else null, checked, off == null)) app.run(command);
            if (off) |why| gui.tooltip(why.reason);
        },
    };
}

/// What stands in a menu item's icon column for an item without an icon.
const no_icon = "   ";

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

/// "OpenReliant EDITOR" from `left`: the name in Newtown at 16 pixels spaced 0.02 em, Reliant in
/// orange, then EDITOR 8 pixels after it in small capitals spaced 0.14 em, on the same baseline.
/// The name's line is centred on `middle`, as the design's stylesheet centres it. Where it ends.
pub fn wordmark(left: f32, middle: f32) f32 {
    const list = gui.drawList();
    const name_size = 16;
    gui.brand(name_size);
    const name_top = gui.textTop(middle);
    const baseline = name_top + gui.ascent();
    var x = left;
    x += gui.drawSpaced(list, .{ .x = x, .y = name_top }, theme.text, "Open", 0.02 * name_size);
    x += gui.drawSpaced(list, .{ .x = x, .y = name_top }, theme.accent, "Reliant", 0.02 * name_size);
    gui.popFont();
    x += px(8);
    gui.sans(.semibold, fonts.size.tiny);
    x += gui.drawSpaced(list, .{ .x = x, .y = baseline - gui.ascent() }, theme.text_dim, "EDITOR", 0.14 * fonts.size.tiny);
    gui.popFont();
    return x;
}

const search_box_height = 26;

/// The search box that opens the command palette.
fn searchBox(app: *App, width: f32, placeholder: []const u8) bool {
    const at = gui.cursor();
    const height = px(search_box_height);
    const clicked = c.ImGui_InvisibleButton("search", .{ .x = width, .y = height }, 0);
    gui.handCursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    gui.rect(list, at, max, theme.field, 4);
    gui.outline(list, at, max, if (gui.hovered()) theme.border_strong else theme.border, 4);
    const middle = at.y + height / 2;
    widgets.drawIcon(list, .{ .x = at.x + px(8), .y = middle }, .search, fonts.size.icon_small, theme.text_dim);
    gui.sans(.regular, fonts.size.ui);
    gui.drawText(list, .{ .x = at.x + px(8) + px(14) + px(8), .y = gui.textTop(middle) }, theme.text_dim, placeholder);
    gui.popFont();
    if (app.keyText(.palette)) |key| {
        const key_width = widgets.keyChipWidth(key);
        widgets.drawKeyChip(list, .{ .x = max.x - px(8) - key_width, .y = middle }, key, .normal);
    }
    return clicked;
}

/// The mode switch's line and its padding inside it, around its buttons.
const mode_switch_inset = 1 + 2;

/// The modes the switch offers, with their labels and icons.
const modes = [_]struct { app_mod.Mode, []const u8, ui.icons.Icon }{
    .{ .mod, "Mod", .box },
    .{ .mission, "Mission", .flag },
};

/// A button of the mode switch: its icon and label in 12 pixels of padding, the label heavier for
/// the mode on.
fn modeButtonWidth(label: []const u8, on: bool) f32 {
    gui.sans(if (on) .medium else .regular, fonts.size.ui);
    defer gui.popFont();
    return px(12) * 2 + px(14) + px(6) + gui.textSize(label).x;
}

fn modeSwitchWidth(current: app_mod.Mode) f32 {
    var width = px(mode_switch_inset) * 2 + px(2) * (modes.len - 1);
    for (modes) |mode| width += modeButtonWidth(mode[1], mode[0] == current);
    return width;
}

/// The switch between Mod and Mission mode. Its buttons have IDs of their own, apart from the
/// menus of the same names beside them.
fn modeSwitch(app: *App) void {
    gui.pushId("mode");
    defer gui.popId();
    const width = modeSwitchWidth(app.mode);
    const height = px(mode_switch_height);
    const at = gui.cursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    gui.rect(list, at, max, theme.field, 5);
    gui.outline(list, at, max, theme.border, 5);
    var x = at.x + px(mode_switch_inset);
    const button_top = at.y + px(mode_switch_inset);
    const button_height = height - px(mode_switch_inset) * 2;
    const middle = at.y + height / 2;
    const off = app.unavailable(.switch_mode);
    for (modes) |mode| {
        const on = app.mode == mode[0];
        const button_width = modeButtonWidth(mode[1], on);
        gui.setCursor(.{ .x = x, .y = button_top });
        const pressed = c.ImGui_InvisibleButton(gui.z(mode[1]), .{ .x = button_width, .y = button_height }, 0);
        if (on) gui.rect(list, .{ .x = x, .y = button_top }, .{ .x = x + button_width, .y = button_top + button_height }, theme.border, 3);
        const disabled = !on and off != null;
        const foreground = if (on) theme.white else if (disabled) theme.text_off else theme.text_muted;
        widgets.drawIcon(list, .{ .x = x + px(12), .y = middle }, mode[2], fonts.size.icon_small, if (on and mode[0] == .mission) theme.accent else foreground);
        gui.sans(if (on) .medium else .regular, fonts.size.ui);
        gui.drawText(list, .{ .x = x + px(12) + px(14) + px(6), .y = gui.textTop(middle) }, foreground, mode[1]);
        gui.popFont();
        if (disabled) gui.tooltip(off.?.reason);
        if (pressed and !disabled and !on) app.run(.switch_mode);
        x += button_width + px(2);
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
    const row: ToolbarRow = .{ .top = top + px(toolbar_padding) };
    gui.setCursor(.{ .x = window_pos.x + px(10), .y = row.top });
    gui.pushVar2(c.ImGuiStyleVar_ItemSpacing, .{ .x = px(6), .y = px(6) });
    defer gui.popVar(1);

    const document = app.document;
    const title = if (document) |open| open.outline().name orelse if (open.number) |number| gui.print("Mission {d}", .{number}) else open.file else "No mission";
    const picker_tip = if (document) |open| gui.print("{s}, in the mod {s}", .{ open.file, if (app.project) |opened| opened.name else "" }) else null;
    row.centre(widgets.picker_height);
    if (widgets.picker("mission picker", title, theme.accent, picker_tip)) _ = c.ImGui_OpenPopup("missions", 0);
    missionMenu(app);

    row.next(6, widgets.view_tabs_height);
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
    row.next(6, widgets.divider_height);
    widgets.toolbarDivider();

    row.next(6, widgets.tool_button_height);
    const problem_count = if (document) |open| open.problems().len else 0;
    if (widgets.toolButton("build", .{
        .label = "Build",
        .icon = .hammer,
        .pill = if (problem_count > 0) .{ .text = gui.print("{d}", .{problem_count}), .style = .err } else null,
        .disabled = app.unavailable(.build),
        .tooltip = if (app.keyText(.build)) |key| gui.print("Build, {s}", .{key}) else "Build",
    })) app.run(.build);
    row.next(6, widgets.tool_button_height);
    if (widgets.toolButton("play", .{ .label = "Play in game", .icon = .play, .corners = .left, .disabled = app.unavailable(.play) })) app.run(.play);
    row.next(0, widgets.tool_button_height);
    if (widgets.toolButton("play from part", .{ .icon = .chevron_down, .icon_only = true, .corners = .right, .disabled = app.unavailable(.play_from_part), .tooltip = "Play from a part" })) app.run(.play_from_part);
    row.next(6, widgets.divider_height);
    widgets.toolbarDivider();
    row.next(6, widgets.tool_button_height);
    const held = app.held();
    if (widgets.toolButton("continue", .{
        .label = "Continue",
        .icon = .step_forward,
        .style = if (held) .primary else .normal,
        .weight = if (held) .semibold else .regular,
        .key = if (held) app.keyText(.@"continue") else null,
        .disabled = app.unavailable(.@"continue"),
    })) app.run(.@"continue");
    inline for (.{ .{ Command.step_over, ui.icons.Icon.redo_dot }, .{ Command.step_into, ui.icons.Icon.arrow_down_to_dot }, .{ Command.pause, ui.icons.Icon.pause }, .{ Command.unlink, ui.icons.Icon.square } }) |button| {
        row.next(6, widgets.tool_button_height);
        const tip = if (app.keyText(button[0])) |key| gui.print("{s}, {s}", .{ commands.info(button[0]).label, key }) else commands.info(button[0]).label;
        if (widgets.toolButton(@tagName(button[0]), .{ .icon = button[1], .icon_only = true, .disabled = app.unavailable(button[0]), .tooltip = tip })) app.run(button[0]);
    }

    // The chips, at the toolbar's end.
    var chips: [3]widgets.Chip = undefined;
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
    if (holdChip(app)) |chip| {
        chips[chip_count] = chip;
        chip_count += 1;
    }
    chips[chip_count] = linkChip(app);
    chip_count += 1;
    var total: f32 = 0;
    for (chips[0..chip_count]) |chip| total += widgets.chipWidth(chip) + px(8);
    gui.sameLine(0);
    const right = window_pos.x + width - px(10);
    const start = @max(gui.cursor().x + px(8), right - total + px(8));
    gui.setCursor(.{ .x = start, .y = row.top });
    row.centre(widgets.chip_height);
    for (chips[0..chip_count], 0..) |chip, index| {
        if (index > 0) row.next(8, widgets.chip_height);
        widgets.chip(chip);
    }
    gui.setCursor(.{ .x = window_pos.x, .y = top + px(toolbar_height) });
}

/// The chip of a held script, or a paused mission: where it holds, and the script's clock.
fn holdChip(app: *const App) ?widgets.Chip {
    const session = &app.session;
    const clock = if (session.state) |snapshot| gui.print("{d} s", .{snapshot.state.clock}) else null;
    if (session.held) |held| {
        const text = if (session.heldStatement()) |statement| gui.print("Held · line {d}", .{statement.at.line + 1}) else gui.print("Held · offset {d}", .{held.offset});
        return .{ .style = .held, .text = text, .extra = clock, .extra_mono = true, .tooltip = "Threads, timers, clock stopped · ships fly on" };
    }
    if (session.paused) return .{ .style = .held, .text = "Paused", .extra = clock, .extra_mono = true, .tooltip = "Whole mission paused" };
    return null;
}

/// The chip of the editor link: to OpenReliant, which names the game once it answers, then the
/// mission it plays.
pub fn linkChip(app: *const App) widgets.Chip {
    const session = &app.session;
    return switch (session.link_state) {
        .off => .{ .style = .idle, .text = "OpenReliant", .extra = "not linked", .tooltip = "Play links · or Game · Link to game" },
        .waiting => .{ .style = .idle, .text = "OpenReliant", .extra = "waiting", .tooltip = gui.print("127.0.0.1:{d}", .{session.port}) },
        .linked => linked: {
            const greeting = session.greeting.?;
            const tooltip = gui.print("OpenReliant {s} · 127.0.0.1:{d}", .{ greeting.openreliant, session.port });
            const playing = session.playing orelse break :linked .{ .style = .linked, .text = greeting.game, .extra = "linked", .tooltip = tooltip };
            if (session.held != null) break :linked .{ .style = .linked, .text = greeting.game, .tooltip = tooltip };
            break :linked switch (playing.match) {
                .older_build => .{ .style = .warning, .text = "Older build", .extra = "restart mission", .tooltip = "Rebuild, restart: each attempt rereads the file" },
                .this_build, .other_mission, .unknown => .{ .style = .linked, .text = greeting.game, .extra = gui.print("mission {d}", .{playing.number}), .tooltip = tooltip },
            };
        },
    };
}

/// The toolbar's row of controls, each centred on the row as the design's flex row centres them.
const ToolbarRow = struct {
    top: f32,

    /// Moves the cursor down for the next control, `height` design pixels high, to sit in the
    /// middle of the row.
    fn centre(row: ToolbarRow, height: f32) void {
        gui.setCursor(.{ .x = gui.cursor().x, .y = row.top + (px(toolbar_row) - px(height)) / 2 });
    }

    /// Puts the next control `gap` design pixels after the last one, in the middle of the row.
    fn next(row: ToolbarRow, gap: f32, height: f32) void {
        gui.sameLine(gap);
        row.centre(height);
    }
};

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
    const text_y = gui.textTop(middle);
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
    } else if (app.held() or app.session.paused) {
        const text = if (app.held()) "Held" else "Paused";
        gui.dot(list, .{ .x = x + px(3.5), .y = middle }, 3.5, theme.accent);
        x += px(7) + px(6);
        gui.drawText(list, .{ .x = x, .y = text_y }, theme.held_text, text);
        x += gui.textSize(text).x + gap;
    }
    const cursor = document.editor.cursor();
    // The Scene view shows the map and the place under the pointer instead of the cursor.
    const where = if (app.view == .scene) scene_view.status() else gui.print("Ln {d}, Col {d}", .{ cursor.line + 1, cursor.index + 1 });
    for ([_][]const u8{ document.file, where, keyHints(app) }) |part| {
        gui.drawText(list, .{ .x = x, .y = text_y }, theme.text_muted, part);
        x += gui.textSize(part).x + gap;
    }

    // At the end: the last build, and live changes.
    var right = window_pos.x + width - px(10);
    const live = if (app.session.link_state == .off) "Live changes: not linked" else "Live changes: planned";
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
    if (app.held()) {
        return gui.print("{s} continue · {s} step over · {s} step into · {s}", .{ app.keyText(.@"continue") orelse "", app.keyText(.step_over) orelse "", app.keyText(.step_into) orelse "", views_hint });
    }
    return gui.print("{s} build · {s} breakpoint · {s}", .{ app.keyText(.build) orelse "", app.keyText(.toggle_breakpoint) orelse "", views_hint });
}

/// The full layout: the outline on the left, the source in the middle with the debugging panels
/// under it, and the inspector on the right, as the design shows them: the outline 250 pixels wide,
/// the inspector 310, the debugging panels 250 high and the variables 300 wide, their lines
/// included. The source is the dock space's central node, which takes what the window gains.
pub fn fullLayout(dockspace: c.ImGuiID, size: gui.Vec2) void {
    c.or_dock_builder_reset(dockspace, size.x, size.y);
    var left: c.ImGuiID = 0;
    var rest: c.ImGuiID = 0;
    _ = c.or_dock_builder_split(dockspace, c.ImGuiDir_Left, share(250, size.x), &left, &rest);
    const rest_width = size.x - between() - inside(250);
    var right: c.ImGuiID = 0;
    var middle: c.ImGuiID = 0;
    _ = c.or_dock_builder_split(rest, c.ImGuiDir_Right, share(310, rest_width), &right, &middle);
    const middle_width = rest_width - between() - inside(310);
    var bottom: c.ImGuiID = 0;
    var source: c.ImGuiID = 0;
    _ = c.or_dock_builder_split(middle, c.ImGuiDir_Down, share(250, size.y), &bottom, &source);
    var bottom_right: c.ImGuiID = 0;
    var bottom_left: c.ImGuiID = 0;
    _ = c.or_dock_builder_split(bottom, c.ImGuiDir_Right, share(300, middle_width), &bottom_right, &bottom_left);
    for ([_]Panel{ .mission, .find }) |panel| c.or_dock_builder_dock_window(panel.title(), left);
    c.or_dock_builder_dock_window(Panel.source.title(), source);
    for ([_]Panel{ .threads, .breakpoints, .output, .problems }) |panel| c.or_dock_builder_dock_window(panel.title(), bottom_left);
    for ([_]Panel{ .variables, .watch }) |panel| c.or_dock_builder_dock_window(panel.title(), bottom_right);
    for ([_]Panel{ .inspector, .reference, .live_scene }) |panel| c.or_dock_builder_dock_window(panel.title(), right);
    c.or_dock_builder_finish(dockspace);
}

/// The room between two dock nodes: the panels' lines and the gap between them.
fn between() f32 {
    return px(theme.panel_gap + theme.panel_line * 2);
}

/// The inside of a panel `length` design pixels long, its lines left out: its dock node's length.
fn inside(length: f32) f32 {
    return px(length - theme.panel_line * 2);
}

/// The share of a dock node `total` long that a split gives the child at its side, for a panel
/// `length` design pixels long there: the dock builder splits what the room between them leaves.
fn share(length: f32, total: f32) f32 {
    return inside(length) / (total - between());
}
