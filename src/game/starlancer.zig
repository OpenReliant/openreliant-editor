//! StarLancer's profile: its missions, their source and the words of its script, read from
//! OpenReliant's tables and built with OpenReliant's own compiler, as `sltool dte build` builds
//! them.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const openreliant = @import("openreliant");
const source_parser = @import("source_parser");
const dte = openreliant.dte;
const source = dte.source;
const syntax = source.syntax;
const commands = openreliant.engine.game.executor.commands;
const conditions = openreliant.engine.vm.conditions;
const vm = openreliant.engine.vm;
const mission_editor = openreliant.engine.game.mission.editor;

const game = @import("../game.zig");

pub const profile: game.Profile = .{
    .name = "StarLancer",
    .vm = "starlancer",
    .folder = "StarLancer",
    .mission_extension = ".dte",
    .source_extension = ".mission.luau",
    .language = language,
    .build = build,
    .outline = outline,
    .listing = listing,
    .missionNumber = missionNumber,
    // The game's missions don't use 90 and on, as the guide to writing missions says.
    .first_new_mission = 90,
    .newMission = newMission,
    .playArguments = playArguments,
    .gameMissions = gameMissions,
    .readGameMission = readGameMission,
    .decompile = decompile,
    .difference = difference,
    .sameScript = sameScript,
    .scriptFlags = scriptFlags,
    .link = .{
        .script_flags = mission_editor.tagNamed("script_flags"),
        .run_control = mission_editor.tagNamed("run_control"),
        .stopped = @backingInt(mission_editor.Sent.stopped),
        .first_finished = @backingInt(mission_editor.Sent.first_finished),
        .runControl = runControl,
    },
};

const bigfile = openreliant.engine.game.bigfile;
const files = openreliant.engine.files;
const winmain = openreliant.engine.game.winmain;

/// Opens the game's archive in the folder `game_folder`, with no mods.
fn openArchive(arena: Allocator, io: std.Io, game_folder: []const u8) game.ReadError!struct { std.Io.Dir, bigfile.Hog } {
    const dir = std.Io.Dir.cwd().openDir(io, game_folder, .{ .iterate = true }) catch return error.Unreadable;
    var name_buffer: [files.max_path]u8 = undefined;
    const name = files.find(io, dir, bigfile.resource_name, &name_buffer) orelse return error.Unreadable;
    const archive = bigfile.Hog.open(arena, io, dir, name) catch |err| switch (err) {
        error.OutOfMemory => |oom| return oom,
        else => return error.Unreadable,
    };
    return .{ dir, archive };
}

fn gameMissions(arena: Allocator, io: std.Io, game_folder: []const u8) game.ReadError![]const game.GameMission {
    const dir, const archive = try openArchive(arena, io, game_folder);
    defer dir.close(io);
    var found: std.AutoArrayHashMapUnmanaged(u32, game.GameMission.Origin) = .empty;
    for (archive.archive.entries) |entry| {
        if (winmain.missionNumber(entry.name)) |number| try found.put(arena, number, .archive);
    }
    // Loose files take the place of the archive's, as the game reads them first.
    var folder_name: [files.max_path]u8 = undefined;
    if (files.find(io, dir, "missions", &folder_name)) |name| {
        if (dir.openDir(io, name, .{ .iterate = true })) |opened| {
            var folder = opened;
            defer folder.close(io);
            var entries = folder.iterate();
            while (entries.next(io) catch null) |entry| {
                if (winmain.missionNumber(entry.name)) |number| try found.put(arena, number, .loose);
            }
        } else |_| {}
    }
    const missions = try arena.alloc(game.GameMission, found.count());
    for (missions, found.keys(), found.values()) |*mission, number, origin| mission.* = .{ .number = number, .origin = origin };
    std.mem.sort(game.GameMission, missions, {}, struct {
        fn less(_: void, a: game.GameMission, b: game.GameMission) bool {
            return a.number < b.number;
        }
    }.less);
    return missions;
}

fn readGameMission(arena: Allocator, io: std.Io, game_folder: []const u8, number: u32) game.ReadError!?[]const u8 {
    const dir, var archive = try openArchive(arena, io, game_folder);
    defer dir.close(io);
    defer archive.close(arena);
    var path_buffer: [winmain.mission_path_size]u8 = undefined;
    const path = winmain.missionPath(&path_buffer, std.math.cast(u16, number) orelse return null, false, false);
    const file = openreliant.engine.game.mission.bind.read(io, arena, dir, &archive, path) catch |err| switch (err) {
        error.OutOfMemory => |oom| return oom,
        else => return error.Unreadable,
    } orelse return null;
    return file.image;
}

fn decompile(arena: Allocator, image: []const u8) game.ReadError![]const u8 {
    const mission = dte.Mission.parse(image) catch return error.NotAMission;
    var out: Writer.Allocating = .init(arena);
    source.write.write(&out.writer, arena, mission) catch |err| switch (err) {
        error.OutOfMemory, error.WriteFailed => return error.OutOfMemory,
        else => return error.NotAMission,
    };
    return out.written();
}

fn difference(arena: Allocator, a: []const u8, b: []const u8) game.ReadError!?[]const u8 {
    const first = dte.Mission.parse(a) catch return error.NotAMission;
    const second = dte.Mission.parse(b) catch return error.NotAMission;
    return dte.same.difference(arena, first, second) catch |err| switch (err) {
        error.OutOfMemory => |oom| return oom,
        else => return error.NotAMission,
    };
}

fn sameScript(a: []const u8, b: []const u8) bool {
    const first = dte.Mission.parse(a) catch return false;
    const second = dte.Mission.parse(b) catch return false;
    const first_script = first.script() catch return false;
    const second_script = second.script() catch return false;
    if (!std.mem.eql(u8, first_script, second_script)) return false;
    const first_parts = first.parts() catch return false;
    const second_parts = second.parts() catch return false;
    if (first_parts.len != second_parts.len) return false;
    for (first_parts, second_parts) |one, other| if (one.block() != other.block()) return false;
    const first_triggers = first.triggers() catch return false;
    const second_triggers = second.triggers() catch return false;
    if (first_triggers.len != second_triggers.len) return false;
    for (first_triggers, second_triggers) |one, other| if (one.block() != other.block()) return false;
    return true;
}

/// The flags the editor link copies over the mission's section 10, as many bytes as
/// `dte.Mission.scriptFlagsSize` gives, with bit 0 set on the bytes the script holds before
/// (`vm_run`, docs/engine/editor-link.md in OpenReliant). An offset past the script is left out.
fn scriptFlags(arena: Allocator, image: []const u8, offsets: []const u32) Allocator.Error!?[]u8 {
    const mission = dte.Mission.parse(image) catch return null;
    const flags = try arena.alloc(u8, mission.scriptFlagsSize());
    @memset(flags, 0);
    for (offsets) |offset| {
        if (offset < flags.len) flags[offset] = holds;
    }
    return flags;
}

/// The flag of a byte the script holds before.
const holds = 1;

fn runControl(control: game.Control) [8]u8 {
    const RunControl = mission_editor.RunControl;
    const payload: RunControl = switch (control) {
        .pause => |on| .{ .command = .pause, .argument = @intFromBool(on) },
        .run_on => .{ .command = .run_on, .argument = 0 },
        .step_into => .{ .command = .step_into, .argument = 0 },
        .step_over => .{ .command = .step_over, .argument = 0 },
        .run_part => |part| .{ .command = .run_part, .argument = part },
    };
    return std.mem.toBytes(payload);
}

/// Luau's keywords, the contextual ones too, which mission source is written in.
const luau_keywords = [_][]const u8{
    "and",   "break",  "continue", "do",   "else", "elseif", "end",   "export",
    "false", "for",    "function", "if",   "in",   "local",  "nil",   "not",
    "or",    "repeat", "return",   "then", "true", "type",   "until", "while",
};

fn language(arena: Allocator) Allocator.Error!game.Language {
    var words: std.ArrayList(game.Word) = .empty;
    for (luau_keywords) |keyword| try words.append(arena, .{ .name = keyword, .kind = .keyword });

    for (std.enums.values(source.names.Word)) |word| {
        const declared = source.language.declaration(word);
        try words.append(arena, .{
            .name = @tagName(word),
            .kind = .declaration,
            .signature = try arena.print("{f}", .{source.language.Signature{ .word = word }}),
            .about = declared.about,
            .source = switch (source.language.groupOf(word)) {
                .declaration => "Mission source: a declaration",
                .script => "Mission source: the script",
                .index => "Mission source: a record by its index",
            },
        });
    }

    for (commands.table, 0..) |command, number| {
        const listed = try source.language.parameters(arena, command);
        const parameters = try arena.alloc(game.Parameter, listed.len);
        var signature: Writer.Allocating = .init(arena);
        signature.writer.print("{s}(", .{command.name}) catch return error.OutOfMemory;
        for (parameters, listed, 0..) |*parameter, from, index| {
            parameter.* = .{ .name = from.name, .type = try arena.print("{f}", .{from.type}), .label = from.label };
            signature.writer.print("{s}{s}: {s}", .{ if (index == 0) "" else ", ", parameter.name, parameter.type }) catch return error.OutOfMemory;
        }
        signature.writer.writeByte(')') catch return error.OutOfMemory;
        try words.append(arena, .{
            .name = command.name,
            .kind = .command,
            .signature = signature.written(),
            .about = command.description,
            .source = try arena.print("Command {d} of the catalogue", .{number}),
            .parameters = parameters,
        });
    }

    for (conditions.table, 0..) |condition, number| {
        const name = source.vocabulary.name(.condition, @intCast(number)) orelse continue;
        const value_names = try source.script.eventNames(arena, condition.values);
        const parameters = try arena.alloc(game.Parameter, condition.values.len);
        for (parameters, condition.values, value_names) |*parameter, value, value_name| parameter.* = .{
            .name = value_name,
            .type = source.language.eventValueType(value.kinds),
            .label = value.label,
        };
        try words.append(arena, .{
            .name = name,
            .kind = .condition,
            .signature = try arena.print("\"{s}\"", .{name}),
            .about = try watches(arena, condition),
            .source = try arena.print("{s} · condition {d}", .{ condition.name, number }),
            .parameters = parameters,
        });
    }

    for (@typeInfo(vm.GameVariable).@"enum".field_names) |name| {
        try words.append(arena, .{ .name = name, .kind = .game_variable, .source = "One of the game's variables" });
    }

    inline for (comptime std.enums.values(source.vocabulary.Kind)) |kind| {
        if (comptime source.vocabulary.Names(kind)) |Enum| {
            for (@typeInfo(Enum).@"enum".field_names) |name| {
                if (source.vocabulary.isPlaceholder(name)) continue;
                try words.append(arena, .{ .name = name, .kind = .value, .type = kind.typeName(), .source = kind.typeName() });
            }
        }
    }
    return .init(arena, "Luau", "game", try words.toOwnedSlice(arena));
}

/// What a trigger of `condition` watches: "watches a ship", "watches a flight group or a squad".
fn watches(arena: Allocator, condition: conditions.Condition) Allocator.Error![]const u8 {
    var subjects: std.ArrayList([]const u8) = .empty;
    if (condition.subjects.ship) try subjects.append(arena, "a ship");
    if (condition.subjects.flight_group) try subjects.append(arena, "a flight group");
    if (condition.subjects.squad) try subjects.append(arena, "a squad");
    if (subjects.items.len == 0) return "watches no object";
    var text: Writer.Allocating = .init(arena);
    text.writer.writeAll("watches ") catch return error.OutOfMemory;
    for (subjects.items, 0..) |subject, index| {
        if (index > 0) text.writer.writeAll(if (index == subjects.items.len - 1) " or " else ", ") catch return error.OutOfMemory;
        text.writer.writeAll(subject) catch return error.OutOfMemory;
    }
    return text.written();
}

fn build(arena: Allocator, text: []const u8) Allocator.Error!game.Built {
    var failure: source.compile.Failure = undefined;
    const made = source_parser.buildMapped(arena, text, &failure) catch |err| switch (err) {
        error.OutOfMemory => |oom| return oom,
        error.Invalid => {
            const problems = try arena.alloc(game.Problem, 1);
            problems[0] = problem(failure.at, failure.message);
            return .{ .problems = problems };
        },
    };
    const statements = try arena.alloc(game.Statement, made.statements.len);
    for (statements, made.statements) |*statement, from| statement.* = .{
        .offset = from.offset,
        .at = .{ .line = from.at.line, .column = from.at.column },
        .stops = from.stops,
    };
    return .{ .mission = .{ .file = made.file, .statements = statements } };
}

/// A problem from OpenReliant's message, with the kind of mistake it is where the editor can offer
/// a fix.
fn problem(at: syntax.Position, message: []const u8) game.Problem {
    return .{ .at = .{ .line = at.line, .column = at.column }, .message = message, .kind = kindOf(message) };
}

/// The kind of mistake OpenReliant's message describes, read from its words: the compiler says
/// "`enemy` is not declared" (`compile.zig`). A test checks the words against the compiler.
fn kindOf(message: []const u8) game.Problem.Kind {
    const ending = "` is not declared";
    if (message.len > ending.len + 1 and message[0] == '`' and std.mem.endsWith(u8, message, ending)) {
        return .{ .not_declared = message[1 .. message.len - ending.len] };
    }
    return .other;
}

fn outline(arena: Allocator, text: []const u8) Allocator.Error!game.Outline {
    const tree = try source_parser.parse(arena, text);
    const errors = try arena.alloc(game.Problem, tree.errors.len);
    for (errors, tree.errors) |*made, found| made.* = problem(found.at, found.message);

    var records: std.ArrayList(game.Record) = .empty;
    var groups: std.StringHashMapUnmanaged(usize) = .empty;
    var mission_name: ?[]const u8 = null;
    const statements = switch (tree.get(tree.root)) {
        .block => |list| list,
        else => &.{},
    };
    for (statements, 0..) |statement, index| {
        const first: u32 = tree.at(statement).line;
        const next: ?u32 = if (index + 1 < statements.len) tree.at(statements[index + 1]).line else null;
        const last = lastLine(text, first, next);
        switch (tree.get(statement)) {
            .assign => |assign| {
                if (assign.targets.len != 1 or assign.values.len != 1) continue;
                const name = switch (tree.get(assign.targets[0])) {
                    .global_name => |global| global,
                    else => continue,
                };
                const call = callOf(tree, assign.values[0]) orelse continue;
                var record = try recordOf(arena, tree, call, name, &groups) orelse continue;
                record.first_line = first;
                record.last_line = last;
                record.column = tree.at(statement).column;
                if (record.section == .flight_groups) try groups.put(arena, name, groups.count());
                try records.append(arena, record);
            },
            .call_statement => |index_of_call| {
                const call = callOf(tree, index_of_call) orelse continue;
                if (std.mem.eql(u8, call.callee, "mission")) {
                    if (call.arguments.len > 0) mission_name = stringField(tree, call.arguments[0], "name");
                    continue;
                }
                if (!std.mem.eql(u8, call.callee, "on") or call.arguments.len < 2) continue;
                const subject: []const u8 = switch (tree.get(call.arguments[0])) {
                    .global_name => |global| global,
                    .nil => "none",
                    else => "?",
                };
                const condition: []const u8 = switch (tree.get(call.arguments[1])) {
                    .string => |string| string,
                    else => "?",
                };
                const fields: ?syntax.Index = if (call.arguments.len > 2 and tree.get(call.arguments[2]) == .table) call.arguments[2] else null;
                try records.append(arena, .{
                    .section = .triggers,
                    .name = "",
                    .subject = subject,
                    .title = try arena.print("{s} · {s}", .{ subject, condition }),
                    .condition = condition,
                    .fields = if (fields) |table| try fieldsOf(arena, tree, table) else &.{},
                    .first_line = first,
                    .last_line = last,
                    .column = tree.at(statement).column,
                });
            },
            else => {},
        }
    }
    // Each record's place among its section's.
    var counts: std.EnumArray(game.Section, usize) = .initFill(0);
    for (records.items) |*record| {
        record.index = counts.get(record.section);
        counts.set(record.section, record.index + 1);
    }
    return .{ .name = mission_name, .records = try records.toOwnedSlice(arena), .errors = errors };
}

/// The fields of the table at `table`, with their simple values as the source writes them.
fn fieldsOf(arena: Allocator, tree: syntax.Tree, table: syntax.Index) Allocator.Error![]const game.Field {
    const items = switch (tree.get(table)) {
        .table => |items| items,
        else => return &.{},
    };
    var found: std.ArrayList(game.Field) = .empty;
    for (items) |item| switch (tree.get(item)) {
        .item => |shown| switch (shown) {
            .record => |record| {
                const value = tree.get(record.value);
                try found.append(arena, .{
                    .name = record.key,
                    .value = switch (value) {
                        .global_name => |name| name,
                        .string => |string| try arena.print("\"{s}\"", .{string}),
                        .number => |number| try arena.print("{d}", .{number}),
                        .boolean => |boolean| if (boolean) "true" else "false",
                        .nil => "nil",
                        .table => |list| try vectorText(arena, tree, list),
                        else => "…",
                    },
                    .names_record = value == .global_name,
                });
            },
            else => {},
        },
        else => {},
    };
    return found.toOwnedSlice(arena);
}

/// A call by a name: the name, and its arguments.
const Call = struct {
    callee: []const u8,
    arguments: []const syntax.Index,
};

fn callOf(tree: syntax.Tree, index: syntax.Index) ?Call {
    const call = switch (tree.get(index)) {
        .call => |call| call,
        else => return null,
    };
    const callee = switch (tree.get(call.function)) {
        .global_name => |global| global,
        else => return null,
    };
    return .{ .callee = callee, .arguments = call.arguments };
}

/// The record `name = constructor(...)` declares, without its lines, or null for a call that
/// declares none.
fn recordOf(arena: Allocator, tree: syntax.Tree, call: Call, name: []const u8, groups: *const std.StringHashMapUnmanaged(usize)) Allocator.Error!?game.Record {
    const word = std.meta.stringToEnum(source.names.Word, call.callee) orelse return null;
    const display = if (call.arguments.len > 0) stringOf(tree, call.arguments[0]) else null;
    const fields: ?syntax.Index = for (call.arguments) |argument| {
        if (tree.get(argument) == .table) break argument;
    } else null;
    var record: game.Record = .{ .section = .ships, .name = name, .title = display orelse name, .display = display orelse "", .first_line = 0, .last_line = 0 };
    if (fields) |table| {
        if (globalField(tree, table, "group")) |group| record.group = groups.get(group);
        record.fields = try fieldsOf(arena, tree, table);
    }
    switch (word) {
        .flight_group => {
            record.section = .flight_groups;
            // StarLancer's flight groups are named "(FG)Alpha" or "<FG>Alpha", which the outline
            // shows as "Alpha".
            if (display) |shown| record.title = groupTitle(shown);
            record.group = groups.count();
            if (fields) |table| if (stringField(tree, table, "wing")) |wing| {
                record.detail = wingLabel(wing);
            };
        },
        .ship => {
            record.section = .ships;
            if (fields) |table| record.detail = stringField(tree, table, "type") orelse "";
        },
        .nav_point, .waypoint, .point, .curve_point => {
            record.section = .markers;
            record.detail = switch (word) {
                .nav_point => "nav point",
                .waypoint => "waypoint",
                .point => "point",
                else => "curve point",
            };
        },
        .squad => record.section = .squads,
        .formation => record.section = .formations,
        .curve => {
            record.section = .curves;
            record.title = name;
        },
        .part => {
            record.section = .parts;
            if (fields) |table| record.starts = booleanField(tree, table, "start");
        },
        .handler => {
            record.section = .parts;
            record.title = name;
            record.detail = "handler";
        },
        .global => {
            record.section = .globals;
            if (call.arguments.len > 1) switch (tree.get(call.arguments[1])) {
                .number => |value| record.detail = try arena.print("{d}", .{value}),
                else => {},
            };
        },
        else => return null,
    }
    return record;
}

/// A list of up to four numbers as the source writes it, such as a place, `{ 0, 0, 40000 }`; "…"
/// for any other table.
fn vectorText(arena: Allocator, tree: syntax.Tree, items: []const syntax.Index) Allocator.Error![]const u8 {
    if (items.len == 0 or items.len > 4) return "…";
    var text: Writer.Allocating = .init(arena);
    text.writer.writeAll("{ ") catch return error.OutOfMemory;
    for (items, 0..) |item, index| {
        const value = switch (tree.get(item)) {
            .item => |found| switch (found) {
                .list => |value| value,
                else => return "…",
            },
            else => return "…",
        };
        const number = switch (tree.get(value)) {
            .number => |number| number,
            .unary => |unary| if (unary.operator == .minus) switch (tree.get(unary.operand)) {
                .number => |number| -number,
                else => return "…",
            } else return "…",
            else => return "…",
        };
        text.writer.print("{s}{d}", .{ if (index == 0) "" else ", ", number }) catch return error.OutOfMemory;
    }
    text.writer.writeAll(" }") catch return error.OutOfMemory;
    return text.written();
}

/// A flight group's display name without its tag, `(FG)` or `<FG>`.
fn groupTitle(name: []const u8) []const u8 {
    for ([_][]const u8{ "(FG)", "<FG>" }) |tag| {
        if (std.ascii.startsWithIgnoreCase(name, tag)) {
            const rest = std.mem.trim(u8, name[tag.len..], " ");
            if (rest.len > 0) return rest;
        }
    }
    return name;
}

fn wingLabel(wing: []const u8) []const u8 {
    if (std.mem.eql(u8, wing, "player")) return "player wing";
    if (std.mem.eql(u8, wing, "second")) return "second wing";
    if (std.mem.eql(u8, wing, "third")) return "third wing";
    return "";
}

fn stringOf(tree: syntax.Tree, index: syntax.Index) ?[]const u8 {
    return switch (tree.get(index)) {
        .string => |string| string,
        else => null,
    };
}

/// The value of the field `key` of the table at `index`.
fn field(tree: syntax.Tree, table: syntax.Index, key: []const u8) ?syntax.Index {
    const items = switch (tree.get(table)) {
        .table => |items| items,
        else => return null,
    };
    for (items) |item| switch (tree.get(item)) {
        .item => |found| switch (found) {
            .record => |record| if (std.mem.eql(u8, record.key, key)) return record.value,
            else => {},
        },
        else => {},
    };
    return null;
}

fn stringField(tree: syntax.Tree, table: syntax.Index, key: []const u8) ?[]const u8 {
    return stringOf(tree, field(tree, table, key) orelse return null);
}

fn globalField(tree: syntax.Tree, table: syntax.Index, key: []const u8) ?[]const u8 {
    return switch (tree.get(field(tree, table, key) orelse return null)) {
        .global_name => |global| global,
        else => null,
    };
}

fn booleanField(tree: syntax.Tree, table: syntax.Index, key: []const u8) bool {
    return switch (tree.get(field(tree, table, key) orelse return false)) {
        .boolean => |value| value,
        else => false,
    };
}

/// The last line of a statement starting on `first`, the next one starting on `next`: the line
/// before the next statement, past the blank lines and the comments between them.
fn lastLine(text: []const u8, first: u32, next: ?u32) u32 {
    var line_number: u32 = 0;
    var last_code = first;
    var iterator = std.mem.splitScalar(u8, text, '\n');
    while (iterator.next()) |line| : (line_number += 1) {
        if (line_number < first) continue;
        if (next) |stop| if (line_number >= stop) break;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "--")) continue;
        last_code = line_number;
    }
    return last_code;
}

fn listing(arena: Allocator, image: []const u8) Allocator.Error![]const u8 {
    var out: Writer.Allocating = .init(arena);
    writeListing(arena, image, &out.writer) catch |err| switch (err) {
        error.OutOfMemory => |oom| return oom,
        error.WriteFailed => return error.OutOfMemory,
        else => {
            out.clearRetainingCapacity();
            out.writer.print("The mission can't be read: {t}\n", .{err}) catch return error.OutOfMemory;
        },
    };
    return out.written();
}

/// Writes each of the script's routines, its parts and the blocks its triggers run, as `sltool dte
/// script` does.
fn writeListing(arena: Allocator, image: []const u8, writer: *Writer) !void {
    const mission = try dte.Mission.parse(image);
    const code = try mission.script();
    const parts = try mission.parts();
    const routines = try mission.routines(arena);
    try writer.print("{d} bytes of script in {d} routines\n", .{ code.len, routines.len });
    for (routines) |routine| {
        try writer.print("\n{d} to {d}: ", .{ routine.start, routine.start + routine.extent });
        switch (routine.owner) {
            .part => |index| {
                try writer.print("part {d}", .{index});
                const name = mission.name(parts[index].name);
                if (name.len != 0) try writer.print(", {s}", .{name});
            },
            .triggers => |indices| {
                try writer.writeAll(if (indices.len == 1) "trigger" else "triggers");
                for (indices, 0..) |index, place| try writer.print("{s}{d}", .{ if (place == 0) " " else ", ", index });
            },
        }
        try writer.writeByte('\n');
        const constants = routine.constants(code);
        const disassembly = try dte.disassemble(arena, code, routine.start) orelse {
            try writer.writeAll("  no block here\n");
            continue;
        };
        try dte.listing.write(writer, mission, disassembly, constants, .{});
        if (constants.len != 0) {
            try writer.writeAll("  constants:");
            for (constants) |value| try writer.print(" {d}", .{value});
            try writer.writeByte('\n');
        }
    }
}

/// The number of a mission file, `mission90.dte`, or of its source, `mission90.mission.luau`.
fn missionNumber(file_name: []const u8) ?u32 {
    if (std.ascii.endsWithIgnoreCase(file_name, profile.source_extension)) {
        var buffer: [256]u8 = undefined;
        const stem = file_name[0 .. file_name.len - profile.source_extension.len];
        const name = std.fmt.bufPrint(&buffer, "{s}{s}", .{ stem, profile.mission_extension }) catch return null;
        return openreliant.engine.game.winmain.missionNumber(name) orelse null;
    }
    return openreliant.engine.game.winmain.missionNumber(file_name) orelse null;
}

/// A new mission: the player's ship in its flight group, in the player's wing, and the part that
/// makes the group as the mission starts.
fn newMission(arena: Allocator, name: []const u8) Allocator.Error![]const u8 {
    return arena.print(
        \\-- {0s}: a new mission.
        \\
        \\mission({{ name = "{0s}" }})
        \\
        \\alpha = flight_group("(FG)Alpha", {{ wing = "player" }})
        \\
        \\-- The first ship is always the player's.
        \\player = ship("Player", {{ type = "predator", group = alpha }})
        \\
        \\-- This part runs as the mission starts.
        \\start = part("(F)Start", function()
        \\    CreateFlightGroup(alpha)
        \\    return 1
        \\end, {{ start = true }})
        \\
    , .{name});
}

/// `openreliant <game folder> --mission <number>`, with `--part`, `--skip-launch`, `--watch` and
/// `--editor-link` for the options asked for.
fn playArguments(arena: Allocator, game_folder: []const u8, number: u32, play: game.Play) Allocator.Error![]const []const u8 {
    var arguments: std.ArrayList([]const u8) = .empty;
    try arguments.appendSlice(arena, &.{ game_folder, "--mission", try arena.print("{d}", .{number}) });
    if (play.part) |part| try arguments.appendSlice(arena, &.{ "--part", part });
    if (play.skip_launch) try arguments.append(arena, "--skip-launch");
    if (play.watch) |ship| try arguments.appendSlice(arena, &.{ "--watch", ship });
    if (play.link) |port| try arguments.appendSlice(arena, &.{ "--editor-link", "--editor-link-port", try arena.print("{d}", .{port}) });
    return arguments.toOwnedSlice(arena);
}

/// The guide's first mission, `mission90.mission.luau` in OpenReliant's guide to writing missions,
/// which the tests and the design use.
pub const first_mission =
    \\-- mission90.mission.luau: a first mission. The player's ship starts in space, with a nav point
    \\-- ahead, where two Sabres wait. Once the player reaches the nav point, the Sabres attack, and once
    \\-- both are destroyed, the mission ends as a success.
    \\
    \\mission({ name = "First Mission" })
    \\
    \\-- Flight groups. The player's own is listed in the player's wing.
    \\
    \\alpha = flight_group("(FG)Alpha", { wing = "player" })
    \\navs = flight_group("(FG)Nav points")
    \\enemies = flight_group("(FG)Enemies")
    \\
    \\-- Ships. The first ship is always the player's.
    \\
    \\player = ship("Player", { type = "predator", group = alpha })
    \\nav = nav_point("Nav 1", { group = navs, position = { 0, 0, 40000 } })
    \\sabre_1 = ship("Sabre 1", {
    \\    type = "sabre",
    \\    group = enemies,
    \\    position = { -2000, 0, 42000 },
    \\    yaw = 180,
    \\})
    \\sabre_2 = ship("Sabre 2", {
    \\    type = "sabre",
    \\    group = enemies,
    \\    position = { 2000, 0, 42000 },
    \\    yaw = 180,
    \\})
    \\
    \\-- The script. This part runs as the mission starts.
    \\
    \\start = part("(F)Start", function()
    \\    -- A mission's ships appear as their flight groups are made.
    \\    CreateFlightGroup(alpha)
    \\    CreateFlightGroup(navs)
    \\    CreateFlightGroup(enemies)
    \\    -- The display points the player to the nav point, until the player is within 5000 of it.
    \\    SetFlybackMarker(nav, 5000)
    \\    PlayMusic("New_Mission01.wav", 0)
    \\    return 1
    \\end, { start = true })
    \\
    \\-- Once the player's ship comes within 4000 of the nav point, the Sabres attack it.
    \\
    \\on(nav, "ship_reached", { reached_ship = player }, function(reached_ship)
    \\    SetAI(enemies, "fight", 1, player)
    \\    return 1
    \\end)
    \\
    \\-- Once both Sabres are destroyed, the mission ends as a success.
    \\
    \\on(enemies, "destroyed", function(killer, victim)
    \\    game.mission_success = 3
    \\    Wait(5)
    \\    game.mission_over = 1
    \\    return 1
    \\end)
    \\
;

test "the first mission's outline" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const made = try outline(arena.allocator(), first_mission);
    try std.testing.expectEqualStrings("First Mission", made.name.?);
    try std.testing.expectEqual(0, made.errors.len);
    try std.testing.expectEqual(3, made.count(.flight_groups));
    try std.testing.expectEqual(3, made.count(.ships));
    try std.testing.expectEqual(1, made.count(.markers));
    try std.testing.expectEqual(1, made.count(.parts));
    try std.testing.expectEqual(2, made.count(.triggers));
    try std.testing.expectEqual(0, made.count(.globals));

    const alpha = made.named("alpha").?;
    try std.testing.expectEqualStrings("Alpha", alpha.title);
    // The source keeps the name as it is, tag and all.
    try std.testing.expectEqualStrings("(FG)Alpha", alpha.display);
    try std.testing.expectEqualStrings("player wing", alpha.detail);
    try std.testing.expectEqual(0, alpha.group.?);
    const sabre = made.named("sabre_1").?;
    try std.testing.expectEqualStrings("sabre", sabre.detail);
    try std.testing.expectEqual(2, sabre.group.?);
    try std.testing.expectEqual(16, sabre.first_line);
    try std.testing.expectEqual(21, sabre.last_line);
    const start = made.named("start").?;
    try std.testing.expect(start.starts);
    // The design's trigger: lines 45 to 48, counting from 1.
    const trigger = made.at(44).?;
    try std.testing.expectEqualStrings("nav · ship_reached", trigger.title);
    try std.testing.expectEqualStrings("nav", trigger.subject);
    // A trigger has no name of its own, so the subject's name finds the subject.
    try std.testing.expectEqual(.markers, made.named("nav").?.section);
    try std.testing.expectEqual(44, trigger.first_line);
    try std.testing.expectEqual(47, trigger.last_line);
}

test groupTitle {
    try std.testing.expectEqualStrings("Alpha", groupTitle("(FG)Alpha"));
    try std.testing.expectEqualStrings("Reliant group", groupTitle("<FG>Reliant group"));
    try std.testing.expectEqualStrings("Buccaneers G2", groupTitle("<FG> Buccaneers G2"));
    try std.testing.expectEqualStrings("(FG)", groupTitle("(FG)"));
}

test "a ship's place shows as its numbers" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const made = try outline(arena.allocator(), first_mission);
    const sabre = made.named("sabre_1").?;
    for (sabre.fields) |given| {
        if (std.mem.eql(u8, given.name, "position")) try std.testing.expectEqualStrings("{ -2000, 0, 42000 }", given.value);
    }
}

test "a build of the first mission makes a mission whose listing reads" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const built = try build(arena.allocator(), first_mission);
    const mission = built.mission;
    try std.testing.expect(std.mem.find(u8, try listing(arena.allocator(), mission.file), "routines") != null);
}

test "the first mission's statements hold on their lines" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const mission = (try build(arena.allocator(), first_mission)).mission;
    const script = try (try dte.Mission.parse(mission.file)).script();
    // The design's held line, the Sabres' attack on line 46 counting from 1, holds before its
    // command.
    const attack = mission.statementOn(45).?;
    try std.testing.expectEqual(dte.Opcode.command, @as(dte.Opcode, @fromBackingInt(script[attack.offset])));
    try std.testing.expectEqual(attack, mission.statementAt(attack.offset).?);
    // Its trigger's `return 1` can't hold, so a breakpoint there moves on, to the next trigger.
    try std.testing.expectEqual(null, mission.statementOn(46));
    try std.testing.expectEqual(52, mission.breakpointFor(46, 100).?.at.line);
}

test scriptFlags {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const mission = (try build(arena.allocator(), first_mission)).mission;
    const attack = mission.statementOn(45).?.offset;
    const flags = (try scriptFlags(arena.allocator(), mission.file, &.{ attack, 1_000_000 })).?;
    const parsed = try dte.Mission.parse(mission.file);
    try std.testing.expectEqual(parsed.scriptFlagsSize(), flags.len);
    try std.testing.expectEqual(1, std.mem.count(u8, flags, &.{holds}));
    try std.testing.expectEqual(holds, flags[attack]);
    try std.testing.expectEqual(null, try scriptFlags(arena.allocator(), "not a mission", &.{}));
}

test sameScript {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const built = (try build(arena.allocator(), first_mission)).mission.file;
    // A comment changes nothing the game runs; another statement does.
    const commented = try std.mem.concat(arena.allocator(), u8, &.{ "-- A comment.\n", first_mission });
    try std.testing.expect(sameScript(built, (try build(arena.allocator(), commented)).mission.file));
    const changed = try std.mem.replaceOwned(u8, arena.allocator(), first_mission, "Wait(5)", "Wait(6)");
    try std.testing.expect(!sameScript(built, (try build(arena.allocator(), changed)).mission.file));
    try std.testing.expect(!sameScript(built, "not a mission"));
}

test runControl {
    const RunControl = mission_editor.RunControl;
    const step = std.mem.bytesToValue(RunControl, &runControl(.step_over));
    try std.testing.expectEqual(RunControl.Command.step_over, step.command);
    const paused = std.mem.bytesToValue(RunControl, &runControl(.{ .pause = true }));
    try std.testing.expectEqual(RunControl.Command.pause, paused.command);
    try std.testing.expectEqual(1, paused.argument);
    try std.testing.expectEqual(7, std.mem.bytesToValue(RunControl, &runControl(.{ .run_part = 7 })).argument);
}

test "a name that isn't declared is a mistake the editor can fix" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const broken = try std.mem.replaceOwned(u8, arena.allocator(), first_mission, "on(enemies,", "on(enemy,");
    const built = try build(arena.allocator(), broken);
    const found = built.problems[0];
    try std.testing.expectEqual(51, found.at.line);
    try std.testing.expectEqualStrings("enemy", found.kind.not_declared);
}

test "the language has the game's words" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const made = try language(arena.allocator());
    const comms = made.find("CommsFromShip").?;
    try std.testing.expectEqual(.command, comms.kind);
    try std.testing.expectEqualStrings("Command 24 of the catalogue", comms.source);
    const reached = made.find("ship_reached").?;
    try std.testing.expectEqual(.condition, reached.kind);
    try std.testing.expectEqualStrings("ShipReached · condition 4", reached.source);
    try std.testing.expectEqualStrings("watches a ship", reached.about);
    try std.testing.expectEqual(.declaration, made.find("on").?.kind);
    try std.testing.expectEqual(.keyword, made.find("function").?.kind);
    try std.testing.expectEqual(.game_variable, made.find("mission_success").?.kind);
}

test "a new mission builds" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const text = try newMission(arena.allocator(), "New Mission");
    try std.testing.expect(try build(arena.allocator(), text) == .mission);
    const made = try outline(arena.allocator(), text);
    try std.testing.expectEqualStrings("New Mission", made.name.?);
    try std.testing.expectEqual(1, made.count(.parts));
}

test playArguments {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const arguments = try playArguments(arena.allocator(), "StarLancer", 90, .{ .part = "(F)Start", .skip_launch = true, .link = 4000 });
    const expected = [_][]const u8{ "StarLancer", "--mission", "90", "--part", "(F)Start", "--skip-launch", "--editor-link", "--editor-link-port", "4000" };
    try std.testing.expectEqual(expected.len, arguments.len);
    for (expected, arguments) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "a built mission decompiles to source that builds the same mission" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const built = (try build(arena.allocator(), first_mission)).mission.file;
    const text = try decompile(arena.allocator(), built);
    const again = (try build(arena.allocator(), text)).mission.file;
    try std.testing.expectEqual(null, try difference(arena.allocator(), built, again));
}

test missionNumber {
    try std.testing.expectEqual(90, missionNumber("mission90.mission.luau"));
    try std.testing.expectEqual(90, missionNumber("mission90.dte"));
    try std.testing.expectEqual(null, missionNumber("readme.txt"));
}
