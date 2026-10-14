// The editor's calls into Dear ImGui's internal API (`extras.h`).

#include "extras.h"

#include "imgui.h"
#include "imgui_internal.h"

extern "C" {

bool or_dock_builder_has_node(unsigned int node) { return ImGui::DockBuilderGetNode(node) != nullptr; }

void or_dock_builder_reset(unsigned int dockspace, float width, float height) {
    ImGui::DockBuilderRemoveNode(dockspace);
    ImGui::DockBuilderAddNode(dockspace, ImGuiDockNodeFlags_DockSpace);
    ImGui::DockBuilderSetNodeSize(dockspace, ImVec2(width, height));
}

unsigned int or_dock_builder_split(unsigned int node, int direction, float ratio, unsigned int *at_direction, unsigned int *opposite) {
    return ImGui::DockBuilderSplitNode(node, static_cast<ImGuiDir>(direction), ratio, at_direction, opposite);
}

void or_dock_builder_dock_window(const char *name, unsigned int node) { ImGui::DockBuilderDockWindow(name, node); }

void or_dock_builder_finish(unsigned int dockspace) { ImGui::DockBuilderFinish(dockspace); }

bool or_imgui_window_tab(float rect[4], void **draw_list, bool *selected) {
    ImGuiWindow *window = ImGui::GetCurrentWindow();
    ImGuiDockNode *node = window->DockNode;
    if (!window->DockIsActive || !node || !node->TabBar || !node->HostWindow) return false;
    *selected = node->TabBar->VisibleTabId == window->TabId;
    if (node->IsHiddenTabBar() || node->IsNoTabBar()) return false;
    ImGuiTabBar *bar = node->TabBar;
    ImGuiTabItem *tab = ImGui::TabBarFindTabByID(bar, window->TabId);
    if (!tab || tab->Width <= 0.0f) return false;
    // Where ImGui draws the tab (`TabItemEx`).
    rect[0] = bar->BarRect.Min.x + IM_TRUNC(tab->Offset - bar->ScrollingAnim);
    rect[1] = bar->BarRect.Min.y;
    rect[2] = rect[0] + tab->Width;
    rect[3] = bar->BarRect.Max.y;
    *draw_list = node->HostWindow->DrawList;
    return true;
}

} // extern "C"
