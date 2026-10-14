//! The source views' text editor: ImGuiColorTextEdit through its C shim (`text_editor/shim.h`),
//! with the design's colours and gutter, and the words of a game's language coloured.

const std = @import("std");
const c = @import("c");

const theme = @import("theme.zig");
const Color = theme.Color;

pub const Pos = c.OrTextPos;

/// A language for the editor's colours: its keywords, its declarations, the game's commands as
/// known names, and the special words, such as `game`, in a colour of their own.
pub const Language = struct {
    handle: *c.OrTextLanguage,

    pub const Words = struct {
        keywords: []const []const u8 = &.{},
        declarations: []const []const u8 = &.{},
        known: []const []const u8 = &.{},
        special: []const []const u8 = &.{},
    };

    pub fn init(name: []const u8, words: Words) Language {
        const handle = c.or_text_language_create(name.ptr, name.len).?;
        for ([_]struct { []const []const u8, c.OrTextWord }{
            .{ words.keywords, c.OR_TEXT_WORD_KEYWORD },
            .{ words.declarations, c.OR_TEXT_WORD_DECLARATION },
            .{ words.known, c.OR_TEXT_WORD_IDENTIFIER },
            .{ words.special, c.OR_TEXT_WORD_SPECIAL },
        }) |list| for (list[0]) |word| c.or_text_language_add(handle, list[1], word.ptr, word.len);
        return .{ .handle = handle };
    }

    pub fn deinit(language: Language) void {
        c.or_text_language_destroy(language.handle);
    }
};

/// The design's colours for code (`design/README.md`).
pub fn palette() [c.OR_TEXT_COLOR_COUNT]u32 {
    var colors: [c.OR_TEXT_COLOR_COUNT]u32 = @splat(theme.text);
    colors[c.OR_TEXT_COLOR_TEXT] = theme.syntax.name;
    colors[c.OR_TEXT_COLOR_KEYWORD] = theme.syntax.keyword;
    colors[c.OR_TEXT_COLOR_DECLARATION] = theme.syntax.declaration;
    colors[c.OR_TEXT_COLOR_NUMBER] = theme.syntax.number;
    colors[c.OR_TEXT_COLOR_STRING] = theme.syntax.string;
    colors[c.OR_TEXT_COLOR_PUNCTUATION] = theme.syntax.punctuation;
    colors[c.OR_TEXT_COLOR_PREPROCESSOR] = theme.syntax.game;
    colors[c.OR_TEXT_COLOR_IDENTIFIER] = theme.syntax.name;
    colors[c.OR_TEXT_COLOR_KNOWN_IDENTIFIER] = theme.syntax.command;
    colors[c.OR_TEXT_COLOR_COMMENT] = theme.syntax.comment;
    colors[c.OR_TEXT_COLOR_BACKGROUND] = theme.code;
    colors[c.OR_TEXT_COLOR_CURSOR] = theme.text;
    colors[c.OR_TEXT_COLOR_SELECTION] = theme.fade(theme.rgb(0x2a3d66), 0.85);
    colors[c.OR_TEXT_COLOR_WHITESPACE] = theme.rgb(0x2b3346);
    colors[c.OR_TEXT_COLOR_MATCHING_BRACKET_BACKGROUND] = theme.fade(theme.white, 0.07);
    colors[c.OR_TEXT_COLOR_MATCHING_BRACKET_ACTIVE] = theme.text_strong;
    colors[c.OR_TEXT_COLOR_MATCHING_BRACKET_LEVEL1] = theme.syntax.punctuation;
    colors[c.OR_TEXT_COLOR_MATCHING_BRACKET_LEVEL2] = theme.syntax.punctuation;
    colors[c.OR_TEXT_COLOR_MATCHING_BRACKET_LEVEL3] = theme.syntax.punctuation;
    colors[c.OR_TEXT_COLOR_MATCHING_BRACKET_ERROR] = theme.error_icon;
    colors[c.OR_TEXT_COLOR_LINE_NUMBER] = theme.chevron;
    colors[c.OR_TEXT_COLOR_CURRENT_LINE_NUMBER] = theme.text_menu;
    colors[c.OR_TEXT_COLOR_CURRENT_LINE_HIGHLIGHT] = theme.fade(theme.white, 0.025);
    colors[c.OR_TEXT_COLOR_CURRENT_LINE_HIGHLIGHT_BORDER] = theme.fade(theme.white, 0);
    return colors;
}

pub const TextEditor = struct {
    handle: *c.OrTextEditor,

    pub fn init() TextEditor {
        const handle = c.or_text_editor_create().?;
        const colors = palette();
        c.or_text_editor_set_palette(handle, &colors);
        c.or_text_editor_set_tab_size(handle, 4, true);
        c.or_text_editor_set_options(handle, true, true, true, true, true, true);
        c.or_text_editor_set_find_replace(handle, true);
        c.or_text_editor_set_show_whitespace(handle, false);
        return .{ .handle = handle };
    }

    pub fn deinit(editor: TextEditor) void {
        c.or_text_editor_destroy(editor.handle);
    }

    /// Draws the editor in the space left. True when the text changed.
    pub fn render(editor: TextEditor, id: [:0]const u8) bool {
        return c.or_text_editor_render(editor.handle, id, 0, 0);
    }

    pub fn setLanguage(editor: TextEditor, language: ?Language) void {
        c.or_text_editor_set_language(editor.handle, if (language) |known| known.handle else null);
    }

    pub fn setReadOnly(editor: TextEditor, on: bool) void {
        c.or_text_editor_set_read_only(editor.handle, on);
    }

    pub fn setText(editor: TextEditor, value: []const u8) void {
        c.or_text_editor_set_text(editor.handle, value.ptr, value.len);
    }

    /// The text, valid until the next call on the editor.
    pub fn text(editor: TextEditor) []const u8 {
        var length: usize = 0;
        const start = c.or_text_editor_text(editor.handle, &length);
        return start[0..length];
    }

    /// Line `line`'s text, valid until the next call on the editor.
    pub fn lineText(editor: TextEditor, line: usize) []const u8 {
        var length: usize = 0;
        const start = c.or_text_editor_line_text(editor.handle, line, &length);
        return start[0..length];
    }

    pub fn lineCount(editor: TextEditor) usize {
        return c.or_text_editor_line_count(editor.handle);
    }

    pub fn replace(editor: TextEditor, start: Pos, end: Pos, with: []const u8) void {
        c.or_text_editor_replace(editor.handle, start, end, with.ptr, with.len);
    }

    /// A number that changes whenever the text does.
    pub fn version(editor: TextEditor) usize {
        return c.or_text_editor_undo_index(editor.handle);
    }

    pub fn canUndo(editor: TextEditor) bool {
        return c.or_text_editor_can_undo(editor.handle);
    }

    pub fn canRedo(editor: TextEditor) bool {
        return c.or_text_editor_can_redo(editor.handle);
    }

    pub fn undo(editor: TextEditor) void {
        c.or_text_editor_undo(editor.handle);
    }

    pub fn redo(editor: TextEditor) void {
        c.or_text_editor_redo(editor.handle);
    }

    pub fn cut(editor: TextEditor) void {
        c.or_text_editor_cut(editor.handle);
    }

    pub fn copy(editor: TextEditor) void {
        c.or_text_editor_copy(editor.handle);
    }

    pub fn paste(editor: TextEditor) void {
        c.or_text_editor_paste(editor.handle);
    }

    pub fn selectAll(editor: TextEditor) void {
        c.or_text_editor_select_all(editor.handle);
    }

    pub fn toggleComments(editor: TextEditor) void {
        c.or_text_editor_toggle_comments(editor.handle);
    }

    pub fn openFind(editor: TextEditor) void {
        c.or_text_editor_open_find(editor.handle);
    }

    pub fn findNext(editor: TextEditor) void {
        c.or_text_editor_find_next(editor.handle);
    }

    pub fn focus(editor: TextEditor) void {
        c.or_text_editor_focus(editor.handle);
    }

    pub fn cursor(editor: TextEditor) Pos {
        return c.or_text_editor_cursor(editor.handle);
    }

    pub fn setCursor(editor: TextEditor, pos: Pos) void {
        c.or_text_editor_set_cursor(editor.handle, pos);
    }

    pub fn select(editor: TextEditor, start: Pos, end: Pos) void {
        c.or_text_editor_select(editor.handle, start, end);
    }

    pub fn scrollToLine(editor: TextEditor, line: usize) void {
        c.or_text_editor_scroll_to_line(editor.handle, line);
    }

    pub fn wordStart(editor: TextEditor, pos: Pos) Pos {
        return c.or_text_editor_word_start(editor.handle, pos);
    }

    pub fn wordEnd(editor: TextEditor, pos: Pos) Pos {
        return c.or_text_editor_word_end(editor.handle, pos);
    }

    pub fn lineHeight(editor: TextEditor) f32 {
        return c.or_text_editor_line_height(editor.handle);
    }

    pub fn glyphWidth(editor: TextEditor) f32 {
        return c.or_text_editor_glyph_width(editor.handle);
    }

    /// Where on the screen the character at `pos` starts, once the editor has been drawn.
    pub fn screenPos(editor: TextEditor, pos: Pos) c.ImVec2 {
        var at: c.ImVec2 = undefined;
        c.or_text_editor_screen_pos(editor.handle, pos, &at.x, &at.y);
        return at;
    }

    pub fn mouseOverGlyph(editor: TextEditor, at: c.ImVec2) bool {
        return c.or_text_editor_mouse_over_glyph(editor.handle, at.x, at.y);
    }

    pub fn posAt(editor: TextEditor, at: c.ImVec2) Pos {
        return c.or_text_editor_pos_at(editor.handle, at.x, at.y);
    }

    pub fn toggleFold(editor: TextEditor, line: usize) void {
        c.or_text_editor_toggle_fold(editor.handle, line);
    }

    /// The number kept with `line`, which moves with the line as the text above it changes.
    pub fn lineData(editor: TextEditor, line: usize) usize {
        return c.or_text_editor_line_data(editor.handle, line);
    }

    pub fn setLineData(editor: TextEditor, line: usize, data: usize) void {
        c.or_text_editor_set_line_data(editor.handle, line, data);
    }

    /// The lines with data, into `lines`, in order.
    pub fn linesWithData(editor: TextEditor, lines: []usize) []usize {
        const count = c.or_text_editor_lines_with_data(editor.handle, lines.ptr, lines.len);
        const found = lines[0..@min(count, lines.len)];
        std.mem.sort(usize, found, {}, std.sort.asc(usize));
        return found;
    }

    pub fn addMarker(editor: TextEditor, line: usize, number_color: Color, text_color: Color, tooltip: []const u8) void {
        c.or_text_editor_add_marker(editor.handle, line, number_color, text_color, "", 0, tooltip.ptr, tooltip.len);
    }

    pub fn clearMarkers(editor: TextEditor) void {
        c.or_text_editor_clear_markers(editor.handle);
    }

    pub fn addSquiggle(editor: TextEditor, start: Pos, end: Pos, color: Color, tooltip: []const u8) void {
        c.or_text_editor_add_squiggle(editor.handle, start, end, color, tooltip.ptr, tooltip.len);
    }

    pub fn clearSquiggles(editor: TextEditor) void {
        c.or_text_editor_clear_squiggles(editor.handle);
    }

    /// Draws each visible line's number with `draw`, called with `context`.
    pub fn setLineNumbers(editor: TextEditor, comptime Context: type, context: *Context, comptime draw: fn (*Context, *const c.OrTextLineNumber) void) void {
        const Bridge = struct {
            fn call(user: ?*anyopaque, number: [*c]const c.OrTextLineNumber) callconv(.c) void {
                draw(@ptrCast(@alignCast(user.?)), number);
            }
        };
        c.or_text_editor_set_line_numbers(editor.handle, Bridge.call, context);
    }

    /// Draws each visible line's decoration, `width` characters between its number and its text,
    /// with `draw`, called with `context`.
    pub fn setDecorations(editor: TextEditor, width: usize, comptime Context: type, context: *Context, comptime draw: fn (*Context, *const c.OrTextDecoration) void) void {
        const Bridge = struct {
            fn call(user: ?*anyopaque, decoration: [*c]const c.OrTextDecoration) callconv(.c) void {
                draw(@ptrCast(@alignCast(user.?)), decoration);
            }
        };
        c.or_text_editor_set_decorations(editor.handle, width, Bridge.call, context);
    }

    /// Fills the menu a right click opens on the text with `fill`, called with `context`.
    pub fn setTextMenu(editor: TextEditor, comptime Context: type, context: *Context, comptime fill: fn (*Context, Pos) void) void {
        const Bridge = struct {
            fn call(user: ?*anyopaque, pos: c.OrTextPos) callconv(.c) void {
                fill(@ptrCast(@alignCast(user.?)), pos);
            }
        };
        c.or_text_editor_set_context_menus(editor.handle, Bridge.call, null, context);
    }

    pub fn setLineSpacing(editor: TextEditor, spacing: f32) void {
        c.or_text_editor_set_line_spacing(editor.handle, spacing);
    }

    pub fn setMargins(editor: TextEditor, line_numbers: usize, decorations: usize, text_margin: usize) void {
        c.or_text_editor_set_margins(editor.handle, line_numbers, decorations, text_margin);
    }
};
