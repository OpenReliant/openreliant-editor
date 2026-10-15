//! An open mission: its source in the text editor, checked as it's typed, its outline from the
//! last source that parsed, its problems, the build of its text with the map of its script's
//! statements, its breakpoints, the line where the game holds its script, and what its last build
//! wrote.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const c = @import("c");

const game = @import("../game.zig");
const text_editor = @import("../ui/text_editor.zig");
const theme = @import("../ui/theme.zig");
const TextEditor = text_editor.TextEditor;

/// How long the source waits after the last change before it's checked again, in milliseconds.
pub const check_delay_ms = 300;

/// The most breakpoints a mission keeps.
pub const max_breakpoints = 256;

/// What a line's data holds.
const LineFlags = packed struct(usize) {
    breakpoint: bool = false,
    _: @Int(.unsigned, @bitSizeOf(usize) - 1) = 0,
};

/// A check of the source: its outline, its problems, and its build where it has none, in an arena
/// of their own.
const Check = struct {
    arena: std.heap.ArenaAllocator,
    outline: game.Outline = .{ .records = &.{}, .errors = &.{} },
    problems: []const game.Problem = &.{},
    mission: ?game.Mission = null,

    fn deinit(check: *Check) void {
        check.arena.deinit();
    }
};

/// What the last build wrote.
pub const Build = struct {
    /// The mission file's name, such as `mission90.dte`.
    file: []const u8,
    /// When, as the clock showed it: "09:33:58".
    time: [8]u8,
};

pub const Document = struct {
    gpa: Allocator,
    profile: *const game.Profile,
    /// The source file's path, and its name.
    path: []const u8,
    file: []const u8,
    number: ?u32,
    editor: TextEditor,
    /// The editor's version when the text was saved.
    saved_version: usize,
    /// The version the last check read, and when the text last changed.
    checked_version: usize,
    changed_at: u64 = 0,
    check: Check,
    /// The outline of the last source that parsed, which the outline shows while the source has
    /// errors.
    good: Check,
    /// Whether the outline is from older source than the text's.
    outline_stale: bool = false,
    /// A number that changes whenever `good` does.
    outline_generation: usize = 0,
    built: ?Build = null,
    /// The listing of the last build's script, in its own arena.
    listing: ?[]const u8 = null,
    listing_arena: std.heap.ArenaAllocator,
    /// Whether the listing changed since the listing view showed it.
    listing_fresh: bool = false,
    /// The line where the game holds the script, counting from 0, which the text tints.
    held_line: ?u32 = null,
    /// The change to the text that the interface asked for during a frame, made once the frame is
    /// drawn (`flush`): making it checks the text again, which replaces the outline the frame drew
    /// from. Its strings are in `queue_arena`.
    queued: ?Queued = null,
    queue_arena: std.heap.ArenaAllocator,
    /// What the map shows of the text (`scene`), in its own arena, with the text's version and the
    /// outline's generation it was read from.
    scene_read: ?struct { version: usize, generation: usize, scene: game.Scene } = null,
    scene_arena: std.heap.ArenaAllocator,

    /// Opens the source file at `path`.
    pub fn open(gpa: Allocator, io: Io, path: []const u8, profile: *const game.Profile, language: ?text_editor.Language) !*Document {
        const text = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 * 1024 * 1024));
        defer gpa.free(text);
        const document = try gpa.create(Document);
        errdefer gpa.destroy(document);
        const own_path = try gpa.dupe(u8, path);
        errdefer gpa.free(own_path);
        const editor: TextEditor = .init();
        editor.setLanguage(language);
        editor.setText(text);
        const file = std.fs.path.basename(own_path);
        document.* = .{
            .gpa = gpa,
            .profile = profile,
            .path = own_path,
            .file = file,
            .number = profile.missionNumber(file),
            .editor = editor,
            .saved_version = editor.version(),
            .checked_version = editor.version() +% 1,
            .check = .{ .arena = .init(gpa) },
            .good = .{ .arena = .init(gpa) },
            .listing_arena = .init(gpa),
            .queue_arena = .init(gpa),
            .scene_arena = .init(gpa),
        };
        document.recheck() catch {};
        return document;
    }

    pub fn close(document: *Document) void {
        document.editor.deinit();
        document.check.deinit();
        document.good.deinit();
        document.listing_arena.deinit();
        document.queue_arena.deinit();
        document.scene_arena.deinit();
        document.gpa.free(document.path);
        document.gpa.destroy(document);
    }

    pub fn dirty(document: *const Document) bool {
        return document.editor.version() != document.saved_version;
    }

    /// The problems of the source as last checked.
    pub fn problems(document: *const Document) []const game.Problem {
        return document.check.problems;
    }

    /// The outline to show: the last one that parsed.
    pub fn outline(document: *const Document) game.Outline {
        return document.good.outline;
    }

    /// What the map shows of the mission (`Profile.scene`), read again only once the text or its
    /// outline changed, since reading it parses the whole script.
    pub fn scene(document: *Document) Allocator.Error!game.Scene {
        const version = document.editor.version();
        if (document.scene_read) |read| {
            if (read.version == version and read.generation == document.outline_generation) return read.scene;
        }
        document.scene_read = null;
        _ = document.scene_arena.reset(.retain_capacity);
        const arena = document.scene_arena.allocator();
        const made = try document.profile.scene(arena, try arena.dupe(u8, document.editor.text()), document.outline());
        document.scene_read = .{ .version = version, .generation = document.outline_generation, .scene = made };
        return made;
    }

    /// The build of the text as last checked, with the map of its script's statements; null while
    /// the text has problems.
    pub fn mission(document: *const Document) ?game.Mission {
        return document.check.mission;
    }

    /// Checks the text again once it has rested for `check_delay_ms` since its last change. True
    /// when it checked.
    pub fn update(document: *Document, now_ms: u64) bool {
        const version = document.editor.version();
        if (version == document.checked_version) return false;
        if (document.changed_at == 0) {
            document.changed_at = now_ms;
            return false;
        }
        if (now_ms -% document.changed_at < check_delay_ms) return false;
        document.recheck() catch {};
        return true;
    }

    /// Notes that the text changed now, which delays its check.
    pub fn touched(document: *Document, now_ms: u64) void {
        document.changed_at = now_ms;
    }

    /// Whether a check is waiting for the text to rest.
    pub fn checkPending(document: *const Document) bool {
        return document.editor.version() != document.checked_version;
    }

    /// Reads the outline and the problems of the text as it is.
    pub fn recheck(document: *Document) Allocator.Error!void {
        var check: Check = .{ .arena = .init(document.gpa) };
        errdefer check.deinit();
        const arena = check.arena.allocator();
        const text = try arena.dupe(u8, document.editor.text());
        check.outline = try document.profile.outline(arena, text);
        if (check.outline.errors.len > 0) {
            check.problems = check.outline.errors;
        } else {
            switch (try document.profile.build(arena, text)) {
                .mission => |made| check.mission = made,
                .problems => |found| check.problems = found,
            }
        }
        document.checked_version = document.editor.version();
        document.changed_at = 0;
        if (check.outline.errors.len == 0) {
            // The outline parsed: it becomes the one shown, in a check of its own.
            var good: Check = .{ .arena = .init(document.gpa) };
            good.outline = try copyOutline(good.arena.allocator(), check.outline);
            document.good.deinit();
            document.good = good;
            document.outline_generation +%= 1;
            document.outline_stale = false;
        } else {
            document.outline_stale = true;
        }
        document.check.deinit();
        document.check = check;
        document.mark();
    }

    /// A change to the text asked for during a frame.
    pub const Queued = union(enum) {
        /// An edit to the record at `index` among `section`'s.
        edit: struct { section: game.Section, index: usize, edit: game.Edit },
        /// A new record of `kind`, under `name` where one is given.
        add: struct { kind: game.NewKind, name: ?[]const u8 },
        /// Text in place of a span of the editor's text.
        replace: struct { start: text_editor.Pos, end: text_editor.Pos, text: []const u8 },
    };

    /// What a queued change came to.
    pub const Made = union(enum) {
        none,
        /// Whether an edit was made.
        edited: bool,
        /// The new record's section, and the line it starts on; null where it wasn't added.
        added: struct { section: game.Section, line: ?u32 },
    };

    /// Asks for `change` to be made once the frame is drawn (`flush`), in place of any asked for
    /// earlier in the frame. Its strings are copied.
    pub fn queue(document: *Document, change: Queued) void {
        _ = document.queue_arena.reset(.retain_capacity);
        const arena = document.queue_arena.allocator();
        document.queued = copyQueued(arena, change) catch null;
    }

    /// Makes the change asked for during the frame, if one was.
    pub fn flush(document: *Document) Allocator.Error!Made {
        const queued = document.queued orelse return .none;
        document.queued = null;
        switch (queued) {
            .edit => |asked| return .{ .edited = try document.editRecord(asked.section, asked.index, asked.edit) },
            .add => |asked| return .{ .added = .{ .section = asked.kind.section, .line = try document.addRecord(asked.kind, asked.name) } },
            .replace => |asked| {
                document.editor.replace(asked.start, asked.end, asked.text);
                try document.recheck();
                return .{ .edited = true };
            },
        }
    }

    /// Makes `edit` to the record at `index` among `section`'s, through the game's profile, as
    /// one step of the editor's undo, and checks the text again at once, so that the outline and
    /// the inspector show the change. Text typed since the last check is checked first. False
    /// where the source can't take the edit: it doesn't parse, or the declaration has no place for
    /// it.
    fn editRecord(document: *Document, section: game.Section, index: usize, edit: game.Edit) Allocator.Error!bool {
        if (document.checkPending()) try document.recheck();
        if (document.outline_stale) return false;
        const current = document.outline().nth(section, index) orelse return false;
        var arena_state: std.heap.ArenaAllocator = .init(document.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const text = try arena.dupe(u8, document.editor.text());
        const change = try document.profile.edit(arena, text, current.*, edit) orelse return false;
        document.editor.replace(posAt(text, change.start), posAt(text, change.end), change.text);
        try document.recheck();
        return true;
    }

    /// Declares a new record of `kind` through the game's profile, as one step of the editor's
    /// undo, under `name` where one is given. The line its declaration starts on; null where the
    /// source doesn't parse, or `name` is taken.
    fn addRecord(document: *Document, kind: game.NewKind, name: ?[]const u8) Allocator.Error!?u32 {
        if (document.checkPending()) try document.recheck();
        if (document.outline_stale) return null;
        var arena_state: std.heap.ArenaAllocator = .init(document.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const text = try arena.dupe(u8, document.editor.text());
        const added = try document.profile.addRecord(arena, text, document.outline(), kind, name) orelse return null;
        document.editor.replace(posAt(text, added.change.start), posAt(text, added.change.end), added.change.text);
        try document.recheck();
        return added.line;
    }

    /// Tints the line where the game holds the script, or none.
    pub fn setHeldLine(document: *Document, line: ?u32) void {
        if (document.held_line == line) return;
        document.held_line = line;
        document.mark();
    }

    /// Puts the problems on the text, each line tinted red and a squiggle under each one's word,
    /// and tints the line where the game holds the script.
    fn mark(document: *Document) void {
        const editor = document.editor;
        editor.clearSquiggles();
        editor.clearMarkers();
        // The text's part of the held line; the gutter draws its own (`views/script.zig`).
        if (document.held_line) |line| editor.addMarker(line, 0, theme.held_line, "");
        for (document.check.problems) |problem| {
            editor.addMarker(problem.at.line, 0, theme.error_line, "");
            const at: text_editor.Pos = .{ .line = problem.at.line, .index = problem.at.column };
            var end = editor.wordEnd(at);
            if (end.line != at.line or end.index <= at.index) end = .{ .line = at.line, .index = at.index + 1 };
            editor.addSquiggle(at, end, theme.error_icon, problem.message);
        }
    }

    /// Saves the text to the source file.
    pub fn save(document: *Document, io: Io) !void {
        const text = document.editor.text();
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = document.path, .data = text });
        document.saved_version = document.editor.version();
    }

    pub const BuildResult = union(enum) {
        built: []const u8,
        problems: []const game.Problem,
        no_number,
    };

    /// Builds the text into the mission file beside the source, and keeps its listing.
    pub fn build(document: *Document, io: Io) !BuildResult {
        try document.recheck();
        if (document.check.problems.len > 0) return .{ .problems = document.check.problems };
        if (document.number == null) return .no_number;
        var arena_state: std.heap.ArenaAllocator = .init(document.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const text = try arena.dupe(u8, document.editor.text());
        const image = switch (try document.profile.build(arena, text)) {
            .mission => |made| made.file,
            .problems => return .{ .problems = document.check.problems },
        };
        const stem = document.file[0 .. document.file.len - document.profile.source_extension.len];
        const file = try std.fmt.allocPrint(arena, "{s}{s}", .{ stem, document.profile.mission_extension });
        const folder = std.fs.path.dirname(document.path) orelse ".";
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(arena, &.{ folder, file }), .data = image });
        _ = document.listing_arena.reset(.retain_capacity);
        const kept = document.listing_arena.allocator();
        document.listing = try document.profile.listing(kept, image);
        document.listing_fresh = true;
        document.built = .{ .file = try kept.dupe(u8, file), .time = clockNow() };
        return .{ .built = document.built.?.file };
    }

    pub fn hasBreakpoint(document: *const Document, line: usize) bool {
        const flags: LineFlags = @bitCast(document.editor.lineData(line));
        return flags.breakpoint;
    }

    pub fn toggleBreakpoint(document: *Document, line: usize) void {
        document.setBreakpoint(line, !document.hasBreakpoint(line));
    }

    pub fn setBreakpoint(document: *Document, line: usize, on: bool) void {
        if (line >= document.editor.lineCount()) return;
        var flags: LineFlags = @bitCast(document.editor.lineData(line));
        flags.breakpoint = on;
        document.editor.setLineData(line, @bitCast(flags));
    }

    /// The lines with breakpoints, in order, into `buffer`.
    pub fn breakpoints(document: *const Document, buffer: *[max_breakpoints]usize) []usize {
        return document.editor.linesWithData(buffer);
    }

    pub fn clearBreakpoints(document: *Document) void {
        var buffer: [max_breakpoints]usize = undefined;
        for (document.breakpoints(&buffer)) |line| document.editor.setLineData(line, 0);
    }
};

/// A copy of `change` in `arena`, with its strings.
fn copyQueued(arena: Allocator, change: Document.Queued) Allocator.Error!Document.Queued {
    return switch (change) {
        .edit => |asked| .{ .edit = .{ .section = asked.section, .index = asked.index, .edit = switch (asked.edit) {
            .field => |set| .{ .field = .{ .name = try arena.dupe(u8, set.name), .value = if (set.value) |value| try arena.dupe(u8, value) else null } },
            .display => |text| .{ .display = try arena.dupe(u8, text) },
            .subject => |text| .{ .subject = try arena.dupe(u8, text) },
            .condition => |text| .{ .condition = try arena.dupe(u8, text) },
            .value => |text| .{ .value = try arena.dupe(u8, text) },
        } } },
        .add => |asked| .{ .add = .{ .kind = asked.kind, .name = if (asked.name) |name| try arena.dupe(u8, name) else null } },
        .replace => |asked| .{ .replace = .{ .start = asked.start, .end = asked.end, .text = try arena.dupe(u8, asked.text) } },
    };
}

/// The text editor's place of byte `at` of `text`: its line, and its character on the line.
fn posAt(text: []const u8, at: usize) text_editor.Pos {
    const start = if (std.mem.findScalarLast(u8, text[0..at], '\n')) |newline| newline + 1 else 0;
    const line = std.mem.count(u8, text[0..start], "\n");
    const index = std.unicode.utf8CountCodepoints(text[start..at]) catch at - start;
    return .{ .line = line, .index = index };
}

test posAt {
    // `é` takes two bytes and is one character.
    try std.testing.expectEqual(text_editor.Pos{ .line = 1, .index = 3 }, posAt("a\nNé b", 6));
    try std.testing.expectEqual(text_editor.Pos{ .line = 0, .index = 0 }, posAt("abc", 0));
}

/// A copy of `outline` in `arena`, so that it outlives the check that read it.
fn copyOutline(arena: Allocator, outline: game.Outline) Allocator.Error!game.Outline {
    const records = try arena.alloc(game.Record, outline.records.len);
    for (records, outline.records) |*copy, record| {
        copy.* = record;
        copy.word = try arena.dupe(u8, record.word);
        copy.name = try arena.dupe(u8, record.name);
        copy.title = try arena.dupe(u8, record.title);
        copy.display = try arena.dupe(u8, record.display);
        copy.detail = try arena.dupe(u8, record.detail);
        copy.subject = try arena.dupe(u8, record.subject);
        copy.condition = try arena.dupe(u8, record.condition);
        const fields = try arena.alloc(game.Field, record.fields.len);
        for (fields, record.fields) |*field, from| field.* = .{ .name = try arena.dupe(u8, from.name), .source = try arena.dupe(u8, from.source), .value = try arena.dupe(u8, from.value), .names_record = from.names_record };
        copy.fields = fields;
    }
    return .{
        .name = if (outline.name) |name| try arena.dupe(u8, name) else null,
        .records = records,
        .errors = &.{},
    };
}

/// The time of day as the clock shows it: "09:33:58".
pub fn clockNow() [8]u8 {
    var shown: [8]u8 = "--:--:--".*;
    var now: c.SDL_Time = 0;
    if (!c.SDL_GetCurrentTime(&now)) return shown;
    var date: c.SDL_DateTime = undefined;
    if (!c.SDL_TimeToDateTime(now, &date, true)) return shown;
    _ = std.fmt.bufPrint(&shown, "{d:0>2}:{d:0>2}:{d:0>2}", .{ @as(u32, @intCast(date.hour)), @as(u32, @intCast(date.minute)), @as(u32, @intCast(date.second)) }) catch {};
    return shown;
}
