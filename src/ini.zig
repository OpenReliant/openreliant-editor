//! INI files as the editor reads and writes them: `[Section]` headings and `key=value` lines, with
//! `;` and `#` starting comments, as OpenReliant's `mod.ini` and the editor's own settings are
//! written. Sections and keys can be written in any case.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Entry = struct {
    section: []const u8,
    key: []const u8,
    value: []const u8,
};

/// The entries of `text`, in order, as slices of it.
pub fn parse(arena: Allocator, text: []const u8) Allocator.Error![]const Entry {
    var entries: std.ArrayList(Entry) = .empty;
    var section: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == ';' or line[0] == '#') continue;
        if (line[0] == '[') {
            const end = std.mem.findScalar(u8, line, ']') orelse continue;
            section = std.mem.trim(u8, line[1..end], " \t");
            continue;
        }
        const equals = std.mem.findScalar(u8, line, '=') orelse continue;
        try entries.append(arena, .{
            .section = section,
            .key = std.mem.trim(u8, line[0..equals], " \t"),
            .value = std.mem.trim(u8, line[equals + 1 ..], " \t"),
        });
    }
    return entries.toOwnedSlice(arena);
}

/// The value of `key` in `section`, the last one given.
pub fn get(entries: []const Entry, section: []const u8, key: []const u8) ?[]const u8 {
    var found: ?[]const u8 = null;
    for (entries) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.section, section) and std.ascii.eqlIgnoreCase(entry.key, key)) found = entry.value;
    }
    return found;
}

test parse {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const entries = try parse(arena.allocator(),
        \\; A mod's manifest.
        \\[Mod]
        \\Name = First Mission
        \\Version=1.0
        \\
        \\[keys]
        \\build=Ctrl+Shift+B
    );
    try std.testing.expectEqual(3, entries.len);
    try std.testing.expectEqualStrings("First Mission", get(entries, "mod", "name").?);
    try std.testing.expectEqualStrings("Ctrl+Shift+B", get(entries, "Keys", "Build").?);
    try std.testing.expectEqual(null, get(entries, "Mod", "Author"));
}
