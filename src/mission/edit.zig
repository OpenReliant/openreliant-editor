//! Changes to mission source that the inspector's forms and the map make: a field of a record's
//! table set, added or taken out, and an argument replaced. Each is one change to a span of the
//! text (`game.Change`), which the document applies as a single step of the editor's undo.
//! OpenReliant's syntax tree gives where each node starts. Where a value ends is read from the
//! text: past its brackets, strings and comments, up to the comma or bracket that closes it.

const std = @import("std");
const Allocator = std.mem.Allocator;

const openreliant = @import("openreliant");
const syntax = openreliant.dte.source.syntax;

const game = @import("../game.zig");
const Change = game.Change;

/// The byte offset in `text` of a place the syntax tree gives: a line and a byte on it, from 0.
pub fn offset(text: []const u8, at: syntax.Position) usize {
    var line: u32 = 0;
    var start: usize = 0;
    while (line < at.line) : (line += 1) {
        const end = std.mem.findScalarPos(u8, text, start, '\n') orelse return text.len;
        start = end + 1;
    }
    return @min(start + at.column, text.len);
}

/// Where the value that starts at byte `start` ends: past its brackets, strings and comments, up
/// to the comma, semicolon or closing bracket after it, and before the spaces and comments in
/// between. It reads names, strings, numbers, tables and calls; a function's body can hold commas
/// of its own, so its end isn't found this way.
pub fn valueEnd(text: []const u8, start: usize) usize {
    var depth: usize = 0;
    var at = start;
    var end = start;
    while (at < text.len) {
        switch (text[at]) {
            ' ', '\t', '\r', '\n' => {
                at += 1;
                continue;
            },
            '-' => if (at + 1 < text.len and text[at + 1] == '-') {
                at = commentEnd(text, at);
                continue;
            },
            '"', '\'' => {
                at = quotedEnd(text, at);
                end = at;
                continue;
            },
            '[' => if (longLevel(text, at)) |level| {
                at = longEnd(text, at, level);
                end = at;
                continue;
            } else {
                depth += 1;
            },
            '(', '{' => depth += 1,
            ')', '}', ']' => {
                if (depth == 0) break;
                depth -= 1;
            },
            ',', ';' => if (depth == 0) break,
            else => {},
        }
        at += 1;
        end = at;
    }
    return end;
}

/// Past the comment that starts with `--` at `at`: a long one to its closing brackets, a short
/// one to the end of its line.
fn commentEnd(text: []const u8, at: usize) usize {
    const rest = at + 2;
    if (rest < text.len and text[rest] == '[') if (longLevel(text, rest)) |level| return longEnd(text, rest, level);
    return std.mem.findScalarPos(u8, text, rest, '\n') orelse text.len;
}

/// Past the string quoted at `at`, with its escapes; an unfinished one ends with its line.
fn quotedEnd(text: []const u8, at: usize) usize {
    const quote = text[at];
    var place = at + 1;
    while (place < text.len) : (place += 1) switch (text[place]) {
        '\\' => place += 1,
        '\n' => return place,
        else => if (text[place] == quote) return place + 1,
    };
    return text.len;
}

/// The level of the long bracket opening at `at`, `[[` or `[==[`: the number of `=`. Null for a
/// lone `[`.
fn longLevel(text: []const u8, at: usize) ?usize {
    var place = at + 1;
    while (place < text.len and text[place] == '=') place += 1;
    if (place < text.len and text[place] == '[') return place - at - 1;
    return null;
}

/// Past the long string or comment whose brackets of `level` open at `at`.
fn longEnd(text: []const u8, at: usize, level: usize) usize {
    var place = at + level + 2;
    while (std.mem.findScalarPos(u8, text, place, ']')) |close| {
        const equals = close + 1 + level;
        if (equals < text.len and text[equals] == ']' and std.mem.allEqual(u8, text[close + 1 .. equals], '=')) return equals + 1;
        place = close + 1;
    }
    return text.len;
}

/// The span of the value at node `index`: where it starts, and where it ends (`valueEnd`).
pub fn span(tree: syntax.Tree, text: []const u8, index: syntax.Index) struct { usize, usize } {
    const start = offset(text, tree.at(index));
    return .{ start, valueEnd(text, start) };
}

/// The change that writes `value` in place of the value at node `index`.
pub fn replace(tree: syntax.Tree, text: []const u8, index: syntax.Index, value: []const u8) Change {
    const start, const end = span(tree, text, index);
    return .{ .start = start, .end = end, .text = value };
}

/// The item of the table at `table` whose key is `key`, and its value.
pub fn fieldOf(tree: syntax.Tree, table: syntax.Index, key: []const u8) ?struct { item: syntax.Index, value: syntax.Index } {
    for (tree.get(table).table) |item| switch (tree.get(item)) {
        .item => |found| switch (found) {
            .record => |record| if (std.mem.eql(u8, record.key, key)) return .{ .item = item, .value = record.value },
            else => {},
        },
        else => {},
    };
    return null;
}

/// The change that sets `key` of the table at `table` to `value`, as the source writes it: the
/// value replaced where the table has the key, or the key added after the table's last item, on a
/// line of its own where the items are each on one.
pub fn setField(arena: Allocator, tree: syntax.Tree, text: []const u8, table: syntax.Index, key: []const u8, value: []const u8) Allocator.Error!Change {
    if (fieldOf(tree, table, key)) |found| return replace(tree, text, found.value, value);
    const open = offset(text, tree.at(table));
    const close = valueEnd(text, open) - 1;
    const items = tree.get(table).table;
    if (items.len == 0) return .{ .start = open, .end = close + 1, .text = try arena.print("{{ {s} = {s} }}", .{ key, value }) };
    const last = items[items.len - 1];
    const last_start = offset(text, tree.at(last));
    const last_end = itemEnd(tree, text, last);
    const comma = after(text, last_end, ',');
    if (lineAt(text, last_start) == lineAt(text, open)) {
        // On one line: `{ type = "sabre", group = enemies }`.
        if (comma) |at| return .{ .start = at + 1, .end = at + 1, .text = try arena.print(" {s} = {s},", .{ key, value }) };
        return .{ .start = last_end, .end = last_end, .text = try arena.print(", {s} = {s}", .{ key, value }) };
    }
    // An item to a line, as the last one is indented, with a comma after it as the last has one.
    const indent = indentAt(text, last_start);
    if (comma) |at| return .{ .start = at + 1, .end = at + 1, .text = try arena.print("\n{s}{s} = {s},", .{ indent, key, value }) };
    return .{ .start = last_end, .end = last_end, .text = try arena.print(",\n{s}{s} = {s}", .{ indent, key, value }) };
}

/// The change that takes `key` out of the table at `table`, with its comma, and its line where it
/// has one to itself; null where the table doesn't have it.
pub fn removeField(tree: syntax.Tree, text: []const u8, table: syntax.Index, key: []const u8) ?Change {
    const found = fieldOf(tree, table, key) orelse return null;
    const items = tree.get(table).table;
    const start = offset(text, tree.at(found.item));
    const end = itemEnd(tree, text, found.item);
    const comma = after(text, end, ',');
    const through = if (comma) |at| at + 1 else end;
    // On a line of its own: the whole line goes.
    const line_start = lineStart(text, start);
    const line_end = std.mem.findScalarPos(u8, text, through, '\n') orelse text.len;
    if (blank(text[line_start..start]) and blank(text[through..line_end]) and line_end < text.len) {
        return .{ .start = line_start, .end = line_end + 1, .text = "" };
    }
    if (items.len == 1) {
        // The only item: the table is left empty.
        const open = offset(text, tree.at(table));
        return .{ .start = open, .end = valueEnd(text, open), .text = "{}" };
    }
    if (comma) |at| return .{ .start = start, .end = skipSpaces(text, at + 1), .text = "" };
    // The last item, without a comma after it: the comma before it goes too.
    const previous = items[std.mem.findScalar(syntax.Index, items, found.item).? - 1];
    return .{ .start = itemEnd(tree, text, previous), .end = end, .text = "" };
}

/// The change that adds a table of `key = value` as an argument after the argument at node
/// `argument`, which is a name, a string, a number or a table.
pub fn addTable(arena: Allocator, tree: syntax.Tree, text: []const u8, argument: syntax.Index, key: []const u8, value: []const u8) Allocator.Error!Change {
    _, const end = span(tree, text, argument);
    return .{ .start = end, .end = end, .text = try arena.print(", {{ {s} = {s} }}", .{ key, value }) };
}

/// The change that adds `argument`, as the source writes it, after the last argument of the call
/// at node `call`, whatever its arguments are: a function's too, since the call's brackets hold
/// it.
pub fn appendArgument(arena: Allocator, tree: syntax.Tree, text: []const u8, call: syntax.Index, argument: []const u8) Allocator.Error!Change {
    _, const end = span(tree, text, call);
    const close = end - 1;
    const empty = tree.get(call).call.arguments.len == 0;
    return .{ .start = close, .end = close, .text = if (empty) argument else try arena.print(", {s}", .{argument}) };
}

/// Where the item at node `item` ends: its value's end.
fn itemEnd(tree: syntax.Tree, text: []const u8, item: syntax.Index) usize {
    const value = switch (tree.get(item)) {
        .item => |found| switch (found) {
            .list => |value| value,
            .record => |record| record.value,
            .general => |general| general.value,
        },
        else => item,
    };
    _, const end = span(tree, text, value);
    return end;
}

/// The place of `byte` after `at`, past spaces, on the same line; null where another byte comes
/// first.
fn after(text: []const u8, at: usize, byte: u8) ?usize {
    var place = at;
    while (place < text.len and (text[place] == ' ' or text[place] == '\t')) place += 1;
    return if (place < text.len and text[place] == byte) place else null;
}

fn skipSpaces(text: []const u8, at: usize) usize {
    var place = at;
    while (place < text.len and (text[place] == ' ' or text[place] == '\t')) place += 1;
    return place;
}

fn lineAt(text: []const u8, at: usize) usize {
    return std.mem.count(u8, text[0..at], "\n");
}

fn lineStart(text: []const u8, at: usize) usize {
    return if (std.mem.findScalarLast(u8, text[0..at], '\n')) |newline| newline + 1 else 0;
}

/// The spaces and tabs that start the line holding byte `at`.
fn indentAt(text: []const u8, at: usize) []const u8 {
    const start = lineStart(text, at);
    var end = start;
    while (end < at and (text[end] == ' ' or text[end] == '\t')) end += 1;
    return text[start..end];
}

fn blank(text: []const u8) bool {
    return std.mem.trim(u8, text, " \t\r").len == 0;
}

/// `value` as mission source writes a string: in double quotes, with its quotes, backslashes and
/// control characters escaped.
pub fn string(arena: Allocator, value: []const u8) Allocator.Error![]const u8 {
    var written: std.Io.Writer.Allocating = .init(arena);
    const writer = &written.writer;
    writer.writeByte('"') catch return error.OutOfMemory;
    for (value) |byte| switch (byte) {
        '"' => writer.writeAll("\\\"") catch return error.OutOfMemory,
        '\\' => writer.writeAll("\\\\") catch return error.OutOfMemory,
        '\n' => writer.writeAll("\\n") catch return error.OutOfMemory,
        // Three digits, so that a digit after it doesn't join the escape.
        0...9, 11...31, 127 => writer.print("\\{d:0>3}", .{byte}) catch return error.OutOfMemory,
        else => writer.writeByte(byte) catch return error.OutOfMemory,
    };
    writer.writeByte('"') catch return error.OutOfMemory;
    return written.written();
}

/// `value` as mission source writes a number: a whole one without a point, `42000`.
pub fn number(arena: Allocator, value: f64) Allocator.Error![]const u8 {
    return arena.print("{d}", .{value});
}

/// `values` as mission source writes a place or a direction: `{ -2000, 0, 42000 }`.
pub fn vector(arena: Allocator, values: []const f64) Allocator.Error![]const u8 {
    var written: std.Io.Writer.Allocating = .init(arena);
    const writer = &written.writer;
    writer.writeAll("{ ") catch return error.OutOfMemory;
    for (values, 0..) |value, index| writer.print("{s}{d}", .{ if (index == 0) "" else ", ", value }) catch return error.OutOfMemory;
    writer.writeAll(" }") catch return error.OutOfMemory;
    return written.written();
}

pub const testing = struct {
    const source_parser = @import("source_parser");

    /// `text` with `change` made.
    pub fn applied(arena: Allocator, text: []const u8, change: Change) Allocator.Error![]const u8 {
        return std.mem.concat(arena, u8, &.{ text[0..change.start], change.text, text[change.end..] });
    }

    /// The table of the first statement's call, `name = constructor(..., { ... })`.
    fn table(tree: syntax.Tree) syntax.Index {
        const statement = tree.get(tree.root).block[0];
        const call = tree.get(tree.get(statement).assign.values[0]).call;
        for (call.arguments) |argument| if (tree.get(argument) == .table) return argument;
        unreachable;
    }

    /// `text` with `key` of its first record set to `value`.
    fn set(arena: Allocator, text: []const u8, key: []const u8, value: []const u8) ![]const u8 {
        const tree = try source_parser.parse(arena, text);
        return testing.applied(arena, text, try setField(arena, tree, text, table(tree), key, value));
    }

    /// `text` with `key` of its first record taken out.
    fn remove(arena: Allocator, text: []const u8, key: []const u8) ![]const u8 {
        const tree = try source_parser.parse(arena, text);
        return testing.applied(arena, text, removeField(tree, text, table(tree), key) orelse return error.TestUnexpectedResult);
    }
};

test valueEnd {
    try std.testing.expectEqual(5, valueEnd("alpha, b", 0));
    try std.testing.expectEqual(18, valueEnd("{ 1, { 2, 3 }, 4 } }", 0));
    // Strings, with their escapes and brackets, and comments are read past.
    try std.testing.expectEqual(9, valueEnd("\"a, \\\" }\" -- note, }\n, b", 0));
    try std.testing.expectEqual(12, valueEnd("[==[a]]b]==], c", 0));
    try std.testing.expectEqual(12, valueEnd("call(a, \"b\")\n, c", 0));
    // A minus is a number's sign, and `--[[ ]]` a comment that can end before the line does.
    try std.testing.expectEqual(5, valueEnd("-2000 --[[ x ]], 1", 0));
}

test offset {
    try std.testing.expectEqual(7, offset("ab\ncdef\ng", .{ .line = 1, .column = 4 }));
    try std.testing.expectEqual(0, offset("", .{ .line = 3, .column = 2 }));
}

test setField {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // A value replaced, whatever it is.
    try std.testing.expectEqualStrings(
        \\s = ship("S", { type = "sabre", position = { 1, 2, 3 } })
    , try testing.set(arena,
        \\s = ship("S", { type = "sabre", position = { -5, 0, 40000 } })
    , "position", "{ 1, 2, 3 }"));
    // A field added to a table on one line.
    try std.testing.expectEqualStrings(
        \\s = ship("S", { type = "sabre", pilot = "jones" })
    , try testing.set(arena,
        \\s = ship("S", { type = "sabre" })
    , "pilot", "\"jones\""));
    // To an empty table.
    try std.testing.expectEqualStrings(
        \\s = nav_point("N", { group = navs })
    , try testing.set(arena,
        \\s = nav_point("N", {})
    , "group", "navs"));
    // An item to a line, with the last item's comma or without it.
    try std.testing.expectEqualStrings(
        \\s = ship("S", {
        \\    type = "sabre",
        \\    yaw = 90,
        \\})
    , try testing.set(arena,
        \\s = ship("S", {
        \\    type = "sabre",
        \\})
    , "yaw", "90"));
    try std.testing.expectEqualStrings(
        \\s = ship("S", {
        \\  type = "sabre",
        \\  yaw = 90
        \\})
    , try testing.set(arena,
        \\s = ship("S", {
        \\  type = "sabre"
        \\})
    , "yaw", "90"));
}

test removeField {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // On one line, with the comma after it, or before it for the last.
    try std.testing.expectEqualStrings(
        \\s = ship("S", { type = "sabre" })
    , try testing.remove(arena,
        \\s = ship("S", { pilot = "jones", type = "sabre" })
    , "pilot"));
    try std.testing.expectEqualStrings(
        \\s = ship("S", { type = "sabre" })
    , try testing.remove(arena,
        \\s = ship("S", { type = "sabre", pilot = "jones" })
    , "pilot"));
    // The only item leaves an empty table.
    try std.testing.expectEqualStrings(
        \\s = part("P", {})
    , try testing.remove(arena,
        \\s = part("P", { start = true })
    , "start"));
    // A line of its own goes whole.
    try std.testing.expectEqualStrings(
        \\s = ship("S", {
        \\    type = "sabre",
        \\})
        \\
    , try testing.remove(arena,
        \\s = ship("S", {
        \\    type = "sabre",
        \\    yaw = 90,
        \\})
        \\
    , "yaw"));
}

test appendArgument {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const text =
        \\p = part("(F)Start", function()
        \\    SetAI(a, "fight", b)
        \\    return 1
        \\end)
    ;
    const tree = try testing.source_parser.parse(arena, text);
    const statement = tree.get(tree.root).block[0];
    const made = try appendArgument(arena, tree, text, tree.get(statement).assign.values[0], "{ start = true }");
    try std.testing.expectEqualStrings(
        \\p = part("(F)Start", function()
        \\    SetAI(a, "fight", b)
        \\    return 1
        \\end, { start = true })
    , try testing.applied(arena, text, made));
}

test string {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    try std.testing.expectEqualStrings("\"(FG)\\\"Alpha\\\"\\\\\"", try string(arena_state.allocator(), "(FG)\"Alpha\"\\"));
    try std.testing.expectEqualStrings("{ -2000, 0, 42000.5 }", try vector(arena_state.allocator(), &.{ -2000, 0, 42000.5 }));
    try std.testing.expectEqualStrings("90", try number(arena_state.allocator(), 90));
}
