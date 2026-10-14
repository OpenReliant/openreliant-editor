//! OpenReliant Editor: a mission editor, script debugger and mod editor for OpenReliant. This
//! file reads the command line and runs the window's frames; `app.zig` is the editor itself.

const std = @import("std");
const c = @import("c");

pub const app = @import("app.zig");
pub const breakpoints = @import("debug/breakpoints.zig");
pub const commands = @import("commands.zig");
pub const connection = @import("link/connection.zig");
pub const session = @import("debug/session.zig");
pub const game = @import("game.zig");
pub const ini = @import("ini.zig");
pub const keys = @import("keys.zig");
pub const palette = @import("palette.zig");
pub const panels = @import("panels.zig");
pub const project = @import("project.zig");
pub const settings = @import("settings.zig");
pub const shell = @import("shell.zig");
pub const ui = @import("ui.zig");
pub const document = @import("mission/document.zig");
pub const script_view = @import("views/script.zig");
pub const start_screen = @import("screens/start.zig");
pub const settings_screen = @import("screens/settings.zig");
pub const icon = @import("platform/icon.zig");
pub const version = @import("version.zig");
const Window = @import("platform/window.zig").Window;

/// What the command line asks for.
const Options = struct {
    /// A mod folder to open.
    open: ?[]const u8 = null,
    /// The game's folder for this run, in place of the one the settings keep.
    game_folder: ?[]const u8 = null,
    /// Draws without showing a window, and saves the frame to this PNG file, for checking the
    /// screens against the design.
    screenshot: ?[:0]const u8 = null,
    /// The line of the mission to show, counting from 1.
    line: ?u32 = null,
    frames: u32 = 10,
    width: u32 = 1440,
    height: u32 = 900,
    show: ?Show = null,
    /// Opens each of the game's own missions as the editor does and builds it again from its
    /// source, without a window.
    check_missions: bool = false,
    print_version: bool = false,

    const Show = enum { start, settings, palette, keys, link, problems };

    const usage =
        \\Usage: openreliant-editor [<mod folder or mission file>] [options]
        \\
        \\  --version              the editor's version
        \\  --line <number>        show this line of the mission
        \\  --game <folder>        the game's folder for this run
        \\  --screenshot <file>    draw without a window and save a frame as a PNG file
        \\  --frames <count>       the frames drawn before the picture; 10 by default
        \\  --size <width>x<height>  the window's size; 1440x900 by default
        \\  --show <screen>        start, settings, keys, link, palette or problems
        \\  --check-missions       open each of the game's missions as source, build it again,
        \\                         and check it's the same mission
        \\
    ;

    fn parse(args: []const [:0]const u8) ?Options {
        var options: Options = .{};
        if (args.len == 2 and std.mem.eql(u8, args[1], "--version")) {
            options.print_version = true;
            return options;
        }
        var index: usize = 1;
        while (index < args.len) : (index += 1) {
            const arg = args[index];
            const value: ?[:0]const u8 = if (index + 1 < args.len) args[index + 1] else null;
            if (std.mem.eql(u8, arg, "--game")) {
                options.game_folder = value orelse return null;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--line")) {
                options.line = std.fmt.parseInt(u32, value orelse return null, 10) catch return null;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--screenshot")) {
                options.screenshot = value orelse return null;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--frames")) {
                options.frames = std.fmt.parseInt(u32, value orelse return null, 10) catch return null;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--size")) {
                const text = value orelse return null;
                const x = std.mem.findScalar(u8, text, 'x') orelse return null;
                options.width = std.fmt.parseInt(u32, text[0..x], 10) catch return null;
                options.height = std.fmt.parseInt(u32, text[x + 1 ..], 10) catch return null;
                index += 1;
            } else if (std.mem.eql(u8, arg, "--check-missions")) {
                options.check_missions = true;
            } else if (std.mem.eql(u8, arg, "--show")) {
                options.show = std.meta.stringToEnum(Show, value orelse return null) orelse return null;
                index += 1;
            } else if (std.mem.startsWith(u8, arg, "-")) {
                return null;
            } else {
                options.open = arg;
            }
        }
        return options;
    }
};

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const options = Options.parse(args) orelse {
        std.debug.print("{s}", .{Options.usage});
        return 2;
    };
    if (options.print_version) {
        var out_buffer: [64]u8 = undefined;
        var stdout: std.Io.File.Writer = .initStreaming(.stdout(), io, &out_buffer);
        try stdout.interface.print("openreliant-editor {s}\n", .{version.string});
        try stdout.interface.flush();
        return 0;
    }

    // A run that takes a picture keeps no settings, so that it shows the defaults and changes
    // nothing.
    var editor_settings: settings.Settings = if (options.screenshot != null) .{ .arena = .init(gpa) } else .load(gpa, io);
    defer editor_settings.deinit();
    if (options.game_folder) |folder| editor_settings.game_folder = folder;
    if (options.check_missions) return checkMissions(gpa, io, game.all[0], editor_settings.game_folder orelse {
        std.debug.print("openreliant-editor: no game folder: give one with --game\n", .{});
        return 2;
    });
    const ini_path: ?[:0]const u8 = if (editor_settings.folder) |folder| try std.fmt.allocPrintSentinel(arena, "{s}layout.ini", .{folder}, 0) else null;
    var window = try Window.open("OpenReliant Editor", options.width, options.height, if (ini_path) |path| path.ptr else null, options.screenshot != null);
    defer window.close();
    ui.fonts.load();
    ui.theme.apply(window.scale);
    ui.gui.scale = window.scale;

    var editor = try app.App.init(gpa, io, &window, &editor_settings, game.all[0]);
    defer editor.deinit();
    if (options.open) |path| {
        // A file opens as Open… opens it; a folder as a mod.
        if (std.Io.Dir.cwd().openDir(io, path, .{})) |opened| {
            var folder = opened;
            folder.close(io);
            editor.openMod(path);
        } else |_| editor.openFile(path);
    }
    if (options.line) |line| editor.goTo(line -| 1, 0);
    if (options.show) |shown| switch (shown) {
        .start => editor.screen = .start,
        .settings, .keys, .link => {
            editor.screen = .settings;
            editor.settings_page = switch (shown) {
                .keys => .keys,
                .link => .editor_link,
                else => .game,
            };
        },
        .palette => editor.palette.show(.commands),
        .problems => editor.showPanel(.problems),
    };

    var frame: u32 = 0;
    while (!editor.quit) : (frame += 1) {
        if (options.screenshot) |path| {
            window.keepBusy();
            if (!window.beginFrame()) continue;
            editor.frame();
            if (frame + 1 < options.frames) {
                window.endFrame(ui.theme.floats(ui.theme.ground));
                continue;
            }
            try window.capture(ui.theme.floats(ui.theme.ground), path);
            break;
        }
        if (!window.beginFrame()) continue;
        editor.frame();
        window.endFrame(ui.theme.floats(ui.theme.ground));
    }
    return 0;
}

/// Opens each of the game's own missions in `game_folder` as the editor does, as source, reads its
/// outline, builds it again and compares the two missions, and prints what it found. Fails if any
/// mission doesn't come back the same.
fn checkMissions(gpa: std.mem.Allocator, io: std.Io, profile: *const game.Profile, game_folder: []const u8) !u8 {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const missions = profile.gameMissions(arena_state.allocator(), io, game_folder) catch |err| {
        std.debug.print("openreliant-editor: can't read the missions of {s}: {t}\n", .{ game_folder, err });
        return 1;
    };
    var out_buffer: [4096]u8 = undefined;
    var stdout: std.Io.File.Writer = .initStreaming(.stdout(), io, &out_buffer);
    const out = &stdout.interface;
    defer out.flush() catch {};
    try out.writeAll("mission  where            lines  records  result\n");
    var failed: usize = 0;
    for (missions) |mission| {
        var each: std.heap.ArenaAllocator = .init(gpa);
        defer each.deinit();
        const arena = each.allocator();
        try out.print("{d:>7}  {s:<15}  ", .{ mission.number, mission.origin.label() });
        const result = checkMission(arena, io, profile, game_folder, mission.number, out) catch |err| blk: {
            try out.print("fails: {t}\n", .{err});
            break :blk false;
        };
        if (!result) failed += 1;
        try out.flush();
    }
    try out.print("{d} missions, {d} failing\n", .{ missions.len, failed });
    return if (failed == 0) 0 else 1;
}

fn checkMission(arena: std.mem.Allocator, io: std.Io, profile: *const game.Profile, game_folder: []const u8, number: u32, out: *std.Io.Writer) !bool {
    const image = try profile.readGameMission(arena, io, game_folder, number) orelse {
        try out.writeAll("missing\n");
        return false;
    };
    const text = try profile.decompile(arena, image);
    const lines = std.mem.count(u8, text, "\n");
    const outline = try profile.outline(arena, text);
    try out.print("{d:>5}  {d:>7}  ", .{ lines, outline.records.len });
    if (outline.errors.len > 0) {
        try out.print("doesn't parse: {d}:{d}: {s}\n", .{ outline.errors[0].at.line + 1, outline.errors[0].at.column + 1, outline.errors[0].message });
        return false;
    }
    switch (try profile.build(arena, text)) {
        .problems => |found| {
            try out.print("doesn't build: {d}:{d}: {s}\n", .{ found[0].at.line + 1, found[0].at.column + 1, found[0].message });
            return false;
        },
        .mission => |again| {
            if (try profile.difference(arena, image, again.file)) |differs| {
                try out.print("differs: {s}\n", .{differs});
                return false;
            }
            try out.writeAll("the same mission\n");
            return true;
        },
    }
}

test {
    std.testing.refAllDecls(@This());
}
