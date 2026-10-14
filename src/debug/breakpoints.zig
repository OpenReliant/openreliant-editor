//! The editor's breakpoints (design/debugger.md): where each one holds the game's script, by the
//! build's map of the script's statements, and the breakpoints of each source file, kept in the
//! editor's settings folder so that they come back when the file opens again. They're the
//! editor's, not the mod's.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const game = @import("../game.zig");
const ini = @import("../ini.zig");

/// Where a breakpoint on `line` holds the script in `mission`, a build of the source: before the
/// first statement on the line that the script can hold before, or on the next line that has one,
/// within the code of the record that holds the line. Outside a record, the next one's code counts.
/// Null where nothing holds.
pub fn place(mission: game.Mission, outline: game.Outline, line: u32) ?game.Statement {
    const last_line = if (outline.at(line)) |record| record.last_line else std.math.maxInt(u32);
    return mission.breakpointFor(line, last_line);
}

/// The offsets in the script where the breakpoints on `lines` hold it, in order, each once.
pub fn offsets(arena: Allocator, mission: game.Mission, outline: game.Outline, lines: []const usize) Allocator.Error![]u32 {
    var found: std.ArrayList(u32) = .empty;
    for (lines) |line| {
        const statement = place(mission, outline, @intCast(line)) orelse continue;
        if (std.mem.findScalar(u32, found.items, statement.offset) == null) try found.append(arena, statement.offset);
    }
    std.mem.sort(u32, found.items, {}, std.sort.asc(u32));
    return found.items;
}

/// The name of the file the breakpoints are kept in, in the settings folder.
const file_name = "breakpoints.ini";

/// The breakpoints of each source file, by its path, as `breakpoints.ini` keeps them: a section
/// for each file, and a line for each breakpoint, its line counted from 1.
pub const Store = struct {
    gpa: Allocator,
    /// The file they're kept in; null where the system gives no settings folder, and nothing is
    /// kept.
    path: ?[]const u8 = null,
    /// The lines of each file's breakpoints, counted from 0, in order. The paths and the lines are
    /// the store's.
    files: std.StringArrayHashMapUnmanaged([]const u32) = .empty,

    /// The breakpoints kept in the settings folder `folder`.
    pub fn load(gpa: Allocator, io: Io, folder: ?[]const u8) Store {
        var store: Store = .{ .gpa = gpa };
        const settings = folder orelse return store;
        store.path = std.fs.path.join(gpa, &.{ settings, file_name }) catch return store;
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const text = Io.Dir.cwd().readFileAlloc(io, store.path.?, arena.allocator(), .limited(4 * 1024 * 1024)) catch return store;
        store.read(arena.allocator(), text) catch {};
        return store;
    }

    pub fn deinit(store: *Store) void {
        store.forget();
        store.files.deinit(store.gpa);
        if (store.path) |path| store.gpa.free(path);
    }

    /// The lines of the breakpoints of the source file at `source`, counted from 0.
    pub fn lines(store: *const Store, source: []const u8) []const u32 {
        return store.files.get(source) orelse &.{};
    }

    /// Keeps `kept`, lines counted from 0, as the breakpoints of the source file at `source`, and
    /// saves them all.
    pub fn keep(store: *Store, io: Io, source: []const u8, kept: []const usize) void {
        store.set(source, kept) catch return;
        store.save(io);
    }

    /// Forgets every file's breakpoints, and saves.
    pub fn removeAll(store: *Store, io: Io) void {
        store.forget();
        store.save(io);
    }

    /// How many files have breakpoints, and how many breakpoints they have in all.
    pub fn count(store: *const Store) struct { files: usize, breakpoints: usize } {
        var breakpoints: usize = 0;
        for (store.files.values()) |kept| breakpoints += kept.len;
        return .{ .files = store.files.count(), .breakpoints = breakpoints };
    }

    fn set(store: *Store, source: []const u8, kept: []const usize) Allocator.Error!void {
        const gpa = store.gpa;
        if (kept.len == 0) {
            const removed = store.files.fetchOrderedRemove(source) orelse return;
            gpa.free(removed.key);
            gpa.free(removed.value);
            return;
        }
        const made = try gpa.alloc(u32, kept.len);
        errdefer gpa.free(made);
        for (made, kept) |*line, from| line.* = @intCast(from);
        std.mem.sort(u32, made, {}, std.sort.asc(u32));
        const entry = try store.files.getOrPut(gpa, source);
        if (entry.found_existing) {
            gpa.free(entry.value_ptr.*);
        } else {
            entry.key_ptr.* = gpa.dupe(u8, source) catch |err| {
                store.files.orderedRemoveAt(entry.index);
                return err;
            };
        }
        entry.value_ptr.* = made;
    }

    fn forget(store: *Store) void {
        for (store.files.keys(), store.files.values()) |path, kept| {
            store.gpa.free(path);
            store.gpa.free(kept);
        }
        store.files.clearRetainingCapacity();
    }

    fn read(store: *Store, arena: Allocator, text: []const u8) Allocator.Error!void {
        var by_file: std.StringArrayHashMapUnmanaged(std.ArrayList(usize)) = .empty;
        for (try ini.parse(arena, text)) |entry| {
            const line = std.fmt.parseInt(u32, entry.key, 10) catch continue;
            if (line == 0 or !std.ascii.eqlIgnoreCase(entry.value, line_kind)) continue;
            const found = try by_file.getOrPutValue(arena, entry.section, .empty);
            try found.value_ptr.append(arena, line - 1);
        }
        for (by_file.keys(), by_file.values()) |source, kept| try store.set(source, kept.items);
    }

    fn write(store: *const Store, out: *Io.Writer) Io.Writer.Error!void {
        try out.writeAll("; OpenReliant Editor's breakpoints, by source file, each on its line counted from 1.\n");
        for (store.files.keys(), store.files.values()) |source, kept| {
            try out.print("\n[{s}]\n", .{source});
            for (kept) |line| try out.print("{d}={s}\n", .{ line + 1, line_kind });
        }
    }

    /// Saves the breakpoints. A failure is logged: the editor works on without them.
    fn save(store: *const Store, io: Io) void {
        const path = store.path orelse return;
        var text: Io.Writer.Allocating = .init(store.gpa);
        defer text.deinit();
        store.write(&text.writer) catch return;
        Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text.written() }) catch |err| {
            std.log.warn("can't save {s}: {t}", .{ path, err });
        };
    }
};

/// What a line of `breakpoints.ini` says of a breakpoint: that it holds on its line. Breakpoints
/// with conditions, counts and messages come with stage 2 of the design.
const line_kind = "line";

test place {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const source = game.starlancer.first_mission;
    const mission = (try game.starlancer.profile.build(arena.allocator(), source)).mission;
    const outline = try game.starlancer.profile.outline(arena.allocator(), source);
    // The Sabres' attack holds on its own line, 46 counting from 1.
    try std.testing.expectEqual(45, place(mission, outline, 45).?.at.line);
    // Its trigger's `return 1` and `end` can't hold, and nothing after them in the trigger does.
    try std.testing.expectEqual(null, place(mission, outline, 46));
    try std.testing.expectEqual(null, place(mission, outline, 47));
    // A blank line between records takes the next record's first statement.
    try std.testing.expectEqual(52, place(mission, outline, 48).?.at.line);
    const found = try offsets(arena.allocator(), mission, outline, &.{ 52, 45, 48, 46 });
    try std.testing.expectEqual(2, found.len);
    try std.testing.expect(found[0] < found[1]);
}

test Store {
    const gpa = std.testing.allocator;
    var store: Store = .{ .gpa = gpa };
    defer store.deinit();
    try store.set("/mods/a/mission90.mission.luau", &.{ 52, 45 });
    try store.set("/mods/b/mission91.mission.luau", &.{3});
    try std.testing.expectEqualSlices(u32, &.{ 45, 52 }, store.lines("/mods/a/mission90.mission.luau"));
    try std.testing.expectEqual(3, store.count().breakpoints);
    // They read back as written, a file's lines counted from 1.
    var text: Io.Writer.Allocating = .init(gpa);
    defer text.deinit();
    try store.write(&text.writer);
    try std.testing.expect(std.mem.find(u8, text.written(), "[/mods/a/mission90.mission.luau]\n46=line\n53=line\n") != null);
    var again: Store = .{ .gpa = gpa };
    defer again.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    try again.read(arena.allocator(), text.written());
    try std.testing.expectEqualSlices(u32, &.{3}, again.lines("/mods/b/mission91.mission.luau"));
    // A file without breakpoints is forgotten.
    try again.set("/mods/b/mission91.mission.luau", &.{});
    try std.testing.expectEqual(1, again.count().files);
    try std.testing.expectEqual(0, again.lines("/mods/c.mission.luau").len);
}
