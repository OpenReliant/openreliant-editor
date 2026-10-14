//! The command palette: every action by name, the mission's records, the game's catalogue and
//! the source's lines, by what's typed first: `>` for actions, `@` for records, `#` for the
//! catalogue, `:` for a line.

const std = @import("std");
const c = @import("c");

const app_mod = @import("app.zig");
const App = app_mod.App;
const commands = @import("commands.zig");
const Command = commands.Command;
const game = @import("game.zig");
const ui = @import("ui.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const Icon = ui.icons.Icon;
const theme = ui.theme;
const widgets = ui.widgets;
const px = gui.px;

/// The most results the list shows.
const max_results = 40;

pub const Kind = enum {
    commands,
    records,
    catalogue,
    line,
    /// The actions that play, with Play from part chosen and its form beside it.
    play_from_part,
    /// The game's own missions, to open as the source of a new mod.
    game_missions,

    fn prefix(kind: Kind) []const u8 {
        return switch (kind) {
            .commands => "> ",
            .records => "@",
            .catalogue => "#",
            .line => ":",
            .play_from_part => "> play",
            .game_missions => "mission ",
        };
    }
};

pub const State = struct {
    open: bool = false,
    /// Whether the input takes the keyboard next frame.
    focus: bool = false,
    text: [128:0]u8 = @splat(0),
    selected: usize = 0,
    /// Whether the palette lists the game's own missions, for Edit a game mission.
    listing_missions: bool = false,
    /// The result to choose once the list is made, by its command.
    choose: ?Command = null,
    /// Play from part's form: the part, by its place among the parts, whether to skip the launch,
    /// and the ship to watch, by its place among the ships.
    part: usize = 0,
    skip_launch: bool = true,
    watch: ?usize = null,

    pub fn show(state: *State, kind: Kind) void {
        state.open = true;
        state.focus = true;
        state.selected = 0;
        state.text = @splat(0);
        const prefix = kind.prefix();
        @memcpy(state.text[0..prefix.len], prefix);
        state.choose = if (kind == .play_from_part) .play_from_part else null;
        state.listing_missions = kind == .game_missions;
    }
};

/// A result of the palette.
const Result = union(enum) {
    command: Command,
    record: usize,
    word: usize,
    line: u32,
    /// One of the game's own missions, by its place in the list.
    game_mission: usize,
};

pub fn draw(app: *App) void {
    const state = &app.palette;
    if (!state.open) return;
    const viewport = c.ImGui_GetMainViewport();
    const width = @min(px(980), viewport.*.WorkSize.x - px(40));
    const height = @min(px(485), viewport.*.WorkSize.y - px(100));
    c.ImGui_SetNextWindowPos(.{ .x = viewport.*.WorkPos.x + (viewport.*.WorkSize.x - width) / 2, .y = viewport.*.WorkPos.y + px(70) }, c.ImGuiCond_Always);
    c.ImGui_SetNextWindowSize(.{ .x = width, .y = height }, c.ImGuiCond_Always);
    gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
    gui.pushVar(c.ImGuiStyleVar_WindowRounding, px(8));
    gui.pushVar(c.ImGuiStyleVar_WindowBorderSize, px(1));
    gui.pushColor(c.ImGuiCol_WindowBg, theme.panel);
    gui.pushColor(c.ImGuiCol_Border, theme.border_strong);
    const visible = c.ImGui_Begin("##palette", &state.open, c.ImGuiWindowFlags_NoDecoration | c.ImGuiWindowFlags_NoMove | c.ImGuiWindowFlags_NoSavedSettings | c.ImGuiWindowFlags_NoDocking);
    gui.popColor(2);
    gui.popVar(3);
    defer c.ImGui_End();
    if (!visible) return;
    // A click outside or Escape closes it.
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_Escape) or (c.ImGui_IsMouseClicked(c.ImGuiMouseButton_Left) and !c.ImGui_IsWindowHovered(c.ImGuiHoveredFlags_ChildWindows | c.ImGuiHoveredFlags_AllowWhenBlockedByActiveItem))) {
        state.open = false;
        return;
    }
    const at = c.ImGui_GetWindowPos();
    const list = gui.drawList();

    // The input.
    widgets.drawIcon(list, .{ .x = at.x + px(16), .y = at.y + px(26) }, .terminal, fonts.size.icon, theme.accent);
    gui.setCursor(.{ .x = at.x + px(42), .y = at.y + px(12) });
    c.ImGui_SetNextItemWidth(width - px(42) - px(70));
    if (state.focus) {
        c.ImGui_SetKeyboardFocusHere();
        state.focus = false;
    }
    gui.pushColor(c.ImGuiCol_FrameBg, theme.fade(theme.panel, 0));
    gui.pushColor(c.ImGuiCol_FrameBgHovered, theme.fade(theme.panel, 0));
    gui.pushColor(c.ImGuiCol_FrameBgActive, theme.fade(theme.panel, 0));
    gui.pushColor(c.ImGuiCol_NavCursor, theme.fade(theme.panel, 0));
    gui.pushVar(c.ImGuiStyleVar_FrameBorderSize, 0);
    gui.sans(.regular, 16);
    const entered = c.ImGui_InputTextEx("##query", &state.text, state.text.len + 1, c.ImGuiInputTextFlags_EnterReturnsTrue | c.ImGuiInputTextFlags_AutoSelectAll, null, null);
    gui.popFont();
    gui.popVar(1);
    gui.popColor(4);
    const esc_width = widgets.keyChipWidth("Esc");
    widgets.drawKeyChip(list, .{ .x = at.x + width - px(16) - esc_width, .y = at.y + px(26) }, "Esc", .normal);
    gui.rect(list, .{ .x = at.x, .y = at.y + px(51) }, .{ .x = at.x + width, .y = at.y + px(52) }, theme.divider, 0);

    // What the text asks for.
    const query = std.mem.sliceTo(&state.text, 0);
    const kind: Kind, const term = if (std.mem.startsWith(u8, query, "mission ") and state.listing_missions) .{ Kind.game_missions, query["mission ".len..] } else if (std.mem.startsWith(u8, query, "@@")) .{ Kind.records, query[2..] } else if (std.mem.startsWith(u8, query, "@")) .{ Kind.records, query[1..] } else if (std.mem.startsWith(u8, query, "#")) .{ Kind.catalogue, query[1..] } else if (std.mem.startsWith(u8, query, ":")) .{ Kind.line, query[1..] } else .{ Kind.commands, std.mem.trimStart(u8, std.mem.trimStart(u8, query, ">"), " ") };
    const offsets = std.mem.startsWith(u8, query, "@@");
    var results: [max_results]Result = undefined;
    const count = if (offsets) 0 else gather(app, kind, std.mem.trim(u8, term, " "), &results);
    if (state.choose) |wanted| {
        for (results[0..count], 0..) |result, index| {
            if (result == .command and result.command == wanted) state.selected = index;
        }
        state.choose = null;
    }
    if (count > 0) state.selected = @min(state.selected, count - 1) else state.selected = 0;
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_DownArrow) and count > 0) state.selected = (state.selected + 1) % count;
    if (c.ImGui_IsKeyPressed(c.ImGuiKey_UpArrow) and count > 0) state.selected = (state.selected + count - 1) % count;

    // The list on the left, the chosen result on the right.
    const split = width * 0.5;
    const list_top = at.y + px(52) + px(8);
    const footer_top = at.y + height - px(40);
    gui.rect(list, .{ .x = at.x + split, .y = at.y + px(52) }, .{ .x = at.x + split + px(1), .y = at.y + height }, theme.divider, 0);
    gui.setCursor(.{ .x = at.x + px(8), .y = list_top });
    _ = c.ImGui_BeginChild("results", .{ .x = split - px(16), .y = footer_top - list_top }, 0, 0);
    var activated: ?Result = null;
    for (results[0..count], 0..) |result, index| {
        gui.pushIdInt(index);
        defer gui.popId();
        if (resultRow(app, result, index == state.selected, term)) {
            state.selected = index;
            activated = result;
        }
    }
    if (offsets) {
        widgets.caption(gui.print("Script offsets · planned {f}", .{commands.plans.debugger}), theme.text_dim, fonts.size.small, .regular);
    } else if (count == 0) {
        gui.setCursor(gui.add(gui.cursor(), .{ .x = px(8), .y = px(6) }));
        widgets.caption(if (kind == .line) "Type a line number" else "Nothing matches", theme.text_dim, fonts.size.small, .regular);
    }
    c.ImGui_EndChild();
    footer(list, .{ .x = at.x + px(16), .y = footer_top }, split);

    gui.setCursor(.{ .x = at.x + split + px(18), .y = list_top + px(8) });
    _ = c.ImGui_BeginChild("detail", .{ .x = width - split - px(36), .y = height - px(52) - px(24) }, 0, 0);
    if (count > 0) detail(app, results[state.selected]);
    c.ImGui_EndChild();

    if (entered and count > 0) activated = results[state.selected];
    if (activated) |chosen| {
        if (chosen == .command and chosen.command == .play_from_part) {
            const io = c.ImGui_GetIO();
            if (io.*.KeyCtrl) copyCommand(app) else playFromPart(app);
            state.open = false;
        } else run(app, chosen);
    }
}

/// The parts of the open mission that Play from part can start.
fn parts(app: *App, buffer: *[64]*const game.Record) []*const game.Record {
    var count: usize = 0;
    const document = app.document orelse return buffer[0..0];
    for (document.outline().records) |*record| {
        if (record.section != .parts or count == buffer.len or std.mem.eql(u8, record.detail, "handler")) continue;
        buffer[count] = record;
        count += 1;
    }
    return buffer[0..count];
}

/// The ships of the open mission, which Play from part can watch.
fn ships(app: *App, buffer: *[64]*const game.Record) []*const game.Record {
    var count: usize = 0;
    const document = app.document orelse return buffer[0..0];
    for (document.outline().records) |*record| {
        if (record.section != .ships or count == buffer.len) continue;
        buffer[count] = record;
        count += 1;
    }
    return buffer[0..count];
}

/// What Play from part's form asks for.
fn playOptions(app: *App) game.Play {
    const state = &app.palette;
    var part_buffer: [64]*const game.Record = undefined;
    var ship_buffer: [64]*const game.Record = undefined;
    const found_parts = parts(app, &part_buffer);
    const found_ships = ships(app, &ship_buffer);
    return .{
        .part = if (found_parts.len > 0) found_parts[@min(state.part, found_parts.len - 1)].title else null,
        .skip_launch = state.skip_launch,
        .watch = if (state.watch) |index| if (index < found_ships.len) found_ships[index].title else null else null,
    };
}

fn playFromPart(app: *App) void {
    app.play(playOptions(app));
}

/// The command line Play from part runs, as text, quoted where a value holds spaces.
fn commandLine(app: *App) []const u8 {
    const document = app.document orelse return "";
    const number = document.number orelse return "";
    const folder = app.settings.game_folder orelse return "";
    const arguments = app.profile.playArguments(gui.frameAllocator(), std.fs.path.basename(folder), number, playOptions(app)) catch return "";
    var text: std.Io.Writer.Allocating = .init(gui.frameAllocator());
    text.writer.writeAll("openreliant") catch return "";
    for (arguments) |argument| {
        const quoted = std.mem.findAny(u8, argument, " ()") != null;
        text.writer.print(" {s}{s}{s}", .{ if (quoted) "\"" else "", argument, if (quoted) "\"" else "" }) catch return "";
    }
    return text.written();
}

fn copyCommand(app: *App) void {
    _ = c.SDL_SetClipboardText(gui.z(commandLine(app)));
    app.toasts.push(.success, "Command copied", commandLine(app));
}

/// Play from part's form, beside the list: the part, the launch, the ship to watch, and the
/// command line it runs.
fn playForm(app: *App) void {
    const state = &app.palette;
    widgets.caption("Play from part", theme.text_strong, 15, .semibold);
    widgets.caption("Runs the part after the launch, like a trigger", theme.text_muted, fonts.size.ui, .regular);
    gui.space(12);
    var part_buffer: [64]*const game.Record = undefined;
    var ship_buffer: [64]*const game.Record = undefined;
    const found_parts = parts(app, &part_buffer);
    const found_ships = ships(app, &ship_buffer);
    widgets.sectionHeading("Part");
    gui.space(6);
    if (found_parts.len == 0) {
        widgets.caption("The mission has no parts", theme.text_dim, fonts.size.small, .regular);
    } else {
        const chosen = found_parts[@min(state.part, found_parts.len - 1)];
        if (widgets.frame("part", .{ .label = chosen.title, .mono_label = true, .mark = .{ .icon = .{ .icon = .braces, .color = theme.syntax.command } } })) _ = c.ImGui_OpenPopup("parts", 0);
        if (c.ImGui_BeginPopup("parts", 0)) {
            for (found_parts, 0..) |part, index| {
                if (c.ImGui_MenuItemEx(gui.z(part.title), null, index == state.part, true)) state.part = index;
            }
            c.ImGui_EndPopup();
        }
    }
    gui.space(10);
    if (widgets.checkbox("skip launch", "Skip launch", state.skip_launch, null)) state.skip_launch = !state.skip_launch;
    _ = widgets.checkbox("earlier parts", "Run earlier parts first, for their variables", false, .{ .reason = gui.print("Planned · {f}", .{commands.plans.play_from_part}) });
    _ = widgets.checkbox("break first", "Break at its first statement", false, .{ .reason = gui.print("Planned · {f}", .{commands.plans.debugger}) });
    gui.space(12);
    widgets.sectionHeading("Watch");
    gui.space(6);
    const watched = if (state.watch) |index| if (index < found_ships.len) found_ships[index] else null else null;
    if (widgets.frame("watch", .{
        .label = if (watched) |ship| ship.title else "The player's ship",
        .mark = if (watched) |ship| .{ .icon = .{ .icon = .navigation_2, .color = if (ship.group) |group| theme.groups[group % theme.groups.len] else theme.text_menu } } else .none,
    })) _ = c.ImGui_OpenPopup("ships", 0);
    if (c.ImGui_BeginPopup("ships", 0)) {
        if (c.ImGui_MenuItemEx("The player's ship", null, state.watch == null, true)) state.watch = null;
        for (found_ships, 0..) |ship, index| {
            if (c.ImGui_MenuItemEx(gui.z(ship.title), null, state.watch == index, true)) state.watch = index;
        }
        c.ImGui_EndPopup();
    }
    gui.space(12);
    widgets.sectionHeading("Command line");
    gui.space(6);
    const at = gui.cursor();
    const width = gui.available().x;
    const text = commandLine(app);
    gui.mono(.regular, fonts.size.small);
    const text_size = c.ImGui_CalcTextSizeEx(text.ptr, text.ptr + text.len, false, width - px(52));
    gui.popFont();
    const height = text_size.y + px(20);
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.code, 4);
    gui.outline(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.border, 4);
    gui.mono(.regular, fonts.size.small);
    c.ImDrawList_AddTextImFontPtrEx(list, c.ImGui_GetFont(), c.ImGui_GetFontSize(), .{ .x = at.x + px(10), .y = at.y + px(10) }, theme.text_button, text.ptr, text.ptr + text.len, width - px(52), null);
    gui.popFont();
    gui.setCursor(.{ .x = at.x + width - px(34), .y = at.y + px(8) });
    if (widgets.toolButton("copy", .{ .icon = .copy, .icon_only = true, .height = 24, .tooltip = "Copy the command" })) copyCommand(app);
    gui.setCursor(.{ .x = at.x, .y = at.y + height + px(12) });
    widgets.caption(gui.print("Enter: play · {s}+Enter: copy command", .{if (@import("builtin").target.os.tag == .macos) "Cmd" else "Ctrl"}), theme.text_dim, fonts.size.small, .regular);
    gui.sameLine(0);
    gui.setCursor(.{ .x = at.x + width - px(80), .y = gui.cursor().y - px(4) });
    if (widgets.toolButton("play", .{ .label = "Play", .icon = .play, .style = .primary, .weight = .semibold, .disabled = app.unavailable(.play_from_part) })) {
        playFromPart(app);
        app.palette.open = false;
    }
}

/// The results for `term`, the best first.
fn gather(app: *App, kind: Kind, term: []const u8, results: *[max_results]Result) usize {
    var count: usize = 0;
    switch (kind) {
        .commands, .play_from_part => for (std.enums.values(Command)) |command| {
            if (count == max_results) break;
            const known = commands.info(command);
            if (!known.in_palette) continue;
            if (term.len > 0 and std.ascii.findIgnoreCase(app.label(command), term) == null) continue;
            results[count] = .{ .command = command };
            count += 1;
        },
        .records => if (app.document) |document| for (document.outline().records, 0..) |record, index| {
            if (count == max_results) break;
            if (term.len > 0 and std.ascii.findIgnoreCase(record.title, term) == null and std.ascii.findIgnoreCase(record.name, term) == null) continue;
            results[count] = .{ .record = index };
            count += 1;
        },
        .catalogue => for (app.language.words, 0..) |word, index| {
            if (count == max_results) break;
            if (word.kind == .keyword) continue;
            if (term.len == 0 or std.ascii.findIgnoreCase(word.name, term) == null) continue;
            results[count] = .{ .word = index };
            count += 1;
        },
        .line => if (app.document) |document| {
            const number = std.fmt.parseInt(u32, term, 10) catch return 0;
            if (number == 0 or number > document.editor.lineCount()) return 0;
            results[0] = .{ .line = number - 1 };
            count = 1;
        },
        .game_missions => for (app.listedGameMissions(), 0..) |mission, index| {
            if (count == max_results) break;
            if (term.len > 0 and !std.mem.startsWith(u8, gui.print("{d}", .{mission.number}), term)) continue;
            results[count] = .{ .game_mission = index };
            count += 1;
        },
    }
    return count;
}

/// A row of the list: its group, its name with the typed part lit, and its key. True when
/// clicked.
fn resultRow(app: *App, result: Result, selected: bool, term: []const u8) bool {
    const at = gui.cursor();
    const width = gui.available().x;
    const height = px(34);
    const clicked = c.ImGui_InvisibleButton("result", .{ .x = width, .y = height }, 0);
    const hovered = gui.hovered();
    const list = gui.drawList();
    if (selected) gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.popup_selected, 5) else if (hovered) gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.row_hover, 5);
    const middle = at.y + height / 2;
    var group: []const u8 = "";
    var name: []const u8 = "";
    var key: ?[]const u8 = null;
    var off = false;
    switch (result) {
        .command => |command| {
            const known = commands.info(command);
            group = known.group orelse if (commands.menuOf(command)) |menu| menu.label() else "";
            name = app.label(command);
            key = app.keyText(command);
            off = app.unavailable(command) != null;
        },
        .record => |index| {
            const record = app.document.?.outline().records[index];
            group = record.section.label();
            name = record.title;
        },
        .word => |index| {
            const word = app.language.words[index];
            group = word.kind.label();
            name = word.name;
        },
        .line => |line| {
            group = "Line";
            name = gui.print("Go to line {d}", .{line + 1});
        },
        .game_mission => |index| {
            const mission = app.listedGameMissions()[index];
            group = "Game";
            name = gui.print("Mission {d}", .{mission.number});
        },
    }
    gui.sans(.regular, fonts.size.smaller);
    gui.drawText(list, .{ .x = at.x + px(12), .y = gui.textTop(middle) }, theme.text_dim, group);
    gui.popFont();
    gui.sans(.regular, fonts.size.body);
    const x = at.x + px(84);
    const color = if (off) theme.text_off else theme.text_button;
    if (term.len > 0) if (std.ascii.findIgnoreCase(name, term)) |found| {
        // The typed part in orange.
        gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, color, name[0..found]);
        const lit_x = x + gui.textSize(name[0..found]).x;
        gui.popFont();
        gui.sans(.semibold, fonts.size.body);
        gui.drawText(list, .{ .x = lit_x, .y = gui.textTop(middle) }, theme.rgb(0xffb070), name[found .. found + term.len]);
        const rest_x = lit_x + gui.textSize(name[found .. found + term.len]).x;
        gui.popFont();
        gui.sans(.regular, fonts.size.body);
        gui.drawText(list, .{ .x = rest_x, .y = gui.textTop(middle) }, color, name[found + term.len ..]);
        gui.popFont();
        drawKey(list, at, width, middle, key);
        return clicked;
    };
    gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, color, name);
    gui.popFont();
    drawKey(list, at, width, middle, key);
    return clicked;
}

fn drawKey(list: *c.ImDrawList, at: gui.Vec2, width: f32, middle: f32, key: ?[]const u8) void {
    const written = key orelse return;
    const key_width = widgets.keyChipWidth(written);
    widgets.drawKeyChip(list, .{ .x = at.x + width - px(12) - key_width, .y = middle }, written, .normal);
}

/// The chosen result in full.
fn detail(app: *App, result: Result) void {
    switch (result) {
        .command => |command| {
            if (command == .play_from_part and app.unavailable(command) == null) return playForm(app);
            widgets.caption(app.label(command), theme.text_strong, 15, .semibold);
            if (app.keyText(command)) |key| widgets.caption(gui.print("{s} · {s}", .{ if (commands.menuOf(command)) |menu| menu.label() else "", key }), theme.text_dim, fonts.size.small, .regular);
            gui.space(10);
            if (app.unavailable(command)) |off| {
                widgets.caption(off.reason, theme.text_muted, fonts.size.ui, .regular);
            } else {
                widgets.caption("Enter: run", theme.text_dim, fonts.size.small, .regular);
            }
        },
        .record => |index| {
            const record = app.document.?.outline().records[index];
            widgets.caption(record.title, theme.text_strong, 15, .semibold);
            widgets.monoCaption(record.name, theme.text_dim, fonts.size.small, .regular);
            gui.space(8);
            widgets.caption(gui.print("{s} · lines {d} to {d}", .{ record.section.label(), record.first_line + 1, record.last_line + 1 }), theme.text_muted, fonts.size.ui, .regular);
            gui.space(8);
            widgets.caption("Enter: go to it", theme.text_dim, fonts.size.small, .regular);
        },
        .word => |index| {
            const word = app.language.words[index];
            widgets.monoCaption(word.name, theme.syntax.command, 15, .semibold);
            widgets.caption(word.source, theme.text_dim, fonts.size.small, .regular);
            gui.space(8);
            c.ImGui_PushTextWrapPos(0);
            if (word.signature.len > 0) widgets.monoCaption(word.signature, theme.text_button, fonts.size.small, .regular);
            gui.space(6);
            if (word.about.len > 0) widgets.caption(word.about, theme.text_menu, fonts.size.ui, .regular);
            c.ImGui_PopTextWrapPos();
            gui.space(8);
            widgets.caption("Enter: show in Reference", theme.text_dim, fonts.size.small, .regular);
        },
        .line => |line| {
            widgets.caption(gui.print("Line {d}", .{line + 1}), theme.text_strong, 15, .semibold);
            if (app.document) |document| {
                gui.space(8);
                widgets.monoCaption(std.mem.trim(u8, document.editor.lineText(line), " \t"), theme.syntax.name, fonts.size.ui, .regular);
            }
        },
        .game_mission => |index| {
            const mission = app.listedGameMissions()[index];
            widgets.caption(gui.print("Mission {d}", .{mission.number}), theme.text_strong, 15, .semibold);
            widgets.caption(gui.print("{s}'s mission, {s}", .{ app.profile.name, mission.origin.label() }), theme.text_dim, fonts.size.small, .regular);
            gui.space(10);
            c.ImGui_PushTextWrapPos(0);
            widgets.caption(gui.print("As source in a new mod, mods/mission{d} · its build replaces the game's by name", .{mission.number}), theme.text_menu, fonts.size.ui, .regular);
            c.ImGui_PopTextWrapPos();
            gui.space(8);
            widgets.caption("Enter: open as source", theme.text_dim, fonts.size.small, .regular);
        },
    }
}

/// The hints at the list's foot: what each first character searches.
fn footer(list: *c.ImDrawList, at: gui.Vec2, width: f32) void {
    _ = width;
    var x = at.x;
    const y = at.y + px(12);
    for ([_][2][]const u8{ .{ ">", "commands" }, .{ "@", "records" }, .{ "#", "the catalogue" }, .{ ":", "a line" }, .{ "@@", "an offset" } }) |hint| {
        gui.mono(.semibold, fonts.size.small);
        gui.drawText(list, .{ .x = x, .y = y }, theme.text_menu, hint[0]);
        x += gui.textSize(hint[0]).x + px(2);
        gui.popFont();
        gui.sans(.regular, fonts.size.small);
        gui.drawText(list, .{ .x = x, .y = y }, theme.text_dim, hint[1]);
        x += gui.textSize(hint[1]).x + px(14);
        gui.popFont();
    }
}

fn run(app: *App, result: Result) void {
    app.palette.open = false;
    switch (result) {
        .command => |command| if (app.unavailable(command) == null) app.run(command),
        .record => |index| {
            const record = app.document.?.outline().records[index];
            app.select(record);
            app.goTo(record.first_line, record.column);
        },
        .word => |index| {
            const word = app.language.words[index];
            const kept = @min(word.name.len, app.reference_buffer.len);
            @memcpy(app.reference_buffer[0..kept], word.name[0..kept]);
            app.reference_word = app.reference_buffer[0..kept];
            app.showPanel(.reference);
        },
        .line => |line| app.goTo(line, 0),
        .game_mission => |index| app.editGameMission(app.listedGameMissions()[index].number),
    }
}
