//! The design's widgets, drawn on ImGui's draw lists with ImGui's own buttons for the input: tool
//! buttons, view tabs, chips, pills, key chips, rows of the outline, fields and switches. Each
//! takes its sizes from the design (`design/screens`), in its pixels.

const std = @import("std");
const c = @import("c");

const fonts = @import("fonts.zig");
const gui = @import("gui.zig");
const icons = @import("icons.zig");
const theme = @import("theme.zig");
const Color = theme.Color;
const Icon = icons.Icon;
const Vec2 = gui.Vec2;
const px = gui.px;

/// What a widget shows while it can't be used: the design's greyed-out look, with a tooltip
/// that says why.
pub const Disabled = struct {
    reason: []const u8,
};

pub const ButtonStyle = enum {
    /// The design's `.tb`: a dark button with a line around it.
    normal,
    /// Orange, for the action to take: Continue, a fix to apply.
    primary,
    /// No box until the pointer is over it, as the settings' arrow back.
    ghost,
};

pub const Corners = enum { all, left, right };

pub const ToolButton = struct {
    label: []const u8 = "",
    icon: ?Icon = null,
    icon_color: ?Color = null,
    style: ButtonStyle = .normal,
    /// A key chip after the label, such as Continue's F5.
    key: ?[]const u8 = null,
    /// A count's pill after the label, such as Build's problems.
    pill: ?Pill = null,
    disabled: ?Disabled = null,
    tooltip: ?[]const u8 = null,
    /// A square button with the icon alone.
    icon_only: bool = false,
    corners: Corners = .all,
    height: f32 = tool_button_height,
    /// The label's size and weight.
    size: f32 = fonts.size.ui,
    weight: fonts.Weight = .regular,
};

/// The design's heights of the toolbar's controls.
pub const tool_button_height = 28;
pub const picker_height = 30;
/// The view tabs' box: 26 pixels high tabs inside its line and padding.
pub const view_tabs_height = view_tab_height + view_tabs_inset * 2;
pub const divider_height = 20;
pub const chip_height = 26;

const view_tab_height = 26;
const view_tab_rounding = 4;
/// The view tabs' line and padding around the tabs.
const view_tabs_inset = 1 + 2;

/// How wide the design's `.tb` button is with `options`: its parts with 6 pixels between them,
/// in 10 pixels of padding, or 30 pixels for an icon alone.
pub fn toolButtonWidth(options: ToolButton) f32 {
    if (options.icon_only) return px(30);
    gui.sans(options.weight, options.size);
    defer gui.popFont();
    var width = px(10) * 2;
    var parts: f32 = 0;
    if (options.icon != null) {
        width += px(fonts.size.icon);
        parts += 1;
    }
    if (options.label.len > 0) {
        width += gui.textSize(options.label).x;
        parts += 1;
    }
    if (options.key) |key| {
        width += keyChipWidth(key);
        parts += 1;
    }
    if (options.pill) |pill_shown| {
        width += pillWidth(pill_shown.text);
        parts += 1;
    }
    if (parts > 1) width += px(6) * (parts - 1);
    return width;
}

/// The design's `.tb` button. True when clicked.
pub fn toolButton(id: []const u8, options: ToolButton) bool {
    const icon_size = fonts.size.icon;
    const width = toolButtonWidth(options);
    gui.sans(options.weight, options.size);
    defer gui.popFont();
    const label_width = if (options.label.len > 0) gui.textSize(options.label).x else 0;
    const height = px(options.height);
    const at = gui.cursor();
    const clicked = c.ImGui_InvisibleButton(gui.z(id), .{ .x = width, .y = height }, 0) and options.disabled == null;
    const hovered = c.ImGui_IsItemHovered(c.ImGuiHoveredFlags_AllowWhenDisabled);
    const held = c.ImGui_IsItemActive();
    if (options.disabled == null) gui.handCursor();

    var background = theme.button;
    var border = theme.border;
    var foreground = theme.text_button;
    switch (options.style) {
        .normal => if (hovered and options.disabled == null) {
            background = if (held) theme.button_pressed else theme.button_hover;
            border = theme.border_hover;
            foreground = theme.white;
        },
        .primary => {
            background = theme.accent;
            border = theme.accent;
            foreground = theme.on_accent;
            if (hovered and options.disabled == null) background = theme.accent_hover;
        },
        .ghost => {
            const lit = hovered and options.disabled == null;
            background = if (lit) theme.row_hover else theme.fade(theme.row_hover, 0);
            border = background;
            foreground = if (lit) theme.white else theme.text_menu;
        },
    }
    if (options.disabled != null) {
        background = theme.button_off;
        border = theme.border_off;
        foreground = theme.text_off;
    }
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    const flags: c.ImDrawFlags = switch (options.corners) {
        .all => c.ImDrawFlags_RoundCornersAll,
        .left => c.ImDrawFlags_RoundCornersLeft,
        .right => c.ImDrawFlags_RoundCornersRight,
    };
    c.ImDrawList_AddRectFilledEx(list, at, max, background, px(4), flags);
    c.ImDrawList_AddRectEx(list, at, max, border, px(4), px(1), flags);

    var x = at.x + px(10);
    const middle = at.y + height / 2;
    if (options.icon) |icon| {
        const color = if (options.disabled != null) foreground else options.icon_color orelse foreground;
        if (options.icon_only) {
            drawIconCentered(list, .{ .x = at.x + width / 2, .y = middle }, icon, icon_size, color);
        } else {
            drawIcon(list, .{ .x = x, .y = middle }, icon, icon_size, color);
            x += px(icon_size) + px(6);
        }
    }
    if (options.label.len > 0) {
        gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, foreground, options.label);
        x += label_width + px(6);
    }
    if (options.key) |key| {
        const on_accent = options.style == .primary and options.disabled == null;
        drawKeyChip(list, .{ .x = x, .y = middle }, key, if (on_accent) .on_accent else .normal);
        x += keyChipWidth(key) + px(6);
    }
    if (options.pill) |pill_shown| drawPill(list, .{ .x = x, .y = middle }, pill_shown);

    if (options.disabled) |off| {
        gui.tooltip(off.reason);
    } else if (options.tooltip) |tip| {
        gui.tooltip(tip);
    }
    return clicked;
}

/// Draws `icon` at `size` design pixels, centred on `middle.y`, starting at `middle.x`.
pub fn drawIcon(list: *c.ImDrawList, middle: Vec2, icon: Icon, size: f32, color: Color) void {
    gui.iconFont(size);
    defer gui.popFont();
    const glyph = icon.text();
    gui.drawText(list, .{ .x = middle.x, .y = middle.y - c.ImGui_GetFontSize() / 2 }, color, glyph);
}

/// Draws `icon` at `size` design pixels centred on `center`, for an icon on its own in a box, such
/// as an icon button's. The icons' font gives each icon a wider advance than its own, with the
/// icon in its middle, so that a column of icons lines up (`fonts.mergeIcons`): the advance is
/// what's centred here, where `drawIcon` starts the icon at its point.
pub fn drawIconCentered(list: *c.ImDrawList, center: Vec2, icon: Icon, size: f32, color: Color) void {
    gui.iconFont(size);
    const advance = gui.textSize(icon.text()).x;
    gui.popFont();
    drawIcon(list, .{ .x = @round(center.x - advance / 2), .y = center.y }, icon, size, color);
}

/// An icon as an item, `size` design pixels square, in the line's flow.
pub fn iconItem(which: Icon, size: f32, color: Color) void {
    const at = gui.cursor();
    c.ImGui_Dummy(.{ .x = px(size), .y = px(size) });
    drawIcon(gui.drawList(), .{ .x = at.x, .y = at.y + px(size) / 2 }, which, size, color);
}

pub const KeyChipStyle = enum { normal, on_accent };

/// The design's `.key`: a key's name in a small box.
pub fn keyChip(text: []const u8) void {
    const at = gui.cursor();
    const width = keyChipWidth(text);
    const height = keyChipHeight();
    c.ImGui_Dummy(.{ .x = width, .y = height });
    drawKeyChip(gui.drawList(), .{ .x = at.x, .y = at.y + height / 2 }, text, .normal);
}

pub fn keyChipWidth(text: []const u8) f32 {
    gui.mono(.medium, fonts.size.tiny);
    defer gui.popFont();
    return gui.textSize(text).x + px(4) * 2 + px(2);
}

/// A key chip's height: a line as high as its font's size, 2 pixels above and below it, and its
/// line.
fn keyChipHeight() f32 {
    return px(fonts.size.tiny) + px(2) * 2 + px(2);
}

/// Draws a key chip starting at `middle.x`, centred on `middle.y`.
pub fn drawKeyChip(list: *c.ImDrawList, middle: Vec2, text: []const u8, style: KeyChipStyle) void {
    gui.mono(.medium, fonts.size.tiny);
    defer gui.popFont();
    const width = gui.textSize(text).x + px(4) * 2 + px(2);
    const height = keyChipHeight();
    const min = gui.vec2(middle.x, middle.y - height / 2);
    const max = gui.vec2(middle.x + width, middle.y + height / 2);
    const background, const border, const foreground = switch (style) {
        .normal => .{ theme.bar, theme.key_border, theme.text_muted },
        .on_accent => .{ theme.accent_key, theme.accent_key, theme.on_accent_key },
    };
    gui.rect(list, min, max, background, 3);
    gui.outline(list, min, max, border, 3);
    gui.drawText(list, .{ .x = min.x + px(5), .y = gui.textTopIn(middle.y, fonts.size.tiny) }, foreground, text);
}

pub const PillStyle = enum { normal, err, warn };

pub const Pill = struct {
    text: []const u8,
    style: PillStyle = .normal,
};

/// The design's `.pill`: a count in a rounded box.
pub fn pill(shown: Pill) void {
    const at = gui.cursor();
    const width = pillWidth(shown.text);
    const height = px(16);
    c.ImGui_Dummy(.{ .x = width, .y = height });
    drawPill(gui.drawList(), .{ .x = at.x, .y = at.y + height / 2 }, shown);
}

pub fn pillWidth(text: []const u8) f32 {
    gui.sans(.regular, fonts.size.tiny);
    defer gui.popFont();
    return @max(px(18), gui.textSize(text).x + px(5) * 2);
}

/// The design's pills have 16 pixel lines.
const pill_line = 16;

pub fn drawPill(list: *c.ImDrawList, middle: Vec2, shown: Pill) void {
    gui.sans(.regular, fonts.size.tiny);
    defer gui.popFont();
    const width = @max(px(18), gui.textSize(shown.text).x + px(5) * 2);
    const height = px(16);
    const background, const foreground = switch (shown.style) {
        .normal => .{ theme.pill, theme.text_menu },
        .err => .{ theme.error_pill, theme.error_pill_text },
        .warn => .{ theme.warning_pill, theme.warning_pill_text },
    };
    const min = gui.vec2(middle.x, middle.y - height / 2);
    gui.rect(list, min, .{ .x = middle.x + width, .y = middle.y + height / 2 }, background, 9);
    const text_width = gui.textSize(shown.text).x;
    gui.drawText(list, .{ .x = middle.x + (width - text_width) / 2, .y = gui.textTopIn(middle.y, pill_line) }, foreground, shown.text);
}

pub const ChipStyle = enum {
    /// The script is held: orange.
    held,
    /// A linked game: teal.
    linked,
    /// No game linked: grey.
    idle,
    /// A problem: yellow.
    warning,
};

pub const Chip = struct {
    style: ChipStyle,
    text: []const u8,
    /// A second part in a dimmer colour, such as the time held.
    extra: ?[]const u8 = null,
    extra_mono: bool = false,
    tooltip: ?[]const u8 = null,
};

/// The design's status chips at the toolbar's end: a dot or an icon, a label and a detail.
pub fn chipWidth(shown: Chip) f32 {
    gui.sans(.regular, fonts.size.small);
    var width = px(11) * 2 + gui.textSize(shown.text).x;
    gui.popFont();
    width += switch (shown.style) {
        .warning => px(14) + px(7),
        else => px(7) + px(7),
    };
    if (shown.extra) |extra| {
        if (shown.extra_mono) gui.mono(.regular, fonts.size.small) else gui.sans(.regular, fonts.size.small);
        width += px(7) + gui.textSize(extra).x;
        gui.popFont();
    }
    return width;
}

pub fn chip(shown: Chip) void {
    const width = chipWidth(shown);
    const height = px(chip_height);
    const at = gui.cursor();
    c.ImGui_Dummy(.{ .x = width, .y = height });
    const list = gui.drawList();
    const background, const border, const foreground, const dim, const dot_color = switch (shown.style) {
        .held => .{ theme.held, theme.held, theme.held_text, theme.held_dim, theme.accent },
        .linked => .{ theme.linked_chip, theme.linked_border, theme.linked_text, theme.linked_text, theme.linked },
        .idle => .{ theme.field, theme.border, theme.text_muted, theme.text_dim, theme.text_off },
        .warning => .{ theme.warning_chip, theme.warning_border, theme.warning_text, theme.warning_dim, theme.warning_text },
    };
    const max = gui.vec2(at.x + width, at.y + height);
    gui.rect(list, at, max, background, 13);
    gui.outline(list, at, max, border, 13);
    var x = at.x + px(11);
    const middle = at.y + height / 2;
    if (shown.style == .warning) {
        drawIcon(list, .{ .x = x, .y = middle }, .triangle_alert, fonts.size.icon_small, foreground);
        x += px(14) + px(7);
    } else {
        gui.dot(list, .{ .x = x + px(3.5), .y = middle }, 3.5, dot_color);
        x += px(7) + px(7);
    }
    gui.sans(.regular, fonts.size.small);
    gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, foreground, shown.text);
    x += gui.textSize(shown.text).x + px(7);
    gui.popFont();
    if (shown.extra) |extra| {
        if (shown.extra_mono) gui.mono(.regular, fonts.size.small) else gui.sans(.regular, fonts.size.small);
        gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, dim, extra);
        gui.popFont();
    }
    if (shown.tooltip) |tip| gui.tooltip(tip);
}

/// A thin upright line between groups of the toolbar's buttons, with 4 pixels to each side.
pub fn toolbarDivider() void {
    const at = gui.cursor();
    const height = px(divider_height);
    c.ImGui_Dummy(.{ .x = px(4) * 2 + px(1), .y = height });
    const x = at.x + px(4);
    gui.rect(gui.drawList(), .{ .x = x, .y = at.y }, .{ .x = x + px(1), .y = at.y + height }, theme.border, 0);
}

/// The height of the design's tab bar over a panel, `.tabbar`, its line at the bottom included.
pub const tab_bar_height = 30;

/// The design's panel tab, `.tab`: its padding of 12 on each side, and its parts 7 apart.
pub const PanelTab = struct {
    label: []const u8,
    icon: ?Icon = null,
    /// The icon's colour where it isn't the label's, such as the source file's orange.
    icon_color: ?Color = null,
    /// A dimmer part after the label, such as the listing's file.
    detail: ?[]const u8 = null,
    /// A dot after the label, for changes not saved.
    dot: bool = false,
    /// A count's pill after the label.
    pill: ?Pill = null,
    /// The tab in front.
    on: bool = false,

    const padding = 12;
    const gap = 7;
    const dot_size = 7;

    /// Its width, with its line at the right.
    pub fn width(tab: PanelTab) f32 {
        gui.sans(.regular, fonts.size.ui);
        defer gui.popFont();
        var total = px(padding) * 2 + gui.spacedWidth(tab.label, 0) + px(1);
        if (tab.icon != null) total += px(fonts.size.icon_small) + px(gap);
        if (tab.detail) |detail| total += px(gap) + gui.spacedWidth(detail, 0);
        if (tab.dot) total += px(gap) + px(dot_size);
        if (tab.pill) |shown| total += px(gap) + pillWidth(shown.text);
        return total;
    }

    /// Draws it from `min` to `max`, the tab bar's line under it left out: in front, the panel's
    /// colour with an orange line over it, and a line at its right.
    pub fn draw(tab: PanelTab, list: *c.ImDrawList, min: Vec2, max: Vec2, hovered: bool) void {
        const right = max.x - px(1);
        if (tab.on) {
            gui.rect(list, min, .{ .x = right, .y = max.y }, theme.panel, 0);
            gui.rect(list, min, .{ .x = right, .y = min.y + px(2) }, theme.accent, 0);
        }
        gui.rect(list, .{ .x = right, .y = min.y }, max, theme.tab_divider, 0);
        const foreground = if (tab.on) theme.text_strong else if (hovered) theme.text else theme.text_muted;
        const middle = (min.y + max.y) / 2;
        var x = min.x + px(padding);
        if (tab.icon) |icon| {
            drawIcon(list, .{ .x = x, .y = middle }, icon, fonts.size.icon_small, tab.icon_color orelse foreground);
            x += px(fonts.size.icon_small) + px(gap);
        }
        gui.sans(.regular, fonts.size.ui);
        defer gui.popFont();
        gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, foreground, tab.label);
        x += gui.spacedWidth(tab.label, 0);
        if (tab.detail) |detail| {
            x += px(gap);
            gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_faint, detail);
            x += gui.spacedWidth(detail, 0);
        }
        if (tab.dot) {
            x += px(gap);
            gui.dot(list, .{ .x = x + px(dot_size) / 2, .y = middle }, dot_size / 2, theme.text_menu);
            x += px(dot_size);
        }
        if (tab.pill) |shown| drawPill(list, .{ .x = x + px(gap), .y = middle }, shown);
    }
};

/// A panel's own tab bar, as the source panel's: `tabs` side by side from its left on the bar's
/// colour, with its line under them. The tab clicked, if one is.
pub fn panelTabs(tabs: []const PanelTab) ?usize {
    const at = gui.cursor();
    const width = gui.available().x;
    const height = px(tab_bar_height);
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.bar, 0);
    gui.rect(list, .{ .x = at.x, .y = at.y + height - px(1) }, .{ .x = at.x + width, .y = at.y + height }, theme.tab_divider, 0);
    var clicked: ?usize = null;
    var x = at.x;
    for (tabs, 0..) |tab, index| {
        const tab_width = tab.width();
        gui.setCursor(.{ .x = x, .y = at.y });
        gui.pushIdInt(index);
        if (c.ImGui_InvisibleButton("tab", .{ .x = tab_width, .y = height - px(1) }, 0)) clicked = index;
        gui.popId();
        tab.draw(list, .{ .x = x, .y = at.y }, .{ .x = x + tab_width, .y = at.y + height - px(1) }, gui.hovered());
        if (tab.dot) gui.tooltip("Changed since saved");
        x += tab_width;
    }
    gui.setCursor(.{ .x = at.x, .y = at.y + height });
    return clicked;
}

pub const ViewTab = struct {
    label: []const u8,
    icon: Icon,
    disabled: ?Disabled = null,
    tooltip: ?[]const u8 = null,
};

/// The design's `.views`: a mission's views, Script, Scene and Blocks, as tabs in one box. The
/// index of the tab clicked, if one was.
pub fn viewTabs(id: []const u8, tabs: []const ViewTab, current: usize) ?usize {
    gui.pushId(id);
    defer gui.popId();
    gui.sans(.medium, fonts.size.ui);
    defer gui.popFont();
    var total: f32 = px(view_tabs_inset) * 2 + px(2) * @as(f32, @floatFromInt(tabs.len - 1));
    for (tabs) |tab| total += tabWidth(tab);
    const at = gui.cursor();
    const height = px(view_tabs_height);
    const list = gui.drawList();
    const box_max = gui.vec2(at.x + total, at.y + height);
    gui.rect(list, at, box_max, theme.code, 6);
    gui.outline(list, at, box_max, theme.border, 6);
    var clicked: ?usize = null;
    var x = at.x + px(view_tabs_inset);
    const tab_top = at.y + px(view_tabs_inset);
    for (tabs, 0..) |tab, index| {
        const width = tabWidth(tab);
        gui.setCursor(.{ .x = x, .y = tab_top });
        gui.pushIdInt(index);
        const pressed = c.ImGui_InvisibleButton("view", .{ .x = width, .y = px(view_tab_height) }, 0);
        gui.popId();
        const hovered = c.ImGui_IsItemHovered(c.ImGuiHoveredFlags_AllowWhenDisabled);
        if (tab.disabled == null) gui.handCursor();
        const on = index == current;
        const min = gui.vec2(x, tab_top);
        const max = gui.vec2(x + width, tab_top + px(view_tab_height));
        var foreground = theme.text_muted;
        if (tab.disabled != null) {
            foreground = theme.text_off;
        } else if (on) {
            gui.rect(list, min, max, theme.border, view_tab_rounding);
            // An orange line along the bottom: the tab's last 2 pixels, which thin out into its
            // rounded corners.
            c.ImDrawList_PushClipRect(list, .{ .x = min.x, .y = max.y - px(2) }, max, true);
            gui.rect(list, min, max, theme.accent, view_tab_rounding);
            c.ImDrawList_PopClipRect(list);
            foreground = theme.white;
        } else if (hovered) {
            gui.rect(list, min, max, theme.row_hover, view_tab_rounding);
            foreground = theme.white;
        }
        const middle = at.y + height / 2;
        drawIcon(list, .{ .x = x + px(11), .y = middle }, tab.icon, fonts.size.icon_small, foreground);
        gui.drawText(list, .{ .x = x + px(11) + px(14) + px(7), .y = gui.textTop(middle) }, foreground, tab.label);
        if (tab.disabled) |off| {
            gui.tooltip(off.reason);
        } else if (tab.tooltip) |tip| {
            gui.tooltip(tip);
        }
        if (pressed and tab.disabled == null) clicked = index;
        x += width + px(2);
    }
    gui.setCursor(.{ .x = at.x, .y = at.y });
    c.ImGui_Dummy(.{ .x = total, .y = height });
    return clicked;
}

fn tabWidth(tab: ViewTab) f32 {
    return px(11) * 2 + px(14) + px(7) + gui.textSize(tab.label).x;
}

/// The design's mission picker, `.mpick`: the open mission's name with a flag and a chevron.
/// True when clicked.
pub fn picker(id: []const u8, label: []const u8, flag_color: Color, tooltip: ?[]const u8) bool {
    gui.sans(.semibold, fonts.size.body);
    defer gui.popFont();
    const width = px(10) * 2 + px(14) + px(7) + gui.textSize(label).x + px(7) + px(12);
    const height = px(picker_height);
    const at = gui.cursor();
    const clicked = c.ImGui_InvisibleButton(gui.z(id), .{ .x = width, .y = height }, 0);
    const hovered = gui.hovered();
    gui.handCursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    gui.rect(list, at, max, theme.field, 5);
    gui.outline(list, at, max, if (hovered) theme.border_strong else theme.border, 5);
    const middle = at.y + height / 2;
    var x = at.x + px(10);
    drawIcon(list, .{ .x = x, .y = middle }, .flag, fonts.size.icon_small, flag_color);
    x += px(14) + px(7);
    gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_strong, label);
    x += gui.textSize(label).x + px(7);
    drawIcon(list, .{ .x = x, .y = middle }, .chevron_down, fonts.size.icon_tiny, theme.text_dim);
    if (tooltip) |tip| gui.tooltip(tip);
    return clicked;
}

/// The design's section heading, `.sect`: small capitals, spaced.
pub fn sectionHeading(text: []const u8) void {
    gui.sans(.semibold, fonts.size.tiny);
    defer gui.popFont();
    var upper: [128]u8 = undefined;
    const shown = std.ascii.upperString(upper[0..@min(text.len, upper.len)], text[0..@min(text.len, upper.len)]);
    const at = gui.cursor();
    const width = gui.spacedWidth(shown, 0.84);
    const height = px(fonts.size.tiny * fonts.line_height);
    c.ImGui_Dummy(.{ .x = width, .y = height });
    _ = gui.drawSpaced(gui.drawList(), .{ .x = at.x, .y = gui.textTop(at.y + height / 2) }, theme.text_dim, shown, 0.84);
}

pub const Badge = struct {
    text: []const u8,
    background: Color,
    foreground: Color,
};

/// Draws `text` at `at`, cut off with an ellipsis where it would pass `limit`.
pub fn clippedText(list: *c.ImDrawList, at: Vec2, limit: f32, color: Color, text: []const u8) void {
    if (at.x + gui.textSize(text).x <= limit) return gui.drawText(list, at, color, text);
    const ellipsis = "…";
    const shown = fittingStart(text, limit - at.x - gui.textSize(ellipsis).x, textWidth);
    gui.drawText(list, at, color, shown);
    gui.drawText(list, .{ .x = at.x + gui.textSize(shown).x, .y = at.y }, color, ellipsis);
}

/// How wide `text` is in the current font.
fn textWidth(text: []const u8) f32 {
    return gui.textSize(text).x;
}

/// The longest start of `text` that is at most `room` wide by `width` and ends between two
/// characters. It halves the lengths the start can be, since a longer start is never narrower.
/// `text` itself is wider than `room`.
fn fittingStart(text: []const u8, room: f32, comptime width: fn ([]const u8) f32) []const u8 {
    var fits: usize = 0;
    var too_long = text.len;
    while (too_long - fits > 1) {
        const half = fits + (too_long - fits) / 2;
        // The nearest end between two characters, below the half or else above it.
        var end = half;
        while (end > fits and isContinuation(text[end])) end -= 1;
        if (end == fits) {
            end = half;
            while (end < too_long and isContinuation(text[end])) end += 1;
            if (end == too_long) break;
        }
        if (width(text[0..end]) <= room) fits = end else too_long = end;
    }
    return text[0..fits];
}

/// Whether `byte` continues a character of UTF-8 rather than starting one.
fn isContinuation(byte: u8) bool {
    return byte & 0xc0 == 0x80;
}

test fittingStart {
    const characters = struct {
        /// A width of 1 for each character.
        fn width(text: []const u8) f32 {
            const count = std.unicode.utf8CountCodepoints(text) catch @panic("a start that splits a character");
            return @floatFromInt(count);
        }
    }.width;
    try std.testing.expectEqualStrings("abc", fittingStart("abcdef", 3, characters));
    try std.testing.expectEqualStrings("", fittingStart("abcdef", 0.5, characters));
    // A cut never splits a character: "é" is two bytes.
    try std.testing.expectEqualStrings("é", fittingStart("éa", 1, characters));
    try std.testing.expectEqualStrings("aéé", fittingStart("aééé", 3, characters));
    try std.testing.expectEqualStrings("aé", fittingStart("aé€é", 2.5, characters));
}

/// The design's small uppercase badges, such as START and HELD, ending at `right`. Where the badge
/// starts.
pub fn drawBadge(list: *c.ImDrawList, right: f32, middle: f32, shown: Badge) f32 {
    gui.sans(.semibold, fonts.size.tiny);
    defer gui.popFont();
    var upper: [32]u8 = undefined;
    const text = std.ascii.upperString(upper[0..@min(shown.text.len, upper.len)], shown.text[0..@min(shown.text.len, upper.len)]);
    const width = gui.spacedWidth(text, 0.5) + px(6) * 2;
    const height = px(16);
    const min = gui.vec2(right - width, middle - height / 2);
    gui.rect(list, min, .{ .x = right, .y = middle + height / 2 }, shown.background, 3);
    _ = gui.drawSpaced(list, .{ .x = min.x + px(6), .y = gui.textTop(middle) }, shown.foreground, text, 0.5);
    return min.x;
}

pub const RowMark = union(enum) {
    none,
    /// A coloured square, as a flight group's.
    swatch: Color,
    icon: struct { icon: Icon, color: Color, size: f32 = fonts.size.icon_tiny },
};

pub const RowEnd = union(enum) {
    none,
    /// A count or a detail in the dim colour.
    text: struct { text: []const u8, mono: bool = false, color: Color = theme.text_dim },
    badge: Badge,
    /// A breakpoint's red dot.
    dot: Color,
};

pub const Row = struct {
    label: []const u8,
    indent: f32 = 10,
    /// Null for a row that doesn't fold; whether it's open for one that does.
    open: ?bool = null,
    mark: RowMark = .none,
    end: RowEnd = .none,
    selected: bool = false,
    /// A row in error: a dark red background and red text.
    failed: bool = false,
    strong: bool = false,
    mono_label: bool = false,
    label_color: ?Color = null,
};

pub const RowResult = struct {
    clicked: bool = false,
    double_clicked: bool = false,
    toggled: bool = false,
};

/// The design's `.row`: a line of the outline, 24 pixels high, with a chevron when it folds, an
/// icon or a swatch, its label, and a count or a badge at its end.
pub fn row(id: []const u8, shown: Row) RowResult {
    const width = gui.available().x;
    const height = px(24);
    const at = gui.cursor();
    var result: RowResult = .{};
    result.clicked = c.ImGui_InvisibleButton(gui.z(id), .{ .x = @max(width, 1), .y = height }, 0);
    result.double_clicked = c.ImGui_IsItemHovered(0) and c.ImGui_IsMouseDoubleClicked(c.ImGuiMouseButton_Left);
    const hovered = gui.hovered();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    if (shown.selected) {
        gui.rect(list, at, max, theme.selected, 0);
    } else if (shown.failed) {
        gui.rect(list, at, max, theme.error_outline_row, 0);
    } else if (hovered) {
        gui.rect(list, at, max, theme.row_hover, 0);
    }
    const middle = at.y + height / 2;
    var x = at.x + px(shown.indent);
    if (shown.open) |open| {
        drawIcon(list, .{ .x = x, .y = middle }, if (open) .chevron_down else .chevron_right, fonts.size.icon_tiny, theme.text_dim);
        x += px(12) + px(7);
        if (result.clicked) result.toggled = true;
    }
    switch (shown.mark) {
        .none => {},
        .swatch => |color| {
            gui.rect(list, .{ .x = x, .y = middle - px(4.5) }, .{ .x = x + px(9), .y = middle + px(4.5) }, color, 2);
            x += px(9) + px(7);
        },
        .icon => |mark| {
            drawIcon(list, .{ .x = x, .y = middle }, mark.icon, mark.size, mark.color);
            x += px(mark.size) + px(7);
        },
    }
    // The end first, so that a long label stops short of it.
    const right = max.x - px(10);
    var end_left = right;
    switch (shown.end) {
        .none => {},
        .text => |end| {
            if (end.mono) gui.mono(.regular, fonts.size.smaller) else gui.sans(.regular, fonts.size.smaller);
            const end_width = gui.textSize(end.text).x;
            end_left = right - end_width;
            gui.drawText(list, .{ .x = end_left, .y = gui.textTop(middle) }, end.color, end.text);
            gui.popFont();
        },
        .badge => |badge| end_left = drawBadge(list, right, middle, badge),
        .dot => |color| {
            end_left = right - px(8);
            gui.dot(list, .{ .x = right - px(4), .y = middle }, 4, color);
        },
    }
    const label_color = shown.label_color orelse if (shown.selected) theme.selected_text else if (shown.failed) theme.error_text else if (shown.strong) theme.text_strong else theme.text_row;
    if (shown.mono_label) gui.mono(if (shown.strong) .semibold else .regular, fonts.size.ui) else gui.sans(if (shown.strong) .semibold else .regular, fonts.size.ui);
    clippedText(list, .{ .x = x, .y = gui.textTop(middle) }, end_left - px(8), label_color, shown.label);
    gui.popFont();
    return result;
}

/// The design's `.field`: a label 96 pixels wide, then whatever follows on the same line.
pub fn fieldLabel(text: []const u8, mono_label: bool) void {
    fieldLabelWidth(text, mono_label, 96);
}

/// `fieldLabel` with a label `width` design pixels wide, such as the Scene's inspector's 84.
pub fn fieldLabelWidth(text: []const u8, mono_label: bool, width: f32) void {
    const at = gui.cursor();
    const height = px(26);
    c.ImGui_Dummy(.{ .x = px(width), .y = height });
    if (mono_label) gui.mono(.regular, fonts.size.small) else gui.sans(.regular, fonts.size.small);
    gui.drawText(gui.drawList(), .{ .x = at.x, .y = gui.textTop(at.y + height / 2) }, theme.text_muted, text);
    gui.popFont();
    gui.sameLine(8);
}

pub const Frame = struct {
    label: []const u8,
    mono_label: bool = false,
    /// Dim, for a value left out, such as `none`.
    dim_label: bool = false,
    detail: ?[]const u8 = null,
    mark: RowMark = .none,
    chevron: bool = true,
    disabled: ?Disabled = null,
    /// Its width; by default the space left on the line.
    width: ?f32 = null,
};

/// The design's `.frame`: a field that opens a list, as the inspector's.
pub fn frame(id: []const u8, shown: Frame) bool {
    const width = shown.width orelse gui.available().x;
    const height = px(26);
    const at = gui.cursor();
    const clicked = c.ImGui_InvisibleButton(gui.z(id), .{ .x = @max(width, 1), .y = height }, 0) and shown.disabled == null;
    const hovered = gui.hovered();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    gui.rect(list, at, max, theme.button, 3);
    gui.outline(list, at, max, if (hovered and shown.disabled == null) theme.border_strong else theme.border, 3);
    const middle = at.y + height / 2;
    var x = drawMark(list, at.x + px(8), middle, shown.mark);
    const limit = max.x - px(8) - (if (shown.chevron) px(12) + px(6) else 0);
    if (shown.mono_label) gui.mono(.regular, fonts.size.ui) else gui.sans(.regular, fonts.size.ui);
    clippedText(list, .{ .x = x, .y = gui.textTop(middle) }, limit, if (shown.dim_label) theme.text_dim else theme.text, shown.label);
    x += gui.textSize(shown.label).x + px(7);
    gui.popFont();
    if (shown.detail) |detail| if (x < limit) {
        gui.mono(.regular, fonts.size.ui);
        clippedText(list, .{ .x = x, .y = gui.textTop(middle) }, limit, theme.text_dim, detail);
        gui.popFont();
    };
    if (shown.chevron) drawIcon(list, .{ .x = max.x - px(8) - px(12), .y = middle }, .chevron_down, fonts.size.icon_tiny, theme.text_dim);
    if (shown.disabled) |off| gui.tooltip(off.reason);
    return clicked;
}

/// Draws a row's mark from `x`, centred on `middle`. Where the text after it starts.
fn drawMark(list: *c.ImDrawList, x: f32, middle: f32, mark: RowMark) f32 {
    switch (mark) {
        .none => return x,
        .swatch => |color| {
            gui.rect(list, .{ .x = x, .y = middle - px(4.5) }, .{ .x = x + px(9), .y = middle + px(4.5) }, color, 2);
            return x + px(9) + px(7);
        },
        .icon => |shown| {
            drawIcon(list, .{ .x = x, .y = middle }, shown.icon, shown.size, shown.color);
            return x + px(shown.size) + px(7);
        },
    }
}

pub const Choice = struct {
    label: []const u8,
    /// After the label, dimmer, such as a record's name in the source.
    detail: ?[]const u8 = null,
    mono: bool = false,
    /// Dim, for the choice that leaves a value out, such as `none`.
    dim: bool = false,
    mark: RowMark = .none,
};

/// The most choices a list shows without a field to find one in.
const choices_without_find = 12;

/// The design's frame that opens a list under it: `shown` in the frame and `choices` in the list,
/// with a field to find one by its label where the list is long. The choice clicked, if one is.
pub fn pick(id: []const u8, shown: Frame, choices: []const Choice) ?usize {
    gui.pushId(id);
    defer gui.popId();
    const at = gui.cursor();
    const width = shown.width orelse gui.available().x;
    if (frame("frame", shown)) _ = c.ImGui_OpenPopup("choices", 0);
    c.ImGui_SetNextWindowPos(.{ .x = at.x, .y = at.y + px(26) + px(2) }, c.ImGuiCond_Always);
    c.ImGui_SetNextWindowSizeConstraints(.{ .x = width, .y = 0 }, .{ .x = @max(width, px(240)), .y = px(320) }, null, null);
    if (!c.ImGui_BeginPopup("choices", c.ImGuiWindowFlags_NoMove)) return null;
    defer c.ImGui_EndPopup();
    const Find = struct {
        var text: [64:0]u8 = @splat(0);
    };
    const finding = choices.len > choices_without_find;
    if (finding) {
        if (c.ImGui_IsWindowAppearing()) {
            Find.text[0] = 0;
            c.ImGui_SetKeyboardFocusHere();
        }
        searchField("##find", &Find.text, "Find", gui.available().x, 26, true);
        gui.space(4);
    }
    const term = std.mem.sliceTo(&Find.text, 0);
    var chosen: ?usize = null;
    for (choices, 0..) |item, index| {
        if (finding and term.len > 0 and std.ascii.findIgnoreCase(item.label, term) == null) continue;
        gui.pushIdInt(index);
        defer gui.popId();
        if (choiceRow(item)) chosen = index;
    }
    if (chosen != null) c.ImGui_CloseCurrentPopup();
    return chosen;
}

/// A row of a list to choose from, as `pick`'s. True when clicked.
pub fn choiceRow(item: Choice) bool {
    const width = gui.available().x;
    const height = px(26);
    const at = gui.cursor();
    const clicked = c.ImGui_InvisibleButton("choice", .{ .x = @max(width, 1), .y = height }, 0);
    const list = gui.drawList();
    if (gui.hovered()) gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.row_hover, 3);
    const middle = at.y + height / 2;
    var x = drawMark(list, at.x + px(8), middle, item.mark);
    if (item.mono) gui.mono(.regular, fonts.size.ui) else gui.sans(.regular, fonts.size.ui);
    gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, if (item.dim) theme.text_dim else theme.text, item.label);
    x += gui.textSize(item.label).x + px(7);
    gui.popFont();
    if (item.detail) |detail| {
        gui.mono(.regular, fonts.size.ui);
        gui.drawText(list, .{ .x = x, .y = gui.textTop(middle) }, theme.text_dim, detail);
        gui.popFont();
    }
    return clicked;
}

pub const TextField = struct {
    mono: bool = false,
    /// Takes numbers: digits, a sign, a point and an exponent. At rest the number sits at the
    /// right of the box, as the design's vectors do.
    number: bool = false,
    /// A letter in a coloured box at the start, as a vector's X, Y and Z.
    tag: ?Tag = null,
    /// Shown dim while the value is empty, such as `none`.
    hint: ?[]const u8 = null,
    /// Its width; by default the space left on the line.
    width: ?f32 = null,
    disabled: ?Disabled = null,
};

pub const Tag = struct {
    letter: []const u8,
    color: Color,
    text: Color = theme.on_axis,
};

/// The field being typed in, and its text: one at a time.
const Typing = struct {
    var id: c.ImGuiID = 0;
    var buffer: [256:0]u8 = @splat(0);
};

/// The design's field to type in, with `value` in it. The text typed, as the typing ends with
/// Enter or by leaving the field after a change; null otherwise. Escape puts the value back.
pub fn textField(id: []const u8, value: []const u8, options: TextField) ?[]const u8 {
    const width = options.width orelse gui.available().x;
    const height = px(26);
    const at = gui.cursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    const middle = at.y + height / 2;
    gui.rect(list, at, max, theme.button, 3);
    gui.outline(list, at, max, theme.border, 3);
    var left = at.x + px(8);
    if (options.tag) |tag| {
        const tag_width = px(18);
        c.ImDrawList_AddRectFilledEx(list, at, .{ .x = at.x + tag_width, .y = max.y }, tag.color, px(3), c.ImDrawFlags_RoundCornersLeft);
        gui.sans(.semibold, fonts.size.note);
        gui.drawText(list, .{ .x = at.x + (tag_width - gui.textSize(tag.letter).x) / 2, .y = gui.textTop(middle) }, tag.text, tag.letter);
        gui.popFont();
        left = at.x + tag_width + px(6);
    }
    if (options.number) gui.mono(.regular, 12) else if (options.mono) gui.mono(.regular, fonts.size.ui) else gui.sans(.regular, fonts.size.ui);
    defer gui.popFont();

    const label = gui.print("##{s}", .{id});
    const key = c.ImGui_GetID(label);
    const typing = Typing.id == key;
    var shown: [256:0]u8 = undefined;
    const buffer: *[256:0]u8 = if (typing) &Typing.buffer else buffer: {
        const length = @min(value.len, shown.len);
        @memcpy(shown[0..length], value[0..length]);
        shown[length] = 0;
        break :buffer &shown;
    };
    // At rest a number is drawn here, at the right, which the input can't do: its own text is
    // hidden until it's typed in. A long one takes the padding before it's cut.
    const right_aligned = options.number and !typing;
    if (right_aligned) {
        const text_width = gui.textSize(value).x;
        const first = if (options.tag != null) left - px(4) else left;
        clippedText(list, .{ .x = @max(first, max.x - px(6) - text_width), .y = gui.textTop(middle) }, max.x - px(2), theme.text, value);
    }
    if (!typing and value.len == 0) if (options.hint) |hint| gui.drawText(list, .{ .x = left, .y = gui.textTop(middle) }, theme.text_dim, hint);
    gui.setCursor(.{ .x = left - px(2), .y = at.y });
    c.ImGui_SetNextItemWidth(max.x - left - px(4));
    pushBareInput(gui.textTop(middle) - at.y);
    if (right_aligned) gui.pushColor(c.ImGuiCol_Text, theme.fade(theme.text, 0));
    if (options.disabled != null) c.ImGui_BeginDisabled(true);
    _ = c.ImGui_InputText(label, buffer, buffer.len + 1, if (options.number) c.ImGuiInputTextFlags_CharsScientific else 0);
    if (options.disabled != null) c.ImGui_EndDisabled();
    if (right_aligned) gui.popColor(1);
    popBareInput();
    if (options.disabled) |off| gui.tooltip(off.reason);
    if (c.ImGui_IsItemActivated()) {
        Typing.id = key;
        Typing.buffer = buffer.*;
    }
    const typed: ?[]const u8 = if (c.ImGui_IsItemDeactivatedAfterEdit()) std.mem.sliceTo(&Typing.buffer, 0) else null;
    if (c.ImGui_IsItemDeactivated()) Typing.id = 0;
    gui.setCursor(at);
    c.ImGui_Dummy(.{ .x = width, .y = height });
    return typed;
}

/// Leaves an ImGui text input bare inside a box the caller draws: no frame and no line around it,
/// with its text `padding_y` from its top. `popBareInput` ends it.
pub fn pushBareInput(padding_y: f32) void {
    gui.pushColor(c.ImGuiCol_FrameBg, theme.fade(theme.field, 0));
    gui.pushColor(c.ImGuiCol_FrameBgHovered, theme.fade(theme.field, 0));
    gui.pushColor(c.ImGuiCol_FrameBgActive, theme.fade(theme.field, 0));
    gui.pushColor(c.ImGuiCol_NavCursor, theme.fade(theme.field, 0));
    gui.pushVar(c.ImGuiStyleVar_FrameBorderSize, 0);
    gui.pushVar2(c.ImGuiStyleVar_FramePadding, .{ .x = px(2), .y = padding_y });
}

pub fn popBareInput() void {
    gui.popVar(2);
    gui.popColor(4);
}

/// How `choice` draws: the box's height, the space each side of a label, the labels' size, and the
/// corners' radius. The defaults are the settings' `.seg`.
pub const ChoiceLook = struct {
    height: f32 = 30,
    padding: f32 = 12,
    font: f32 = fonts.size.ui,
    rounding: f32 = 5,
};

/// The design's choice of a few, as the settings' `.seg` and the map's views: each option as wide
/// as its label, the one chosen lit. The option clicked, if one is.
pub fn choice(id: []const u8, options: []const []const u8, current: usize, look: ChoiceLook) ?usize {
    gui.pushId(id);
    defer gui.popId();
    gui.sans(.regular, look.font);
    defer gui.popFont();
    // The options sit 3 pixels inside the box's line, 2 pixels apart.
    const inset = px(3);
    var width = inset * 2 + px(2) * @as(f32, @floatFromInt(options.len - 1));
    for (options) |option| width += gui.textSize(option).x + px(look.padding) * 2;
    const height = px(look.height);
    const at = gui.cursor();
    const list = gui.drawList();
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.field, look.rounding);
    gui.outline(list, at, .{ .x = at.x + width, .y = at.y + height }, theme.border, look.rounding);
    var chosen: ?usize = null;
    var x = at.x + inset;
    for (options, 0..) |option, index| {
        const item_width = gui.textSize(option).x + px(look.padding) * 2;
        gui.setCursor(.{ .x = x, .y = at.y + inset });
        gui.pushIdInt(index);
        if (c.ImGui_InvisibleButton("option", .{ .x = item_width, .y = height - inset * 2 }, 0)) chosen = index;
        gui.popId();
        const on = index == current;
        if (on) gui.rect(list, .{ .x = x, .y = at.y + inset }, .{ .x = x + item_width, .y = at.y + height - inset }, theme.border, 3);
        gui.drawText(list, .{ .x = x + px(look.padding), .y = gui.textTop(at.y + height / 2) }, if (on) theme.white else theme.text_muted, option);
        x += item_width + px(2);
    }
    gui.setCursor(at);
    c.ImGui_Dummy(.{ .x = width, .y = height });
    return chosen;
}

/// The design's `.chip` that turns something on and off, such as the map's Ranges: an icon and a
/// label, lit while on. True when clicked.
pub fn toggleChip(id: []const u8, label: []const u8, icon: Icon, on: bool, disabled: ?Disabled) bool {
    gui.sans(.regular, fonts.size.small);
    defer gui.popFont();
    const icon_size = fonts.size.icon_small;
    const width = px(9) + px(icon_size) + px(6) + gui.textSize(label).x + px(9);
    const height = px(24);
    const at = gui.cursor();
    const clicked = c.ImGui_InvisibleButton(gui.z(id), .{ .x = width, .y = height }, 0) and disabled == null;
    if (disabled == null) gui.handCursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    const lit = on and disabled == null;
    gui.rect(list, at, max, if (lit) theme.pill else theme.field, 4);
    gui.outline(list, at, max, if (lit) theme.border_strong else theme.border, 4);
    const color = if (disabled != null) theme.text_off else if (lit) theme.text_strong else theme.text_muted;
    const middle = at.y + height / 2;
    drawIcon(list, .{ .x = at.x + px(9), .y = middle }, icon, icon_size, color);
    gui.drawText(list, .{ .x = at.x + px(9) + px(icon_size) + px(6), .y = gui.textTop(middle) }, color, label);
    if (disabled) |off| gui.tooltip(off.reason);
    return clicked;
}

/// The design's segmented switch, such as a trigger's Repeats: Once, Always, Counted.
pub fn segmented(id: []const u8, options: []const []const u8, current: usize, disabled: ?Disabled) ?usize {
    gui.pushId(id);
    defer gui.popId();
    const width = gui.available().x;
    const height = px(28);
    const at = gui.cursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + height);
    gui.rect(list, at, max, theme.field, 4);
    gui.outline(list, at, max, theme.border, 4);
    const count: f32 = @floatFromInt(options.len);
    const each = (width - px(2) * 2 - px(2) * (count - 1)) / count;
    var chosen: ?usize = null;
    gui.sans(.regular, fonts.size.small);
    defer gui.popFont();
    for (options, 0..) |option, index| {
        const x = at.x + px(2) + @as(f32, @floatFromInt(index)) * (each + px(2));
        gui.setCursor(.{ .x = x, .y = at.y + px(2) });
        gui.pushIdInt(index);
        if (c.ImGui_InvisibleButton("option", .{ .x = each, .y = px(22) }, 0) and disabled == null) chosen = index;
        gui.popId();
        const on = index == current;
        if (on) gui.rect(list, .{ .x = x, .y = at.y + px(2) }, .{ .x = x + each, .y = at.y + px(24) }, theme.border, 3);
        const text_width = gui.textSize(option).x;
        gui.drawText(list, .{ .x = x + (each - text_width) / 2, .y = gui.textTop(at.y + px(2) + px(22) / 2) }, if (on) theme.white else theme.text_muted, option);
        if (disabled) |off| gui.tooltip(off.reason);
    }
    gui.setCursor(at);
    c.ImGui_Dummy(.{ .x = width, .y = height });
    return chosen;
}

/// The design's checkbox: a box that turns orange, and its label.
pub fn checkbox(id: []const u8, label: []const u8, checked: bool, disabled: ?Disabled) bool {
    gui.sans(.regular, fonts.size.ui);
    defer gui.popFont();
    const box = px(13);
    const width = box + px(8) + gui.textSize(label).x;
    const height = px(22);
    const at = gui.cursor();
    const clicked = c.ImGui_InvisibleButton(gui.z(id), .{ .x = width, .y = height }, 0) and disabled == null;
    const list = gui.drawList();
    const middle = at.y + height / 2;
    const min = gui.vec2(at.x, middle - box / 2);
    const max = gui.vec2(at.x + box, middle + box / 2);
    if (checked) {
        gui.rect(list, min, max, theme.accent, 3);
        drawIconCentered(list, .{ .x = (min.x + max.x) / 2, .y = middle }, .check, 12, theme.on_accent);
    } else {
        gui.rect(list, min, max, theme.button, 3);
        gui.outline(list, min, max, theme.border_strong, 3);
    }
    gui.drawText(list, .{ .x = at.x + box + px(8), .y = gui.textTop(middle) }, if (disabled == null) theme.text_menu else theme.text_off, label);
    if (disabled) |off| gui.tooltip(off.reason);
    return clicked;
}

/// The design's switch, the settings' `.sw`: a track 30 by 16 pixels, orange while on, with a
/// knob 12 pixels wide at the end it's switched to. True when clicked.
pub fn toggle(id: []const u8, on: bool, disabled: ?Disabled) bool {
    const width = px(30);
    const height = px(16);
    const at = gui.cursor();
    const clicked = c.ImGui_InvisibleButton(gui.z(id), .{ .x = width, .y = height }, 0) and disabled == null;
    if (disabled == null) gui.handCursor();
    const list = gui.drawList();
    const middle = at.y + height / 2;
    gui.rect(list, at, .{ .x = at.x + width, .y = at.y + height }, if (on) theme.accent else theme.border, 8);
    const knob_x = if (on) at.x + px(16) + px(6) else at.x + px(2) + px(6);
    gui.dot(list, .{ .x = knob_x, .y = middle }, 6, if (on) theme.on_accent else theme.text_dim);
    if (disabled) |off| gui.tooltip(off.reason);
    return clicked;
}

/// Text in `color`, at a size and weight, as an item.
pub fn caption(text: []const u8, color: Color, size: f32, weight: fonts.Weight) void {
    gui.sans(weight, size);
    gui.textColored(color, text);
    gui.popFont();
}

pub fn monoCaption(text: []const u8, color: Color, size: f32, weight: fonts.Weight) void {
    gui.mono(weight, size);
    gui.textColored(color, text);
    gui.popFont();
}

/// Text that wraps at the space left, in `color`.
pub fn paragraph(text: []const u8, color: Color, size: f32) void {
    gui.sans(.regular, size);
    c.ImGui_PushTextWrapPos(0);
    gui.textColored(color, text);
    c.ImGui_PopTextWrapPos();
    gui.popFont();
}

/// A link in the design's orange, underlined, which opens `url` in the browser.
pub fn link(text: []const u8, url: [:0]const u8) void {
    gui.sans(.regular, fonts.size.ui);
    defer gui.popFont();
    const at = gui.cursor();
    const size = gui.textSize(text);
    const clicked = c.ImGui_InvisibleButton(gui.z(text), size, 0);
    const hovered = gui.hovered();
    gui.handCursor();
    const color = if (hovered) theme.rgb(0xffc58f) else theme.link_text;
    const list = gui.drawList();
    gui.drawText(list, at, color, text);
    gui.line(list, .{ .x = at.x, .y = at.y + size.y }, .{ .x = at.x + size.x, .y = at.y + size.y }, color);
    if (clicked) _ = c.SDL_OpenURL(url);
}

/// A text field for a search or a filter, the design's: a box with a line around it, a search
/// icon where `icon` is set, and `hint` while it's empty.
pub fn searchField(id: [:0]const u8, buffer: [:0]u8, hint: [:0]const u8, width: f32, height: f32, icon: bool) void {
    const at = gui.cursor();
    const list = gui.drawList();
    const max = gui.vec2(at.x + width, at.y + px(height));
    gui.rect(list, at, max, theme.field, 4);
    gui.outline(list, at, max, theme.border, 4);
    var x = at.x + px(8);
    if (icon) {
        drawIcon(list, .{ .x = x, .y = at.y + px(height) / 2 }, .search, fonts.size.icon_small, theme.text_dim);
        x += px(14) + px(4);
    }
    gui.sans(.regular, fonts.size.ui);
    defer gui.popFont();
    const padding_y = gui.textTop(at.y + px(height) / 2) - at.y;
    gui.setCursor(.{ .x = x, .y = at.y });
    c.ImGui_SetNextItemWidth(max.x - x - px(6));
    pushBareInput(padding_y);
    gui.pushColor(c.ImGuiCol_TextDisabled, theme.text_dim);
    _ = c.ImGui_InputTextWithHint(id, hint, buffer.ptr, buffer.len + 1, 0);
    gui.popColor(1);
    popBareInput();
    gui.setCursor(at);
    c.ImGui_Dummy(.{ .x = width, .y = px(height) });
}

/// A horizontal line across the space left.
pub fn rule(color: Color) void {
    const at = gui.cursor();
    const width = gui.available().x;
    gui.rect(gui.drawList(), at, .{ .x = at.x + width, .y = at.y + px(1) }, color, 0);
    c.ImGui_Dummy(.{ .x = width, .y = px(1) });
}
