//! A mod, the editor's project: a folder in the game's `mods` folder, with its manifest,
//! `mod.ini`, and its files. A mission is one of a mod's files, its source a `.mission.luau` file
//! beside the mission file it builds.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const game = @import("game.zig");
const ini = @import("ini.zig");

/// What a mod holds, which the start screen tags it by.
pub const Kind = enum {
    missions,
    ships,
    sound,
    other,

    pub fn label(kind: Kind) []const u8 {
        return switch (kind) {
            .missions => "Missions",
            .ships => "Ships",
            .sound => "Sound",
            .other => "Mod",
        };
    }
};

/// A mod as the start screen lists it.
pub const Summary = struct {
    path: []const u8,
    /// Its folder's name.
    folder: []const u8,
    /// The name its manifest gives, or its folder's.
    name: []const u8,
    /// What it holds, in a few words: "1 mission", "3 scripts".
    holds: []const u8,
    kind: Kind,
};

/// A mission of a mod, by its source file.
pub const Mission = struct {
    /// The source file's name, such as `mission90.mission.luau`.
    file: []const u8,
    number: ?u32,
};

pub const Project = struct {
    arena: std.heap.ArenaAllocator,
    path: []const u8,
    folder: []const u8,
    name: []const u8,
    missions: []const Mission,

    /// Opens the mod in the folder `path`.
    pub fn open(gpa: Allocator, io: Io, path: []const u8, profile: *const game.Profile) !Project {
        var arena_state: std.heap.ArenaAllocator = .init(gpa);
        errdefer arena_state.deinit();
        const arena = arena_state.allocator();
        const own_path = try arena.dupe(u8, path);
        var dir = try Io.Dir.cwd().openDir(io, own_path, .{ .iterate = true });
        defer dir.close(io);
        var missions: std.ArrayList(Mission) = .empty;
        var each = dir.iterate();
        while (try each.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (!std.ascii.endsWithIgnoreCase(entry.name, profile.source_extension)) continue;
            const file = try arena.dupe(u8, entry.name);
            try missions.append(arena, .{ .file = file, .number = profile.missionNumber(file) });
        }
        std.mem.sort(Mission, missions.items, {}, struct {
            fn less(_: void, a: Mission, b: Mission) bool {
                return std.mem.lessThan(u8, a.file, b.file);
            }
        }.less);
        const folder = std.fs.path.basename(own_path);
        return .{
            .arena = arena_state,
            .path = own_path,
            .folder = folder,
            .name = manifestName(io, arena, dir) orelse folder,
            .missions = try missions.toOwnedSlice(arena),
        };
    }

    pub fn close(project: *Project) void {
        project.arena.deinit();
    }

    /// The full path of `file` in the mod's folder, in `allocator`.
    pub fn pathOf(project: *const Project, allocator: Allocator, file: []const u8) Allocator.Error![]const u8 {
        return std.fs.path.join(allocator, &.{ project.path, file });
    }
};

/// The name the manifest in `dir` gives, if there is one.
fn manifestName(io: Io, arena: Allocator, dir: Io.Dir) ?[]const u8 {
    const text = dir.readFileAlloc(io, "mod.ini", arena, .limited(64 * 1024)) catch return null;
    const entries = ini.parse(arena, text) catch return null;
    const name = ini.get(entries, "Mod", "Name") orelse return null;
    return if (name.len > 0) name else null;
}

/// The mods in the `mods` folder of the game in `game_folder`, by name. Mods packed in `.hog`
/// archives aren't listed: they're read only.
pub fn listMods(arena: Allocator, io: Io, game_folder: []const u8, profile: *const game.Profile) ![]const Summary {
    const mods_path = try std.fs.path.join(arena, &.{ game_folder, "mods" });
    var mods = Io.Dir.cwd().openDir(io, mods_path, .{ .iterate = true }) catch return &.{};
    defer mods.close(io);
    var found: std.ArrayList(Summary) = .empty;
    var each = mods.iterate();
    while (try each.next(io)) |entry| {
        if (entry.kind != .directory or entry.name[0] == '.') continue;
        const folder = try arena.dupe(u8, entry.name);
        var dir = mods.openDir(io, folder, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        const contents = try look(io, arena, dir, profile);
        try found.append(arena, .{
            .path = try std.fs.path.join(arena, &.{ mods_path, folder }),
            .folder = folder,
            .name = manifestName(io, arena, dir) orelse folder,
            .holds = contents.holds,
            .kind = contents.kind,
        });
    }
    std.mem.sort(Summary, found.items, {}, struct {
        fn less(_: void, a: Summary, b: Summary) bool {
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
    }.less);
    return found.toOwnedSlice(arena);
}

const Contents = struct { holds: []const u8, kind: Kind };

/// What the mod in `dir` holds, from its files' names.
fn look(io: Io, arena: Allocator, dir: Io.Dir, profile: *const game.Profile) !Contents {
    var missions: usize = 0;
    var mission_file: ?[]const u8 = null;
    var scripts: usize = 0;
    var sounds: usize = 0;
    var files: usize = 0;
    var each = dir.iterate();
    while (try each.next(io)) |entry| {
        if (entry.kind != .file) continue;
        files += 1;
        const name = entry.name;
        if (std.ascii.endsWithIgnoreCase(name, profile.source_extension)) {
            missions += 1;
        } else if (std.ascii.endsWithIgnoreCase(name, profile.mission_extension) and profile.missionNumber(name) != null) {
            if (mission_file == null) mission_file = try arena.dupe(u8, name);
        } else if (std.ascii.endsWithIgnoreCase(name, ".luau")) {
            scripts += 1;
        } else if (std.ascii.endsWithIgnoreCase(name, ".wav") or std.ascii.endsWithIgnoreCase(name, ".flac") or std.ascii.endsWithIgnoreCase(name, ".ogg") or std.ascii.endsWithIgnoreCase(name, ".mp3")) {
            sounds += 1;
        }
    }
    if (missions > 0) return .{ .holds = try plural(arena, missions, "mission"), .kind = .missions };
    if (mission_file) |file| return .{ .holds = file, .kind = .missions };
    if (sounds > 0 and sounds * 2 >= files) return .{ .holds = try plural(arena, sounds, "sound file"), .kind = .sound };
    if (scripts > 0) return .{ .holds = try plural(arena, scripts, "script"), .kind = .other };
    return .{ .holds = try plural(arena, files, "file"), .kind = .other };
}

fn plural(arena: Allocator, count: usize, noun: []const u8) Allocator.Error![]const u8 {
    return arena.print("{d} {s}{s}", .{ count, noun, if (count == 1) "" else "s" });
}

/// The game folder the editor finds by itself: a folder named after the game, or holding a
/// `mods` folder, in the current folder or beside the editor.
pub fn findGameFolder(io: Io, arena: Allocator, profile: *const game.Profile) ?[]const u8 {
    const own = std.process.executableDirPathAlloc(io, arena) catch null;
    for ([_]?[]const u8{ ".", own }) |known| {
        const place = known orelse continue;
        const named = std.fs.path.join(arena, &.{ place, profile.folder }) catch continue;
        if (holdsMods(io, named)) return std.fs.path.resolve(arena, &.{named}) catch named;
        if (holdsMods(io, place)) return std.fs.path.resolve(arena, &.{place}) catch place;
    }
    return null;
}

fn holdsMods(io: Io, folder: []const u8) bool {
    var path_buffer: [4096]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buffer, "{s}{s}mods", .{ folder, std.fs.path.sep_str }) catch return false;
    var dir = Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

test plural {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("1 mission", try plural(arena.allocator(), 1, "mission"));
    try std.testing.expectEqualStrings("3 scripts", try plural(arena.allocator(), 3, "script"));
}
