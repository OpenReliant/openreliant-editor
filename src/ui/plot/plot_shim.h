/* ImPlot, which the Scene view's map draws with, through a C interface for the editor's Zig code
 * (`plot.zig`): a plot with equal axes, what its axes show, its places on the screen, and points
 * to drag. Places on the plot are doubles; on the screen, ImGui's pixels. */
#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The part of the plot its axes show. */
typedef struct OrPlotRect {
    double x_min, x_max, y_min, y_max;
} OrPlotRect;

void or_plot_create(void);
void or_plot_destroy(void);

/* The plots' look, their background an ImGui packed colour, with no padding and no border; and their
 * input, where the pointer pans them while the wheel and double clicks are left to the editor. */
void or_plot_style(unsigned int background);

/* Begins a plot `width` by `height` pixels, with equal axes and nothing else: no frame, grid,
 * labels, ticks, menus or box zoom. With `set`, the axes show `limits` from this frame on. False
 * where it isn't drawn; otherwise `or_plot_end` ends it. */
bool or_plot_begin(const char *id, float width, float height, bool set, OrPlotRect limits);
void or_plot_end(void);

/* What the axes show, the plot's area on the screen, and places between the two. */
OrPlotRect or_plot_limits(void);
void or_plot_area(float rect[4]);
void or_plot_to_pixels(double x, double y, float pixels[2]);
void or_plot_from_pixels(float x, float y, double place[2]);

/* The draw list over the plot, clipped to its area between `or_plot_push_clip` and
 * `or_plot_pop_clip`. */
void *or_plot_draw_list(void);
void or_plot_push_clip(void);
void or_plot_pop_clip(void);

/* A point the pointer can drag, `radius` pixels around (`x`, `y`), which the caller draws: true
 * while a drag moves it. */
bool or_plot_drag_point(int id, double *x, double *y, float radius, bool *clicked, bool *hovered, bool *held);

#ifdef __cplusplus
}
#endif
