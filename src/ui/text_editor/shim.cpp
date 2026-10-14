// The text editor's C interface (`shim.h`) over ImGuiColorTextEdit's C++ one.

#include "shim.h"

#include <string>
#include <string_view>
#include <unordered_set>

#include "TextEditor.h"

struct OrTextLanguage {
    TextEditor::Language language;
    // Words with a colour of their own, the palette's "preprocessor" one, such as mission source's
    // `game`.
    std::unordered_set<std::string> special;
};

struct OrTextEditor {
    TextEditor editor;
    // The text and the line last read, which the pointers the interface hands out point into.
    std::string text;
    std::string line;
    OrTextLineNumberFn line_number = nullptr;
    void *line_number_user = nullptr;
    OrTextDecorationFn decoration = nullptr;
    void *decoration_user = nullptr;
    OrTextPopupFn text_menu = nullptr;
    OrTextPopupFn number_menu = nullptr;
    void *menu_user = nullptr;
};

static TextEditor::DocPos docPos(OrTextPos pos) { return TextEditor::DocPos(pos.line, pos.index); }
static OrTextPos orPos(TextEditor::DocPos pos) { return OrTextPos{pos.line, pos.index}; }

// Reads an identifier, as the editor's own tokenizer does: a letter or an underscore, then
// letters, digits and underscores.
static bool startsIdentifier(ImWchar codepoint) {
    return codepoint == '_' || (codepoint >= 'a' && codepoint <= 'z') || (codepoint >= 'A' && codepoint <= 'Z');
}

static bool continuesIdentifier(ImWchar codepoint) {
    return startsIdentifier(codepoint) || (codepoint >= '0' && codepoint <= '9');
}

extern "C" {

OrTextLanguage *or_text_language_create(const char *name, size_t length) {
    auto *made = new OrTextLanguage{*TextEditor::Language::Lua(), {}};
    made->language.name = std::string(name, length);
    made->language.keywords.clear();
    made->language.declarations.clear();
    made->language.identifiers.clear();
    made->language.customTokenizer = [made](TextEditor::Iterator start, TextEditor::Iterator end, TextEditor::Color &color) {
        if (made->special.empty() || start == end || !startsIdentifier(*start)) return start;
        std::string word;
        auto at = start;
        while (at < end && continuesIdentifier(*at)) word.push_back(static_cast<char>(*at++));
        if (made->special.find(word) == made->special.end()) return start;
        color = TextEditor::Color::preprocessor;
        return at;
    };
    return made;
}

void or_text_language_destroy(OrTextLanguage *language) { delete language; }

void or_text_language_add(OrTextLanguage *language, OrTextWord kind, const char *word, size_t length) {
    std::string made(word, length);
    switch (kind) {
    case OR_TEXT_WORD_KEYWORD: language->language.keywords.insert(made); break;
    case OR_TEXT_WORD_DECLARATION: language->language.declarations.insert(made); break;
    case OR_TEXT_WORD_IDENTIFIER: language->language.identifiers.insert(made); break;
    case OR_TEXT_WORD_SPECIAL: language->special.insert(made); break;
    }
}

OrTextEditor *or_text_editor_create(void) { return new OrTextEditor(); }

void or_text_editor_destroy(OrTextEditor *editor) { delete editor; }

bool or_text_editor_render(OrTextEditor *editor, const char *id, float width, float height) {
    return editor->editor.Render(id, ImVec2(width, height));
}

void or_text_editor_focus(OrTextEditor *editor) { editor->editor.SetFocus(); }

void or_text_editor_set_language(OrTextEditor *editor, const OrTextLanguage *language) {
    editor->editor.SetLanguage(language ? &language->language : nullptr);
}

void or_text_editor_set_palette(OrTextEditor *editor, const uint32_t colors[OR_TEXT_COLOR_COUNT]) {
    TextEditor::Palette palette;
    for (size_t index = 0; index < palette.size(); index++) palette[index] = colors[index];
    editor->editor.SetPalette(palette);
}

void or_text_editor_set_read_only(OrTextEditor *editor, bool on) { editor->editor.SetReadOnlyEnabled(on); }

void or_text_editor_set_tab_size(OrTextEditor *editor, size_t size, bool spaces) {
    editor->editor.SetTabSize(size);
    editor->editor.SetInsertSpacesOnTabs(spaces);
}

void or_text_editor_set_line_spacing(OrTextEditor *editor, float spacing) { editor->editor.SetLineSpacing(spacing); }

void or_text_editor_set_margins(OrTextEditor *editor, size_t line_numbers, size_t decorations, size_t text) {
    editor->editor.SetLineNumberLeftMargin(line_numbers);
    editor->editor.SetDecorationLeftMargin(decorations);
    editor->editor.SetTextLeftMargin(text);
}

void or_text_editor_set_options(OrTextEditor *editor, bool line_folding, bool current_line, bool matching_brackets, bool complete_pairs, bool auto_indent, bool scrollbar_map) {
    editor->editor.SetShowMatchingBrackets(matching_brackets);
    editor->editor.SetLineFoldingEnabled(line_folding);
    editor->editor.SetShowCurrentLineHighlightEnabled(current_line);
    editor->editor.SetCompletePairedGlyphs(complete_pairs);
    editor->editor.SetAutoIndentEnabled(auto_indent);
    editor->editor.SetShowScrollbarMiniMapEnabled(scrollbar_map);
}

void or_text_editor_set_find_replace(OrTextEditor *editor, bool on) { editor->editor.SetFindReplaceEnabled(on); }

void or_text_editor_set_show_whitespace(OrTextEditor *editor, bool on) { editor->editor.SetShowWhitespacesEnabled(on); }

void or_text_editor_set_text(OrTextEditor *editor, const char *text, size_t length) {
    editor->editor.SetText(std::string_view(text, length));
}

const char *or_text_editor_text(OrTextEditor *editor, size_t *length) {
    editor->text = editor->editor.GetText();
    *length = editor->text.size();
    return editor->text.c_str();
}

const char *or_text_editor_line_text(OrTextEditor *editor, size_t line, size_t *length) {
    editor->line = editor->editor.GetLineText(line);
    *length = editor->line.size();
    return editor->line.c_str();
}

size_t or_text_editor_line_count(const OrTextEditor *editor) { return editor->editor.GetLineCount(); }

void or_text_editor_replace(OrTextEditor *editor, OrTextPos start, OrTextPos end, const char *text, size_t length) {
    editor->editor.ReplaceSectionText(docPos(start), docPos(end), std::string_view(text, length));
}

size_t or_text_editor_undo_index(const OrTextEditor *editor) { return editor->editor.GetUndoIndex(); }

bool or_text_editor_can_undo(const OrTextEditor *editor) { return editor->editor.CanUndo(); }
bool or_text_editor_can_redo(const OrTextEditor *editor) { return editor->editor.CanRedo(); }
void or_text_editor_undo(OrTextEditor *editor) { editor->editor.Undo(); }
void or_text_editor_redo(OrTextEditor *editor) { editor->editor.Redo(); }
void or_text_editor_cut(OrTextEditor *editor) { editor->editor.Cut(); }
void or_text_editor_copy(OrTextEditor *editor) { editor->editor.Copy(); }
void or_text_editor_paste(OrTextEditor *editor) { editor->editor.Paste(); }
void or_text_editor_select_all(OrTextEditor *editor) { editor->editor.SelectAll(); }
void or_text_editor_toggle_comments(OrTextEditor *editor) { editor->editor.ToggleComments(); }
void or_text_editor_open_find(OrTextEditor *editor) { editor->editor.OpenFindReplaceWindow(); }
void or_text_editor_find_next(OrTextEditor *editor) { editor->editor.FindNext(); }
bool or_text_editor_has_selection(const OrTextEditor *editor) { return editor->editor.AnyCursorHasSelection(); }

OrTextPos or_text_editor_cursor(const OrTextEditor *editor) { return orPos(editor->editor.GetMainCursorPosition()); }

void or_text_editor_selection(const OrTextEditor *editor, OrTextPos *start, OrTextPos *end) {
    auto selection = editor->editor.GetMainCursorSelection();
    *start = orPos(selection.start);
    *end = orPos(selection.end);
}

void or_text_editor_set_cursor(OrTextEditor *editor, OrTextPos pos) { editor->editor.SetCursor(docPos(pos)); }

void or_text_editor_select(OrTextEditor *editor, OrTextPos start, OrTextPos end) {
    editor->editor.SelectRegion(docPos(start), docPos(end));
}

void or_text_editor_scroll_to_line(OrTextEditor *editor, size_t line) { editor->editor.ScrollToLine(line); }

size_t or_text_editor_first_visible_line(const OrTextEditor *editor) {
    return editor->editor.VisPos2DocPos(TextEditor::VisPos(editor->editor.GetFirstVisibleRow(), 0)).line;
}

size_t or_text_editor_last_visible_line(const OrTextEditor *editor) {
    return editor->editor.VisPos2DocPos(TextEditor::VisPos(editor->editor.GetLastVisibleRow(), 0)).line;
}

OrTextPos or_text_editor_word_start(const OrTextEditor *editor, OrTextPos pos) {
    return orPos(editor->editor.FindWordStart(docPos(pos), true));
}

OrTextPos or_text_editor_word_end(const OrTextEditor *editor, OrTextPos pos) {
    return orPos(editor->editor.FindWordEnd(docPos(pos), true));
}

float or_text_editor_line_height(const OrTextEditor *editor) { return editor->editor.GetLineHeight(); }
float or_text_editor_glyph_width(const OrTextEditor *editor) { return editor->editor.GetGlyphWidth(); }

void or_text_editor_screen_pos(const OrTextEditor *editor, OrTextPos pos, float *x, float *y) {
    auto at = editor->editor.DocPos2ScreenPos(docPos(pos));
    *x = at.x;
    *y = at.y;
}

bool or_text_editor_mouse_over_text(const OrTextEditor *editor, float x, float y) {
    return editor->editor.IsMousePosOverTextArea(ImVec2(x, y));
}

bool or_text_editor_mouse_over_glyph(const OrTextEditor *editor, float x, float y) {
    return editor->editor.IsMousePosOverGlyph(ImVec2(x, y));
}

OrTextPos or_text_editor_pos_at(const OrTextEditor *editor, float x, float y) {
    return orPos(editor->editor.GetDocPosAtMousePos(ImVec2(x, y)));
}

void or_text_editor_toggle_fold(OrTextEditor *editor, size_t line) { editor->editor.ToggleAtLine(line); }
bool or_text_editor_line_foldable(const OrTextEditor *editor, size_t line) { return editor->editor.IsLineFoldable(line); }
bool or_text_editor_line_folded(const OrTextEditor *editor, size_t line) { return editor->editor.IsLineFolded(line); }

void or_text_editor_set_line_data(OrTextEditor *editor, size_t line, uintptr_t data) {
    editor->editor.SetUserData(line, reinterpret_cast<void *>(data));
}

uintptr_t or_text_editor_line_data(const OrTextEditor *editor, size_t line) {
    return reinterpret_cast<uintptr_t>(editor->editor.GetUserData(line));
}

size_t or_text_editor_lines_with_data(const OrTextEditor *editor, size_t *lines, size_t capacity) {
    size_t count = 0;
    editor->editor.IterateUserData([&](size_t line, void *data) {
        if (!data) return;
        if (count < capacity) lines[count] = line;
        count++;
    });
    return count;
}

void or_text_editor_add_marker(OrTextEditor *editor, size_t line, uint32_t number_color, uint32_t text_color, const char *number_tooltip, size_t number_tooltip_length, const char *text_tooltip, size_t text_tooltip_length) {
    editor->editor.AddMarker(line, number_color, text_color, std::string_view(number_tooltip, number_tooltip_length), std::string_view(text_tooltip, text_tooltip_length));
}

void or_text_editor_clear_markers(OrTextEditor *editor) { editor->editor.ClearMarkers(); }

void or_text_editor_add_squiggle(OrTextEditor *editor, OrTextPos start, OrTextPos end, uint32_t color, const char *tooltip, size_t tooltip_length) {
    editor->editor.AddSquiggle(docPos(start), docPos(end), 0, color, std::string_view(tooltip, tooltip_length));
}

void or_text_editor_clear_squiggles(OrTextEditor *editor) { editor->editor.ClearSquiggles(); }

void or_text_editor_set_line_numbers(OrTextEditor *editor, OrTextLineNumberFn draw, void *user) {
    editor->line_number = draw;
    editor->line_number_user = user;
    if (!draw) {
        editor->editor.ClearCustomLineNumberRenderer();
        return;
    }
    editor->editor.SetCustomLineNumberRenderer([editor](const TextEditor::CustomLineNumber &data) {
        OrTextLineNumber number{data.drawList, data.pos.x, data.pos.y, data.size.x, data.size.y, data.lineNumber, data.cursorLineNumber};
        editor->line_number(editor->line_number_user, &number);
    });
}

void or_text_editor_set_decorations(OrTextEditor *editor, size_t width, OrTextDecorationFn draw, void *user) {
    editor->decoration = draw;
    editor->decoration_user = user;
    if (!draw) {
        editor->editor.ClearLineDecorator();
        return;
    }
    editor->editor.SetLineDecorator(width, [editor](TextEditor::Decorator &data) {
        OrTextDecoration decoration{data.line, data.width, data.height, data.glyphSize.x, data.glyphSize.y};
        editor->decoration(editor->decoration_user, &decoration);
    });
}

void or_text_editor_set_context_menus(OrTextEditor *editor, OrTextPopupFn text, OrTextPopupFn line_numbers, void *user) {
    editor->text_menu = text;
    editor->number_menu = line_numbers;
    editor->menu_user = user;
    if (text) {
        editor->editor.SetTextContextMenuCallback([editor](TextEditor::PopupData &data) { editor->text_menu(editor->menu_user, orPos(data.pos)); });
    } else {
        editor->editor.ClearTextContextMenuCallback();
    }
    if (line_numbers) {
        editor->editor.SetLineNumberContextMenuCallback([editor](TextEditor::PopupData &data) { editor->number_menu(editor->menu_user, orPos(data.pos)); });
    } else {
        editor->editor.ClearLineNumberContextMenuCallback();
    }
}

} // extern "C"
