//! The start screen: the guided first mission, a new mission or mod, a game mission to change, the
//! mods in the game's `mods` folder, the game, and the guides.

const std = @import("std");
const c = @import("c");

const app_mod = @import("../app.zig");
const App = app_mod.App;
const commands = @import("../commands.zig");
const shell = @import("../shell.zig");
const ui = @import("../ui.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const Icon = ui.icons.Icon;
const theme = ui.theme;
const widgets = ui.widgets;
const px = gui.px;

/// The widest the screen's content gets, and its gaps.
const max_width = 1240;

const Filter = struct {
    var text: [64:0]u8 = @splat(0);
};

pub fn draw(app: *App) void {
    shell.beginScreen("start", .start, theme.fade(theme.bar, 0.85));
    defer c.ImGui_End();
    sky();
    app.shortcuts();
    shell.menuBar(app, .start);

    // The page is at most 1240 pixels wide, with 16 pixels of padding to each side inside that.
    const window_pos = c.ImGui_GetWindowPos();
    const window_width = c.ImGui_GetWindowWidth();
    const width = @min(window_width, px(max_width)) - px(16) * 2;
    const left = window_pos.x + (window_width - width) / 2;
    _ = c.ImGui_BeginChild("page", .{ .x = 0, .y = 0 }, 0, 0);
    defer c.ImGui_EndChild();
    // The page gives each gap itself, as the design does.
    gui.pushVar2(c.ImGuiStyleVar_ItemSpacing, .{ .x = 0, .y = 0 });
    defer gui.popVar(1);
    const top = gui.cursor().y + px(44);

    // The heading, in Newtown at 60 pixels spaced 0.02 em, in a line as high as its letters; 8
    // pixels under it, the line under it, at 16 pixels in a line of 24; and 34 before the cards.
    const list = gui.drawList();
    const heading_size = 60;
    gui.brand(heading_size);
    const heading_y = gui.textTopIn(top + px(heading_size) / 2, heading_size);
    var x = left;
    x += gui.drawSpaced(list, .{ .x = x, .y = heading_y }, theme.text, "OPEN", 0.02 * heading_size);
    x += gui.drawSpaced(list, .{ .x = x, .y = heading_y }, theme.accent, "RELIANT", 0.02 * heading_size);
    _ = gui.drawSpaced(list, .{ .x = x, .y = heading_y }, theme.text, " EDITOR", 0.02 * heading_size);
    gui.popFont();
    const line_top = top + px(heading_size) + px(8);
    gui.sans(.regular, 16);
    gui.drawText(list, .{ .x = left, .y = gui.textTopIn(line_top + px(24) / 2, 24) }, theme.text_menu, gui.print("Missions and mods for {s} · every change live in the game", .{app.profile.name}));
    gui.popFont();
    gui.setCursor(.{ .x = left, .y = top });
    c.ImGui_Dummy(.{ .x = width, .y = line_top + px(24) - top });
    gui.setCursor(.{ .x = left, .y = line_top + px(24) + px(34) });

    // Two columns, 480 and 420 pixels wide and sharing the room left over, or one under the other
    // where they don't fit.
    const gap = px(28);
    const bases = [2]f32{ px(480), px(420) };
    const two = bases[0] + gap + bases[1] <= width;
    const share = (width - gap - bases[0] - bases[1]) / 2;
    const left_width = if (two) bases[0] + share else width;
    const right_width = if (two) bases[1] + share else width;
    const row_top = gui.cursor().y;
    gui.setCursor(.{ .x = left, .y = row_top });
    c.ImGui_BeginGroup();
    startSomething(app, left_width);
    c.ImGui_EndGroup();
    const left_bottom = gui.cursor().y;
    if (two) gui.setCursor(.{ .x = left + left_width + gap, .y = row_top }) else gui.setCursor(.{ .x = left, .y = left_bottom + gap });
    c.ImGui_BeginGroup();
    yourMods(app, right_width);
    c.ImGui_EndGroup();
    const right_bottom = gui.cursor().y;

    const second_top = @max(left_bottom, right_bottom) + px(34);
    gui.setCursor(.{ .x = left, .y = second_top });
    c.ImGui_BeginGroup();
    gameBox(app, left_width);
    c.ImGui_EndGroup();
    if (two) gui.setCursor(.{ .x = left + left_width + gap, .y = second_top }) else gui.setCursor(.{ .x = left, .y = gui.cursor().y + gap });
    c.ImGui_BeginGroup();
    learn();
    c.ImGui_EndGroup();
    gui.space(32);
}

/// The sky behind the start screen: a few stars, an orange glow at the top right and a blue one at
/// the bottom left.
fn sky() void {
    const list = c.ImGui_GetWindowDrawList();
    const pos = c.ImGui_GetWindowPos();
    const size = c.ImGui_GetWindowSize();
    glow(list, .{ .x = pos.x + size.x * 0.85, .y = pos.y - size.y * 0.1 }, size.x * 0.55, theme.rgb(0x2a160a));
    glow(list, .{ .x = pos.x - size.x * 0.1, .y = pos.y + size.y * 1.1 }, size.x * 0.5, theme.rgb(0x0d1631));
    for ([_][3]f32{ .{ 0.12, 0.18, 0.5 }, .{ 0.72, 0.09, 0.4 }, .{ 0.38, 0.62, 0.3 }, .{ 0.88, 0.44, 0.45 }, .{ 0.25, 0.80, 0.35 } }) |star| {
        gui.dot(list, .{ .x = pos.x + size.x * star[0], .y = pos.y + size.y * star[1] }, 0.8, theme.fade(theme.white, star[2]));
    }
}

/// A soft round glow of `color` around `center`, fading out at `radius`.
fn glow(list: *c.ImDrawList, center: gui.Vec2, radius: f32, color: theme.Color) void {
    const steps = 24;
    var step: usize = steps;
    while (step > 0) : (step -= 1) {
        const share = @as(f32, @floatFromInt(step)) / steps;
        c.ImDrawList_AddCircleFilled(list, center, radius * share, theme.fade(color, 0.09), 64);
    }
}

/// The ways to start: the guided first mission, a new mission, a game mission, a new mod, and
/// opening a folder.
fn startSomething(app: *App, width: f32) void {
    if (card("guided", .{
        .width = width,
        .title = "Your first mission, guided",
        .detail = "From an empty map to playing it",
        .icon = .flag,
        .tile = theme.accent,
        .tile_icon = theme.on_accent,
        .featured = true,
        .disabled = app.unavailable(.layout_guided),
    })) app.run(.layout_guided);
    gui.space(10);
    const half = (width - px(10)) / 2;
    const row_top = gui.cursor();
    var new_mission: Card = .{ .width = half, .title = "New mission", .detail = "Empty mission · Mission mode", .icon = .plus, .tile = theme.rgb(0x1d1530), .tile_icon = theme.syntax.game, .disabled = app.unavailable(.new_mission) };
    var game_mission: Card = .{ .width = half, .title = "Edit a game mission", .detail = "Decompile into a new mod · replaces it by name", .icon = .file_code, .tile = theme.rgb(0x12203a), .tile_icon = theme.syntax.keyword, .disabled = app.unavailable(.edit_game_mission) };
    // The cards of a row are as high as each other.
    const row_height = @max(cardHeight(new_mission), cardHeight(game_mission));
    new_mission.height = row_height;
    game_mission.height = row_height;
    if (card("new mission", new_mission)) app.run(.new_mission);
    gui.setCursor(.{ .x = row_top.x + half + px(10), .y = row_top.y });
    if (card("game mission", game_mission)) app.run(.edit_game_mission);
    gui.setCursor(.{ .x = row_top.x, .y = gui.cursor().y + px(10) });
    newMod(app, width);
    gui.space(10);
    const open = commands.info(.open_file);
    if (chipButton("open", open.label, open.icon, app.keyText(.open_file), null)) app.run(.open_file);
    gui.sameLine(8);
    if (chipButton("open hog", "Open .hog, read only", .box, null, app.unavailable(.open_hog))) app.run(.open_hog);
}

const Card = struct {
    width: f32,
    title: []const u8,
    detail: []const u8,
    icon: Icon,
    tile: theme.Color,
    tile_icon: theme.Color,
    featured: bool = false,
    disabled: ?widgets.Disabled = null,
    /// The card's height, where it's set by its row; its own otherwise.
    height: ?f32 = null,
};

/// The design's card, `.act`: in its line, a tile with the icon, 12 pixels, then the title and the
/// detail under it, 2 pixels apart, and a chevron after them on the featured card.
const CardLayout = struct {
    tile: f32,
    padding: gui.Vec2,
    text_x: f32,
    text_width: f32,
    title_size: f32,
    /// The title's line, and each of the detail's.
    title_line: f32,
    detail_line: f32,
    detail_lines: usize,

    /// The detail's size, and its lines' height in ems.
    const detail_size = fonts.size.ui;
    const detail_line_height = 1.4;

    fn of(shown: Card, left: f32) CardLayout {
        const tile = px(if (shown.featured) 46 else 38);
        const padding = if (shown.featured) gui.vec2(px(18), px(18)) else gui.vec2(px(14), px(12));
        const text_x = left + px(1) + padding.x + tile + px(12);
        const chevron = if (shown.featured) px(12) + px(fonts.size.icon) else 0;
        const text_width = left + shown.width - px(1) - padding.x - chevron - text_x;
        const title_size: f32 = if (shown.featured) 16 else 14;
        gui.sans(.regular, detail_size);
        defer gui.popFont();
        return .{
            .tile = tile,
            .padding = padding,
            .text_x = text_x,
            .text_width = text_width,
            .title_size = title_size,
            .title_line = px(title_size * fonts.line_height),
            .detail_line = px(detail_size * detail_line_height),
            .detail_lines = gui.wrap(shown.detail, text_width).count(),
        };
    }

    /// The title and the detail together.
    fn textHeight(layout: CardLayout) f32 {
        return layout.title_line + px(2) + layout.detail_line * @as(f32, @floatFromInt(layout.detail_lines));
    }

    /// The card's height, with its line.
    fn height(layout: CardLayout) f32 {
        return @max(layout.tile, layout.textHeight()) + layout.padding.y * 2 + px(1) * 2;
    }
};

/// The height a card's content needs.
fn cardHeight(shown: Card) f32 {
    return CardLayout.of(shown, 0).height();
}

/// The design's `.act`: a card with an icon in a tile, a title and a line under it.
fn card(id: []const u8, shown: Card) bool {
    const at = gui.cursor();
    const layout = CardLayout.of(shown, at.x);
    const tile = layout.tile;
    const padding_x = layout.padding.x;
    const height = shown.height orelse layout.height();
    const clicked = c.ImGui_InvisibleButton(gui.z(id), .{ .x = shown.width, .y = height }, 0) and shown.disabled == null;
    const hovered = gui.hovered();
    if (shown.disabled == null) gui.handCursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + shown.width, at.y + height);
    if (shown.featured) {
        c.ImDrawList_AddRectFilledMultiColor(list, at, max, theme.rgb(0x1f150c), theme.rgb(0x1f150c), theme.rgb(0x160f09), theme.rgb(0x160f09));
        gui.outline(list, at, max, if (hovered) theme.accent else theme.rgb(0x6a3d16), 8);
    } else {
        gui.rect(list, at, max, theme.panel, 8);
        gui.outline(list, at, max, if (hovered and shown.disabled == null) theme.border_strong else theme.rgb(0x232938), 8);
    }
    const tile_min = gui.vec2(at.x + px(1) + padding_x, at.y + (height - tile) / 2);
    gui.rect(list, tile_min, .{ .x = tile_min.x + tile, .y = tile_min.y + tile }, if (shown.disabled != null and !shown.featured) theme.button_off else shown.tile, 8);
    widgets.drawIcon(list, .{ .x = tile_min.x + (tile - px(20)) / 2, .y = tile_min.y + tile / 2 }, shown.icon, 20, if (shown.disabled != null and !shown.featured) theme.text_off else shown.tile_icon);
    // The title and the detail, together in the middle of the card.
    const text_top = at.y + (height - layout.textHeight()) / 2;
    gui.sans(.semibold, layout.title_size);
    gui.drawText(list, .{ .x = layout.text_x, .y = gui.textTopIn(text_top + layout.title_line / 2, layout.title_line / gui.scale) }, if (shown.featured) theme.selected_text else if (shown.disabled != null) theme.text_muted else theme.text, shown.title);
    gui.popFont();
    gui.sans(.regular, CardLayout.detail_size);
    var lines = gui.wrap(shown.detail, layout.text_width);
    var line_top = text_top + layout.title_line + px(2);
    while (lines.next()) |line| : (line_top += layout.detail_line) {
        gui.drawText(list, .{ .x = layout.text_x, .y = gui.textTopIn(line_top + layout.detail_line / 2, layout.detail_line / gui.scale) }, if (shown.featured) theme.rgb(0xd9c3ad) else theme.text_muted, line);
    }
    gui.popFont();
    if (shown.featured) widgets.drawIcon(list, .{ .x = max.x - padding_x - px(14), .y = at.y + height / 2 }, .chevron_right, fonts.size.icon_small, theme.accent);
    if (shown.disabled) |off| gui.tooltip(off.reason);
    return clicked;
}

/// The new mod card, with the templates to start from.
fn newMod(app: *App, width: f32) void {
    const at = gui.cursor();
    const list = gui.drawList();
    c.ImDrawList_ChannelsSplit(list, 2);
    c.ImDrawList_ChannelsSetCurrent(list, 1);
    const tile = px(38);
    const tile_min = gui.vec2(at.x + px(14), at.y + px(14));
    gui.rect(list, tile_min, .{ .x = tile_min.x + tile, .y = tile_min.y + tile }, theme.rgb(0x0f2221), 8);
    widgets.drawIcon(list, .{ .x = tile_min.x + px(9), .y = tile_min.y + tile / 2 }, .box, 20, theme.syntax.command);
    gui.sans(.semibold, 13.5);
    gui.drawText(list, .{ .x = tile_min.x + tile + px(12), .y = tile_min.y + px(1) }, theme.text, "New mod");
    gui.popFont();
    gui.sans(.regular, fonts.size.small);
    gui.drawText(list, .{ .x = tile_min.x + tile + px(12), .y = tile_min.y + px(21) }, theme.text_dim, "From a template · Mod mode");
    gui.popFont();
    gui.setCursor(.{ .x = at.x + px(14) + px(50), .y = tile_min.y + tile + px(10) });
    const off = app.unavailable(.new_mod);
    const templates = [_][]const u8{ "Music", "Sounds, speech", "Ship, gun, missile", "Rules (hooks)", "Textures, models", "HUD", "Game mode", "Empty" };
    var x = gui.cursor().x;
    const right = at.x + width - px(14);
    var y = gui.cursor().y;
    for (templates) |template| {
        gui.sans(.regular, fonts.size.small);
        const chip_width = gui.textSize(template).x + px(20);
        gui.popFont();
        if (x + chip_width > right) {
            x = at.x + px(14) + px(50);
            y += px(32);
        }
        gui.setCursor(.{ .x = x, .y = y });
        _ = chipButton(template, template, null, null, off);
        x += chip_width + px(6);
    }
    const bottom = y + px(26) + px(14);
    c.ImDrawList_ChannelsSetCurrent(list, 0);
    gui.rect(list, at, .{ .x = at.x + width, .y = bottom }, theme.panel, 8);
    gui.outline(list, at, .{ .x = at.x + width, .y = bottom }, theme.rgb(0x232938), 8);
    c.ImDrawList_ChannelsMerge(list);
    gui.setCursor(.{ .x = at.x, .y = bottom });
    c.ImGui_Dummy(.{ .x = width, .y = 0 });
}

/// The design's `.chip`: a rounded button, with an icon and a key where given.
fn chipButton(id: []const u8, label: []const u8, icon: ?Icon, key: ?[]const u8, disabled: ?widgets.Disabled) bool {
    gui.sans(.regular, fonts.size.small);
    defer gui.popFont();
    var width = gui.textSize(label).x + px(10) * 2;
    if (icon != null) width += px(14) + px(8);
    if (key) |written| width += px(8) + widgets.keyChipWidth(written);
    const height = px(if (icon != null) 30 else 26);
    const at = gui.cursor();
    const clicked = c.ImGui_InvisibleButton(gui.z(id), .{ .x = width, .y = height }, 0) and disabled == null;
    const hovered = gui.hovered() and disabled == null;
    if (disabled == null) gui.handCursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    gui.rect(list, at, max, if (disabled != null) theme.button_off else theme.field, height / 2 / gui.scale);
    gui.outline(list, at, max, if (hovered) theme.border_strong else if (disabled != null) theme.border_off else theme.key_border, height / 2 / gui.scale);
    const middle = at.y + height / 2;
    var x = at.x + px(10);
    const color = if (disabled != null) theme.text_off else theme.text_menu;
    if (icon) |which| {
        widgets.drawIcon(list, .{ .x = x, .y = middle }, which, fonts.size.icon_small, color);
        x += px(14) + px(8);
    }
    gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, color, label);
    x += gui.textSize(label).x + px(8);
    if (key) |written| widgets.drawKeyChip(list, .{ .x = x, .y = middle }, written, .normal);
    if (disabled) |off| gui.tooltip(off.reason);
    return clicked;
}

/// The mods in the game's `mods` folder.
fn yourMods(app: *App, width: f32) void {
    const at = gui.cursor();
    const list = gui.drawList();
    c.ImDrawList_ChannelsSplit(list, 2);
    c.ImDrawList_ChannelsSetCurrent(list, 1);
    // The heading: YOUR MODS, the folder, and the filter.
    gui.setCursor(.{ .x = at.x + px(12), .y = at.y + px(17) });
    widgets.sectionHeading("Your mods");
    gui.sameLine(10);
    const folder = if (app.settings.game_folder) |path| gui.print("{s}{s}mods", .{ std.fs.path.basename(path), std.fs.path.sep_str }) else "no game folder";
    widgets.monoCaption(folder, theme.text_faint, fonts.size.smaller, .regular);
    const filter_width = px(170);
    gui.setCursor(.{ .x = at.x + width - px(12) - filter_width, .y = at.y + px(12) });
    widgets.searchField("##mods filter", &Filter.text, "Filter", filter_width, 26, false);
    gui.setCursor(.{ .x = at.x, .y = at.y + px(48) });
    gui.rect(list, gui.cursor(), .{ .x = at.x + width, .y = gui.cursor().y + px(1) }, theme.divider, 0);
    c.ImGui_Dummy(.{ .x = width, .y = px(1) });

    const mods = app.listedMods();
    const filter = std.mem.sliceTo(&Filter.text, 0);
    var shown: usize = 0;
    for (mods, 0..) |mod, index| {
        if (filter.len > 0 and std.ascii.findIgnoreCase(mod.name, filter) == null and std.ascii.findIgnoreCase(mod.folder, filter) == null) continue;
        gui.pushIdInt(index);
        defer gui.popId();
        shown += 1;
        const row_at = gui.cursor();
        const height = px(59);
        if (c.ImGui_InvisibleButton("mod", .{ .x = width, .y = height }, 0)) app.openMod(mod.path);
        const hovered = gui.hovered();
        gui.handCursor();
        if (hovered) gui.rect(list, row_at, .{ .x = row_at.x + width, .y = row_at.y + height }, theme.row_hover, 0);
        gui.rect(list, .{ .x = row_at.x, .y = row_at.y + height - px(1) }, .{ .x = row_at.x + width, .y = row_at.y + height }, theme.rgb(0x171c27), 0);
        gui.sans(.semibold, fonts.size.body);
        gui.drawText(list, .{ .x = row_at.x + px(12), .y = row_at.y + px(11) }, theme.text, mod.name);
        gui.popFont();
        gui.sans(.regular, fonts.size.small);
        gui.drawText(list, .{ .x = row_at.x + px(12), .y = row_at.y + px(31) }, theme.text_dim, gui.print("{s} · {s}", .{ mod.folder, mod.holds }));
        gui.popFont();
        const tag_bg, const tag_fg = switch (mod.kind) {
            .missions => .{ theme.rgb(0x1d1530), theme.rgb(0xd7ccff) },
            .ships => .{ theme.rgb(0x2a1414), theme.rgb(0xffb3a8) },
            .sound => .{ theme.rgb(0x0f2221), theme.rgb(0x9ff0e3) },
            .other => .{ theme.pill, theme.text_menu },
        };
        tag(list, .{ .x = row_at.x + width - px(12), .y = row_at.y + height / 2 }, mod.kind.label(), tag_bg, tag_fg);
    }
    if (shown == 0) {
        gui.setCursor(.{ .x = at.x + px(12), .y = gui.cursor().y + px(12) });
        widgets.caption(if (app.settings.game_folder == null) "No game folder · set it in Game settings" else if (mods.len == 0) "No mods in the mods folder" else "None match", theme.text_dim, fonts.size.small, .regular);
        gui.space(12);
    }
    gui.setCursor(.{ .x = at.x + px(12), .y = gui.cursor().y + px(10) });
    widgets.caption(".hog mods: read only · unpack to edit", theme.text_dim, fonts.size.small, .regular);
    const bottom = gui.cursor().y + px(10);
    c.ImDrawList_ChannelsSetCurrent(list, 0);
    gui.rect(list, at, .{ .x = at.x + width, .y = bottom }, theme.fade(theme.panel, 0.92), 8);
    gui.outline(list, at, .{ .x = at.x + width, .y = bottom }, theme.rgb(0x232938), 8);
    c.ImDrawList_ChannelsMerge(list);
    gui.setCursor(.{ .x = at.x, .y = bottom });
    c.ImGui_Dummy(.{ .x = width, .y = 0 });
}

/// The design's `.tag`: a small rounded label, right-aligned at `right`.
fn tag(list: *c.ImDrawList, right_middle: gui.Vec2, text: []const u8, background: theme.Color, foreground: theme.Color) void {
    gui.sans(.semibold, 11);
    defer gui.popFont();
    const width = gui.spacedWidth(text, 0.33) + px(7) * 2;
    const height = px(20);
    const min = gui.vec2(right_middle.x - width, right_middle.y - height / 2);
    gui.rect(list, min, .{ .x = right_middle.x, .y = right_middle.y + height / 2 }, background, 10);
    _ = gui.drawSpaced(list, .{ .x = min.x + px(7), .y = gui.textTop(right_middle.y) }, foreground, text, 0.33);
}

/// The game: whether it's linked, and its settings.
fn gameBox(app: *App, width: f32) void {
    const at = gui.cursor();
    const height = px(68);
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    gui.rect(list, at, max, theme.fade(theme.panel, 0.92), 8);
    gui.outline(list, at, max, theme.border, 8);
    const middle = at.y + height / 2;
    const session = &app.session;
    const greeting = if (session.link_state == .linked) session.greeting else null;
    gui.dot(list, .{ .x = at.x + px(21), .y = middle }, 5, if (greeting != null) theme.linked else theme.text_off);
    gui.sans(.semibold, fonts.size.body);
    // The link is to OpenReliant, which says which game it plays once it answers.
    const state = if (greeting) |linked| gui.print("{s} · linked", .{linked.game}) else if (session.link_state == .waiting) "OpenReliant · waiting" else "OpenReliant · not linked";
    gui.drawText(list, .{ .x = at.x + px(40), .y = at.y + px(15) }, theme.text, state);
    gui.popFont();
    gui.sans(.regular, fonts.size.ui);
    const detail = if (greeting) |linked|
        gui.print("OpenReliant {s} · port {d}", .{ linked.openreliant, session.port })
    else if (app.settings.game_folder) |folder|
        gui.print("Game folder {s}", .{std.fs.path.basename(folder)})
    else
        "No game folder yet";
    gui.drawText(list, .{ .x = at.x + px(40), .y = at.y + px(37) }, theme.text_muted, detail);
    gui.popFont();
    if (app.settings.game_folder) |folder| if (c.ImGui_IsMouseHoveringRect(at, max)) gui.tooltipNow(folder);
    gui.setCursor(.{ .x = max.x - px(16) - px(110), .y = middle - px(15) });
    if (chipButton("game settings", "Game settings", null, null, null)) app.run(.game_settings);
    gui.setCursor(.{ .x = at.x, .y = max.y });
    c.ImGui_Dummy(.{ .x = width, .y = 0 });
}

fn learn() void {
    widgets.sectionHeading("Learn");
    gui.space(8);
    const links = [_]struct { []const u8, [:0]const u8 }{
        .{ "Writing missions", "https://github.com/OpenReliant/openreliant/blob/main/docs/guide/missions.md" },
        .{ "Mission reference", "https://github.com/OpenReliant/openreliant/blob/main/docs/guide/mission-reference.md" },
        .{ "What mods can do", "https://github.com/OpenReliant/openreliant/blob/main/docs/guide/what-mods-can-do.md" },
        .{ "Modding", "https://github.com/OpenReliant/openreliant/blob/main/docs/guide/modding.md" },
        .{ "Scripting", "https://github.com/OpenReliant/openreliant/blob/main/docs/guide/scripting.md" },
    };
    for (links, 0..) |link, index| {
        if (index > 0) gui.sameLine(18);
        widgets.link(link[0], link[1]);
    }
}
