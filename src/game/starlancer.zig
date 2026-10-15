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
const orders = openreliant.engine.game.ai.orders;
const curves = openreliant.engine.game.executor.curves;
const math = openreliant.engine.surrender.math;
const game_mission = openreliant.engine.game.mission;
const gameobj = openreliant.engine.game.gameobj;
const planets = openreliant.engine.game.create.planets;
const conditions = openreliant.engine.vm.conditions;
const vm = openreliant.engine.vm;
const mission_editor = openreliant.engine.game.mission.editor;

const game = @import("../game.zig");
const source_edit = @import("../mission/edit.zig");

pub const profile: game.Profile = .{
    .name = "StarLancer",
    .vm = "starlancer",
    .folder = "StarLancer",
    .mission_extension = ".dte",
    .source_extension = ".mission.luau",
    .language = language,
    .build = build,
    .outline = outline,
    .edit = edit,
    .fields = fieldForms,
    .fieldKind = fieldKind,
    .scene = scene,
    .new_kinds = &new_kinds,
    .addRecord = addRecord,
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
                var record = try recordOf(arena, text, tree, call, name, &groups) orelse continue;
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
                const fields = tableOf(tree, call);
                try records.append(arena, .{
                    .section = .triggers,
                    .word = "on",
                    .name = "",
                    .subject = subject,
                    .title = try arena.print("{s} · {s}", .{ subject, condition }),
                    .condition = condition,
                    .fields = if (fields) |table| try fieldsOf(arena, text, tree, table) else &.{},
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

/// The fields of the table at `table` of `text`, with their simple values as the source writes
/// them, and each value's own text.
fn fieldsOf(arena: Allocator, text: []const u8, tree: syntax.Tree, table: syntax.Index) Allocator.Error![]const game.Field {
    const items = switch (tree.get(table)) {
        .table => |items| items,
        else => return &.{},
    };
    var found: std.ArrayList(game.Field) = .empty;
    for (items) |item| switch (tree.get(item)) {
        .item => |shown| switch (shown) {
            .record => |record| {
                const value = tree.get(record.value);
                const start, const end = source_edit.span(tree, text, record.value);
                try found.append(arena, .{
                    .name = record.key,
                    .source = text[start..end],
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

/// The table of fields of a declaration's call: a trigger's third argument where it's a table, or
/// another declaration's first table.
fn tableOf(tree: syntax.Tree, call: Call) ?syntax.Index {
    if (std.mem.eql(u8, call.callee, "on")) {
        return if (call.arguments.len > 2 and tree.get(call.arguments[2]) == .table) call.arguments[2] else null;
    }
    for (call.arguments) |argument| if (tree.get(argument) == .table) return argument;
    return null;
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
fn recordOf(arena: Allocator, text: []const u8, tree: syntax.Tree, call: Call, name: []const u8, groups: *const std.StringHashMapUnmanaged(usize)) Allocator.Error!?game.Record {
    const word = std.meta.stringToEnum(source.names.Word, call.callee) orelse return null;
    const display = if (call.arguments.len > 0) stringOf(tree, call.arguments[0]) else null;
    const fields = tableOf(tree, call);
    var record: game.Record = .{ .section = .ships, .word = call.callee, .name = name, .title = display orelse name, .display = display orelse "", .first_line = 0, .last_line = 0 };
    if (fields) |table| {
        if (globalField(tree, table, "group")) |group| record.group = groups.get(group);
        record.fields = try fieldsOf(arena, text, tree, table);
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

/// The change to `text` that makes `change` to `record`, through the declaration on the record's
/// first line: its table's field, its display name, a trigger's subject or condition, or a
/// global's value. A record without a table gets one where its declaration takes it: a trigger's
/// after its condition, a part's after its code, and the others' after their display name.
fn edit(arena: Allocator, text: []const u8, record: game.Record, change: game.Edit) Allocator.Error!?game.Change {
    const tree = try source_parser.parse(arena, text);
    const found = declarationAt(tree, record.first_line) orelse return null;
    const arguments = found.call.arguments;
    const trigger = std.mem.eql(u8, found.call.callee, "on");
    switch (change) {
        .field => |set| {
            if (tableOf(tree, found.call)) |at| {
                const value = set.value orelse return source_edit.removeField(tree, text, at, set.name);
                return try source_edit.setField(arena, tree, text, at, set.name, value);
            }
            const value = set.value orelse return null;
            if (std.mem.eql(u8, found.call.callee, "part")) {
                return try source_edit.appendArgument(arena, tree, text, found.node, try arena.print("{{ {s} = {s} }}", .{ set.name, value }));
            }
            const after: usize = if (trigger) 1 else 0;
            if (arguments.len <= after) return null;
            return try source_edit.addTable(arena, tree, text, arguments[after], set.name, value);
        },
        .display => |name| {
            if (trigger or arguments.len == 0 or tree.get(arguments[0]) != .string) return null;
            return source_edit.replace(tree, text, arguments[0], try source_edit.string(arena, name));
        },
        .subject => |subject| {
            if (!trigger or arguments.len == 0) return null;
            return source_edit.replace(tree, text, arguments[0], subject);
        },
        .condition => |condition| {
            if (!trigger or arguments.len < 2) return null;
            return source_edit.replace(tree, text, arguments[1], try source_edit.string(arena, condition));
        },
        .value => |value| {
            if (!std.mem.eql(u8, found.call.callee, "global") or arguments.len < 2) return null;
            return source_edit.replace(tree, text, arguments[1], value);
        },
    }
}

/// The call that declares a record on `line`: `name = word(...)` or `on(...)`, with its node.
fn declarationAt(tree: syntax.Tree, line: u32) ?struct { node: syntax.Index, call: Call } {
    const statements = switch (tree.get(tree.root)) {
        .block => |list| list,
        else => return null,
    };
    for (statements) |statement| {
        if (tree.at(statement).line != line) continue;
        const node = switch (tree.get(statement)) {
            .assign => |assign| if (assign.values.len == 1) assign.values[0] else return null,
            .call_statement => |call| call,
            else => return null,
        };
        return .{ .node = node, .call = callOf(tree, node) orelse return null };
    }
    return null;
}

/// The fields of a record's table, from OpenReliant's tables of the language.
fn fieldForms(record: game.Record) []const game.FieldForm {
    const word = std.meta.stringToEnum(source.names.Word, record.word) orelse return &.{};
    return switch (word) {
        .flight_group => &forms.flight_group,
        .ship => &forms.ship,
        .nav_point, .waypoint, .curve_point => &forms.marker,
        .point => &forms.point,
        .curve => &forms.curve,
        .part => &forms.part,
        .on => &forms.trigger,
        else => &.{},
    };
}

const forms = struct {
    const flight_group = formsOf(source.language.flight_group_fields);
    const ship = formsOf(source.language.ship_fields);
    const marker = formsOf(source.language.marker_fields);
    const point = formsOf(source.language.point_fields);
    const curve = formsOf(source.language.curve_fields);
    const part = formsOf(source.language.part_fields);
    const trigger = formsOf(source.language.trigger_fields);
};

fn formsOf(comptime table: source.language.Table) [table.fields.len]game.FieldForm {
    var made: [table.fields.len]game.FieldForm = undefined;
    for (&made, table.fields) |*form, from| {
        form.* = .{ .name = from.name, .about = from.about, .kind = fieldKind(from.type), .optional = std.mem.endsWith(u8, from.type, "?") };
        for (hints) |hint| if (std.mem.eql(u8, hint.name, from.name)) {
            form.label = hint.label;
            form.heading = hint.heading;
            form.row = hint.row;
            form.letter = hint.letter;
            form.note = hint.note;
        };
    }
    return made;
}

/// How the inspector lays out a ship's and a marker's place: under a heading, with its angles on
/// one row, and a short label for its place in a formation.
const hints = [_]struct { name: []const u8, label: ?[]const u8 = null, heading: ?[]const u8 = null, row: ?[]const u8 = null, letter: []const u8 = "", note: ?[]const u8 = null }{
    .{ .name = "formation_point", .label = "Formation" },
    .{ .name = "position", .heading = "Place" },
    .{ .name = "yaw", .row = "Angles", .letter = "Y" },
    .{ .name = "pitch", .row = "Angles", .letter = "P" },
    .{ .name = "roll", .row = "Angles", .letter = "R", .note = "degrees · Y down" },
};

/// The kind of value a type of mission source takes, as the language's tables write it: a record,
/// a name of the game's values, a wing, a vector, a number, a boolean, or source for the rest.
fn fieldKind(type_name: []const u8) game.FieldKind {
    const bare = std.mem.trimEnd(u8, type_name, "?");
    for (record_types) |entry| if (std.mem.eql(u8, bare, entry[0])) return .{ .record = entry[1] };
    if (std.mem.eql(u8, bare, "Vector")) return .vector;
    if (std.mem.eql(u8, bare, "number")) return .number;
    if (std.mem.eql(u8, bare, "boolean")) return .boolean;
    if (std.mem.eql(u8, bare, "Wing")) return .{ .strings = &wings };
    inline for (comptime std.enums.values(source.vocabulary.Kind)) |kind| {
        if (std.mem.eql(u8, bare, comptime kind.typeName())) return .{ .value = comptime kind.typeName() };
    }
    return .source;
}

/// The language's types of the mission's records, and the outline's sections that hold them.
const record_types = [_]struct { []const u8, []const game.Section }{
    .{ "FlightGroup", &.{.flight_groups} },
    .{ source.language.mission_ship, &.{ .ships, .markers } },
    .{ "Entity", &.{ .ships, .markers, .flight_groups, .squads } },
    .{ "Squad", &.{.squads} },
    .{ "Formation", &.{.formations} },
    .{ "Curve", &.{.curves} },
    .{ "Part", &.{.parts} },
};

/// A flight group's wings, as mission source names them.
const wings = names: {
    const all = @typeInfo(dte.FlightGroup.Wing).@"enum".field_names;
    var list: [all.len][]const u8 = undefined;
    for (&list, all) |*name, from| name.* = from;
    const final = list;
    break :names final;
};

/// What the map shows of a mission: each ship and marker where its `position` places it, a ship
/// pointing as the game turns it by its yaw, pitch and roll (`mission.recordOrientation`), its
/// planets and the sun's and nebulae's markers as scenery, the range of each ShipReached trigger
/// and of each flyback marker the script sets, each curve as the director's camera runs it
/// (`executor.curves.point`), and the routes the script sends ships along (`RouteWalk`).
fn scene(arena: Allocator, text: []const u8, known: game.Outline) Allocator.Error!game.Scene {
    const tree = try source_parser.parse(arena, text);
    var things: std.ArrayList(game.Thing) = .empty;
    var ranges: std.ArrayList(game.Range) = .empty;
    var paths: std.ArrayList([]const [3]f64) = .empty;
    var walk: RouteWalk = .{ .arena = arena, .tree = tree, .known = known };
    var player: ?usize = null;
    for (known.records) |record| switch (record.section) {
        .ships => {
            // The first ship is the player's.
            if (record.index == 0) player = things.items.len;
            const scenery = if (record.given("type")) |given| isScenery(std.mem.trim(u8, given.value, "\"")) else false;
            try walk.addThing(record, things.items.len);
            try things.append(arena, .{
                .section = record.section,
                .index = record.index,
                .kind = if (scenery) .scenery else .ship,
                .place = vectorOf(record, "position"),
                .heading = if (scenery) null else headingOf(record),
            });
        },
        .markers => {
            try walk.addThing(record, things.items.len);
            try things.append(arena, .{
                .section = record.section,
                .index = record.index,
                .kind = markerKind(record),
                .place = vectorOf(record, "position"),
            });
        },
        .flight_groups => if (record.group) |group| try walk.groups.put(arena, record.name, group),
        .squads => try walk.squads.put(arena, record.name, {}),
        .triggers => if (std.meta.stringToEnum(dte.Condition, record.condition) == .ship_reached) {
            const subject = known.named(record.subject) orelse continue;
            // As far as OpenReliant's mission events watch.
            try ranges.append(arena, .{ .section = subject.section, .index = subject.index, .radius = game_mission.events.reached_reach, .label = record.condition, .style = .trigger });
        },
        .curves => try paths.append(arena, try curvePath(arena, record)),
        else => {},
    };
    // The flyback markers the script sets: `SetFlybackMarker(nav, 5000)`, anywhere in its code.
    for (0..tree.nodes.len) |index| {
        const call = callOf(tree, @intCast(index)) orelse continue;
        if (!std.mem.eql(u8, call.callee, set_flyback_marker.name) or call.arguments.len < set_flyback_marker.params.len) continue;
        const name = globalName(tree, call.arguments[0]) orelse continue;
        const radius = switch (tree.get(call.arguments[1])) {
            .number => |value| value,
            else => continue,
        };
        const subject = known.named(name) orelse continue;
        try ranges.append(arena, .{ .section = subject.section, .index = subject.index, .radius = radius, .label = "flyback", .style = .hint });
    }
    return .{ .things = things.items, .player = player, .ranges = ranges.items, .curves = paths.items, .routes = try walk.read(), .place_field = "position" };
}

/// How the map shows a marker: a point that marks a place on a curve, and a curve point, with the
/// curves; a nav point, a waypoint and the other points, such as where ships jump in, always.
fn markerKind(record: game.Record) game.ThingKind {
    return switch (std.meta.stringToEnum(source.names.Word, record.word) orelse return .marker) {
        .curve_point => .camera,
        .point => if (record.given("marker") != null) .camera else .marker,
        else => .marker,
    };
}

/// The commands the map reads: `SetAI`, whose order sends the entity it names to its target
/// (command `0x0B`), `SetPatrolRoute`, which sends it round a flight group's waypoints (`0x0D`),
/// and `SetFlybackMarker`, which sets the display's flyback marker on it within a range (`0x46`).
const set_ai = commands.table[0x0B];
const set_patrol_route = commands.table[0x0D];
const set_flyback_marker = commands.table[0x46];
/// `SetAI`'s parameters: the entity it sends, its order, and its target, which may be none.
const set_ai_entity = 0;
const set_ai_order = for (set_ai.params, 0..) |param, index| {
    if (source.vocabulary.of(param) == .order) break index;
} else @compileError("SetAI takes no order");
const set_ai_target = set_ai.params.len - 1;

comptime {
    std.debug.assert(std.mem.eql(u8, set_ai.name, "SetAI") and std.mem.eql(u8, set_patrol_route.name, "SetPatrolRoute"));
    std.debug.assert(std.mem.eql(u8, set_flyback_marker.name, "SetFlybackMarker"));
    std.debug.assert(set_ai.params[set_ai_target].kinds.ship and set_ai.params[set_ai_target].extra.nullable);
    std.debug.assert(set_patrol_route.params[1].kinds.flight_group);
}

/// How an order sends a ship to its target, where it does (OpenReliant's
/// [orders](https://github.com/OpenReliant/openreliant/blob/main/docs/engine/orders.md#the-orders)):
/// Fly and Escort fly it there, Jump Out and Warp Out jump it there, and Jump In and Warp In bring
/// it in there.
const Move = enum { fly, jump, arrive };

fn moveOf(order: orders.Order) ?Move {
    return switch (order) {
        .fly, .escort => .fly,
        .jump_out, .jump_out_spread, .warp_out, .fixed_gate_jump_out => .jump,
        .jump_in, .jump_in_spread, .warp_in, .fixed_gate_jump_in => .arrive,
        else => null,
    };
}

/// The order the argument at `index` gives: by its name, or by its number.
fn orderOf(tree: syntax.Tree, index: syntax.Index) ?orders.Order {
    const number: u32 = switch (tree.get(index)) {
        .string => |name| source.vocabulary.value(.order, name) orelse return null,
        .number => |value| if (value >= 0 and value <= std.math.maxInt(i16) and @floor(value) == value) @intFromFloat(value) else return null,
        else => return null,
    };
    return @fromBackingInt(std.math.cast(i16, number) orelse return null);
}

fn globalName(tree: syntax.Tree, index: syntax.Index) ?[]const u8 {
    return switch (tree.get(index)) {
        .global_name => |name| name,
        else => null,
    };
}

/// Reads where the script sends its ships and groups (`game.Route`): each order that sends one to
/// a marker, in the order the source gives them, through branches and triggers.
const RouteWalk = struct {
    arena: Allocator,
    tree: syntax.Tree,
    known: game.Outline,
    /// The ships and markers of the scene, by their records' names.
    things: std.StringHashMapUnmanaged(Placed) = .empty,
    /// The flight groups, by name, each with its place among them (`Record.group`), and the
    /// squads.
    groups: std.StringHashMapUnmanaged(usize) = .empty,
    squads: std.StringHashMapUnmanaged(void) = .empty,
    /// Each flight group's first ship, where a group's route starts.
    first_ships: std.AutoHashMapUnmanaged(usize, []const u8) = .empty,
    /// The ships and groups the script brings in by a jump or a warp, by name, and the groups by
    /// their place among the groups: such a ship waits far off until it comes in, so its route
    /// starts where it comes in, not where it starts.
    arriving: std.StringHashMapUnmanaged(void) = .empty,
    arriving_groups: std.AutoHashMapUnmanaged(usize, void) = .empty,
    /// Where the orders read so far send each ship or group.
    whereabouts: Whereabouts = .empty,
    /// The legs so far, by the name of the ship or group they're for.
    legs: std.StringArrayHashMapUnmanaged(std.ArrayList(game.Leg)) = .empty,

    /// A ship or a marker of the scene: its place among the scene's things, its section, and its
    /// flight group.
    const Placed = struct { thing: usize, section: game.Section, group: ?usize };

    /// A place a route reaches: the thing, and whether the route starts there.
    const Spot = struct { thing: usize, starts: bool };

    /// Where the orders send each ship or group, by name: at a spot, or lost where the script
    /// leaves it unknown, such as after branches that send it to different places.
    const Whereabouts = std.StringHashMapUnmanaged(union(enum) { at: Spot, lost });

    fn addThing(walk: *RouteWalk, record: game.Record, thing: usize) Allocator.Error!void {
        try walk.things.put(walk.arena, record.name, .{ .thing = thing, .section = record.section, .group = record.group });
        if (record.section != .ships) return;
        const group = record.group orelse return;
        const first = try walk.first_ships.getOrPut(walk.arena, group);
        if (!first.found_existing) first.value_ptr.* = record.name;
    }

    /// The routes, from the whole script.
    fn read(walk: *RouteWalk) Allocator.Error![]const game.Route {
        for (0..walk.tree.nodes.len) |index| {
            const found = callOf(walk.tree, @intCast(index)) orelse continue;
            if (!std.mem.eql(u8, found.callee, set_ai.name) or found.arguments.len < set_ai.params.len) continue;
            const given = orderOf(walk.tree, found.arguments[set_ai_order]) orelse continue;
            if (moveOf(given) != .arrive) continue;
            const subject = globalName(walk.tree, found.arguments[set_ai_entity]) orelse continue;
            try walk.arriving.put(walk.arena, subject, {});
            if (walk.groups.get(subject)) |group| try walk.arriving_groups.put(walk.arena, group, {});
        }
        try walk.visit(walk.tree.root);
        var routes: std.ArrayList(game.Route) = .empty;
        var each = walk.legs.iterator();
        while (each.next()) |entry| {
            const ship = walk.things.get(entry.key_ptr.*);
            try routes.append(walk.arena, .{
                .ship = if (ship) |placed| placed.thing else null,
                .group = if (ship) |placed| placed.group else walk.groups.get(entry.key_ptr.*),
                .legs = entry.value_ptr.items,
            });
        }
        return routes.items;
    }

    /// Reads the orders of the code at `index`, statement by statement.
    fn visit(walk: *RouteWalk, index: syntax.Index) Allocator.Error!void {
        switch (walk.tree.get(index)) {
            .block => |statements| for (statements) |statement| try walk.visit(statement),
            .@"if" => |both| try walk.branch(both.then, both.@"else"),
            .call_statement => |statement| try walk.visit(statement),
            .call => |found| try walk.call(found.function, found.arguments),
            .function => |function| try walk.visit(function.body),
            .local, .assign => |binding| for (binding.values) |value| try walk.visit(value),
            .@"return" => |values| for (values) |value| try walk.visit(value),
            .table => |items| for (items) |item| try walk.visit(item),
            .item => |item| try walk.visit(switch (item) {
                .list => |value| value,
                .record => |record| record.value,
                .general => |general| general.value,
            }),
            else => {},
        }
    }

    fn call(walk: *RouteWalk, function: syntax.Index, arguments: []const syntax.Index) Allocator.Error!void {
        if (globalName(walk.tree, function)) |callee| {
            if (std.mem.eql(u8, callee, set_ai.name)) return walk.order(arguments);
            if (std.mem.eql(u8, callee, set_patrol_route.name)) return walk.patrol(arguments);
            if (std.meta.stringToEnum(source.names.Word, callee) == .on) try walk.reached(arguments);
        }
        for (arguments) |argument| try walk.visit(argument);
    }

    /// `SetAI`: an order that sends the ship or group to a marker adds a leg from where it is.
    fn order(walk: *RouteWalk, arguments: []const syntax.Index) Allocator.Error!void {
        if (arguments.len < set_ai.params.len) return;
        const subject = walk.subjectOf(arguments[set_ai_entity]) orelse return;
        const move = moveOf(orderOf(walk.tree, arguments[set_ai_order]) orelse return) orelse return;
        // Sent out of the mission, or after a ship: where it is next isn't known.
        const target = walk.markerOf(arguments[set_ai_target]) orelse return walk.whereabouts.put(walk.arena, subject, .lost);
        const from = walk.whereIs(subject);
        if (from) |spot| if (spot.thing == target) return;
        switch (move) {
            .arrive => return walk.whereabouts.put(walk.arena, subject, .{ .at = .{ .thing = target, .starts = true } }),
            .fly, .jump => if (from) |spot| {
                try walk.addLeg(subject, .{ .from = spot.thing, .to = target, .way = if (move == .jump) .jump else .fly, .starts = spot.starts });
            },
        }
        try walk.whereabouts.put(walk.arena, subject, .{ .at = .{ .thing = target, .starts = false } });
    }

    /// `SetPatrolRoute`: the ship or group flies to the route's first waypoint, then round its
    /// waypoints in the order the mission lists them, back to the first (OpenReliant's
    /// `ai/formations.zig`, `nextWaypoint`). Where it is when the patrol starts isn't known, the
    /// route starts at the first waypoint.
    fn patrol(walk: *RouteWalk, arguments: []const syntax.Index) Allocator.Error!void {
        if (arguments.len < set_patrol_route.params.len) return;
        const subject = walk.subjectOf(arguments[0]) orelse return;
        const route = walk.groups.get(globalName(walk.tree, arguments[1]) orelse return) orelse return;
        var at = walk.whereIs(subject);
        var first: ?usize = null;
        for (walk.known.records) |record| {
            if (record.group != route or std.meta.stringToEnum(source.names.Word, record.word) != .waypoint) continue;
            const thing = (walk.things.get(record.name) orelse continue).thing;
            if (first == null) first = thing;
            if (at) |spot| if (spot.thing != thing) {
                try walk.addLeg(subject, .{ .from = spot.thing, .to = thing, .way = .fly, .starts = spot.starts });
            };
            const starts = at == null;
            at = .{ .thing = thing, .starts = starts };
        }
        if (first) |back| if (at) |spot| if (spot.thing != back) {
            try walk.addLeg(subject, .{ .from = spot.thing, .to = back, .way = .fly });
        };
        // Where the patrol has it when another order comes isn't known.
        try walk.whereabouts.put(walk.arena, subject, .lost);
    }

    /// A ShipReached trigger: as its code runs, the ship its value names is at the marker it
    /// watches.
    fn reached(walk: *RouteWalk, arguments: []const syntax.Index) Allocator.Error!void {
        if (arguments.len < 3) return;
        const condition = stringOf(walk.tree, arguments[1]) orelse return;
        if (std.meta.stringToEnum(dte.Condition, condition) != .ship_reached) return;
        const marker = walk.markerOf(arguments[0]) orelse return;
        const items = switch (walk.tree.get(arguments[2])) {
            .table => |items| items,
            else => return,
        };
        for (items) |item| switch (walk.tree.get(item)) {
            .item => |kind| switch (kind) {
                .record => |record| if (walk.subjectOf(record.value)) |ship| {
                    try walk.whereabouts.put(walk.arena, ship, .{ .at = .{ .thing = marker, .starts = false } });
                },
                else => {},
            },
            else => {},
        };
    }

    /// Reads both ways of a branch from where the walk is. Where they leave a ship or a group in
    /// different places, it could be in either: lost.
    fn branch(walk: *RouteWalk, then: syntax.Index, otherwise: ?syntax.Index) Allocator.Error!void {
        const before = try walk.whereabouts.clone(walk.arena);
        try walk.visit(then);
        const after_then = walk.whereabouts;
        walk.whereabouts = before;
        if (otherwise) |other| try walk.visit(other);
        var each = after_then.iterator();
        while (each.next()) |entry| {
            const other = walk.whereabouts.get(entry.key_ptr.*) orelse {
                try walk.whereabouts.put(walk.arena, entry.key_ptr.*, .lost);
                continue;
            };
            if (!std.meta.eql(other, entry.value_ptr.*)) try walk.whereabouts.put(walk.arena, entry.key_ptr.*, .lost);
        }
        var others = walk.whereabouts.iterator();
        while (others.next()) |entry| if (!after_then.contains(entry.key_ptr.*)) {
            entry.value_ptr.* = .lost;
        };
    }

    /// Where `subject` is as the walk reaches an order for it: where the orders before sent it, or
    /// else where it starts, unless the script brings it in by a jump or a warp. Null where that
    /// isn't known.
    fn whereIs(walk: *const RouteWalk, subject: []const u8) ?Spot {
        if (walk.whereabouts.get(subject)) |found| return switch (found) {
            .at => |spot| spot,
            .lost => null,
        };
        const start = walk.startOf(subject) orelse return null;
        return .{ .thing = start, .starts = true };
    }

    /// Where `subject` starts: a ship where it is, a flight group where its first ship is; none
    /// for a ship the script brings in by a jump or a warp, by itself or with its group, or for a
    /// squad.
    fn startOf(walk: *const RouteWalk, subject: []const u8) ?usize {
        const ship = if (walk.groups.get(subject)) |group| walk.first_ships.get(group) orelse return null else subject;
        const placed = walk.things.get(ship) orelse return null;
        if (placed.section != .ships or walk.arriving.contains(ship)) return null;
        if (placed.group) |group| if (walk.arriving_groups.contains(group)) return null;
        return placed.thing;
    }

    /// The name of the ship, flight group or squad the argument at `index` names.
    fn subjectOf(walk: *const RouteWalk, index: syntax.Index) ?[]const u8 {
        const name = globalName(walk.tree, index) orelse return null;
        if (walk.things.get(name)) |placed| return if (placed.section == .ships) name else null;
        if (walk.groups.contains(name) or walk.squads.contains(name)) return name;
        return null;
    }

    /// The thing of the marker the argument at `index` names.
    fn markerOf(walk: *const RouteWalk, index: syntax.Index) ?usize {
        const placed = walk.things.get(globalName(walk.tree, index) orelse return null) orelse return null;
        return if (placed.section == .markers) placed.thing else null;
    }

    /// Adds a leg to `subject`'s route, once.
    fn addLeg(walk: *RouteWalk, subject: []const u8, leg: game.Leg) Allocator.Error!void {
        const found = try walk.legs.getOrPut(walk.arena, subject);
        if (!found.found_existing) found.value_ptr.* = .empty;
        for (found.value_ptr.items) |*known| if (known.from == leg.from and known.to == leg.to and known.way == leg.way) {
            known.starts = known.starts or leg.starts;
            return;
        };
        try found.value_ptr.append(walk.arena, leg);
    }
};

/// Whether a ship of the type `type_name` is scenery: a planet, as the original's table of planets
/// has it (`create.planets.original`), or the sun's or a nebula's marker.
fn isScenery(type_name: []const u8) bool {
    const number = source.vocabulary.value(.ship_type, type_name) orelse return false;
    const ship_type: gameobj.Type = @fromBackingInt(std.math.cast(@typeInfo(gameobj.Type).@"enum".tag_type, number) orelse return false);
    for (planets.original) |planet| if (planet.type == ship_type) return true;
    return ship_type == gameobj.Type.of(.sun_marker) or ship_type == gameobj.Type.of(.nebula_marker);
}

/// The points a curve's path passes on the map.
const curve_points = 48;

/// The vector a record's field `name` gives; the origin where it gives none.
fn vectorOf(record: game.Record, name: []const u8) [3]f64 {
    const given = record.given(name) orelse return @splat(0);
    return given.vector() orelse @splat(0);
}

/// The way a ship's nose points, as the game turns it by its angles. An angle left out, or unset
/// as -1, is 0.
fn headingOf(record: game.Record) [3]f64 {
    var ship = std.mem.zeroes(dte.Ship);
    ship.yaw = angleOf(record, "yaw");
    ship.pitch = angleOf(record, "pitch");
    ship.roll = angleOf(record, "roll");
    const nose = math.forward(game_mission.recordOrientation(ship));
    return .{ nose[0], nose[1], nose[2] };
}

fn angleOf(record: game.Record, name: []const u8) i16 {
    const given = record.given(name) orelse return 0;
    const degrees = std.fmt.parseFloat(f64, given.value) catch return 0;
    if (degrees == -1) return 0;
    return std.math.lossyCast(i16, degrees);
}

/// The points a curve record's path passes, from its `from` to its `to`, along its tangents.
fn curvePath(arena: Allocator, record: game.Record) Allocator.Error![]const [3]f64 {
    var curve = dte.Curve.blank;
    for ([_]struct { *[3]f32, []const u8 }{ .{ &curve.from, "from" }, .{ &curve.to, "to" }, .{ &curve.leaving, "leaving" }, .{ &curve.arriving, "arriving" } }) |part| {
        const value = vectorOf(record, part[1]);
        part[0].* = .{ @floatCast(value[0]), @floatCast(value[1]), @floatCast(value[2]) };
    }
    const points = try arena.alloc([3]f64, curve_points);
    for (points, 0..) |*point, at| {
        const on = curves.point(curve, @as(f32, @floatFromInt(at)) / (curve_points - 1));
        point.* = .{ on[0], on[1], on[2] };
    }
    return points;
}

/// The records the outline's + adds. Squads, formations and curves list other records, and are
/// written in the source.
const new_kinds = [_]game.NewKind{
    .{ .word = "ship", .label = "Ship", .section = .ships },
    .{ .word = "nav_point", .label = "Nav point", .section = .markers },
    .{ .word = "waypoint", .label = "Waypoint", .section = .markers },
    .{ .word = "flight_group", .label = "Flight group", .section = .flight_groups },
    .{ .word = "part", .label = "Part", .section = .parts },
    .{ .word = "on", .label = "Trigger", .section = .triggers, .named = false },
    .{ .word = "global", .label = "Global", .section = .globals },
};

/// The condition a new trigger starts with: every ship has it. It watches nothing until a subject
/// is chosen.
const new_condition = "destroyed";

/// Declares a record of `kind` after the last record of its section, or of the sections before
/// it, or at the end of the file: `ship_1 = ship("Ship 1", { type = "predator" })` with the
/// game's first ship type, a part and a trigger with code that does nothing yet, and StarLancer's
/// tags on the display names of flight groups, parts and globals.
fn addRecord(arena: Allocator, text: []const u8, known: game.Outline, kind: game.NewKind, given: ?[]const u8) Allocator.Error!?game.Added {
    const stem = if (std.mem.eql(u8, kind.word, "nav_point")) "nav" else if (std.mem.eql(u8, kind.word, "flight_group")) "group" else kind.word;
    var number: usize = 1;
    const name = given orelse while (true) : (number += 1) {
        const candidate = try arena.print("{s}_{d}", .{ stem, number });
        if (known.named(candidate) == null) break candidate;
    };
    if (given != null and known.named(name) != null) return null;
    const shown = if (given != null) name else try arena.print("{s} {d}", .{ kind.label, number });
    const declaration = switch (std.meta.stringToEnum(source.names.Word, kind.word) orelse return null) {
        .ship => try arena.print("{s} = ship({s}, {{ type = \"{s}\" }})", .{ name, try source_edit.string(arena, shown), source.vocabulary.name(.ship_type, 0) orelse "predator" }),
        .flight_group => try arena.print("{s} = flight_group({s})", .{ name, try source_edit.string(arena, try arena.print("(FG){s}", .{shown})) }),
        .part => try arena.print("{s} = part({s}, function()\n    return 1\nend)", .{ name, try source_edit.string(arena, try arena.print("(F){s}", .{shown})) }),
        .on => "on(nil, \"" ++ new_condition ++ "\", function()\n    return 1\nend)",
        .global => try arena.print("{s} = global({s}, 0)", .{ name, try source_edit.string(arena, try arena.print("(GV){s}", .{name})) }),
        else => try arena.print("{s} = {s}({s})", .{ name, kind.word, try source_edit.string(arena, shown) }),
    };
    // After the last record of its section, or of the nearest section before it.
    var anchor: ?game.Record = null;
    for (std.enums.values(game.Section)) |section| {
        for (known.records) |record| if (record.section == section) {
            anchor = record;
        };
        if (section == kind.section) break;
    }
    if (anchor) |after| {
        const start = source_edit.offset(text, .{ .line = after.last_line, .column = 0 });
        const end = std.mem.findScalarPos(u8, text, start, '\n') orelse text.len;
        return .{ .change = .{ .start = end, .end = end, .text = try arena.print("\n{s}", .{declaration}) }, .line = after.last_line + 1 };
    }
    const lines: u32 = @intCast(std.mem.count(u8, text, "\n"));
    if (text.len == 0 or text[text.len - 1] == '\n') return .{ .change = .{ .start = text.len, .end = text.len, .text = try arena.print("{s}\n", .{declaration}) }, .line = lines };
    return .{ .change = .{ .start = text.len, .end = text.len, .text = try arena.print("\n{s}\n", .{declaration}) }, .line = lines + 1 };
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

test edit {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const made = try outline(arena, first_mission);
    const Case = struct { record: []const u8, edit: game.Edit, from: []const u8, to: []const u8 };
    const cases = [_]Case{
        // A field replaced, in a table of a line to an item.
        .{ .record = "sabre_1", .edit = .{ .field = .{ .name = "position", .value = "{ -1500, 0, 41000 }" } }, .from = "    position = { -2000, 0, 42000 },\n    yaw = 180,\n})\nsabre_2", .to = "    position = { -1500, 0, 41000 },\n    yaw = 180,\n})\nsabre_2" },
        // Added to a table on one line.
        .{ .record = "player", .edit = .{ .field = .{ .name = "pilot", .value = "\"bandit_tigers_leader\"" } }, .from = "{ type = \"predator\", group = alpha }", .to = "{ type = \"predator\", group = alpha, pilot = \"bandit_tigers_leader\" }" },
        // A table where there was none.
        .{ .record = "navs", .edit = .{ .field = .{ .name = "wing", .value = "\"second\"" } }, .from = "flight_group(\"(FG)Nav points\")", .to = "flight_group(\"(FG)Nav points\", { wing = \"second\" })" },
        // The display name.
        .{ .record = "nav", .edit = .{ .display = "Nav \"A\"" }, .from = "nav_point(\"Nav 1\",", .to = "nav_point(\"Nav \\\"A\\\"\"," },
        // A part's field taken out.
        .{ .record = "start", .edit = .{ .field = .{ .name = "start", .value = null } }, .from = "end, { start = true })", .to = "end, {})" },
    };
    for (cases) |case| {
        const record = made.named(case.record).?;
        const change = (try edit(arena, first_mission, record.*, case.edit)).?;
        const changed = try source_edit.testing.applied(arena, first_mission, change);
        try std.testing.expectEqualStrings(try std.mem.replaceOwned(u8, arena, first_mission, case.from, case.to), changed);
        // The mission still builds.
        try std.testing.expect(try build(arena, changed) == .mission);
    }
    // A trigger's condition, and a table for the one that has none, before its code.
    const destroyed = made.records[made.records.len - 1];
    const repeats = (try edit(arena, first_mission, destroyed, .{ .field = .{ .name = "repeats", .value = "\"always\"" } })).?;
    try std.testing.expect(std.mem.find(u8, try source_edit.testing.applied(arena, first_mission, repeats), "on(enemies, \"destroyed\", { repeats = \"always\" }, function(killer, victim)") != null);
    const reached = made.records[made.records.len - 2];
    const condition = (try edit(arena, first_mission, reached, .{ .condition = "destroyed" })).?;
    try std.testing.expect(std.mem.find(u8, try source_edit.testing.applied(arena, first_mission, condition), "on(nav, \"destroyed\", {") != null);
    // A field taken out that isn't there changes nothing.
    try std.testing.expectEqual(null, try edit(arena, first_mission, made.named("navs").?.*, .{ .field = .{ .name = "wing", .value = null } }));
}

test addRecord {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const made = try outline(arena, first_mission);
    // A ship goes after the last ship, under the first free name, and the mission still builds.
    const ship = (try addRecord(arena, first_mission, made, new_kinds[0], null)).?;
    const with_ship = try source_edit.testing.applied(arena, first_mission, ship.change);
    try std.testing.expect(std.mem.find(u8, with_ship, "    yaw = 180,\n})\nship_1 = ship(\"Ship 1\", { type = \"predator\" })\n") != null);
    const again = try outline(arena, with_ship);
    try std.testing.expectEqualStrings("ship_1", again.find(.ships, ship.line).?.name);
    try std.testing.expect(try build(arena, with_ship) == .mission);
    // A name the source uses without declaring it, as a global; a name taken is refused.
    const global = (try addRecord(arena, first_mission, made, new_kinds[6], "convoykilled")).?;
    try std.testing.expect(std.mem.find(u8, try source_edit.testing.applied(arena, first_mission, global.change), "convoykilled = global(\"(GV)convoykilled\", 0)") != null);
    try std.testing.expectEqual(null, try addRecord(arena, first_mission, made, new_kinds[0], "player"));
    // Each kind builds.
    for (new_kinds) |kind| {
        const added = (try addRecord(arena, first_mission, made, kind, null)).?;
        try std.testing.expect(try build(arena, try source_edit.testing.applied(arena, first_mission, added.change)) == .mission);
    }
    try std.testing.expect(source.vocabulary.value(.condition, new_condition) != null);
}

test scene {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const made = try outline(arena.allocator(), first_mission);
    const shown = try scene(arena.allocator(), first_mission, made);
    // The player, the nav point and the two Sabres, each where it starts.
    try std.testing.expectEqual(4, shown.things.len);
    try std.testing.expectEqual(made.named("player").?.index, shown.things[shown.player.?].index);
    const sabre = made.named("sabre_1").?;
    for (shown.things) |thing| if (thing.section == sabre.section and thing.index == sabre.index) {
        try std.testing.expectEqual([3]f64{ -2000, 0, 42000 }, thing.place);
        // Turned half round, it points back along Z.
        try std.testing.expectApproxEqAbs(-1, thing.heading.?[2], 1e-6);
    };
    // The nav point's ShipReached trigger watches within 4000 of it, and the start part sets the
    // flyback marker on it within 5000.
    try std.testing.expectEqual(2, shown.ranges.len);
    try std.testing.expectEqual(made.named("nav").?.index, shown.ranges[0].index);
    try std.testing.expectEqual(4000, shown.ranges[0].radius);
    try std.testing.expectEqual(5000, shown.ranges[1].radius);
    try std.testing.expectEqual(game.RangeStyle.hint, shown.ranges[1].style);
    // A planet's type is scenery; a Sabre's isn't.
    try std.testing.expect(isScenery("neptune_hi") and !isScenery("sabre"));
}

test RouteWalk {
    const text =
        \\alpha = flight_group("(FG)Alpha", { wing = "player" })
        \\raiders = flight_group("(FG)Raiders")
        \\round = flight_group("(FG)Round")
        \\player = ship("Player", { type = "predator", group = alpha })
        \\wingman = ship("Wingman", { type = "predator", group = alpha, position = { 500, 0, 0 } })
        \\raider = ship("Raider", { type = "sabre", group = raiders, position = { 9000000, 0, 0 } })
        \\nav = nav_point("Nav 1", { position = { 0, 0, 40000 } })
        \\entry = point("Raider in", { position = { 5000, 0, 30000 } })
        \\target = waypoint("Raider fly to", { position = { 2000, 0, 35000 } })
        \\out = point("Raider out", { position = { 9000, 0, 35000 } })
        \\left = waypoint("Left", { position = { -3000, 0, 1000 } })
        \\right = waypoint("Right", { position = { 3000, 0, 1000 } })
        \\later = waypoint("Later", { position = { 0, 0, 9000 } })
        \\one = waypoint("One", { group = round, position = { 0, 0, 1 } })
        \\two = waypoint("Two", { group = round, position = { 0, 0, 2 } })
        \\three = waypoint("Three", { group = round, position = { 0, 0, 3 } })
        \\shot = point("Shot", { marker = { curve = path, at = 0.5 } })
        \\start = part("(F)Start", function()
        \\    SetAI(raider, "jump_in", 1, entry)
        \\    SetAI(raider, "fly", 1, target)
        \\    SetAI(alpha, "jump_out", 1, nav)
        \\    if game.mission_success == 1 then
        \\        SetAI(wingman, "fly", 1, left)
        \\    else
        \\        SetAI(wingman, "fly", 1, right)
        \\    end
        \\    SetAI(wingman, "fly", 1, later)
        \\    SetPatrolRoute(raiders, round)
        \\    return 1
        \\end, { start = true })
        \\on(target, "ship_reached", { reached_ship = raider }, function(reached_ship)
        \\    SetAI(raider, "jump_out", 1, out)
        \\    return 1
        \\end)
        \\
    ;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const made = try outline(arena.allocator(), text);
    const shown = try scene(arena.allocator(), text, made);
    const at = struct {
        fn thing(things: []const game.Thing, known: game.Outline, name: []const u8) usize {
            const record = known.named(name).?;
            for (things, 0..) |each, index| if (each.section == record.section and each.index == record.index) return index;
            unreachable;
        }
    };
    const legsOf = struct {
        fn route(routes: []const game.Route, things: []const game.Thing, known: game.Outline, name: []const u8) []const game.Leg {
            const record = known.named(name).?;
            for (routes) |each| {
                if (each.ship) |ship| if (things[ship].section == record.section and things[ship].index == record.index) return each.legs;
                if (each.ship == null and record.section == .flight_groups and each.group == record.group) return each.legs;
            }
            return &.{};
        }
    };
    const things = shown.things;
    // The raider waits far off until it jumps in, so its route starts where it comes in: it flies
    // to its waypoint, and on reaching it jumps out.
    try std.testing.expectEqualSlices(game.Leg, &.{
        .{ .from = at.thing(things, made, "entry"), .to = at.thing(things, made, "target"), .way = .fly, .starts = true },
        .{ .from = at.thing(things, made, "target"), .to = at.thing(things, made, "out"), .way = .jump },
    }, legsOf.route(shown.routes, things, made, "raider"));
    // The player's group jumps to the nav point from where its first ship starts.
    try std.testing.expectEqualSlices(game.Leg, &.{
        .{ .from = at.thing(things, made, "player"), .to = at.thing(things, made, "nav"), .way = .jump, .starts = true },
    }, legsOf.route(shown.routes, things, made, "alpha"));
    // Either branch flies the wingman from its start; after them it could be at either, so no leg
    // leads to the next waypoint.
    try std.testing.expectEqualSlices(game.Leg, &.{
        .{ .from = at.thing(things, made, "wingman"), .to = at.thing(things, made, "left"), .way = .fly, .starts = true },
        .{ .from = at.thing(things, made, "wingman"), .to = at.thing(things, made, "right"), .way = .fly, .starts = true },
    }, legsOf.route(shown.routes, things, made, "wingman"));
    // The raiders' patrol route goes round its waypoints in the order they're listed, back to the
    // first. The group comes in nowhere and starts at its first ship, the raider, which jumps in,
    // so the route starts at the first waypoint.
    try std.testing.expectEqualSlices(game.Leg, &.{
        .{ .from = at.thing(things, made, "one"), .to = at.thing(things, made, "two"), .way = .fly, .starts = true },
        .{ .from = at.thing(things, made, "two"), .to = at.thing(things, made, "three"), .way = .fly },
        .{ .from = at.thing(things, made, "three"), .to = at.thing(things, made, "one"), .way = .fly },
    }, legsOf.route(shown.routes, things, made, "raiders"));
    // A point where a ship comes in is a marker; one that marks a place on a curve shows with the
    // curves.
    try std.testing.expectEqual(game.ThingKind.marker, things[at.thing(things, made, "entry")].kind);
    try std.testing.expectEqual(game.ThingKind.camera, things[at.thing(things, made, "shot")].kind);
}

test fieldForms {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const made = try outline(arena.allocator(), first_mission);
    const ship_forms = fieldForms(made.named("sabre_1").?.*);
    try std.testing.expectEqualStrings("type", ship_forms[0].name);
    try std.testing.expectEqualStrings("ShipType", ship_forms[0].kind.value);
    try std.testing.expectEqual(game.Section.flight_groups, ship_forms[1].kind.record[0]);
    try std.testing.expect(fieldKind("Vector?") == .vector);
    try std.testing.expectEqualStrings("player", fieldKind("Wing?").strings[0]);
    try std.testing.expect(fieldKind("Launch?") == .source);
}

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
