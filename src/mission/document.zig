//! An open mission: its source in the text editor, checked as it's typed, its outline from the
//! last source that parsed, its problems, its breakpoints, and what its last build made.

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

/// A check of the source: its outline and its problems, in an arena of their own.
const Check = struct {
    arena: std.heap.ArenaAllocator,
    outline: game.Outline = .{ .records = &.{}, .errors = &.{} },
    problems: []const game.Problem = &.{},

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
    built: ?Build = null,
    /// The listing of the last build's script, in its own arena.
    listing: ?[]const u8 = null,
    listing_arena: std.heap.ArenaAllocator,
    /// Whether the listing changed since the listing view showed it.
    listing_fresh: bool = false,

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
        };
        document.recheck() catch {};
        return document;
    }

    pub fn close(document: *Document) void {
        document.editor.deinit();
        document.check.deinit();
        document.good.deinit();
        document.listing_arena.deinit();
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
                .mission => check.problems = &.{},
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
            document.outline_stale = false;
        } else {
            document.outline_stale = true;
        }
        document.check.deinit();
        document.check = check;
        document.markProblems();
    }

    /// Puts the problems on the text: the line tinted red, and a squiggle under each one's word.
    fn markProblems(document: *Document) void {
        const editor = document.editor;
        editor.clearSquiggles();
        editor.clearMarkers();
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
            .mission => |made| made,
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
        var flags: LineFlags = @bitCast(document.editor.lineData(line));
        flags.breakpoint = !flags.breakpoint;
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

/// A copy of `outline` in `arena`, so that it outlives the check that read it.
fn copyOutline(arena: Allocator, outline: game.Outline) Allocator.Error!game.Outline {
    const records = try arena.alloc(game.Record, outline.records.len);
    for (records, outline.records) |*copy, record| {
        copy.* = record;
        copy.name = try arena.dupe(u8, record.name);
        copy.title = try arena.dupe(u8, record.title);
        copy.display = try arena.dupe(u8, record.display);
        copy.detail = try arena.dupe(u8, record.detail);
        copy.subject = try arena.dupe(u8, record.subject);
        copy.condition = try arena.dupe(u8, record.condition);
        const fields = try arena.alloc(game.Field, record.fields.len);
        for (fields, record.fields) |*field, from| field.* = .{ .name = try arena.dupe(u8, from.name), .value = try arena.dupe(u8, from.value), .names_record = from.names_record };
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
