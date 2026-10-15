//! What the editor knows of a game on OpenReliant's engine. The interface never names a game's
//! commands, conditions or records itself: it asks the game's profile, which reads them from
//! OpenReliant's own tables, so that when OpenReliant plays other games, each one is a profile
//! here (`game/starlancer.zig` is StarLancer's). A profile's data, its names, extensions, words
//! and records, is kept apart from what it asks of OpenReliant's library, building and reading
//! missions, so that profiles can become files that a Game mode edits, for games made on
//! OpenReliant.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const starlancer = @import("game/starlancer.zig");

/// The games the editor knows, by the name the editor link's `Hello` gives.
pub const all = [_]*const Profile{&starlancer.profile};

/// The game whose profile has `name`, as `Hello` gives it, in any case.
pub fn named(name: []const u8) ?*const Profile {
    for (all) |profile| if (std.ascii.eqlIgnoreCase(profile.name, name)) return profile;
    return null;
}

pub const Profile = struct {
    /// The game's name, as the editor link's `Hello` gives it: "StarLancer".
    name: []const u8,
    /// The dialect of its script VM, as `Hello`'s `vm` gives it.
    vm: []const u8,
    /// The folder the installation guide installs the game in, which the editor looks for.
    folder: []const u8,
    /// A mission file's extension: ".dte".
    mission_extension: []const u8,
    /// A mission source file's extension: ".mission.luau".
    source_extension: []const u8,
    /// The words of mission source, for colours, completion and help. Made once by `language`.
    language: *const fn (arena: Allocator) Allocator.Error!Language,
    /// Builds mission source into a mission file, with the map of its script's statements.
    build: *const fn (arena: Allocator, text: []const u8) Allocator.Error!Built,
    /// The records the source declares, for the outline, with the errors Luau's parser finds.
    outline: *const fn (arena: Allocator, text: []const u8) Allocator.Error!Outline,
    /// The change to the source `text` that makes `edit` to `record`, as the outline of `text`
    /// read it; null where the declaration has no place for it, such as a field taken out that
    /// isn't there.
    edit: *const fn (arena: Allocator, text: []const u8, record: Record, edit: Edit) Allocator.Error!?Change,
    /// The fields a record's table can give, from the game's tables, for the inspector's form.
    fields: *const fn (record: Record) []const FieldForm,
    /// The kind of value a type of mission source takes, such as `FlightGroup?` or `ShipType`, as
    /// the language's parameters and fields name them.
    fieldKind: *const fn (type_name: []const u8) FieldKind,
    /// What the map shows of the mission whose source is `text`, as `known` outlines it.
    scene: *const fn (arena: Allocator, text: []const u8, known: Outline) Allocator.Error!Scene,
    /// The kinds of record the outline's + adds, in the order its menu lists them.
    new_kinds: []const NewKind,
    /// The change to `text`, whose outline is `known`, that declares a new record of `kind` after
    /// the last record of its section: under `name` where one is given, or else a name no record
    /// has. Null where `name` is taken.
    addRecord: *const fn (arena: Allocator, text: []const u8, known: Outline, kind: NewKind, name: ?[]const u8) Allocator.Error!?Added,
    /// A built mission's script, as a listing of its instructions.
    listing: *const fn (arena: Allocator, mission: []const u8) Allocator.Error![]const u8,
    /// The number a mission file's name gives the mission: 90 for `mission90.dte`.
    missionNumber: *const fn (file_name: []const u8) ?u32,
    /// The first number a new mission takes, past the game's own missions.
    first_new_mission: u32,
    /// The source of a new mission named `name`: the least that builds and plays.
    newMission: *const fn (arena: Allocator, name: []const u8) Allocator.Error![]const u8,
    /// The command line that plays mission `number` of the game in `game_folder`, with the
    /// options `play` asks for, after the program's path.
    playArguments: *const fn (arena: Allocator, game_folder: []const u8, number: u32, play: Play) Allocator.Error![]const []const u8,
    /// The game's own missions in `game_folder`, by their numbers, mods left out.
    gameMissions: *const fn (arena: Allocator, io: std.Io, game_folder: []const u8) ReadError![]const GameMission,
    /// The mission file of the game's mission `number`, as the game reads it, mods left out.
    readGameMission: *const fn (arena: Allocator, io: std.Io, game_folder: []const u8, number: u32) ReadError!?[]const u8,
    /// A mission file as mission source.
    decompile: *const fn (arena: Allocator, mission: []const u8) ReadError![]const u8,
    /// How mission `b` differs from mission `a`, in a few words; null where they're the same
    /// mission, as the game plays them.
    difference: *const fn (arena: Allocator, a: []const u8, b: []const u8) ReadError!?[]const u8,
    /// Whether missions `a` and `b` have the same script, with the same routines for the same
    /// parts and triggers, so that a map of `a`'s statements holds for `b`. Their globals' values
    /// can differ, as a game's mission file gives them as they stand.
    sameScript: *const fn (a: []const u8, b: []const u8) bool,
    /// The script's flags for `mission`, as its script VM reads them: a byte for each byte of the
    /// script, with the flag that holds the script set on each of `offsets`. Null for a file that
    /// isn't a mission the profile can read.
    scriptFlags: *const fn (arena: Allocator, mission: []const u8, offsets: []const u32) Allocator.Error!?[]u8,
    /// The game's own messages on the editor link.
    link: Link,
};

/// The game's own messages on the editor link, beside OpenReliant's, by the tags its table gives
/// them: StarLancer's are OpenReliant's `engine.game.mission.editor`.
pub const Link = struct {
    /// The script's flags, from the editor (`Profile.scriptFlags`).
    script_flags: u16,
    /// Run control, from the editor (`runControl`).
    run_control: u16,
    /// A thread stopped, from the game: the offset in the script it stopped before.
    stopped: u16,
    /// Whether the thread pool's first thread has finished, from the game.
    first_finished: u16,
    /// The payload of run control that asks for `control`.
    runControl: *const fn (control: Control) [8]u8,
};

/// What the editor asks of the game's script with run control.
pub const Control = union(enum) {
    /// Pauses the whole mission, or lets it go on.
    pause: bool,
    /// Lets the held script run on to the next breakpoint.
    run_on,
    /// Runs to the next statement any thread runs.
    step_into,
    /// Runs to the next statement of the same block, past the parts it calls.
    step_over,
    /// Runs a part at once, on a new thread, by its index.
    run_part: u32,
};

pub const ReadError = Allocator.Error || error{
    /// The game's folder or its archive can't be read.
    Unreadable,
    /// The file isn't a mission the profile can read.
    NotAMission,
};

/// One of the game's own missions.
pub const GameMission = struct {
    number: u32,
    /// Where the game keeps it.
    origin: Origin,

    pub const Origin = enum {
        /// In the game's archive.
        archive,
        /// A file in the game's folder.
        loose,

        pub fn label(origin: Origin) []const u8 {
            return switch (origin) {
                .archive => "in the archive",
                .loose => "loose file",
            };
        }
    };
};

/// How to play a mission: whole, or from a part with the view on a ship.
pub const Play = struct {
    /// The part to run once the launch is over, by its name.
    part: ?[]const u8 = null,
    /// Whether to play the launch through without showing it.
    skip_launch: bool = false,
    /// The ship to watch, by its name.
    watch: ?[]const u8 = null,
    /// The port the game's editor link listens at, for the editor to link to it; null for none.
    link: ?u16 = null,
};

/// A change the inspector or the map makes to a record of mission source.
pub const Edit = union(enum) {
    /// A field of its table set to a value as the source writes it, or taken out with null.
    field: struct { name: []const u8, value: ?[]const u8 },
    /// Its display name.
    display: []const u8,
    /// A trigger's subject, as the source writes it: a record's name, or `nil`.
    subject: []const u8,
    /// A trigger's condition, by its name.
    condition: []const u8,
    /// A global's starting value, as the source writes it.
    value: []const u8,
};

/// A field a record's table can give, for the inspector's form.
pub const FieldForm = struct {
    name: []const u8,
    /// What it is, in the language's words.
    about: []const u8,
    kind: FieldKind,
    /// Whether the table can leave it out, which `none` does.
    optional: bool = true,
    /// The label the form shows; by default its name, as `Formation point` for `formation_point`.
    label: ?[]const u8 = null,
    /// A heading the form shows before it, such as `Place`.
    heading: ?[]const u8 = null,
    /// For a field shown on one row with the next ones of the same row: the row's label, such as
    /// `Angles`, and the field's letter in it, such as `Y` for the yaw.
    row: ?[]const u8 = null,
    letter: []const u8 = "",
    /// A note under its row, such as the angles' unit.
    note: ?[]const u8 = null,
};

/// The kind of value a field takes, which picks its control in the inspector.
pub const FieldKind = union(enum) {
    /// A record of the mission, of one of these sections, by its name.
    record: []const Section,
    /// A name of the game's values of this type, such as `ShipType`: the language's words of
    /// kind `value` whose type it is.
    value: []const u8,
    /// One of a few strings.
    strings: []const []const u8,
    /// A place or a direction: `{ x, y, z }`.
    vector,
    number,
    boolean,
    /// Anything else, which the inspector shows and takes as source.
    source,
};

/// What the map shows of a mission (`Profile.scene`), in the game's coordinates, Y down: where its
/// records start, the ranges its triggers watch, its curves, and where its script sends its ships.
pub const Scene = struct {
    things: []const Thing,
    /// The player's ship, by its place in `things`, where the mission has one.
    player: ?usize = null,
    ranges: []const Range,
    /// Each curve, as the points it passes.
    curves: []const []const [3]f64,
    routes: []const Route = &.{},
    /// The field the map writes a dragged thing's place to, such as `position`.
    place_field: []const u8,
};

/// A record the map places.
pub const Thing = struct {
    /// The record, by its section and its place among the section's (`Outline.nth`).
    section: Section,
    index: usize,
    kind: ThingKind,
    /// Where it starts.
    place: [3]f64,
    /// The way it points, as a unit vector; null for what points nowhere, such as a marker.
    heading: ?[3]f64 = null,
};

/// What a thing on the map is, which picks how it's drawn.
pub const ThingKind = enum {
    /// A ship, a capital ship or a station: an arrow that points the way it heads.
    ship,
    /// A nav point, a waypoint or a point, such as where a ship jumps in: a diamond.
    marker,
    /// A point of the director's camera's curves: shown with the curves.
    camera,
    /// Scenery far off, such as a planet or the sun: a ring, which the map's fit leaves out.
    scenery,
};

/// Where the script sends a ship or a group: a leg from each place it sends it to the next, as its
/// orders read in the order the source gives them. It's a reading of the script, not a run of it:
/// triggers run when their conditions hold, which may be in another order.
pub const Route = struct {
    /// The ship it's for, by its place in `Scene.things`; none for a group's.
    ship: ?usize,
    /// The flight group whose colour it takes: the ship's, or the group's own (`Record.group`).
    group: ?usize,
    legs: []const Leg,
};

/// A leg of a route, between two things by their place in `Scene.things`.
pub const Leg = struct {
    from: usize,
    to: usize,
    way: Way,
    /// Whether the route starts at `from`: where its ship starts, or where it comes in.
    starts: bool = false,
};

/// How a ship goes along a leg.
pub const Way = enum { fly, jump };

/// A distance the mission watches within, around one of its records.
pub const Range = struct {
    /// The record it's around, by its section and its place among the section's.
    section: Section,
    index: usize,
    radius: f64,
    /// What watches it, such as a trigger's condition.
    label: []const u8,
    style: RangeStyle,
};

pub const RangeStyle = enum {
    /// A trigger fires within it.
    trigger,
    /// A hint of the game's, such as the display's flyback marker.
    hint,
};

/// A kind of record the outline's + adds.
pub const NewKind = struct {
    /// The word that declares it, such as `ship`.
    word: []const u8,
    /// What the menu calls it, such as `Ship`.
    label: []const u8,
    section: Section,
    /// Whether it's declared under a name the script uses, which a trigger isn't, so that
    /// Declare can't offer it.
    named: bool = true,
};

/// A record declared: the change to the source, and the line its declaration starts on once the
/// change is made.
pub const Added = struct {
    change: Change,
    line: u32,
};

/// A change to mission source: the bytes from `start` to `end` replaced by `text`.
pub const Change = struct {
    start: usize,
    end: usize,
    text: []const u8,
};

/// A place in a file, counting lines and columns from 0.
pub const Place = struct {
    line: u32,
    column: u32 = 0,
};

/// What a build of mission source made.
pub const Built = union(enum) {
    mission: Mission,
    /// Why there's none.
    problems: []const Problem,
};

/// A mission file built from source, with the map of its script's statements to the source.
pub const Mission = struct {
    file: []const u8,
    /// Each statement of the script, in the order of their offsets.
    statements: []const Statement,

    /// The statement that ends at `offset`, the offset of a stop, if one does.
    pub fn statementAt(mission: Mission, offset: u32) ?Statement {
        const index = std.sort.binarySearch(Statement, mission.statements, offset, Statement.order) orelse return null;
        return mission.statements[index];
    }

    /// Where a breakpoint on `line` holds the script: the first statement it can hold before on
    /// that line, or on the next line that has one, up to `last_line`. Null where none does.
    pub fn breakpointFor(mission: Mission, line: u32, last_line: u32) ?Statement {
        var best: ?Statement = null;
        for (mission.statements) |statement| {
            if (!statement.stops or statement.at.line < line or statement.at.line > last_line) continue;
            const better = if (best) |found| statement.at.line < found.at.line else true;
            if (better) best = statement;
        }
        return best;
    }

    /// The first statement the script can hold before on `line`.
    pub fn statementOn(mission: Mission, line: u32) ?Statement {
        return mission.breakpointFor(line, line);
    }
};

/// A statement of a built mission's script.
pub const Statement = struct {
    /// The offset in the script of the instruction it ends with, which the script holds before, as
    /// the editor link gives a stop.
    offset: u32,
    /// Where it starts in the source.
    at: Place,
    /// Whether the script can hold before it: it can't before a `return`.
    stops: bool,

    fn order(offset: u32, statement: Statement) std.math.Order {
        return std.math.order(offset, statement.offset);
    }
};

pub const Problem = struct {
    at: Place,
    /// What's wrong, as OpenReliant says it. Names in it are in backticks.
    message: []const u8,
    /// What kind of mistake it is, where the editor can offer a fix.
    kind: Kind = .other,

    pub const Kind = union(enum) {
        other,
        /// A name the source uses without declaring it.
        not_declared: []const u8,
    };
};

/// The kinds of word mission source holds, which colour, complete and describe differently.
pub const WordKind = enum {
    /// The source language's own words, such as `function` and `end`.
    keyword,
    /// Mission source's own words, such as `ship` and `on`.
    declaration,
    /// The game's commands.
    command,
    /// The game's conditions, which triggers watch for, written as strings.
    condition,
    /// The game's variables, under `game.`.
    game_variable,
    /// The names of the game's values, such as orders and ship types, written as strings.
    value,

    pub fn label(kind: WordKind) []const u8 {
        return switch (kind) {
            .keyword => "keyword",
            .declaration => "declaration",
            .command => "command",
            .condition => "condition",
            .game_variable => "variable",
            .value => "value",
        };
    }
};

/// A word of mission source, with what the editor says of it.
pub const Word = struct {
    name: []const u8,
    kind: WordKind,
    /// How it's called or what it holds, such as `SetAI(target: Entity, ...)`; empty for a plain
    /// word.
    signature: []const u8 = "",
    /// What it does, in the game's words where the game has some.
    about: []const u8 = "",
    /// Where it comes from, such as "Command 24 of the catalogue".
    source: []const u8 = "",
    /// Its parameters, or a condition's values.
    parameters: []const Parameter = &.{},
    /// For a value's name, the type it's a value of, such as "Order".
    type: []const u8 = "",
};

pub const Parameter = struct {
    name: []const u8,
    type: []const u8,
    /// The game's own label for it, such as "Ship sending comm".
    label: []const u8,
};

/// All the words of mission source.
pub const Language = struct {
    words: []const Word,
    /// The word for each name.
    by_name: std.StringHashMapUnmanaged(usize),
    /// The source language's name, for the text editor: "Luau".
    name: []const u8,
    /// The special name under which the game's variables are read, such as `game`.
    variables: []const u8,

    pub fn find(language: *const Language, name: []const u8) ?*const Word {
        const index = language.by_name.get(name) orelse return null;
        return &language.words[index];
    }

    /// Makes a language of `words`, in `arena`, the first of each name kept.
    pub fn init(arena: Allocator, name: []const u8, variables: []const u8, words: []const Word) Allocator.Error!Language {
        var by_name: std.StringHashMapUnmanaged(usize) = .empty;
        for (words, 0..) |word, index| {
            const entry = try by_name.getOrPut(arena, word.name);
            if (!entry.found_existing) entry.value_ptr.* = index;
        }
        return .{ .words = words, .by_name = by_name, .name = name, .variables = variables };
    }
};

/// The sections of the outline, in their order.
pub const Section = enum {
    flight_groups,
    ships,
    markers,
    squads,
    formations,
    curves,
    parts,
    triggers,
    globals,

    pub fn label(section: Section) []const u8 {
        return switch (section) {
            .flight_groups => "Flight groups",
            .ships => "Ships",
            .markers => "Markers",
            .squads => "Squads",
            .formations => "Formations",
            .curves => "Curves",
            .parts => "Parts",
            .triggers => "Triggers",
            .globals => "Globals",
        };
    }

    /// The sections every mission shows, even empty; the others show when they hold a record.
    pub fn alwaysShown(section: Section) bool {
        return switch (section) {
            .flight_groups, .ships, .markers, .parts, .triggers, .globals => true,
            .squads, .formations, .curves => false,
        };
    }
};

/// The records a mission's source declares.
pub const Outline = struct {
    /// The mission's name, from `mission(...)`, if it gives one.
    name: ?[]const u8 = null,
    records: []const Record,
    /// The errors Luau's parser found; the records are those it read.
    errors: []const Problem,

    pub fn count(outline: Outline, section: Section) usize {
        var found: usize = 0;
        for (outline.records) |record| found += @intFromBool(record.section == section);
        return found;
    }

    /// The record declared under `name`, the source's name for it.
    pub fn named(outline: Outline, name: []const u8) ?*const Record {
        if (name.len == 0) return null;
        for (outline.records) |*record| {
            if (std.mem.eql(u8, record.name, name)) return record;
        }
        return null;
    }

    /// The declared record whose name is closest to `name`, by the fewest characters to add,
    /// remove or change, for a name the source uses without declaring it; null where none is
    /// close, more changes away than half the name's characters.
    pub fn closest(outline: Outline, name: []const u8) ?*const Record {
        var best: ?*const Record = null;
        var best_distance: usize = std.math.maxInt(usize);
        for (outline.records) |*record| {
            if (record.name.len == 0) continue;
            const distance = editDistance(name, record.name);
            if (distance < best_distance) {
                best_distance = distance;
                best = record;
            }
        }
        if (best_distance > @max(1, (name.len + 1) / 2)) return null;
        return best;
    }

    /// The record of `section` at `index` among its section's.
    pub fn nth(outline: Outline, section: Section, index: usize) ?*const Record {
        for (outline.records) |*record| {
            if (record.section == section and record.index == index) return record;
        }
        return null;
    }

    /// The record of `section` whose declaration starts on `line`.
    pub fn find(outline: Outline, section: Section, line: u32) ?*const Record {
        for (outline.records) |*record| {
            if (record.section == section and record.first_line == line) return record;
        }
        return null;
    }

    /// The record whose declaration holds `line`.
    pub fn at(outline: Outline, line: u32) ?*const Record {
        for (outline.records) |*record| {
            if (line >= record.first_line and line <= record.last_line) return record;
        }
        return null;
    }
};

/// A field of a record's table: `wing = "player"`.
pub const Field = struct {
    name: []const u8,
    /// The value's source text, as it is.
    source: []const u8 = "",
    /// The value as the source writes it, for a name, a string, a number or a boolean; "…" for
    /// anything longer.
    value: []const u8,
    /// Whether the value names another record, such as `group = alpha`.
    names_record: bool = false,

    /// The value as a place or a direction, where the source writes one as numbers:
    /// `{ -2000, 0, 42000 }`.
    pub fn vector(field: Field) ?[3]f64 {
        var parts = std.mem.tokenizeAny(u8, field.value, "{}, ");
        var made: [3]f64 = undefined;
        for (&made) |*value| value.* = std.fmt.parseFloat(f64, parts.next() orelse return null) catch return null;
        return made;
    }
};

pub const Record = struct {
    section: Section,
    /// The word that declares it, such as `ship` or `nav_point`, or `on` for a trigger.
    word: []const u8 = "",
    /// The name the source declares it under, such as `nav`; empty for a trigger, which has none.
    name: []const u8,
    /// What the outline shows: the record's display name, a flight group's without its tag, or a
    /// trigger's subject and condition.
    title: []const u8,
    /// The display name as the source gives it, tag and all, which a build writes back as it is.
    display: []const u8 = "",
    /// What the outline shows after it: a ship's type, a group's wing, a marker's kind.
    detail: []const u8 = "",
    /// The record's flight group, by its index among the groups, for its colour.
    group: ?usize = null,
    /// A part that runs as the mission starts.
    starts: bool = false,
    /// For a trigger, the name of the record it watches, "none" for none, and its condition, as
    /// the source names them.
    subject: []const u8 = "",
    condition: []const u8 = "",
    /// Its place among its section's records, from 0: a trigger's number.
    index: usize = 0,
    /// The fields its table gives, with their values as the source writes simple ones.
    fields: []const Field = &.{},
    /// The lines its declaration takes, from 0.
    first_line: u32,
    last_line: u32,
    column: u32 = 0,

    /// The field `name` its table gives, if it gives one.
    pub fn given(record: Record, name: []const u8) ?Field {
        for (record.fields) |field| if (std.mem.eql(u8, field.name, name)) return field;
        return null;
    }
};

/// The number of characters to add, remove or change to turn `a` into `b`, for names up to 64
/// characters; the most there is for longer ones.
fn editDistance(a: []const u8, b: []const u8) usize {
    if (a.len > 64 or b.len > 64) return std.math.maxInt(usize);
    var previous: [65]usize = undefined;
    var current: [65]usize = undefined;
    for (0..b.len + 1) |j| previous[j] = j;
    for (a, 1..) |char_a, i| {
        current[0] = i;
        for (b, 1..) |char_b, j| {
            const cost: usize = @intFromBool(char_a != char_b);
            current[j] = @min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost);
        }
        @memcpy(previous[0 .. b.len + 1], current[0 .. b.len + 1]);
    }
    return previous[b.len];
}

test Mission {
    const statements = [_]Statement{
        .{ .offset = 10, .at = .{ .line = 4, .column = 4 }, .stops = true },
        .{ .offset = 14, .at = .{ .line = 5, .column = 4 }, .stops = false },
        .{ .offset = 20, .at = .{ .line = 8, .column = 4 }, .stops = true },
        .{ .offset = 26, .at = .{ .line = 8, .column = 20 }, .stops = true },
    };
    const built: Mission = .{ .file = "", .statements = &statements };
    try std.testing.expectEqual(8, built.statementAt(20).?.at.line);
    try std.testing.expectEqual(null, built.statementAt(12));
    // A breakpoint on a line that holds goes there, one on a `return` or a blank line to the next
    // line that holds, its first statement, but no further than the line given.
    try std.testing.expectEqual(10, built.breakpointFor(4, 9).?.offset);
    try std.testing.expectEqual(20, built.breakpointFor(5, 9).?.offset);
    try std.testing.expectEqual(null, built.breakpointFor(5, 7));
    try std.testing.expectEqual(null, built.statementOn(5));
    try std.testing.expectEqual(20, built.statementOn(8).?.offset);
}

test Field {
    try std.testing.expectEqual([3]f64{ -2000, 0, 42000.5 }, (Field{ .name = "position", .value = "{ -2000, 0, 42000.5 }" }).vector().?);
    try std.testing.expectEqual(null, (Field{ .name = "position", .value = "…" }).vector());
}

test editDistance {
    try std.testing.expectEqual(3, editDistance("enemy", "enemies"));
    try std.testing.expectEqual(0, editDistance("nav", "nav"));
}

test "the closest name" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const made = try starlancer.profile.outline(arena.allocator(), starlancer.first_mission);
    try std.testing.expectEqualStrings("enemies", made.closest("enemy").?.name);
    try std.testing.expectEqualStrings("player", made.closest("playr").?.name);
    try std.testing.expectEqual(null, made.closest("zzzzzzzzzz"));
}

test {
    std.testing.refAllDecls(@This());
}
