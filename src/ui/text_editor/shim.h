/* The text editor, ImGuiColorTextEdit's TextEditor, through a C interface for the editor's Zig
 * code (`text_editor.zig`). Lines and characters count from 0. Strings are UTF-8 and come with
 * their length. */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OrTextEditor OrTextEditor;
typedef struct OrTextLanguage OrTextLanguage;

/* A place in the text: a line, and a character on it. */
typedef struct OrTextPos {
    size_t line;
    size_t index;
} OrTextPos;

/* The palette's colours, in the text editor's order (`TextEditor::Color`). */
typedef enum OrTextColor {
    OR_TEXT_COLOR_TEXT,
    OR_TEXT_COLOR_KEYWORD,
    OR_TEXT_COLOR_DECLARATION,
    OR_TEXT_COLOR_NUMBER,
    OR_TEXT_COLOR_STRING,
    OR_TEXT_COLOR_PUNCTUATION,
    OR_TEXT_COLOR_PREPROCESSOR,
    OR_TEXT_COLOR_IDENTIFIER,
    OR_TEXT_COLOR_KNOWN_IDENTIFIER,
    OR_TEXT_COLOR_COMMENT,
    OR_TEXT_COLOR_BACKGROUND,
    OR_TEXT_COLOR_CURSOR,
    OR_TEXT_COLOR_SELECTION,
    OR_TEXT_COLOR_WHITESPACE,
    OR_TEXT_COLOR_MATCHING_BRACKET_BACKGROUND,
    OR_TEXT_COLOR_MATCHING_BRACKET_ACTIVE,
    OR_TEXT_COLOR_MATCHING_BRACKET_LEVEL1,
    OR_TEXT_COLOR_MATCHING_BRACKET_LEVEL2,
    OR_TEXT_COLOR_MATCHING_BRACKET_LEVEL3,
    OR_TEXT_COLOR_MATCHING_BRACKET_ERROR,
    OR_TEXT_COLOR_LINE_NUMBER,
    OR_TEXT_COLOR_CURRENT_LINE_NUMBER,
    OR_TEXT_COLOR_CURRENT_LINE_HIGHLIGHT,
    OR_TEXT_COLOR_CURRENT_LINE_HIGHLIGHT_BORDER,
    OR_TEXT_COLOR_COUNT,
} OrTextColor;

/* The kinds of word a language colours: control words, declarations, known names, and words in
 * the palette's preprocessor colour. */
typedef enum OrTextWord {
    OR_TEXT_WORD_KEYWORD,
    OR_TEXT_WORD_DECLARATION,
    OR_TEXT_WORD_IDENTIFIER,
    OR_TEXT_WORD_SPECIAL,
} OrTextWord;

/* A line's number, for the code that draws it: its box on the screen, in the editor's draw list. */
typedef struct OrTextLineNumber {
    void *draw_list;
    float x, y, width, height;
    size_t line;
    size_t cursor_line;
} OrTextLineNumber;

/* A line's decoration, between its number and its text. The ImGui cursor is at its top left. */
typedef struct OrTextDecoration {
    size_t line;
    float width, height;
    float glyph_width, glyph_height;
} OrTextDecoration;

typedef void (*OrTextLineNumberFn)(void *user, const OrTextLineNumber *number);
typedef void (*OrTextDecorationFn)(void *user, const OrTextDecoration *decoration);
typedef void (*OrTextPopupFn)(void *user, OrTextPos pos);

/* A language based on the editor's Lua: its comments, strings, numbers and brackets, with no words
 * of its own until `or_text_language_add` gives them. */
OrTextLanguage *or_text_language_create(const char *name, size_t length);
void or_text_language_destroy(OrTextLanguage *language);
void or_text_language_add(OrTextLanguage *language, OrTextWord kind, const char *word, size_t length);

OrTextEditor *or_text_editor_create(void);
void or_text_editor_destroy(OrTextEditor *editor);

/* Draws the editor in a child window of `width` by `height` (0 fills the space left), and handles
 * its input. True when the text changed. */
bool or_text_editor_render(OrTextEditor *editor, const char *id, float width, float height);
void or_text_editor_focus(OrTextEditor *editor);

void or_text_editor_set_language(OrTextEditor *editor, const OrTextLanguage *language);
void or_text_editor_set_palette(OrTextEditor *editor, const uint32_t colors[OR_TEXT_COLOR_COUNT]);
void or_text_editor_set_read_only(OrTextEditor *editor, bool on);
void or_text_editor_set_tab_size(OrTextEditor *editor, size_t size, bool spaces);
void or_text_editor_set_line_spacing(OrTextEditor *editor, float spacing);
/* The gutter: the room before the line numbers, between them and the decorations, and before the
 * text, in characters. */
void or_text_editor_set_margins(OrTextEditor *editor, size_t line_numbers, size_t decorations, size_t text);
void or_text_editor_set_options(OrTextEditor *editor, bool line_folding, bool current_line, bool matching_brackets, bool complete_pairs, bool auto_indent, bool scrollbar_map);
void or_text_editor_set_find_replace(OrTextEditor *editor, bool on);
void or_text_editor_set_show_whitespace(OrTextEditor *editor, bool on);

/* The text: set, read (valid until the next call on the editor), and changed by a part. */
void or_text_editor_set_text(OrTextEditor *editor, const char *text, size_t length);
const char *or_text_editor_text(OrTextEditor *editor, size_t *length);
const char *or_text_editor_line_text(OrTextEditor *editor, size_t line, size_t *length);
size_t or_text_editor_line_count(const OrTextEditor *editor);
void or_text_editor_replace(OrTextEditor *editor, OrTextPos start, OrTextPos end, const char *text, size_t length);
/* A number that changes with each change to the text, undone and redone ones too. */
size_t or_text_editor_undo_index(const OrTextEditor *editor);

bool or_text_editor_can_undo(const OrTextEditor *editor);
bool or_text_editor_can_redo(const OrTextEditor *editor);
void or_text_editor_undo(OrTextEditor *editor);
void or_text_editor_redo(OrTextEditor *editor);
void or_text_editor_cut(OrTextEditor *editor);
void or_text_editor_copy(OrTextEditor *editor);
void or_text_editor_paste(OrTextEditor *editor);
void or_text_editor_select_all(OrTextEditor *editor);
void or_text_editor_toggle_comments(OrTextEditor *editor);
void or_text_editor_open_find(OrTextEditor *editor);
void or_text_editor_find_next(OrTextEditor *editor);
bool or_text_editor_has_selection(const OrTextEditor *editor);

/* The main cursor, and its selection. */
OrTextPos or_text_editor_cursor(const OrTextEditor *editor);
void or_text_editor_selection(const OrTextEditor *editor, OrTextPos *start, OrTextPos *end);
void or_text_editor_set_cursor(OrTextEditor *editor, OrTextPos pos);
void or_text_editor_select(OrTextEditor *editor, OrTextPos start, OrTextPos end);
void or_text_editor_scroll_to_line(OrTextEditor *editor, size_t line);
size_t or_text_editor_first_visible_line(const OrTextEditor *editor);
size_t or_text_editor_last_visible_line(const OrTextEditor *editor);
/* Where the word around `pos` starts and ends. */
OrTextPos or_text_editor_word_start(const OrTextEditor *editor, OrTextPos pos);
OrTextPos or_text_editor_word_end(const OrTextEditor *editor, OrTextPos pos);

/* Sizes and places on the screen, valid once the editor has been drawn. */
float or_text_editor_line_height(const OrTextEditor *editor);
float or_text_editor_glyph_width(const OrTextEditor *editor);
void or_text_editor_screen_pos(const OrTextEditor *editor, OrTextPos pos, float *x, float *y);
bool or_text_editor_mouse_over_text(const OrTextEditor *editor, float x, float y);
bool or_text_editor_mouse_over_glyph(const OrTextEditor *editor, float x, float y);
OrTextPos or_text_editor_pos_at(const OrTextEditor *editor, float x, float y);

/* Folding, when line folding is on. */
void or_text_editor_toggle_fold(OrTextEditor *editor, size_t line);
bool or_text_editor_line_foldable(const OrTextEditor *editor, size_t line);
bool or_text_editor_line_folded(const OrTextEditor *editor, size_t line);

/* A number kept with each line, which stays with the line as lines are added and removed above
 * it, such as the line's breakpoint. 0 is none. */
void or_text_editor_set_line_data(OrTextEditor *editor, size_t line, uintptr_t data);
uintptr_t or_text_editor_line_data(const OrTextEditor *editor, size_t line);
/* The lines with data, up to `capacity` of them, into `lines`; how many there are. */
size_t or_text_editor_lines_with_data(const OrTextEditor *editor, size_t *lines, size_t capacity);

/* Marks: a line's number and text in colours with tooltips, and squiggles under a part of the
 * text. */
void or_text_editor_add_marker(OrTextEditor *editor, size_t line, uint32_t number_color, uint32_t text_color, const char *number_tooltip, size_t number_tooltip_length, const char *text_tooltip, size_t text_tooltip_length);
void or_text_editor_clear_markers(OrTextEditor *editor);
void or_text_editor_add_squiggle(OrTextEditor *editor, OrTextPos start, OrTextPos end, uint32_t color, const char *tooltip, size_t tooltip_length);
void or_text_editor_clear_squiggles(OrTextEditor *editor);

/* The code that draws each visible line's number, and each one's decoration in `width`
 * characters. */
void or_text_editor_set_line_numbers(OrTextEditor *editor, OrTextLineNumberFn draw, void *user);
void or_text_editor_set_decorations(OrTextEditor *editor, size_t width, OrTextDecorationFn draw, void *user);
/* The code that fills the menu a right click opens on the text or on the line numbers. */
void or_text_editor_set_context_menus(OrTextEditor *editor, OrTextPopupFn text, OrTextPopupFn line_numbers, void *user);

#ifdef __cplusplus
}
#endif
