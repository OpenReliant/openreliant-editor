// ImPlot through the editor's C interface (`plot_shim.h`).

#include "plot_shim.h"

#include "imgui.h"
#include "implot.h"

extern "C" {

void or_plot_create(void) { ImPlot::CreateContext(); }

void or_plot_destroy(void) { ImPlot::DestroyContext(); }

void or_plot_style(unsigned int background) {
    ImPlotStyle &style = ImPlot::GetStyle();
    style.PlotPadding = ImVec2(0, 0);
    style.PlotBorderSize = 0;
    style.Colors[ImPlotCol_FrameBg] = ImVec4(0, 0, 0, 0);
    style.Colors[ImPlotCol_PlotBg] = ImGui::ColorConvertU32ToFloat4(background);
    // The editor zooms around the pointer itself, over the points too, and fits on a double click
    // with its own fit: ImPlot's zoom does nothing, and its fit waits for a middle double click.
    ImPlotInputMap &input = ImPlot::GetInputMap();
    input.ZoomRate = 0;
    input.Fit = ImGuiMouseButton_Middle;
}

bool or_plot_begin(const char *id, float width, float height, bool set, OrPlotRect limits) {
    if (!ImPlot::BeginPlot(id, ImVec2(width, height), ImPlotFlags_CanvasOnly | ImPlotFlags_Equal)) return false;
    const ImPlotAxisFlags axes = ImPlotAxisFlags_NoDecorations | ImPlotAxisFlags_NoMenus | ImPlotAxisFlags_NoHighlight |
                                 ImPlotAxisFlags_NoSideSwitch;
    ImPlot::SetupAxes(nullptr, nullptr, axes, axes);
    if (set) ImPlot::SetupAxesLimits(limits.x_min, limits.x_max, limits.y_min, limits.y_max, ImPlotCond_Always);
    // The axes settle now, so that the plot's places are known before anything is drawn.
    ImPlot::SetupFinish();
    return true;
}

void or_plot_end(void) { ImPlot::EndPlot(); }

OrPlotRect or_plot_limits(void) {
    const ImPlotRect limits = ImPlot::GetPlotLimits();
    return OrPlotRect{limits.X.Min, limits.X.Max, limits.Y.Min, limits.Y.Max};
}

void or_plot_area(float rect[4]) {
    const ImVec2 at = ImPlot::GetPlotPos();
    const ImVec2 size = ImPlot::GetPlotSize();
    rect[0] = at.x;
    rect[1] = at.y;
    rect[2] = at.x + size.x;
    rect[3] = at.y + size.y;
}

void or_plot_to_pixels(double x, double y, float pixels[2]) {
    const ImVec2 at = ImPlot::PlotToPixels(x, y);
    pixels[0] = at.x;
    pixels[1] = at.y;
}

void or_plot_from_pixels(float x, float y, double place[2]) {
    const ImPlotPoint at = ImPlot::PixelsToPlot(x, y);
    place[0] = at.x;
    place[1] = at.y;
}

void *or_plot_draw_list(void) { return ImPlot::GetPlotDrawList(); }

void or_plot_push_clip(void) { ImPlot::PushPlotClipRect(); }

void or_plot_pop_clip(void) { ImPlot::PopPlotClipRect(); }

bool or_plot_drag_point(int id, double *x, double *y, float radius, bool *clicked, bool *hovered, bool *held) {
    // Drawn clear: the caller draws the marker.
    return ImPlot::DragPoint(id, x, y, ImVec4(0, 0, 0, 0), radius, ImPlotDragToolFlags_NoFit, clicked, hovered, held);
}

} // extern "C"
