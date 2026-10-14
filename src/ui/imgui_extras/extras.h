/* What the editor asks of Dear ImGui's internal API, which Dear Bindings' public C API leaves out:
 * the dock builder that lays out the panels, the current font's ascent, and the places of a docked
 * window's tab and dock node. The internal C bindings aren't translated, since translate-c can't
 * read their structs with bitfields. */
#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Dock nodes' internal flags (`ImGuiDockNodeFlags_`): no tab bar, no window menu button, no close
 * button for the whole node. */
#define OR_DOCK_NODE_NO_TAB_BAR (1 << 12)
#define OR_DOCK_NODE_NO_WINDOW_MENU_BUTTON (1 << 14)
#define OR_DOCK_NODE_NO_CLOSE_BUTTON (1 << 15)

/* The dock builder (`ImGui::DockBuilder*`), with directions as ImGuiDir. */
bool or_dock_builder_has_node(unsigned int node);
void or_dock_builder_reset(unsigned int dockspace, float width, float height);
unsigned int or_dock_builder_split(unsigned int node, int direction, float ratio, unsigned int *at_direction, unsigned int *opposite);
void or_dock_builder_dock_window(const char *name, unsigned int node);
void or_dock_builder_finish(unsigned int dockspace);

/* How far below the top of a line of the current font its baseline is, in pixels, as ImGui places
 * the glyphs (`ImFontBaked::Ascent`). */
float or_imgui_font_ascent(void);

/* The tab of the current window, where a dock node shows it: its rectangle, the draw list its tab
 * bar is drawn in, and whether it's the tab in front. False for a window that shows no tab. */
bool or_imgui_window_tab(float rect[4], void **draw_list, bool *selected);

/* The rectangle of the dock node the current window is in, its tab bar included. False for a
 * window that isn't docked, or that its node doesn't show. */
bool or_imgui_window_dock_node(float rect[4]);

#ifdef __cplusplus
}
#endif
