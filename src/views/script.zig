//! The Script view's source panel: the mission's source and its script listing as tabs, the line
//! that says where the cursor is, and the text editor with the design's gutter, its breakpoints
//! and problems, help on hover and completion from the game's catalogues.

const std = @import("std");
const c = @import("c");

const app_mod = @import("../app.zig");
const App = app_mod.App;
const Document = @import("../mission/document.zig").Document;
const game = @import("../game.zig");
const ui = @import("../ui.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const Icon = ui.icons.Icon;
const text_editor = ui.text_editor;
const theme = ui.theme;
const widgets = ui.widgets;
const px = gui.px;

/// The gutter, in characters: the room before the line numbers, for breakpoints and problems,
/// the room between the numbers and the text, and before the text.
const marker_room = 3;
const decoration_room = 2;
const text_room = 1;

/// How long the pointer rests on a word before its help shows, in milliseconds.
const hover_delay_ms = 450;

/// The most completions the list shows.
const max_completions = 8;

/// Sets up the editor of a newly opened mission: its gutter and the code that draws it.
pub fn attach(app: *App, document: *Document) void {
    const editor = document.editor;
    editor.setMargins(marker_room, 0, text_room);
    // The design's 19 pixel lines for 12.5 pixel code: the editor makes its lines as high as the
    // font's size in ImGui times this.
    editor.setLineSpacing(19 / fonts.face(.mono, .regular, fonts.size.ui).imgui_size);
    editor.setLineNumbers(App, app, drawLineNumber);
    editor.setDecorations(decoration_room, App, app, drawDecoration);
    state = .{};
}

/// What the view keeps between frames: the hover's word, and the completion list.
const State = struct {
    hover_word: [64]u8 = undefined,
    hover_len: usize = 0,
    hover_since: u64 = 0,
    completing: bool = false,
    /// The version of the text the completion last read.
    completion_version: usize = 0,
    selected: usize = 0,
    matches: [max_completions]usize = undefined,
    match_count: usize = 0,
    word_start: text_editor.Pos = .{ .line = 0, .index = 0 },
    /// Where the listing view was last filled from.
    listing_shown: ?[*]const u8 = null,
};

var state: State = .{};

pub fn draw(app: *App) void {
    const document = app.document orelse return;
    tabs(app, document);
    switch (app.source_tab) {
        .source => {
            breadcrumbs(app, document);
            source(app, document);
        },
        .listing => listing(app, document),
    }
}

/// The panel's own tabs: the source file, and its script listing.
fn tabs(app: *App, document: *Document) void {
    const at = gui.cursor();
    const width = gui.available().x;
    const height = px(30);
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.bar, 0);
    gui.rect(list, .{ .x = at.x, .y = at.y + height - px(1) }, .{ .x = at.x + width, .y = at.y + height }, theme.tab_divider, 0);
    gui.sans(.regular, fonts.size.ui);
    defer gui.popFont();
    var x = at.x;
    const middle = at.y + height / 2;
    const listing_detail = if (document.built) |built| built.file else "not built";
    inline for (.{ app_mod.SourceTab.source, app_mod.SourceTab.listing }) |tab| {
        const on = app.source_tab == tab;
        const label = if (tab == .source) document.file else "Script listing";
        var tab_width = px(12) * 2 + px(14) + px(7) + gui.textSize(label).x;
        if (tab == .source and document.dirty()) tab_width += px(7) + px(7);
        if (tab == .listing) tab_width += px(7) + gui.textSize(listing_detail).x;
        gui.setCursor(.{ .x = x, .y = at.y });
        if (c.ImGui_InvisibleButton(@tagName(tab), .{ .x = tab_width, .y = height }, 0)) app.source_tab = tab;
        const hovered = gui.hovered();
        if (on) {
            gui.rect(list, .{ .x = x, .y = at.y }, .{ .x = x + tab_width, .y = at.y + height }, theme.panel, 0);
            gui.rect(list, .{ .x = x, .y = at.y }, .{ .x = x + tab_width, .y = at.y + px(2) }, theme.accent, 0);
        }
        gui.rect(list, .{ .x = x + tab_width - px(1), .y = at.y }, .{ .x = x + tab_width, .y = at.y + height }, theme.tab_divider, 0);
        const foreground = if (on) theme.text_strong else if (hovered) theme.text else theme.text_muted;
        var inner = x + px(12);
        const icon: Icon = if (tab == .source) .file_code else .list;
        widgets.drawIcon(list, .{ .x = inner, .y = middle }, icon, fonts.size.icon_small, if (tab == .source) theme.accent else foreground);
        inner += px(14) + px(7);
        gui.drawText(list, .{ .x = inner, .y = gui.textTop(middle) }, foreground, label);
        inner += gui.textSize(label).x + px(7);
        if (tab == .source and document.dirty()) {
            gui.dot(list, .{ .x = inner + px(3.5), .y = middle }, 3.5, theme.text_menu);
            gui.tooltip("Changed since saved");
        }
        if (tab == .listing) gui.drawText(list, .{ .x = inner, .y = gui.textTop(middle) }, theme.text_faint, listing_detail);
        x += tab_width;
    }
    gui.setCursor(.{ .x = at.x, .y = at.y + height });
}

/// The line under the tabs: the file, the record the cursor is in, and its statement.
fn breadcrumbs(app: *App, document: *Document) void {
    _ = app;
    const at = gui.cursor();
    const width = gui.available().x;
    const height = px(26);
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.breadcrumbs, 0);
    gui.rect(list, .{ .x = at.x, .y = at.y + height - px(1) }, .{ .x = at.x + width, .y = at.y + height }, theme.table_line, 0);
    const middle = at.y + height / 2;
    var x = at.x + px(12);
    gui.sans(.regular, fonts.size.small);
    gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_muted, document.file);
    x += gui.textSize(document.file).x + px(6);
    gui.popFont();
    const cursor = document.editor.cursor();
    if (document.outline().at(@intCast(cursor.line))) |record| {
        widgets.drawIcon(list, .{ .x = x, .y = middle }, .chevron_right, fonts.size.icon_tiny, theme.chevron);
        x += px(12) + px(6);
        gui.mono(.regular, fonts.size.small);
        const name = if (record.section == .triggers) gui.print("on({s}, \"{s}\")", .{ record.subject, record.condition }) else record.title;
        gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_button, name);
        x += gui.textSize(name).x + px(6);
        gui.popFont();
        if (statementOf(document, record.*, cursor.line)) |statement| {
            widgets.drawIcon(list, .{ .x = x, .y = middle }, .chevron_right, fonts.size.icon_tiny, theme.chevron);
            x += px(12) + px(6);
            gui.sans(.regular, fonts.size.small);
            gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_muted, gui.print("statement {d} of {d}", .{ statement[0], statement[1] }));
            gui.popFont();
        }
    }
    c.ImGui_Dummy(.{ .x = width, .y = height });
}

/// Which statement of its record's code the cursor's line is, and how many there are: the lines
/// of the body that hold code.
fn statementOf(document: *Document, record: game.Record, line: usize) ?[2]usize {
    if (record.section != .triggers and record.section != .parts) return null;
    var count: usize = 0;
    var current: ?usize = null;
    var index = record.first_line + 1;
    while (index < record.last_line) : (index += 1) {
        const text = std.mem.trim(u8, document.editor.lineText(index), " \t\r");
        if (text.len == 0 or std.mem.startsWith(u8, text, "--")) continue;
        count += 1;
        if (index == line) current = count;
    }
    return .{ current orelse return null, count };
}

fn source(app: *App, document: *Document) void {
    const editor = document.editor;
    gui.mono(.regular, fonts.size.ui);
    const changed = editor.render("##source");
    gui.popFont();
    app.source_focused = c.ImGui_IsWindowFocused(c.ImGuiFocusedFlags_ChildWindows);
    if (changed) document.touched(c.SDL_GetTicks());
    followCursor(app, document);
    hover(app, document);
    completion(app, document, changed);
}

/// The Reference panel follows the word at the cursor, when the game's catalogues know it.
fn followCursor(app: *App, document: *Document) void {
    const editor = document.editor;
    const cursor = editor.cursor();
    const word = wordAt(editor, cursor) orelse return;
    if (app.language.find(word) == null) return;
    const kept = @min(word.len, app.reference_buffer.len);
    @memcpy(app.reference_buffer[0..kept], word[0..kept]);
    app.reference_word = app.reference_buffer[0..kept];
}

/// The word at `pos`, or just before it, valid until the next call on the editor.
fn wordAt(editor: text_editor.TextEditor, pos: text_editor.Pos) ?[]const u8 {
    const line = editor.lineText(pos.line);
    var start = @min(pos.index, line.len);
    while (start > 0 and isWordCharacter(line[start - 1])) start -= 1;
    var end = @min(pos.index, line.len);
    while (end < line.len and isWordCharacter(line[end])) end += 1;
    if (end <= start) return null;
    return line[start..end];
}

fn isWordCharacter(character: u8) bool {
    return std.ascii.isAlphanumeric(character) or character == '_';
}

/// The game's help for the word under the pointer, once it has rested there.
fn hover(app: *App, document: *Document) void {
    const editor = document.editor;
    const mouse = c.ImGui_GetMousePos();
    if (state.completing or !c.ImGui_IsWindowHovered(c.ImGuiHoveredFlags_ChildWindows) or !editor.mouseOverGlyph(mouse)) {
        state.hover_len = 0;
        return;
    }
    const pos = editor.posAt(mouse);
    const word = wordAt(editor, pos) orelse {
        state.hover_len = 0;
        return;
    };
    const now = c.SDL_GetTicks();
    if (!std.mem.eql(u8, word, state.hover_word[0..state.hover_len])) {
        state.hover_len = @min(word.len, state.hover_word.len);
        @memcpy(state.hover_word[0..state.hover_len], word[0..state.hover_len]);
        state.hover_since = now;
    }
    if (now - state.hover_since < hover_delay_ms) {
        app.window.keepBusy();
        return;
    }
    // A problem on the word says what's wrong first.
    var problem_text: ?[]const u8 = null;
    for (document.problems()) |problem| {
        if (problem.at.line == pos.line and pos.index >= problem.at.column and pos.index <= problem.at.column + word.len) problem_text = problem.message;
    }
    const found = app.language.find(word);
    if (found == null and problem_text == null) return;
    gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = px(12), .y = px(10) });
    defer gui.popVar(1);
    if (c.ImGui_BeginTooltip()) {
        defer c.ImGui_EndTooltip();
        c.ImGui_PushTextWrapPos(px(440));
        defer c.ImGui_PopTextWrapPos();
        if (problem_text) |message| {
            widgets.caption(message, theme.error_text, fonts.size.ui, .regular);
            if (found != null) gui.space(6);
        }
        if (found) |word_found| describe(word_found.*);
    }
}

/// A word's signature, what it does and where it comes from.
fn describe(word: game.Word) void {
    if (word.signature.len > 0) {
        widgets.monoCaption(word.signature, theme.text_button, fonts.size.small, .regular);
        gui.space(6);
    } else {
        widgets.monoCaption(word.name, theme.text_button, fonts.size.small, .regular);
    }
    if (word.about.len > 0) widgets.caption(word.about, theme.text_menu, fonts.size.ui, .regular);
    if (word.source.len > 0) widgets.caption(word.source, theme.text_dim, fonts.size.small, .regular);
}

/// The completion list: the words of the game's catalogues that start as the word being typed,
/// with the chosen one's help beside them. Not made yet: inserting a command's values to tab
/// through ([#12](https://github.com/OpenReliant/openreliant-editor/issues/12)).
fn completion(app: *App, document: *Document, changed: bool) void {
    const editor = document.editor;
    const cursor = editor.cursor();
    const line = editor.lineText(cursor.line);
    var start = @min(cursor.index, line.len);
    while (start > 0 and isWordCharacter(line[start - 1])) start -= 1;
    const typed = line[start..@min(cursor.index, line.len)];
    if (changed) {
        // Typing a word of two characters or more opens the list; anything else closes it.
        state.completing = typed.len >= 2 and !std.ascii.isDigit(typed[0]) and !inComment(line, start) and app.source_focused;
        state.selected = 0;
    }
    if (!state.completing) return;
    if (typed.len == 0 or !app.source_focused) {
        state.completing = false;
        return;
    }
    state.word_start = .{ .line = cursor.line, .index = start };
    findMatches(app, typed);
    if (state.match_count == 0) {
        state.completing = false;
        return;
    }
    // The list takes the keys that move through it and choose from it.
    const route = c.ImGuiInputFlags_RouteGlobal | c.ImGuiInputFlags_RouteOverFocused;
    if (c.ImGui_Shortcut(c.ImGuiKey_Escape, route)) {
        state.completing = false;
        return;
    }
    if (c.ImGui_Shortcut(c.ImGuiKey_DownArrow, route | c.ImGuiInputFlags_Repeat)) state.selected = (state.selected + 1) % state.match_count;
    if (c.ImGui_Shortcut(c.ImGuiKey_UpArrow, route | c.ImGuiInputFlags_Repeat)) state.selected = (state.selected + state.match_count - 1) % state.match_count;
    state.selected = @min(state.selected, state.match_count - 1);
    const chosen = app.language.words[state.matches[state.selected]];
    if (c.ImGui_Shortcut(c.ImGuiKey_Enter, route) or c.ImGui_Shortcut(c.ImGuiKey_Tab, route)) {
        editor.replace(state.word_start, cursor, chosen.name);
        state.completing = false;
        return;
    }
    drawCompletion(app, document, typed);
}

fn inComment(line: []const u8, before: usize) bool {
    const comment = std.mem.find(u8, line, "--") orelse return false;
    return comment < before;
}

/// The words that start as `typed`, the game's commands first.
fn findMatches(app: *App, typed: []const u8) void {
    state.match_count = 0;
    const order = [_]game.WordKind{ .command, .declaration, .keyword, .game_variable, .condition, .value };
    for (order) |kind| {
        for (app.language.words, 0..) |word, index| {
            if (state.match_count == max_completions) return;
            if (word.kind != kind) continue;
            if (word.name.len <= typed.len or !std.ascii.startsWithIgnoreCase(word.name, typed)) continue;
            state.matches[state.match_count] = index;
            state.match_count += 1;
        }
    }
}

fn drawCompletion(app: *App, document: *Document, typed: []const u8) void {
    const editor = document.editor;
    const anchor = editor.screenPos(state.word_start);
    const line_height = editor.lineHeight();
    const list_width = px(280);
    const detail_width = px(360);
    const row_height = px(24);
    const rows: f32 = @floatFromInt(state.match_count);
    const height = @max(rows * row_height + px(8), px(150));
    const at = gui.vec2(anchor.x - px(30), anchor.y + line_height + px(2));
    const list = c.ImGui_GetForegroundDrawList();
    const max = gui.vec2(at.x + list_width + detail_width, at.y + height);
    // The shadow, the box and the line between its halves.
    c.ImDrawList_AddRectFilledEx(list, .{ .x = at.x + px(2), .y = at.y + px(6) }, .{ .x = max.x + px(2), .y = max.y + px(10) }, theme.fade(theme.rgb(0x000000), 0.35), px(8), 0);
    c.ImDrawList_AddRectFilledEx(list, at, max, theme.popup, px(6), 0);
    c.ImDrawList_AddRectEx(list, at, max, theme.border_strong, px(6), px(1), 0);
    c.ImDrawList_AddLineEx(list, .{ .x = at.x + list_width, .y = at.y }, .{ .x = at.x + list_width, .y = max.y }, theme.table_head_line, px(1));
    var y = at.y + px(4);
    for (state.matches[0..state.match_count], 0..) |index, place| {
        const word = app.language.words[index];
        const selected = place == state.selected;
        if (selected) c.ImDrawList_AddRectFilled(list, .{ .x = at.x + px(1), .y = y }, .{ .x = at.x + list_width - px(1), .y = y + row_height }, theme.popup_selected);
        const middle = y + row_height / 2;
        widgets.drawIcon(list, .{ .x = at.x + px(9), .y = middle }, kindIcon(word.kind), fonts.size.icon_small, kindColor(word.kind));
        gui.mono(.regular, fonts.size.ui);
        const text_y = gui.textTop(middle);
        const name_x = at.x + px(9) + px(14) + px(8);
        const typed_width = gui.textSize(word.name[0..typed.len]).x;
        gui.drawText(list, .{ .x = name_x, .y = text_y }, theme.teal_bright, word.name[0..typed.len]);
        gui.drawText(list, .{ .x = name_x + typed_width, .y = text_y }, if (selected) theme.white else theme.text_button, word.name[typed.len..]);
        gui.popFont();
        gui.sans(.regular, fonts.size.smaller);
        const kind = word.kind.label();
        gui.drawText(list, .{ .x = at.x + list_width - px(9) - gui.textSize(kind).x, .y = gui.textTop(middle) }, if (selected) theme.popup_kind else theme.text_dim, kind);
        gui.popFont();
        y += row_height;
    }
    // The chosen word's help.
    const chosen = app.language.words[state.matches[state.selected]];
    var detail_y = at.y + px(10);
    const detail_x = at.x + list_width + px(12);
    const wrap = detail_width - px(24);
    gui.mono(.regular, fonts.size.small);
    detail_y = wrapped(list, .{ .x = detail_x, .y = detail_y }, wrap, theme.text_button, if (chosen.signature.len > 0) chosen.signature else chosen.name) + px(7);
    gui.popFont();
    gui.sans(.regular, fonts.size.ui);
    if (chosen.about.len > 0 or chosen.source.len > 0) {
        const about = if (chosen.about.len > 0 and chosen.source.len > 0) gui.print("{s}. {s}.", .{ std.mem.trimEnd(u8, chosen.about, "."), chosen.source }) else if (chosen.about.len > 0) chosen.about else chosen.source;
        detail_y = wrapped(list, .{ .x = detail_x, .y = detail_y }, wrap, theme.text_menu, about) + px(7);
    }
    gui.popFont();
    gui.sans(.regular, fonts.size.small);
    gui.drawText(list, .{ .x = detail_x, .y = detail_y }, theme.text_dim, "Enter: insert · Esc: close");
    gui.popFont();
}

/// Draws `text` wrapped at `width` from `at`, in the current font; where the next line starts.
fn wrapped(list: *c.ImDrawList, at: gui.Vec2, width: f32, color: theme.Color, text: []const u8) f32 {
    const font = c.ImGui_GetFont();
    const size = c.ImGui_GetFontSize();
    c.ImDrawList_AddTextImFontPtrEx(list, font, size, at, color, text.ptr, text.ptr + text.len, width, null);
    const measured = c.ImGui_CalcTextSizeEx(text.ptr, text.ptr + text.len, false, width);
    return at.y + measured.y;
}

fn kindIcon(kind: game.WordKind) Icon {
    return switch (kind) {
        .command => .terminal,
        .declaration => .braces,
        .keyword => .code,
        .game_variable => .variable,
        .condition => .zap,
        .value => .hash,
    };
}

fn kindColor(kind: game.WordKind) theme.Color {
    return switch (kind) {
        .command => theme.syntax.command,
        .declaration => theme.syntax.declaration,
        .keyword => theme.syntax.keyword,
        .game_variable => theme.syntax.game,
        .condition => theme.syntax.string,
        .value => theme.syntax.number,
    };
}

/// The read-only script listing of the last build.
fn listing(app: *App, document: *Document) void {
    const shown = document.listing orelse {
        gui.setCursor(gui.add(gui.cursor(), .{ .x = px(12), .y = px(12) }));
        widgets.caption(gui.print("Not built yet · {s} builds it", .{app.keyText(.build) orelse "Build"}), theme.text_dim, fonts.size.small, .regular);
        return;
    };
    if (document.listing_fresh or state.listing_shown != shown.ptr) {
        app.listing_view.setText(shown);
        state.listing_shown = shown.ptr;
        document.listing_fresh = false;
    }
    gui.mono(.regular, fonts.size.ui);
    _ = app.listing_view.render("##listing");
    gui.popFont();
}

/// Draws a line's number, with its breakpoint or its problem in the room before it, which a click
/// sets or clears a breakpoint in.
fn drawLineNumber(app: *App, number: *const c.OrTextLineNumber) void {
    const document = app.document orelse return;
    const list: *c.ImDrawList = @ptrCast(@alignCast(number.draw_list));
    const line = number.line;
    const glyph = document.editor.glyphWidth();
    const middle = number.y + number.height / 2;
    // The room before the number holds the marks.
    const marks_min = gui.vec2(number.x - glyph * (marker_room + 1), number.y);
    const marks_max = gui.vec2(number.x - glyph * 0.6, number.y + number.height);
    const center = gui.vec2((marks_min.x + marks_max.x) / 2, middle);
    const breakpoint = document.hasBreakpoint(line);
    var problem = false;
    for (document.problems()) |found| problem = problem or found.at.line == line;
    const hovered = c.ImGui_IsMouseHoveringRect(marks_min, marks_max) and c.ImGui_IsWindowHovered(0);
    if (breakpoint) {
        gui.dot(list, center, 5, theme.breakpoint);
    } else if (problem) {
        widgets.drawIcon(list, .{ .x = center.x - px(6), .y = middle }, .circle_alert, fonts.size.icon_tiny, theme.error_icon);
    } else if (hovered) {
        gui.dot(list, center, 5, theme.fade(theme.breakpoint, 0.35));
    }
    if (hovered) {
        c.ImGui_SetMouseCursor(c.ImGuiMouseCursor_Hand);
        if (c.ImGui_IsMouseClicked(c.ImGuiMouseButton_Left)) document.toggleBreakpoint(line);
    }
    const text = gui.print("{d}", .{line + 1});
    const color = if (problem) theme.error_count else if (line == number.cursor_line) theme.text_menu else theme.text_faint;
    const width = gui.textSize(text).x;
    gui.drawText(list, .{ .x = number.x + number.width - width, .y = gui.textTop(number.y + number.height / 2) }, color, text);
}

/// A line's decoration: a problem's message at the end of its line.
fn drawDecoration(app: *App, decoration: *const c.OrTextDecoration) void {
    const document = app.document orelse return;
    const line = decoration.line;
    for (document.problems()) |problem| {
        if (problem.at.line != line) continue;
        const text = document.editor.lineText(line);
        const end = document.editor.screenPos(.{ .line = line, .index = text.len });
        const list = c.ImGui_GetWindowDrawList();
        const message = shortMessage(document, problem);
        gui.sans(.regular, fonts.size.smaller);
        defer gui.popFont();
        const x = end.x + decoration.glyph_width * 3;
        const height = decoration.height;
        const width = px(12) + px(5) + gui.textSize(message).x + px(16);
        const min = gui.vec2(x, end.y + px(1));
        const max = gui.vec2(x + width, end.y + height - px(1));
        gui.rect(list, min, max, theme.error_outline_row, 3);
        widgets.drawIcon(list, .{ .x = x + px(6), .y = end.y + height / 2 }, .lightbulb, fonts.size.icon_tiny, theme.warning_text);
        gui.drawText(list, .{ .x = x + px(6) + px(12) + px(5), .y = gui.textTop(end.y + height / 2) }, theme.error_text, message);
        return;
    }
}

/// A problem in a few words, as the line's hint shows it: "not declared: enemy · closest: enemies".
fn shortMessage(document: *Document, problem: game.Problem) []const u8 {
    return switch (problem.kind) {
        .not_declared => |name| if (document.outline().closest(name)) |closest|
            gui.print("not declared: {s} · closest: {s}", .{ name, closest.name })
        else
            gui.print("not declared: {s}", .{name}),
        .other => problem.message,
    };
}

test wordAt {
    const editor: text_editor.TextEditor = .init();
    defer editor.deinit();
    editor.setText("    SetAI(enemies, \"fight\")");
    try std.testing.expectEqualStrings("SetAI", wordAt(editor, .{ .line = 0, .index = 6 }).?);
    try std.testing.expectEqualStrings("SetAI", wordAt(editor, .{ .line = 0, .index = 9 }).?);
    try std.testing.expectEqualStrings("enemies", wordAt(editor, .{ .line = 0, .index = 11 }).?);
    try std.testing.expectEqual(null, wordAt(editor, .{ .line = 0, .index = 2 }));
}
