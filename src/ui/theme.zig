//! The editor's look: OpenReliant's colours on a dark ground, as the design gives them
//! (`design/README.md`), and Dear ImGui's style set from them. Sizes are in the design's pixels,
//! which `gui.px` scales to the display.

const std = @import("std");
const c = @import("c");

/// A colour as ImGui takes it: red in the low byte, then green, blue and alpha.
pub const Color = u32;

/// The colour `hex`, written as `0xRRGGBB`, opaque.
pub fn rgb(comptime hex: u24) Color {
    const red: u32 = (hex >> 16) & 0xff;
    const green: u32 = (hex >> 8) & 0xff;
    const blue: u32 = hex & 0xff;
    return red | green << 8 | blue << 16 | 0xff << 24;
}

/// `color` with an alpha of `opacity`, from 0 to 1.
pub fn fade(color: Color, opacity: f32) Color {
    const a: u32 = @intFromFloat(std.math.clamp(opacity, 0, 1) * 255 + 0.5);
    return (color & 0x00ff_ffff) | a << 24;
}

/// `color` mixed with white, `amount` of the way from 0 to 1: the lighter text of a flight group's
/// colour.
pub fn lighten(color: Color, amount: f32) Color {
    var result: Color = color & 0xff00_0000;
    for ([_]u5{ 0, 8, 16 }) |shift| {
        const value: f32 = @floatFromInt((color >> shift) & 0xff);
        const mixed: u32 = @intFromFloat(value + (255 - value) * std.math.clamp(amount, 0, 1) + 0.5);
        result |= mixed << shift;
    }
    return result;
}

pub fn vec4(color: Color) c.ImVec4 {
    return .{
        .x = @as(f32, @floatFromInt(color & 0xff)) / 255,
        .y = @as(f32, @floatFromInt((color >> 8) & 0xff)) / 255,
        .z = @as(f32, @floatFromInt((color >> 16) & 0xff)) / 255,
        .w = @as(f32, @floatFromInt(color >> 24)) / 255,
    };
}

pub fn floats(color: Color) [4]f32 {
    const v = vec4(color);
    return .{ v.x, v.y, v.z, v.w };
}

/// Behind the panels.
pub const ground = rgb(0x07080c);
/// The panels, and the active tab.
pub const panel = rgb(0x10131b);
/// The menu bar, the tab bars and the status bar.
pub const bar = rgb(0x0c0f15);
/// The toolbar under the menu bar.
pub const toolbar = rgb(0x0e1118);
/// Code, the source views and the inspector's code.
pub const code = rgb(0x0b0d12);
/// The map's ground and its grid: a line every few cells, and the cells' lines between them.
pub const map = rgb(0x0a0c11);
pub const map_grid = rgb(0x202839);
pub const map_grid_minor = rgb(0x131824);
/// A trigger's range's label on the map, and a curve, in the dim text's colour.
pub const range_text = rgb(0xf4b27a);
pub const curve = text_dim;
/// The line under the source's tabs that says where the cursor is.
pub const breadcrumbs = rgb(0x0d1017);
/// Fields, search boxes, and switches' tracks.
pub const field = rgb(0x11141c);
/// Buttons.
pub const button = rgb(0x161a24);
pub const button_hover = rgb(0x1d2230);
pub const button_pressed = rgb(0x232938);
/// A greyed-out button, for what doesn't work yet or doesn't apply.
pub const button_off = rgb(0x12151d);
/// The lines around buttons, fields and switches.
pub const border = rgb(0x262d3d);
pub const border_hover = rgb(0x323a4e);
pub const border_strong = rgb(0x36405a);
pub const border_off = rgb(0x1f2533);
/// The lines between panels and bars.
pub const divider = rgb(0x1a1f2b);
pub const tab_divider = rgb(0x1c2230);
/// A row under the pointer.
pub const row_hover = rgb(0x171b26);
/// Table headers, and the lines between table rows.
pub const table_head = rgb(0x0f1219);
pub const table_head_line = rgb(0x1f2533);
pub const table_line = rgb(0x161b26);
/// A count's pill.
pub const pill = rgb(0x1f2533);
pub const key_border = rgb(0x2a3142);

pub const text = rgb(0xe8eaf0);
pub const text_strong = rgb(0xf3f4f7);
pub const text_row = rgb(0xd4d8e1);
pub const text_button = rgb(0xdfe3ea);
pub const text_menu = rgb(0xc9cfdb);
pub const text_muted = rgb(0x9aa3b5);
pub const text_dim = rgb(0x8a93a6);
pub const text_faint = rgb(0x7a8398);
pub const text_off = rgb(0x5d6679);
pub const white = rgb(0xffffff);
pub const chevron = rgb(0x59627a);

/// The focus, the selection and a held script.
pub const accent = rgb(0xf08a2c);
pub const on_accent = rgb(0x170b02);
pub const accent_hover = rgb(0xf6a259);
pub const accent_key = rgb(0xc96d1c);
pub const on_accent_key = rgb(0x1d0e03);
/// A vector's axes in the inspector: X, Y and Z, their letters, and the box of an angle's letter.
pub const axis_x = rgb(0xf2767a);
pub const axis_y = rgb(0x8fd18a);
pub const axis_z = rgb(0x6ba8ff);
pub const on_axis = rgb(0x0b0d12);
pub const axis_off = rgb(0x3a4256);
pub const link_text = rgb(0xf6a259);
pub const selected = rgb(0x3b2412);
pub const selected_text = rgb(0xffe2c4);
pub const held = rgb(0x2a1a0d);
pub const held_text = rgb(0xffd2a6);
pub const held_dim = rgb(0xc79a73);
pub const held_line = fade(accent, 0.14);
/// The row of the thread the game holds.
pub const held_row = rgb(0x1b1510);

/// Breakpoints and errors.
pub const breakpoint = rgb(0xe5484d);
pub const breakpoint_inner = rgb(0x8f1d22);
pub const error_icon = rgb(0xff5c61);
pub const error_text = rgb(0xffc9ca);
pub const error_dim = rgb(0xa99aa0);
pub const error_count = rgb(0xff9a9d);
pub const error_row = rgb(0x1a1014);
pub const error_outline_row = rgb(0x24121a);
pub const error_outline_icon = rgb(0xff8a8d);
pub const error_pill = rgb(0x3a1416);
pub const error_pill_text = rgb(0xffb3b5);
pub const error_line = fade(rgb(0xe5484d), 0.10);

/// Warnings, such as a game that plays the last good build.
pub const warning_chip = rgb(0x1f180b);
pub const warning_border = rgb(0x4a3a14);
pub const warning_text = rgb(0xffd98a);
pub const warning_dim = rgb(0xc9ac6a);
pub const warning_pill = rgb(0x3a2a0e);
pub const warning_pill_text = rgb(0xffd08a);

/// A linked game.
pub const linked = rgb(0x3ccfb4);
pub const linked_chip = rgb(0x0f1d1c);
pub const linked_border = rgb(0x1f3b37);
pub const linked_text = rgb(0xbfeee5);
/// A part that runs at the start, and other teal badges.
pub const teal_badge = rgb(0x0f2321);
pub const teal_badge_text = rgb(0x8fe3d3);
pub const teal_bright = rgb(0x9ff0e3);

/// The completion list.
pub const popup = rgb(0x121620);
pub const popup_selected = rgb(0x23324a);
pub const popup_kind = rgb(0xa9bad6);

/// Mission source's colours, which the source views and the listings share.
pub const syntax = struct {
    pub const keyword = rgb(0x8fb4ff);
    pub const declaration = rgb(0xf4a35c);
    pub const command = rgb(0x63d1c0);
    pub const string = rgb(0xb5d98a);
    pub const number = rgb(0xe7c06b);
    pub const comment = rgb(0x7c869b);
    pub const name = rgb(0xdfe3ea);
    pub const punctuation = rgb(0x9aa3b5);
    pub const game = rgb(0xc4a7ff);
};

/// The colours flight groups take on the map and in the outline, in turn: the player's wing's
/// blue first.
pub const groups = [_]Color{
    rgb(0x5aa9ff), rgb(0xc9cfdb), rgb(0xff7a6b), rgb(0x8fd18a), rgb(0xc4a7ff), rgb(0xe7c06b), rgb(0x63d1c0), rgb(0xf4b27a),
};

/// The colour of the flight group at `index` (`groups`).
pub fn group(index: usize) Color {
    return groups[index % groups.len];
}

/// The design's panels: 3 pixels apart and 3 pixels inside the area they fill, each in a line of 1
/// pixel with corners of 3. The editor draws the line around each dock node, so the nodes are the
/// panels' insides.
pub const panel_gap: f32 = 3;
pub const panel_line: f32 = 1;
pub const panel_rounding: f32 = 3;

/// Sets ImGui's style from the colours, with sizes scaled by `scale`.
pub fn apply(scale: f32) void {
    const style = c.ImGui_GetStyle();
    style.*.WindowPadding = .{ .x = 0, .y = 0 };
    style.*.WindowRounding = 3;
    style.*.WindowBorderSize = 1;
    style.*.ChildRounding = 0;
    style.*.ChildBorderSize = 0;
    style.*.PopupRounding = 6;
    style.*.PopupBorderSize = 1;
    style.*.FramePadding = .{ .x = 8, .y = 5 };
    style.*.FrameRounding = 3;
    style.*.FrameBorderSize = 1;
    style.*.ItemSpacing = .{ .x = 6, .y = 6 };
    style.*.ItemInnerSpacing = .{ .x = 6, .y = 4 };
    style.*.IndentSpacing = 14;
    style.*.ScrollbarSize = 12;
    style.*.ScrollbarRounding = 3;
    style.*.GrabMinSize = 10;
    style.*.GrabRounding = 3;
    // The editor draws the panels' tabs over ImGui's (`panels.tab`), which show nothing of their
    // own.
    style.*.TabRounding = 0;
    style.*.TabBorderSize = 0;
    style.*.TabBarBorderSize = 0;
    style.*.TabBarOverlineSize = 0;
    style.*.SeparatorTextBorderSize = 1;
    // Between two dock nodes, the panels' lines and the gap between them.
    style.*.DockingSeparatorSize = panel_gap + panel_line * 2;
    style.*.WindowMenuButtonPosition = c.ImGuiDir_None;
    c.ImGuiStyle_ScaleAllSizes(style, scale);
    style.*.FontScaleDpi = scale;

    const colors = &style.*.Colors;
    const set = struct {
        fn color(all: *[c.ImGuiCol_COUNT]c.ImVec4, which: c.ImGuiCol, value: Color) void {
            all[@intCast(which)] = vec4(value);
        }
    }.color;
    set(colors, c.ImGuiCol_Text, text);
    set(colors, c.ImGuiCol_TextDisabled, text_off);
    set(colors, c.ImGuiCol_WindowBg, panel);
    set(colors, c.ImGuiCol_ChildBg, fade(panel, 0));
    set(colors, c.ImGuiCol_PopupBg, popup);
    set(colors, c.ImGuiCol_Border, divider);
    set(colors, c.ImGuiCol_BorderShadow, fade(ground, 0));
    set(colors, c.ImGuiCol_FrameBg, button);
    set(colors, c.ImGuiCol_FrameBgHovered, button_hover);
    set(colors, c.ImGuiCol_FrameBgActive, button_hover);
    set(colors, c.ImGuiCol_TitleBg, bar);
    set(colors, c.ImGuiCol_TitleBgActive, bar);
    set(colors, c.ImGuiCol_TitleBgCollapsed, bar);
    set(colors, c.ImGuiCol_MenuBarBg, bar);
    set(colors, c.ImGuiCol_ScrollbarBg, fade(panel, 0));
    set(colors, c.ImGuiCol_ScrollbarGrab, rgb(0x1d2230));
    set(colors, c.ImGuiCol_ScrollbarGrabHovered, rgb(0x2c3446));
    set(colors, c.ImGuiCol_ScrollbarGrabActive, rgb(0x3a4256));
    set(colors, c.ImGuiCol_CheckMark, accent);
    set(colors, c.ImGuiCol_SliderGrab, accent);
    set(colors, c.ImGuiCol_SliderGrabActive, accent);
    set(colors, c.ImGuiCol_Button, button);
    set(colors, c.ImGuiCol_ButtonHovered, button_hover);
    set(colors, c.ImGuiCol_ButtonActive, button_pressed);
    set(colors, c.ImGuiCol_Header, selected);
    set(colors, c.ImGuiCol_HeaderHovered, row_hover);
    set(colors, c.ImGuiCol_HeaderActive, selected);
    set(colors, c.ImGuiCol_Separator, divider);
    set(colors, c.ImGuiCol_SeparatorHovered, border_strong);
    set(colors, c.ImGuiCol_SeparatorActive, accent);
    set(colors, c.ImGuiCol_ResizeGrip, fade(ground, 0));
    set(colors, c.ImGuiCol_ResizeGripHovered, border_strong);
    set(colors, c.ImGuiCol_ResizeGripActive, accent);
    set(colors, c.ImGuiCol_InputTextCursor, text);
    for ([_]c.ImGuiCol{ c.ImGuiCol_Tab, c.ImGuiCol_TabHovered, c.ImGuiCol_TabSelected, c.ImGuiCol_TabDimmed, c.ImGuiCol_TabDimmedSelected }) |tab| set(colors, tab, bar);
    set(colors, c.ImGuiCol_DockingPreview, fade(accent, 0.35));
    set(colors, c.ImGuiCol_DockingEmptyBg, ground);
    set(colors, c.ImGuiCol_TableHeaderBg, table_head);
    set(colors, c.ImGuiCol_TableBorderStrong, table_head_line);
    set(colors, c.ImGuiCol_TableBorderLight, table_line);
    set(colors, c.ImGuiCol_TableRowBg, fade(panel, 0));
    set(colors, c.ImGuiCol_TableRowBgAlt, fade(panel, 0));
    set(colors, c.ImGuiCol_TextLink, link_text);
    set(colors, c.ImGuiCol_TextSelectedBg, fade(accent, 0.30));
    set(colors, c.ImGuiCol_TreeLines, divider);
    set(colors, c.ImGuiCol_DragDropTarget, accent);
    set(colors, c.ImGuiCol_NavCursor, accent);
    set(colors, c.ImGuiCol_NavWindowingHighlight, accent);
    set(colors, c.ImGuiCol_NavWindowingDimBg, fade(ground, 0.6));
    set(colors, c.ImGuiCol_ModalWindowDimBg, fade(ground, 0.65));
}

test rgb {
    try std.testing.expectEqual(@as(Color, 0xff2c8af0), rgb(0xf08a2c));
    try std.testing.expectEqual(@as(Color, 0x242c8af0), fade(rgb(0xf08a2c), 0.14));
}

test lighten {
    // The player's blue, nearly half way to white: the design's light blue.
    try std.testing.expectEqual(rgb(0xa8d1ff), lighten(rgb(0x5aa9ff), 0.47));
    try std.testing.expectEqual(rgb(0x5aa9ff), lighten(rgb(0x5aa9ff), 0));
    try std.testing.expectEqual(rgb(0xffffff), lighten(rgb(0x5aa9ff), 1));
}

test group {
    // The player's wing is the first group, and the colours start again after the last.
    try std.testing.expectEqual(rgb(0x5aa9ff), group(0));
    try std.testing.expectEqual(group(1), group(groups.len + 1));
}
