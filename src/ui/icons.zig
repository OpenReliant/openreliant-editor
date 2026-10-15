//! The interface's icons: glyphs of Lucide's icon font, which `fonts.zig` merges into the
//! interface's font, so that an icon draws as text. Each tag is the icon's name in Lucide with
//! underscores for hyphens, and its value the icon's codepoint in the pinned version of the font,
//! which a test checks against the font's own list.

const std = @import("std");

pub const Icon = enum(u21) {
    archive = 0xe041,
    arrow_down = 0xe042,
    arrow_down_to_dot = 0xe44d,
    arrow_left = 0xe048,
    arrow_right = 0xe049,
    arrow_right_to_line = 0xe459,
    arrow_up = 0xe04a,
    arrow_up_right = 0xe04d,
    audio_waveform = 0xe55b,
    blocks = 0xe4fa,
    book = 0xe05e,
    book_open = 0xe05f,
    box = 0xe061,
    boxes = 0xe2d0,
    braces = 0xe36a,
    bug = 0xe20c,
    cable = 0xe4e3,
    check = 0xe06c,
    chevron_down = 0xe06d,
    chevron_left = 0xe06e,
    chevron_right = 0xe06f,
    chevron_up = 0xe070,
    circle = 0xe076,
    circle_alert = 0xe077,
    circle_dashed = 0xe4b0,
    circle_dot = 0xe345,
    circle_help = 0xe082,
    clipboard_paste = 0xe3e8,
    clock = 0xe087,
    code = 0xe093,
    component = 0xe2ad,
    copy = 0xe09e,
    diamond = 0xe2d2,
    download = 0xe0b2,
    ellipsis = 0xe0b6,
    external_link = 0xe0b9,
    eye = 0xe0ba,
    file = 0xe0c0,
    file_code = 0xe0c3,
    file_plus = 0xe0c9,
    file_search = 0xe0cb,
    file_text = 0xe0cc,
    filter = 0xe0dc,
    flag = 0xe0d1,
    folder = 0xe0d7,
    folder_open = 0xe247,
    graduation_cap = 0xe234,
    hammer = 0xe0ec,
    hash = 0xe0ef,
    history = 0xe1f5,
    image = 0xe0f6,
    info = 0xe0f9,
    keyboard = 0xe284,
    layers = 0xe529,
    layout_dashboard = 0xe1c1,
    lightbulb = 0xe1c2,
    link = 0xe102,
    list = 0xe106,
    log_out = 0xe10e,
    map = 0xe110,
    maximize = 0xe112,
    music = 0xe122,
    navigation_2 = 0xe124,
    package = 0xe129,
    package_plus = 0xe268,
    panel_bottom = 0xe42c,
    panel_left = 0xe12a,
    panel_right = 0xe431,
    pause = 0xe12e,
    pencil = 0xe1f9,
    play = 0xe13c,
    plus = 0xe13d,
    radio = 0xe142,
    redo_2 = 0xe2a0,
    redo_dot = 0xe450,
    refresh_cw = 0xe145,
    rotate_ccw = 0xe148,
    route = 0xe53e,
    save = 0xe14d,
    save_all = 0xe40f,
    scan = 0xe257,
    scissors = 0xe14e,
    search = 0xe151,
    settings = 0xe154,
    sliders_horizontal = 0xe29a,
    spline = 0xe38b,
    square = 0xe167,
    step_forward = 0xe3ea,
    terminal = 0xe181,
    text_select = 0xe6ea,
    triangle_alert = 0xe193,
    undo_2 = 0xe2a1,
    unplug = 0xe45d,
    upload = 0xe19e,
    variable = 0xe473,
    wand_sparkles = 0xe357,
    x = 0xe1b2,
    zap = 0xe1b4,

    /// The icon as UTF-8, to draw as text.
    pub fn text(icon: Icon) [:0]const u8 {
        return switch (icon) {
            inline else => |known| comptime encoded(@backingInt(known)),
        };
    }

    /// The first codepoint and the last of the icons, which the font loads.
    pub const first: u21 = blk: {
        var lowest: u21 = std.math.maxInt(u21);
        for (std.enums.values(Icon)) |icon| lowest = @min(lowest, @backingInt(icon));
        break :blk lowest;
    };
    pub const last: u21 = blk: {
        var highest: u21 = 0;
        for (std.enums.values(Icon)) |icon| highest = @max(highest, @backingInt(icon));
        break :blk highest;
    };
};

fn encoded(comptime codepoint: u21) [:0]const u8 {
    comptime {
        var bytes: [4:0]u8 = @splat(0);
        const length = std.unicode.utf8Encode(codepoint, &bytes) catch unreachable;
        const final = bytes[0..length].* ++ [_:0]u8{};
        return &final;
    }
}

test "each icon has its codepoint in the pinned Lucide" {
    const listing = @embedFile("lucide-codepoints.json");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), listing, .{});
    for (std.enums.values(Icon)) |icon| {
        const tag = @tagName(icon);
        var name_buffer: [64]u8 = undefined;
        const name = name_buffer[0..tag.len];
        @memcpy(name, tag);
        std.mem.replaceScalar(u8, name, '_', '-');
        const found = parsed.object.get(name) orelse {
            std.debug.print("Lucide has no icon {s}\n", .{name});
            return error.TestUnexpectedResult;
        };
        try std.testing.expectEqual(@as(i64, @backingInt(icon)), found.integer);
    }
}

test "an icon is its codepoint in UTF-8" {
    try std.testing.expectEqualStrings("\u{e151}", Icon.search.text());
}
