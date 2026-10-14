//! The editor's own settings, kept for each user where the system keeps such files (SDL's
//! preferences folder for OpenReliant's editor): `editor.ini` with the game's folder, where
//! `openreliant` is and the mods opened lately, and `keys.ini` with the keys changed from their
//! defaults, each system's on its own.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const c = @import("c");

const commands = @import("commands.zig");
const Command = commands.Command;
const ini = @import("ini.zig");
const keys = @import("keys.zig");
const Chord = keys.Chord;

/// How many mods the start screen remembers.
pub const recent_count = 8;

pub const Settings = struct {
    arena: std.heap.ArenaAllocator,
    /// The folder settings are kept in, ending in a separator; null where the system gives none,
    /// when nothing is saved.
    folder: ?[]const u8 = null,
    /// The game's folder, which holds its `mods` folder.
    game_folder: ?[]const u8 = null,
    /// Where `openreliant` is, when the editor doesn't find it by itself.
    openreliant: ?[]const u8 = null,
    /// The mod folders opened lately, the latest first.
    recent: std.ArrayList([]const u8) = .empty,
    keymap: Keymap = .{},

    pub fn load(gpa: Allocator, io: Io) Settings {
        var settings: Settings = .{ .arena = .init(gpa) };
        const arena = settings.arena.allocator();
        if (c.SDL_GetPrefPath("OpenReliant", "Editor")) |path| {
            defer c.SDL_free(path);
            settings.folder = arena.dupe(u8, std.mem.span(path)) catch null;
        }
        const folder = settings.folder orelse return settings;
        if (readFile(io, arena, folder, "editor.ini")) |text| {
            const entries = ini.parse(arena, text) catch &.{};
            settings.game_folder = ini.get(entries, "Game", "Folder");
            settings.openreliant = ini.get(entries, "Game", "OpenReliant");
            for (entries) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.section, "Recent") and settings.recent.items.len < recent_count) {
                    settings.recent.append(arena, entry.value) catch break;
                }
            }
        }
        if (readFile(io, arena, folder, "keys.ini")) |text| {
            const entries = ini.parse(arena, text) catch &.{};
            settings.keymap.read(arena, entries) catch {};
        }
        return settings;
    }

    pub fn deinit(settings: *Settings) void {
        settings.arena.deinit();
    }

    /// Saves `editor.ini`. A failure is logged: the editor works on without its settings.
    pub fn save(settings: *Settings, io: Io) void {
        const folder = settings.folder orelse return;
        var buffer: [16 * 1024]u8 = undefined;
        var out: Io.Writer = .fixed(&buffer);
        settings.write(&out) catch return;
        writeFile(io, folder, "editor.ini", out.buffered());
    }

    fn write(settings: *const Settings, out: *Io.Writer) Io.Writer.Error!void {
        try out.writeAll("; OpenReliant Editor's settings.\n[Game]\n");
        if (settings.game_folder) |path| try out.print("Folder={s}\n", .{path});
        if (settings.openreliant) |path| try out.print("OpenReliant={s}\n", .{path});
        try out.writeAll("\n[Recent]\n");
        for (settings.recent.items, 1..) |path, index| try out.print("{d}={s}\n", .{ index, path });
    }

    /// Saves `keys.ini`.
    pub fn saveKeys(settings: *Settings, io: Io) void {
        const folder = settings.folder orelse return;
        var buffer: [32 * 1024]u8 = undefined;
        var out: Io.Writer = .fixed(&buffer);
        settings.keymap.write(&out) catch return;
        writeFile(io, folder, "keys.ini", out.buffered());
    }

    /// Puts `path` first among the recent mods.
    pub fn remember(settings: *Settings, io: Io, path: []const u8) void {
        const arena = settings.arena.allocator();
        for (settings.recent.items, 0..) |known, index| {
            if (std.mem.eql(u8, known, path)) {
                _ = settings.recent.orderedRemove(index);
                break;
            }
        }
        const kept = arena.dupe(u8, path) catch return;
        settings.recent.insert(arena, 0, kept) catch return;
        if (settings.recent.items.len > recent_count) settings.recent.shrinkRetainingCapacity(recent_count);
        settings.save(io);
    }

    pub fn setGameFolder(settings: *Settings, io: Io, path: []const u8) void {
        settings.game_folder = settings.arena.allocator().dupe(u8, path) catch return;
        settings.save(io);
    }
};

/// The keys of each action on each system: the defaults, with the ones changed in keys.ini.
pub const Keymap = struct {
    changed: std.EnumArray(keys.System, std.EnumArray(Command, ?[]const Chord)) = .initFill(.initFill(null)),

    /// The keys of `command` on `system`.
    pub fn chords(keymap: *const Keymap, command: Command, system: keys.System) []const Chord {
        return keymap.changed.get(system).get(command) orelse commands.info(command).keys.get(system);
    }

    pub fn isChanged(keymap: *const Keymap, command: Command, system: keys.System) bool {
        return keymap.changed.get(system).get(command) != null;
    }

    /// How many actions have keys changed on `system`.
    pub fn changedCount(keymap: *const Keymap, system: keys.System) usize {
        var count: usize = 0;
        for (std.enums.values(Command)) |command| count += @intFromBool(keymap.isChanged(command, system));
        return count;
    }

    pub fn set(keymap: *Keymap, command: Command, system: keys.System, chosen: ?[]const Chord) void {
        keymap.changed.getPtr(system).set(command, chosen);
    }

    pub fn reset(keymap: *Keymap, system: keys.System) void {
        keymap.changed.set(system, .initFill(null));
    }

    /// The first two actions that apply at once with the same key on `system`, if any.
    pub fn conflict(keymap: *const Keymap, system: keys.System) ?[2]Command {
        const all = std.enums.values(Command);
        for (all, 0..) |one, index| {
            for (all[index + 1 ..]) |other| {
                const a = commands.info(one).when;
                const b = commands.info(other).when;
                if (a != .always and b != .always and a != b) continue;
                for (keymap.chords(one, system)) |x| for (keymap.chords(other, system)) |y| {
                    if (x.eql(y)) return .{ one, other };
                };
            }
        }
        return null;
    }

    fn read(keymap: *Keymap, arena: Allocator, entries: []const ini.Entry) Allocator.Error!void {
        for (entries) |entry| {
            const system: keys.System = for (std.enums.values(keys.System)) |system| {
                if (std.ascii.eqlIgnoreCase(entry.section, system.section())) break system;
            } else continue;
            const command = std.meta.stringToEnum(Command, entry.key) orelse continue;
            var list: std.ArrayList(Chord) = .empty;
            var written = std.mem.splitScalar(u8, entry.value, ',');
            while (written.next()) |one| {
                if (std.mem.trim(u8, one, " ").len == 0) continue;
                try list.append(arena, Chord.parse(one, system) orelse continue);
            }
            keymap.set(command, system, try list.toOwnedSlice(arena));
        }
    }

    fn write(keymap: *const Keymap, out: *Io.Writer) Io.Writer.Error!void {
        try out.writeAll("; The keys changed from OpenReliant Editor's defaults, each system's on its own.\n");
        for (std.enums.values(keys.System)) |system| {
            try out.print("\n[{s}]\n", .{system.section()});
            for (std.enums.values(Command)) |command| {
                const chosen = keymap.changed.get(system).get(command) orelse continue;
                try out.print("{t}=", .{command});
                for (chosen, 0..) |one, index| try out.print("{s}{f}", .{ if (index == 0) "" else ", ", one.written(system) });
                try out.writeByte('\n');
            }
        }
    }
};

fn readFile(io: Io, arena: Allocator, folder: []const u8, name: []const u8) ?[]const u8 {
    const path = std.fs.path.join(arena, &.{ folder, name }) catch return null;
    return Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1024 * 1024)) catch null;
}

fn writeFile(io: Io, folder: []const u8, name: []const u8, data: []const u8) void {
    var path_buffer: [4096]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buffer, "{s}{s}{s}", .{ folder, if (std.mem.endsWith(u8, folder, std.fs.path.sep_str)) "" else std.fs.path.sep_str, name }) catch return;
    Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data }) catch |err| {
        std.log.warn("can't save {s}: {t}", .{ path, err });
    };
}

test "changed keys read back as written" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var keymap: Keymap = .{};
    keymap.set(.build, .windows_linux, &.{keys.chord("Ctrl+Shift+B", .windows_linux)});
    keymap.set(.quit, .macos, &.{});
    var buffer: [4096]u8 = undefined;
    var out: Io.Writer = .fixed(&buffer);
    try keymap.write(&out);
    var read_back: Keymap = .{};
    try read_back.read(arena.allocator(), try ini.parse(arena.allocator(), out.buffered()));
    try std.testing.expect(read_back.chords(.build, .windows_linux)[0].eql(keys.chord("Ctrl+Shift+B", .windows_linux)));
    try std.testing.expectEqual(0, read_back.chords(.quit, .macos).len);
    try std.testing.expect(read_back.chords(.build, .macos)[0].eql(keys.chord("Cmd+B", .macos)));
    try std.testing.expectEqual(1, read_back.changedCount(.windows_linux));
    try std.testing.expectEqual(null, (Keymap{}).conflict(.windows_linux));
}
