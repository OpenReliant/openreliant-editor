//! Short messages in the window's bottom right corner, such as "Built mission90.dte", which fade
//! out after a few seconds.

const std = @import("std");
const c = @import("c");

const ui = @import("ui.zig");
const fonts = ui.fonts;
const gui = ui.gui;
const theme = ui.theme;
const widgets = ui.widgets;
const Window = @import("platform/window.zig").Window;

/// How long a message shows, and how long it takes to fade, in milliseconds.
const shown_ms = 4000;
const fade_ms = 600;
/// The most messages at once; a new one pushes out the oldest.
const capacity = 4;

pub const Kind = enum { info, success, failure };

const Toast = struct {
    kind: Kind,
    title: [96]u8 = undefined,
    title_len: usize = 0,
    detail: [160]u8 = undefined,
    detail_len: usize = 0,
    since: u64,
};

pub const Toasts = struct {
    list: [capacity]Toast = undefined,
    count: usize = 0,

    pub fn push(toasts: *Toasts, kind: Kind, title: []const u8, detail: []const u8) void {
        if (toasts.count == capacity) {
            std.mem.copyForwards(Toast, toasts.list[0 .. capacity - 1], toasts.list[1..capacity]);
            toasts.count -= 1;
        }
        var toast: Toast = .{ .kind = kind, .since = c.SDL_GetTicks() };
        toast.title_len = @min(title.len, toast.title.len);
        @memcpy(toast.title[0..toast.title_len], title[0..toast.title_len]);
        toast.detail_len = @min(detail.len, toast.detail.len);
        @memcpy(toast.detail[0..toast.detail_len], detail[0..toast.detail_len]);
        toasts.list[toasts.count] = toast;
        toasts.count += 1;
    }

    pub fn draw(toasts: *Toasts, window: *Window) void {
        const now = c.SDL_GetTicks();
        // Messages past their time leave.
        var kept: usize = 0;
        for (toasts.list[0..toasts.count]) |toast| {
            if (now - toast.since < shown_ms + fade_ms) {
                toasts.list[kept] = toast;
                kept += 1;
            }
        }
        toasts.count = kept;
        if (kept == 0) return;
        window.keepBusy();
        const viewport = c.ImGui_GetMainViewport();
        var bottom = viewport.*.WorkPos.y + viewport.*.WorkSize.y - gui.px(40);
        const right = viewport.*.WorkPos.x + viewport.*.WorkSize.x - gui.px(18);
        const list = c.ImGui_GetForegroundDrawList();
        var index = kept;
        while (index > 0) {
            index -= 1;
            const toast = toasts.list[index];
            const age = now - toast.since;
            const opacity: f32 = if (age < shown_ms) 1 else 1 - @as(f32, @floatFromInt(age - shown_ms)) / fade_ms;
            const width = gui.px(340);
            const height = gui.px(if (toast.detail_len > 0) 62 else 42);
            const min = gui.vec2(right - width, bottom - height);
            const max = gui.vec2(right, bottom);
            const background, const border, const accent = switch (toast.kind) {
                .success => .{ theme.rgb(0x0d1716), theme.linked_border, theme.linked },
                .failure => .{ theme.error_row, theme.rgb(0x3a1416), theme.error_icon },
                .info => .{ theme.panel, theme.border, theme.text_muted },
            };
            c.ImDrawList_AddRectFilledEx(list, min, max, theme.fade(background, 0.97 * opacity), gui.px(6), 0);
            c.ImDrawList_AddRectEx(list, min, max, theme.fade(border, opacity), gui.px(6), gui.px(1), 0);
            const icon: ui.icons.Icon = switch (toast.kind) {
                .success => .check,
                .failure => .circle_alert,
                .info => .info,
            };
            widgets.drawIcon(list, .{ .x = min.x + gui.px(14), .y = min.y + gui.px(21) }, icon, fonts.size.icon, theme.fade(accent, opacity));
            gui.sans(.semibold, fonts.size.ui);
            gui.drawText(list, .{ .x = min.x + gui.px(40), .y = min.y + gui.px(13) }, theme.fade(theme.text_strong, opacity), toast.title[0..toast.title_len]);
            gui.popFont();
            if (toast.detail_len > 0) {
                gui.sans(.regular, fonts.size.small);
                gui.drawText(list, .{ .x = min.x + gui.px(40), .y = min.y + gui.px(34) }, theme.fade(theme.text_menu, opacity), toast.detail[0..toast.detail_len]);
                gui.popFont();
            }
            bottom -= height + gui.px(8);
        }
    }
};
