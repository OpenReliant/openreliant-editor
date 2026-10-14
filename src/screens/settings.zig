//! The settings: the Keys page sets every action's keys on Windows and Linux and on macOS side by
//! side, the current system's in front, and the Game page where the game and `openreliant` are.

const std = @import("std");
const c = @import("c");

const app_mod = @import("../app.zig");
const App = app_mod.App;
const SettingsPage = app_mod.SettingsPage;
const commands = @import("../commands.zig");
const Command = commands.Command;
const keys = @import("../keys.zig");
const shell = @import("../shell.zig");
const ui = @import("../ui.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const Icon = ui.icons.Icon;
const theme = ui.theme;
const widgets = ui.widgets;
const px = gui.px;

/// The width of the navigation, and of the panel of notes on the Keys page.
const nav_width = 218;
const notes_width = 300;

const Find = struct {
    var text: [64:0]u8 = @splat(0);
};

/// The action whose keys are being set, for the system shown in front, and the keys the page asks
/// for.
var capturing: ?Command = null;

pub fn draw(app: *App) void {
    const viewport = c.ImGui_GetMainViewport();
    c.ImGui_SetNextWindowPos(viewport.*.WorkPos, 0);
    c.ImGui_SetNextWindowSize(viewport.*.WorkSize, 0);
    gui.pushVar(c.ImGuiStyleVar_WindowRounding, 0);
    gui.pushVar(c.ImGuiStyleVar_WindowBorderSize, 0);
    gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
    gui.pushVar2(c.ImGuiStyleVar_FramePadding, .{ .x = px(9), .y = (px(34) - px(fonts.size.ui * fonts.em.sans)) / 2 });
    gui.pushColor(c.ImGuiCol_WindowBg, theme.ground);
    gui.pushColor(c.ImGuiCol_MenuBarBg, theme.bar);
    gui.sans(.regular, fonts.size.ui);
    _ = c.ImGui_Begin("settings", null, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoSavedSettings | c.ImGuiWindowFlags_NoBringToFrontOnFocus | c.ImGuiWindowFlags_NoDocking | c.ImGuiWindowFlags_MenuBar);
    gui.popFont();
    gui.popColor(2);
    gui.popVar(4);
    defer c.ImGui_End();
    if (capturing == null) app.shortcuts();
    shell.menuBar(app, .settings);
    if (capturing == null and c.ImGui_IsKeyPressed(c.ImGuiKey_Escape)) app.screen = if (app.document != null) .workspace else .start;

    const pos = c.ImGui_GetWindowPos();
    const size = c.ImGui_GetWindowSize();
    const top = gui.cursor().y + px(3);
    const bottom = pos.y + size.y - px(24);
    const height = bottom - top - px(3);
    const notes = app.settings_page == .keys;
    const content_left = pos.x + px(3) + px(nav_width) + px(3);
    const content_right = pos.x + size.x - px(3) - (if (notes) px(notes_width) + px(3) else 0);

    panel("nav", .{ .x = pos.x + px(3), .y = top }, .{ .x = px(nav_width), .y = height });
    navigation(app);
    c.ImGui_EndChild();

    panel("page", .{ .x = content_left, .y = top }, .{ .x = content_right - content_left, .y = height });
    switch (app.settings_page) {
        .keys => keysPage(app),
        .game => gamePage(app),
        .general, .appearance, .editor_link => plannedPage(app.settings_page),
    }
    c.ImGui_EndChild();

    if (notes) {
        panel("notes", .{ .x = content_right + px(3), .y = top }, .{ .x = px(notes_width), .y = height });
        keyNotes();
        c.ImGui_EndChild();
    }
    statusBar(app, bottom, pos.x, size.x);
}

/// A panel of the page: the design's `.panel`, a dark box with a line around it.
fn panel(id: [:0]const u8, at: gui.Vec2, size: gui.Vec2) void {
    gui.setCursor(at);
    const list = c.ImGui_GetWindowDrawList();
    gui.rect(list, at, gui.add(at, size), theme.panel, 3);
    gui.outline(list, at, gui.add(at, size), theme.divider, 3);
    _ = c.ImGui_BeginChild(id, size, 0, 0);
}

fn navigation(app: *App) void {
    gui.setCursor(gui.add(gui.cursor(), .{ .x = px(12), .y = px(14) }));
    widgets.caption("Settings", theme.text_strong, 16, .semibold);
    gui.space(10);
    const pages = [_]struct { SettingsPage, []const u8 }{
        .{ .general, "General" },
        .{ .appearance, "Appearance" },
        .{ .keys, "Keys" },
        .{ .game, "Game" },
        .{ .editor_link, "Editor link" },
    };
    for (pages) |page| {
        const at = gui.cursor();
        gui.setCursor(.{ .x = c.ImGui_GetWindowPos().x + px(8), .y = at.y });
        const width = gui.available().x - px(8);
        const height = px(30);
        const item = gui.cursor();
        if (c.ImGui_InvisibleButton(gui.z(page[1]), .{ .x = width, .y = height }, 0)) {
            app.settings_page = page[0];
            capturing = null;
        }
        const on = app.settings_page == page[0];
        const list = gui.drawList();
        if (on) gui.rect(list, item, .{ .x = item.x + width, .y = item.y + height }, theme.border, 4) else if (gui.hovered()) gui.rect(list, item, .{ .x = item.x + width, .y = item.y + height }, theme.row_hover, 4);
        gui.sans(.regular, fonts.size.body);
        gui.drawText(list, .{ .x = item.x + px(12), .y = item.y + (height - c.ImGui_GetFontSize()) / 2 }, if (on) theme.white else theme.text_menu, page[1]);
        gui.popFont();
        gui.setCursor(.{ .x = at.x, .y = item.y + height + px(2) });
    }
    c.ImGui_Dummy(.{ .x = 0, .y = 0 });
}

fn plannedPage(page: SettingsPage) void {
    gui.setCursor(gui.add(gui.cursor(), .{ .x = px(14), .y = px(14) }));
    widgets.caption(switch (page) {
        .general => "General",
        .appearance => "Appearance",
        .editor_link => "Editor link",
        else => "",
    }, theme.text_strong, 15, .semibold);
    gui.space(6);
    widgets.caption(gui.print("Planned · {f}", .{if (page == .editor_link) commands.plans.debugger else commands.plans.settings}), theme.text_dim, fonts.size.small, .regular);
}

fn gamePage(app: *App) void {
    const left = gui.cursor().x + px(14);
    gui.setCursor(.{ .x = left, .y = gui.cursor().y + px(14) });
    widgets.caption("Game", theme.text_strong, 15, .semibold);
    widgets.caption(gui.print("{s}'s folder, and the OpenReliant that plays it", .{app.profile.name}), theme.text_dim, fonts.size.small, .regular);
    gui.space(18);
    gui.setCursor(.{ .x = left, .y = gui.cursor().y });
    widgets.sectionHeading("Game folder");
    gui.space(8);
    gui.setCursor(.{ .x = left, .y = gui.cursor().y });
    widgets.monoCaption(app.settings.game_folder orelse "Not set", if (app.settings.game_folder != null) theme.text else theme.text_dim, fonts.size.ui, .regular);
    gui.space(6);
    gui.setCursor(.{ .x = left, .y = gui.cursor().y });
    if (widgets.toolButton("change folder", .{ .label = "Change…", .icon = .folder_open })) app.chooseFolder(.game_folder);
    gui.space(4);
    widgets.caption("Holds resource.hog and the mods folder", theme.text_dim, fonts.size.small, .regular);
    gui.space(18);
    gui.setCursor(.{ .x = left, .y = gui.cursor().y });
    widgets.sectionHeading("OpenReliant");
    gui.space(8);
    gui.setCursor(.{ .x = left, .y = gui.cursor().y });
    var arena: std.heap.ArenaAllocator = .init(app.gpa);
    defer arena.deinit();
    const found = app.findOpenReliant(arena.allocator());
    widgets.monoCaption(found, theme.text, fonts.size.ui, .regular);
    gui.space(4);
    gui.setCursor(.{ .x = left, .y = gui.cursor().y });
    widgets.caption(if (app.settings.openreliant != null) "Set here" else "Found beside the editor or the game folder, or on the system's path", theme.text_dim, fonts.size.small, .regular);
    gui.space(6);
    gui.setCursor(.{ .x = left, .y = gui.cursor().y });
    if (widgets.toolButton("change program", .{ .label = "Change…", .icon = .folder_open })) app.chooseProgram();
    if (app.settings.openreliant != null) {
        gui.sameLine(6);
        if (widgets.toolButton("find program", .{ .label = "Find by itself" })) {
            app.settings.openreliant = null;
            app.settings.save(app.io);
        }
    }
}

/// The Keys page: every action's keys on both systems, with the current one in front.
fn keysPage(app: *App) void {
    const page_left = gui.cursor().x;
    const width = gui.available().x;
    // The heading, the search, the system in front, and Reset and Export.
    gui.setCursor(.{ .x = page_left + px(14), .y = gui.cursor().y + px(10) });
    c.ImGui_BeginGroup();
    widgets.caption("Keys", theme.text_strong, 15, .semibold);
    widgets.caption("Defaults follow each system", theme.text_dim, fonts.size.small, .regular);
    c.ImGui_EndGroup();
    gui.sameLine(16);
    const row_y = gui.cursor().y + px(4);
    gui.setCursor(.{ .x = gui.cursor().x, .y = row_y });
    widgets.searchField("##find keys", &Find.text, "Find an action or a key", px(240), 28, true);
    gui.sameLine(10);
    gui.setCursor(.{ .x = gui.cursor().x, .y = row_y + px(6) });
    widgets.caption("This system", theme.text_muted, fonts.size.small, .regular);
    gui.sameLine(8);
    gui.setCursor(.{ .x = gui.cursor().x, .y = row_y - px(1) });
    systemSwitch(app);
    const buttons_x = page_left + width - px(14) - px(60) - px(6) - px(66);
    gui.setCursor(.{ .x = buttons_x, .y = row_y });
    if (widgets.toolButton("reset", .{ .label = "Reset", .disabled = if (app.settings.keymap.changedCount(app.keys_system) == 0) .{ .reason = "No keys changed" } else null })) {
        app.settings.keymap.reset(app.keys_system);
        app.settings.saveKeys(app.io);
    }
    gui.sameLine(6);
    if (widgets.toolButton("export", .{ .label = "Export", .tooltip = "Copy keys.ini" })) exportKeys(app);
    gui.setCursor(.{ .x = page_left, .y = row_y + px(36) });
    widgets.rule(theme.table_line);

    // The columns: the action, Windows and Linux, macOS, and the pencil.
    const columns = [_]f32{ 0.40, 0.25, 0.25 };
    const head_at = gui.cursor();
    const list = gui.drawList();
    const head_height = px(30);
    gui.rect(list, head_at, .{ .x = head_at.x + width, .y = head_at.y + head_height }, theme.table_head, 0);
    gui.rect(list, .{ .x = head_at.x, .y = head_at.y + head_height - px(1) }, .{ .x = head_at.x + width, .y = head_at.y + head_height }, theme.table_head_line, 0);
    gui.sans(.medium, fonts.size.ui);
    const head_y = head_at.y + (head_height - c.ImGui_GetFontSize()) / 2;
    gui.drawText(list, .{ .x = head_at.x + px(14), .y = head_y }, theme.text_dim, "Action");
    var x = head_at.x + px(14) + width * columns[0];
    for ([_]keys.System{ .windows_linux, .macos }) |system| {
        gui.drawText(list, .{ .x = x, .y = head_y }, if (system == app.keys_system) theme.text_strong else theme.text_dim, system.label());
        x += width * columns[1];
    }
    gui.popFont();
    c.ImGui_Dummy(.{ .x = width, .y = head_height });

    _ = c.ImGui_BeginChild("keys", .{ .x = 0, .y = 0 }, 0, 0);
    defer c.ImGui_EndChild();
    const find = std.mem.sliceTo(&Find.text, 0);
    for (std.enums.values(commands.KeyGroup)) |group| {
        var any = false;
        for (std.enums.values(Command)) |command| {
            if (!listed(app, command, group, find)) continue;
            if (!any) {
                groupHeading(group);
                any = true;
            }
            keyRow(app, command, width, columns);
        }
    }
    captureKeys(app);
}

/// Whether the Keys page lists `command` in `group`, given the search.
fn listed(app: *App, command: Command, group: commands.KeyGroup, find: []const u8) bool {
    const known = commands.info(command);
    if (known.key_group != group) return false;
    // The views show as one row.
    if (command == .view_2 or command == .view_3 or command == .view_4) return false;
    if (find.len == 0) return true;
    if (std.ascii.findIgnoreCase(rowLabel(command), find) != null) return true;
    for ([_]keys.System{ .windows_linux, .macos }) |system| {
        for (app.settings.keymap.chords(command, system)) |chord| {
            if (std.ascii.findIgnoreCase(gui.print("{f}", .{chord.written(system)}), find) != null) return true;
        }
    }
    return false;
}

fn rowLabel(command: Command) []const u8 {
    return if (command == .view_1) "Views 1 to 4" else commands.info(command).label;
}

fn groupHeading(group: commands.KeyGroup) void {
    const at = gui.cursor();
    gui.setCursor(.{ .x = at.x + px(14), .y = at.y + px(14) });
    widgets.sectionHeading(group.label());
    gui.setCursor(.{ .x = at.x, .y = gui.cursor().y + px(6) });
    widgets.rule(theme.table_head_line);
}

fn keyRow(app: *App, command: Command, width: f32, columns: [3]f32) void {
    const at = gui.cursor();
    const height = px(32);
    gui.pushId(@tagName(command));
    defer gui.popId();
    c.ImGui_Dummy(.{ .x = width, .y = height });
    const list = gui.drawList();
    gui.rect(list, .{ .x = at.x, .y = at.y + height - px(1) }, .{ .x = at.x + width, .y = at.y + height }, theme.table_line, 0);
    const middle = at.y + height / 2;
    const keymap = &app.settings.keymap;
    const windows = keymap.chords(command, .windows_linux);
    const macos = keymap.chords(command, .macos);
    if (keys.differBeyondModifier(windows, macos)) gui.dot(list, .{ .x = at.x + px(17), .y = middle }, 3, theme.accent);
    gui.sans(.regular, fonts.size.ui);
    gui.drawText(list, .{ .x = at.x + px(29), .y = middle - c.ImGui_GetFontSize() / 2 }, theme.text_row, rowLabel(command));
    gui.popFont();
    var x = at.x + px(14) + width * columns[0];
    for ([_]keys.System{ .windows_linux, .macos }) |system| {
        const chords = keymap.chords(command, system);
        const front = system == app.keys_system;
        if (capturing == command and front) {
            gui.sans(.regular, fonts.size.small);
            gui.drawText(list, .{ .x = x, .y = middle - c.ImGui_GetFontSize() / 2 }, theme.accent, "Press keys · Esc cancels · Backspace clears");
            gui.popFont();
        } else if (chords.len == 0) {
            gui.sans(.regular, fonts.size.small);
            gui.drawText(list, .{ .x = x, .y = middle - c.ImGui_GetFontSize() / 2 }, theme.text_off, "none");
            gui.popFont();
        } else {
            var chip_x = x;
            for (chords[0..1]) |chord| {
                const text = if (command == .view_1) gui.print("{f} to 4", .{chord.written(system)}) else gui.print("{f}", .{chord.written(system)});
                chip_x += bigKey(list, .{ .x = chip_x, .y = middle }, text, front) + px(6);
            }
            if (keymap.isChanged(command, system)) {
                gui.dot(list, .{ .x = chip_x + px(3), .y = middle }, 2.5, theme.text_menu);
            }
        }
        x += width * columns[1];
    }
    // The pencil sets the keys of the system in front.
    defer gui.setCursor(.{ .x = at.x, .y = at.y + height });
    if (command == .view_1) return;
    gui.setCursor(.{ .x = at.x + width - px(14) - px(26), .y = at.y + px(3) });
    const edit_at = gui.cursor();
    if (c.ImGui_InvisibleButton("edit", .{ .x = px(26), .y = px(26) }, 0)) capturing = command;
    gui.handCursor();
    widgets.drawIcon(list, .{ .x = edit_at.x + px(6), .y = edit_at.y + px(13) }, .pencil, fonts.size.icon_small, if (gui.hovered()) theme.text else theme.text_dim);
    gui.tooltip(gui.print("Set the keys on {s}", .{app.keys_system.label()}));
}

/// The Keys page's larger key chip, `.key` on that page: a raised key. Its width.
fn bigKey(list: *c.ImDrawList, middle: gui.Vec2, text: []const u8, front: bool) f32 {
    gui.mono(.medium, fonts.size.smaller);
    defer gui.popFont();
    const width = gui.textSize(text).x + px(6) * 2 + px(2);
    const height = px(20);
    const min = gui.vec2(middle.x, middle.y - height / 2);
    const max = gui.vec2(middle.x + width, middle.y + height / 2);
    gui.rect(list, min, max, theme.bar, 4);
    gui.outline(list, min, max, theme.key_border, 4);
    gui.rect(list, .{ .x = min.x + px(1), .y = max.y - px(2) }, .{ .x = max.x - px(1), .y = max.y - px(1) }, theme.key_border, 0);
    gui.drawText(list, .{ .x = min.x + px(7), .y = middle.y - c.ImGui_GetFontSize() / 2 - px(1) }, if (front) theme.text_button else theme.text_dim, text);
    return width;
}

/// Reads the keys pressed while an action's keys are being set.
fn captureKeys(app: *App) void {
    const command = capturing orelse return;
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_Escape)) {
        capturing = null;
        return;
    }
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_Backspace)) {
        app.settings.keymap.set(command, app.keys_system, &.{});
        app.settings.saveKeys(app.io);
        capturing = null;
        return;
    }
    const io = c.ImGui_GetIO();
    var key_index: c.ImGuiKey = c.ImGuiKey_NamedKey_BEGIN;
    while (key_index < c.ImGuiKey_NamedKey_END) : (key_index += 1) {
        if (!c.ImGui_IsKeyPressed(key_index)) continue;
        const key = keys.Key.fromImgui(key_index) orelse continue;
        const chord: keys.Chord = .{ .key = key, .primary = io.*.KeyCtrl, .shift = io.*.KeyShift, .alt = io.*.KeyAlt, .secondary = io.*.KeySuper };
        const kept = app.settings.arena.allocator().dupe(keys.Chord, &.{chord}) catch return;
        app.settings.keymap.set(command, app.keys_system, kept);
        app.settings.saveKeys(app.io);
        capturing = null;
        return;
    }
}

fn exportKeys(app: *App) void {
    var buffer: [32 * 1024]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buffer);
    for (std.enums.values(keys.System)) |system| {
        out.print("[{s}]\n", .{system.section()}) catch return;
        for (std.enums.values(Command)) |command| {
            const chords = app.settings.keymap.chords(command, system);
            if (chords.len == 0) continue;
            out.print("{t}=", .{command}) catch return;
            for (chords, 0..) |chord, index| out.print("{s}{f}", .{ if (index == 0) "" else ", ", chord.written(system) }) catch return;
            out.writeByte('\n') catch return;
        }
        out.writeByte('\n') catch return;
    }
    out.writeByte(0) catch return;
    _ = c.SDL_SetClipboardText(@ptrCast(out.buffered().ptr));
    app.toasts.push(.success, "Keys copied", "Every action's keys on both systems, as keys.ini writes them");
}

/// The switch between the systems, the one in front lit.
fn systemSwitch(app: *App) void {
    gui.sans(.regular, fonts.size.ui);
    defer gui.popFont();
    const at = gui.cursor();
    var width = px(2);
    for (std.enums.values(keys.System)) |system| width += gui.textSize(system.label()).x + px(12) * 2 + px(2);
    const height = px(28);
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.field, 5);
    gui.outline(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.border, 5);
    var x = at.x + px(2);
    for (std.enums.values(keys.System)) |system| {
        const item_width = gui.textSize(system.label()).x + px(12) * 2;
        gui.setCursor(.{ .x = x, .y = at.y + px(2) });
        if (c.ImGui_InvisibleButton(gui.z(system.label()), .{ .x = item_width, .y = px(24) }, 0)) {
            app.keys_system = system;
            capturing = null;
        }
        const on = app.keys_system == system;
        if (on) gui.rect(list, .{ .x = x, .y = at.y + px(2) }, .{ .x = x + item_width, .y = at.y + px(26) }, theme.border, 3);
        gui.drawText(list, .{ .x = x + px(12), .y = at.y + (height - c.ImGui_GetFontSize()) / 2 }, if (on) theme.white else theme.text_muted, system.label());
        x += item_width + px(2);
    }
    gui.setCursor(at);
    c.ImGui_Dummy(.{ .x = width, .y = height });
}

/// The notes beside the keys: how the systems' keys differ, and where changed keys are kept.
fn keyNotes() void {
    const left = gui.cursor().x + px(12);
    gui.setCursor(.{ .x = left, .y = gui.cursor().y + px(16) });
    const at = gui.cursor();
    gui.dot(gui.drawList(), .{ .x = at.x + px(3), .y = at.y + px(9) }, 3, theme.accent);
    gui.setCursor(.{ .x = at.x + px(14), .y = at.y });
    widgets.caption("Differs beyond Cmd for Ctrl", theme.text, fonts.size.ui, .regular);
    noteSection(left, "macOS", &.{
        .{ "Modifier", "Cmd for Ctrl" },
        .{ "Debugging", "Xcode's keys" },
        .{ "F11", "Show Desktop · left free" },
        .{ "F-keys", "Media keys by default · fn+F6" },
        .{ "Text", "Option+arrows: words · Cmd+arrows: line ends" },
    });
    noteSection(left, "Windows, Linux", &.{
        .{ "Debugging", "Visual Studio's keys" },
        .{ "Quit", "Alt+F4 · Linux also Ctrl+Q" },
        .{ "Text", "Ctrl+arrows: words · Home, End" },
    });
    gui.setCursor(.{ .x = left, .y = gui.cursor().y + px(18) });
    const box_at = gui.cursor();
    const box_width = gui.available().x - px(12);
    const list = gui.drawList();
    const box_height = px(84);
    gui.rect(list, box_at, .{ .x = box_at.x + box_width, .y = box_at.y + box_height }, theme.panel, 6);
    gui.outline(list, box_at, .{ .x = box_at.x + box_width, .y = box_at.y + box_height }, theme.border, 6);
    gui.setCursor(.{ .x = box_at.x + px(12), .y = box_at.y + px(12) });
    widgets.sectionHeading("Saved in");
    gui.setCursor(.{ .x = box_at.x + px(12), .y = gui.cursor().y + px(4) });
    widgets.monoCaption("keys.ini", theme.text, fonts.size.ui, .regular);
    gui.setCursor(.{ .x = box_at.x + px(12), .y = gui.cursor().y + px(2) });
    widgets.caption("Per system · changed keys only", theme.text_dim, fonts.size.small, .regular);
}

fn noteSection(left: f32, heading: []const u8, rows: []const [2][]const u8) void {
    gui.setCursor(.{ .x = left, .y = gui.cursor().y + px(16) });
    widgets.sectionHeading(heading);
    gui.space(6);
    for (rows) |row| {
        gui.setCursor(.{ .x = left, .y = gui.cursor().y });
        const at = gui.cursor();
        widgets.caption(row[0], theme.text_muted, fonts.size.ui, .regular);
        gui.setCursor(.{ .x = at.x + px(102), .y = at.y });
        gui.wrapAt(c.ImGui_GetWindowPos().x + c.ImGui_GetWindowWidth() - px(12));
        widgets.caption(row[1], theme.text, fonts.size.ui, .regular);
        c.ImGui_PopTextWrapPos();
        gui.space(4);
    }
}

fn statusBar(app: *App, top: f32, left: f32, width: f32) void {
    const list = c.ImGui_GetWindowDrawList();
    gui.rect(list, .{ .x = left, .y = top }, .{ .x = left + width, .y = top + px(24) }, theme.bar, 0);
    gui.rect(list, .{ .x = left, .y = top }, .{ .x = left + width, .y = top + px(1) }, theme.divider, 0);
    gui.sans(.regular, fonts.size.smaller);
    defer gui.popFont();
    const y = top + (px(24) - c.ImGui_GetFontSize()) / 2;
    const system = app.keys_system;
    const first = gui.print("Key map · {s} defaults", .{if (system == .macos) "macOS" else "Windows and Linux"});
    gui.drawText(list, .{ .x = left + px(10), .y = y }, theme.text_muted, first);
    gui.drawText(list, .{ .x = left + px(10) + gui.textSize(first).x + px(16), .y = y }, theme.text_muted, gui.print("{d} changed", .{app.settings.keymap.changedCount(system)}));
    const conflict = app.settings.keymap.conflict(system);
    const end = if (conflict) |pair| gui.print("Conflict: {s} and {s}", .{ commands.info(pair[0]).label, commands.info(pair[1]).label }) else "No conflicts";
    gui.drawText(list, .{ .x = left + width - px(10) - gui.textSize(end).x, .y = y }, if (conflict != null) theme.error_text else theme.text_muted, end);
}
