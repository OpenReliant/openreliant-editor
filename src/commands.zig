//! Every action of the editor, declared once: its label, its icon, the menu it's in, its default
//! keys on each system, when it applies, and whether it works yet. The menus, the toolbar, the
//! command palette and the Keys settings all read this table, so that each action has the same
//! name, icon and keys wherever it shows. An action that doesn't work yet still shows, greyed out,
//! with the issue that plans it.

const std = @import("std");

const keys = @import("keys.zig");
const Chord = keys.Chord;
const Icon = @import("ui/icons.zig").Icon;

pub const Command = enum {
    // File
    new_mission,
    new_mod,
    open_file,
    open_mod,
    open_hog,
    edit_game_mission,
    save,
    save_all,
    close_mod,
    start_screen,
    settings,
    quit,
    // Edit
    undo,
    redo,
    cut,
    copy,
    paste,
    select_all,
    find,
    find_next,
    replace,
    go_to_line,
    comment_line,
    // View
    palette,
    go_to,
    view_1,
    view_2,
    view_3,
    view_4,
    switch_mode,
    layout_full,
    layout_guided,
    full_screen,
    // Mission
    build,
    add_record,
    show_source,
    show_listing,
    // Debug
    @"continue",
    step_over,
    step_into,
    run_to_cursor,
    toggle_breakpoint,
    clear_breakpoints,
    pause,
    let_go,
    // Game
    play,
    play_from_part,
    play_mod_only,
    reload_scripts,
    link,
    game_settings,
    // Window
    show_mission_panel,
    show_find_panel,
    show_problems,
    show_output,
    show_threads,
    show_breakpoints,
    show_variables,
    show_watch,
    show_inspector,
    show_reference,
    show_live_scene,
    reset_layout,
    // Help
    help_missions,
    help_reference,
    help_mods,
    help_modding,
    help_scripting,
    help_keys,
    about,
};

pub const Menu = enum {
    file,
    edit,
    view,
    mission,
    debug,
    game,
    window,
    help,

    pub fn label(menu: Menu) [:0]const u8 {
        return switch (menu) {
            inline else => |which| comptime blk: {
                const name = @tagName(which);
                break :blk [_]u8{std.ascii.toUpper(name[0])} ++ name[1..] ++ "";
            },
        };
    }
};

/// When an action's keys run it, for actions that share keys: F5 plays the mission, but continues
/// the script while it's held.
pub const When = enum { always, held, not_held };

/// Which repository an issue is in.
pub const Repository = enum { editor, openreliant };

/// Where an action that doesn't work yet is planned.
pub const Plan = struct {
    issue: u32,
    repository: Repository = .editor,

    pub fn format(plan: Plan, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (plan.repository) {
            .editor => try writer.print("#{d}", .{plan.issue}),
            .openreliant => try writer.print("OpenReliant #{d}", .{plan.issue}),
        }
    }

    pub fn url(plan: Plan, buffer: []u8) []const u8 {
        const repository = switch (plan.repository) {
            .editor => "openreliant-editor",
            .openreliant => "openreliant",
        };
        return std.fmt.bufPrint(buffer, "https://github.com/OpenReliant/{s}/issues/{d}", .{ repository, plan.issue }) catch "";
    }
};

/// The sections of the Keys settings.
pub const KeyGroup = enum {
    debugging,
    build_and_play,
    general,
    editing,
    files,

    pub fn label(group: KeyGroup) []const u8 {
        return switch (group) {
            .debugging => "Debugging",
            .build_and_play => "Build and play",
            .general => "General",
            .editing => "Editing",
            .files => "Files",
        };
    }
};

/// An action's default keys on each system: none, one, or two.
pub const Defaults = std.EnumArray(keys.System, []const Chord);

pub const Info = struct {
    label: []const u8,
    icon: ?Icon = null,
    /// Where the palette groups it, the menu's name by default.
    group: ?[]const u8 = null,
    when: When = .always,
    /// Null while it works; the plan while it doesn't yet.
    planned: ?Plan = null,
    keys: Defaults = .initFill(&.{}),
    key_group: ?KeyGroup = null,
    /// Whether the command palette lists it.
    in_palette: bool = true,
};

/// The default keys `windows_linux` and `macos` write, the same action's.
fn defaults(comptime windows_linux: []const []const u8, comptime macos: []const []const u8) Defaults {
    const made = comptime blk: {
        @setEvalBranchQuota(100_000);
        var chords_of: Defaults = undefined;
        for ([_]keys.System{ .windows_linux, .macos }, [_][]const []const u8{ windows_linux, macos }) |system, written| {
            var chords: [written.len]Chord = undefined;
            for (&chords, written) |*one, text| one.* = keys.chord(text, system);
            const final = chords;
            chords_of.set(system, &final);
        }
        break :blk chords_of;
    };
    return made;
}

/// Issues of what doesn't work yet, by what each plans.
pub const plans = struct {
    pub const scene: Plan = .{ .issue = 2 };
    pub const blocks: Plan = .{ .issue = 3 };
    pub const mod_mode: Plan = .{ .issue = 4 };
    pub const debugger: Plan = .{ .issue = 5 };
    pub const guided: Plan = .{ .issue = 6 };
    pub const templates: Plan = .{ .issue = 7 };
    pub const records: Plan = .{ .issue = 8 };
    pub const hogs: Plan = .{ .issue = 9 };
    pub const settings: Plan = .{ .issue = 10 };
    pub const live_scene: Plan = .{ .issue = 1059, .repository = .openreliant };
    pub const play_from_part: Plan = .{ .issue = 577, .repository = .openreliant };
    pub const chosen_mods: Plan = .{ .issue = 1202, .repository = .openreliant };
    pub const reload_scripts: Plan = .{ .issue = 1201, .repository = .openreliant };
};

pub fn info(command: Command) Info {
    return switch (command) {
        .new_mission => .{ .label = "New mission", .icon = .file_plus },
        .new_mod => .{ .label = "New mod", .icon = .package_plus, .planned = plans.templates },
        .open_file => .{ .label = "Open…", .icon = .folder_open, .keys = defaults(&.{"Ctrl+O"}, &.{"Cmd+O"}), .key_group = .files },
        .open_mod => .{ .label = "Open mod folder…", .icon = .folder },
        .open_hog => .{ .label = "Open .hog, read only", .icon = .archive, .planned = plans.hogs },
        .edit_game_mission => .{ .label = "Edit a game mission", .icon = .file_code },
        .save => .{ .label = "Save", .icon = .save, .keys = defaults(&.{"Ctrl+S"}, &.{"Cmd+S"}), .key_group = .files },
        .save_all => .{ .label = "Save all", .icon = .save_all, .keys = defaults(&.{"Ctrl+Shift+S"}, &.{"Cmd+Option+S"}), .key_group = .files },
        .close_mod => .{ .label = "Close mod", .icon = .x },
        .start_screen => .{ .label = "Start", .icon = .layout_dashboard },
        .settings => .{ .label = "Settings", .icon = .settings, .keys = defaults(&.{"Ctrl+,"}, &.{"Cmd+,"}), .key_group = .general },
        .quit => .{ .label = "Quit", .icon = .log_out, .keys = defaults(&.{ "Alt+F4", "Ctrl+Q" }, &.{"Cmd+Q"}), .key_group = .general },

        .undo => .{ .label = "Undo", .icon = .undo_2, .keys = defaults(&.{"Ctrl+Z"}, &.{"Cmd+Z"}), .key_group = .editing },
        .redo => .{ .label = "Redo", .icon = .redo_2, .keys = defaults(&.{"Ctrl+Y"}, &.{"Cmd+Shift+Z"}), .key_group = .editing },
        .cut => .{ .label = "Cut", .icon = .scissors, .keys = defaults(&.{"Ctrl+X"}, &.{"Cmd+X"}), .key_group = .editing },
        .copy => .{ .label = "Copy", .icon = .copy, .keys = defaults(&.{"Ctrl+C"}, &.{"Cmd+C"}), .key_group = .editing },
        .paste => .{ .label = "Paste", .icon = .clipboard_paste, .keys = defaults(&.{"Ctrl+V"}, &.{"Cmd+V"}), .key_group = .editing },
        .select_all => .{ .label = "Select all", .icon = .text_select, .keys = defaults(&.{"Ctrl+A"}, &.{"Cmd+A"}), .key_group = .editing },
        .find => .{ .label = "Find", .icon = .search, .keys = defaults(&.{"Ctrl+F"}, &.{"Cmd+F"}), .key_group = .editing },
        .find_next => .{ .label = "Find next", .icon = .search, .keys = defaults(&.{"F3"}, &.{"Cmd+G"}), .key_group = .editing },
        .replace => .{ .label = "Replace", .icon = .search, .keys = defaults(&.{"Ctrl+H"}, &.{"Cmd+Option+F"}), .key_group = .editing },
        .go_to_line => .{ .label = "Go to line", .icon = .arrow_right_to_line, .keys = defaults(&.{"Ctrl+G"}, &.{"Cmd+L"}), .key_group = .editing },
        .comment_line => .{ .label = "Comment line", .icon = .code, .keys = defaults(&.{"Ctrl+/"}, &.{"Cmd+/"}), .key_group = .editing },

        .palette => .{ .label = "Command palette", .icon = .terminal, .keys = defaults(&.{"Ctrl+Shift+P"}, &.{"Cmd+Shift+P"}), .key_group = .general, .in_palette = false },
        .go_to => .{ .label = "Go to record or file", .icon = .search, .keys = defaults(&.{"Ctrl+P"}, &.{"Cmd+P"}), .key_group = .general },
        .view_1 => .{ .label = "View 1", .keys = defaults(&.{"Ctrl+1"}, &.{"Cmd+1"}), .key_group = .general, .in_palette = false },
        .view_2 => .{ .label = "View 2", .keys = defaults(&.{"Ctrl+2"}, &.{"Cmd+2"}), .key_group = .general, .in_palette = false },
        .view_3 => .{ .label = "View 3", .keys = defaults(&.{"Ctrl+3"}, &.{"Cmd+3"}), .key_group = .general, .in_palette = false },
        .view_4 => .{ .label = "View 4", .keys = defaults(&.{"Ctrl+4"}, &.{"Cmd+4"}), .key_group = .general, .in_palette = false },
        .switch_mode => .{ .label = "Mod or Mission mode", .icon = .package, .keys = defaults(&.{"Ctrl+Shift+M"}, &.{"Cmd+Shift+M"}), .key_group = .general, .planned = plans.mod_mode },
        .layout_full => .{ .label = "Full layout", .icon = .layout_dashboard },
        .layout_guided => .{ .label = "Guided layout", .icon = .graduation_cap, .planned = plans.guided },
        .full_screen => .{ .label = "Full screen", .icon = .maximize, .when = .not_held, .keys = defaults(&.{"F11"}, &.{"Ctrl+Cmd+F"}), .key_group = .general },

        .build => .{ .label = "Build", .icon = .hammer, .keys = defaults(&.{"Ctrl+B"}, &.{"Cmd+B"}), .key_group = .build_and_play },
        .add_record => .{ .label = "Add a record", .icon = .plus, .planned = plans.records },
        .show_source => .{ .label = "Mission source", .icon = .file_code },
        .show_listing => .{ .label = "Script listing", .icon = .list },

        .@"continue" => .{ .label = "Continue", .icon = .step_forward, .when = .held, .keys = defaults(&.{"F5"}, &.{"Ctrl+Cmd+Y"}), .key_group = .debugging, .planned = plans.debugger },
        .step_over => .{ .label = "Step over", .icon = .redo_dot, .when = .held, .keys = defaults(&.{"F10"}, &.{"F6"}), .key_group = .debugging, .planned = plans.debugger },
        .step_into => .{ .label = "Step into", .icon = .arrow_down_to_dot, .when = .held, .keys = defaults(&.{"F11"}, &.{"F7"}), .key_group = .debugging, .planned = plans.debugger },
        .run_to_cursor => .{ .label = "Run to cursor", .icon = .arrow_right_to_line, .when = .held, .keys = defaults(&.{"Ctrl+F10"}, &.{"Ctrl+Cmd+C"}), .key_group = .debugging, .planned = plans.debugger },
        .toggle_breakpoint => .{ .label = "Breakpoint on or off", .icon = .circle_dot, .keys = defaults(&.{"F9"}, &.{"Cmd+\\"}), .key_group = .debugging },
        .clear_breakpoints => .{ .label = "Remove all breakpoints", .icon = .x },
        .pause => .{ .label = "Pause mission", .icon = .pause, .keys = defaults(&.{"F6"}, &.{"F8"}), .key_group = .debugging, .planned = plans.debugger },
        .let_go => .{ .label = "Let the script go", .icon = .square, .when = .held, .keys = defaults(&.{"Shift+F5"}, &.{"Cmd+."}), .key_group = .debugging, .planned = plans.debugger },

        .play => .{ .label = "Play in game", .icon = .play, .when = .not_held, .keys = defaults(&.{"F5"}, &.{"Cmd+R"}), .key_group = .build_and_play },
        .play_from_part => .{ .label = "Play from part…", .icon = .play, .keys = defaults(&.{"Ctrl+F5"}, &.{"Ctrl+Cmd+R"}), .key_group = .build_and_play },
        .play_mod_only => .{ .label = "Play with this mod only", .icon = .play, .planned = plans.chosen_mods },
        .reload_scripts => .{ .label = "Reload scripts", .icon = .refresh_cw, .keys = defaults(&.{"Ctrl+R"}, &.{"Cmd+Shift+R"}), .key_group = .build_and_play, .planned = plans.reload_scripts },
        .link => .{ .label = "Link to the game", .icon = .cable, .planned = plans.debugger },
        .game_settings => .{ .label = "Game settings", .icon = .sliders_horizontal },

        .show_mission_panel => .{ .label = "Mission", .icon = .flag, .group = "Panel" },
        .show_find_panel => .{ .label = "Find", .icon = .search, .group = "Panel" },
        .show_problems => .{ .label = "Problems", .icon = .circle_alert, .group = "Panel" },
        .show_output => .{ .label = "Output", .icon = .terminal, .group = "Panel" },
        .show_threads => .{ .label = "Threads", .icon = .list, .group = "Panel" },
        .show_breakpoints => .{ .label = "Breakpoints", .icon = .circle_dot, .group = "Panel" },
        .show_variables => .{ .label = "Variables", .icon = .variable, .group = "Panel" },
        .show_watch => .{ .label = "Watch", .icon = .eye, .group = "Panel" },
        .show_inspector => .{ .label = "Inspector", .icon = .sliders_horizontal, .group = "Panel" },
        .show_reference => .{ .label = "Reference", .icon = .book_open, .group = "Panel" },
        .show_live_scene => .{ .label = "Live scene", .icon = .map, .group = "Panel" },
        .reset_layout => .{ .label = "Reset layout", .icon = .rotate_ccw },

        .help_missions => .{ .label = "Writing missions", .icon = .book_open },
        .help_reference => .{ .label = "Mission reference", .icon = .book },
        .help_mods => .{ .label = "What mods can do", .icon = .book },
        .help_modding => .{ .label = "Modding", .icon = .book },
        .help_scripting => .{ .label = "Scripting", .icon = .book },
        .help_keys => .{ .label = "Keys", .icon = .keyboard },
        .about => .{ .label = "About OpenReliant Editor", .icon = .info },
    };
}

/// A menu's entries: actions, and lines between groups of them.
pub const Entry = union(enum) {
    command: Command,
    separator,
};

pub fn entries(menu: Menu) []const Entry {
    return menu_entries.get(menu);
}

/// Each menu's entries, made while the editor compiles, so that the slices last.
const menu_entries: std.EnumArray(Menu, []const Entry) = .init(.{
    .file = &.{ cmd(.new_mission), cmd(.new_mod), cmd(.open_file), cmd(.open_mod), cmd(.open_hog), cmd(.edit_game_mission), .separator, cmd(.save), cmd(.save_all), .separator, cmd(.close_mod), cmd(.start_screen), .separator, cmd(.settings), .separator, cmd(.quit) },
    .edit = &.{ cmd(.undo), cmd(.redo), .separator, cmd(.cut), cmd(.copy), cmd(.paste), cmd(.select_all), .separator, cmd(.find), cmd(.find_next), cmd(.replace), .separator, cmd(.go_to_line), cmd(.comment_line) },
    .view = &.{ cmd(.palette), cmd(.go_to), .separator, cmd(.view_1), cmd(.view_2), cmd(.view_3), cmd(.view_4), .separator, cmd(.switch_mode), .separator, cmd(.layout_full), cmd(.layout_guided), .separator, cmd(.full_screen) },
    .mission = &.{ cmd(.build), .separator, cmd(.add_record), .separator, cmd(.show_source), cmd(.show_listing) },
    .debug = &.{ cmd(.@"continue"), cmd(.step_over), cmd(.step_into), cmd(.run_to_cursor), .separator, cmd(.toggle_breakpoint), cmd(.clear_breakpoints), .separator, cmd(.pause), cmd(.let_go) },
    .game = &.{ cmd(.play), cmd(.play_from_part), cmd(.play_mod_only), .separator, cmd(.reload_scripts), .separator, cmd(.link), cmd(.game_settings) },
    .window = &.{ cmd(.show_mission_panel), cmd(.show_find_panel), .separator, cmd(.show_problems), cmd(.show_output), cmd(.show_threads), cmd(.show_breakpoints), .separator, cmd(.show_variables), cmd(.show_watch), .separator, cmd(.show_inspector), cmd(.show_reference), cmd(.show_live_scene), .separator, cmd(.reset_layout) },
    .help = &.{ cmd(.help_missions), cmd(.help_reference), cmd(.help_mods), cmd(.help_modding), cmd(.help_scripting), .separator, cmd(.help_keys), .separator, cmd(.about) },
});

fn cmd(command: Command) Entry {
    return .{ .command = command };
}

/// The menu an action is in.
pub fn menuOf(command: Command) ?Menu {
    for (std.enums.values(Menu)) |menu| {
        for (entries(menu)) |entry| switch (entry) {
            .command => |listed| if (listed == command) return menu,
            .separator => {},
        };
    }
    return null;
}

// Each action is in one menu, so that it has one place to be found.
test "each action is in exactly one menu" {
    for (std.enums.values(Command)) |command| {
        var count: usize = 0;
        for (std.enums.values(Menu)) |menu| {
            for (entries(menu)) |entry| switch (entry) {
                .command => |listed| count += @intFromBool(listed == command),
                .separator => {},
            };
        }
        if (count != 1) {
            std.debug.print("{t} is in {d} menus\n", .{ command, count });
            return error.TestUnexpectedResult;
        }
    }
}

// No two actions that apply at the same time share a key on the same system.
test "default keys don't conflict" {
    for (std.enums.values(keys.System)) |system| {
        for (std.enums.values(Command), 0..) |one, index| {
            for (std.enums.values(Command)[index + 1 ..]) |other| {
                const a = info(one);
                const b = info(other);
                if (a.when != .always and b.when != .always and a.when != b.when) continue;
                for (a.keys.get(system)) |chord_a| for (b.keys.get(system)) |chord_b| {
                    if (chord_a.eql(chord_b)) {
                        std.debug.print("{t} and {t} share a key on {t}\n", .{ one, other, system });
                        return error.TestUnexpectedResult;
                    }
                };
            }
        }
    }
}

// An action that has keys is in a section of the Keys settings, which lists every key.
test "each action with keys is in the Keys settings" {
    for (std.enums.values(Command)) |command| {
        const known = info(command);
        const has_keys = known.keys.get(.windows_linux).len > 0 or known.keys.get(.macos).len > 0;
        try std.testing.expectEqual(has_keys, known.key_group != null);
    }
}

test "the design's keys" {
    try std.testing.expect(info(.@"continue").keys.get(.macos)[0].eql(keys.chord("Ctrl+Cmd+Y", .macos)));
    try std.testing.expect(info(.step_over).keys.get(.windows_linux)[0].eql(keys.chord("F10", .windows_linux)));
    try std.testing.expectEqualStrings("File", Menu.file.label());
}
