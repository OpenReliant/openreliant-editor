//! Keys: the chords that run commands, written as each system writes them, such as `Ctrl+Shift+P`
//! on Windows and Linux and `Cmd+Shift+P` on macOS. ImGui sees Cmd on macOS as its Ctrl, so a
//! chord keeps the modifier each system uses for shortcuts as `primary`, and the other one, Ctrl
//! on macOS and the Windows key elsewhere, as `secondary`.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("c");

/// The systems whose keys differ.
pub const System = enum {
    windows_linux,
    macos,

    /// The system the editor runs on.
    pub const current: System = if (builtin.target.os.tag == .macos) .macos else .windows_linux;

    pub fn label(system: System) []const u8 {
        return switch (system) {
            .windows_linux => "Windows, Linux",
            .macos => "macOS",
        };
    }

    /// The name keys.ini gives the system's section.
    pub fn section(system: System) []const u8 {
        return switch (system) {
            .windows_linux => "windows-linux",
            .macos => "macos",
        };
    }
};

/// The keys a chord can end in.
pub const Key = enum {
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    @"0",
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    comma,
    period,
    slash,
    backslash,
    semicolon,
    apostrophe,
    minus,
    equal,
    left_bracket,
    right_bracket,
    grave,
    enter,
    escape,
    tab,
    space,
    backspace,
    delete,
    insert,
    home,
    end,
    page_up,
    page_down,
    up,
    down,
    left,
    right,

    /// How a chord writes the key.
    pub fn name(key: Key) []const u8 {
        return switch (key) {
            .comma => ",",
            .period => ".",
            .slash => "/",
            .backslash => "\\",
            .semicolon => ";",
            .apostrophe => "'",
            .minus => "-",
            .equal => "=",
            .left_bracket => "[",
            .right_bracket => "]",
            .grave => "`",
            .enter => "Enter",
            .escape => "Esc",
            .tab => "Tab",
            .space => "Space",
            .backspace => "Backspace",
            .delete => "Delete",
            .insert => "Insert",
            .home => "Home",
            .end => "End",
            .page_up => "PageUp",
            .page_down => "PageDown",
            .up => "Up",
            .down => "Down",
            .left => "Left",
            .right => "Right",
            inline .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12 => |f| comptime upper(@tagName(f)),
            inline else => |letter| comptime upper(@tagName(letter)),
        };
    }

    /// The key a chord's text names, in any case.
    pub fn parse(text: []const u8) ?Key {
        for (std.enums.values(Key)) |key| {
            if (std.ascii.eqlIgnoreCase(key.name(), text)) return key;
        }
        if (std.ascii.eqlIgnoreCase(text, "Escape")) return .escape;
        return null;
    }

    pub fn imgui(key: Key) c.ImGuiKey {
        return switch (key) {
            .a => c.ImGuiKey_A,
            .b => c.ImGuiKey_B,
            .c => c.ImGuiKey_C,
            .d => c.ImGuiKey_D,
            .e => c.ImGuiKey_E,
            .f => c.ImGuiKey_F,
            .g => c.ImGuiKey_G,
            .h => c.ImGuiKey_H,
            .i => c.ImGuiKey_I,
            .j => c.ImGuiKey_J,
            .k => c.ImGuiKey_K,
            .l => c.ImGuiKey_L,
            .m => c.ImGuiKey_M,
            .n => c.ImGuiKey_N,
            .o => c.ImGuiKey_O,
            .p => c.ImGuiKey_P,
            .q => c.ImGuiKey_Q,
            .r => c.ImGuiKey_R,
            .s => c.ImGuiKey_S,
            .t => c.ImGuiKey_T,
            .u => c.ImGuiKey_U,
            .v => c.ImGuiKey_V,
            .w => c.ImGuiKey_W,
            .x => c.ImGuiKey_X,
            .y => c.ImGuiKey_Y,
            .z => c.ImGuiKey_Z,
            .@"0" => c.ImGuiKey_0,
            .@"1" => c.ImGuiKey_1,
            .@"2" => c.ImGuiKey_2,
            .@"3" => c.ImGuiKey_3,
            .@"4" => c.ImGuiKey_4,
            .@"5" => c.ImGuiKey_5,
            .@"6" => c.ImGuiKey_6,
            .@"7" => c.ImGuiKey_7,
            .@"8" => c.ImGuiKey_8,
            .@"9" => c.ImGuiKey_9,
            .f1 => c.ImGuiKey_F1,
            .f2 => c.ImGuiKey_F2,
            .f3 => c.ImGuiKey_F3,
            .f4 => c.ImGuiKey_F4,
            .f5 => c.ImGuiKey_F5,
            .f6 => c.ImGuiKey_F6,
            .f7 => c.ImGuiKey_F7,
            .f8 => c.ImGuiKey_F8,
            .f9 => c.ImGuiKey_F9,
            .f10 => c.ImGuiKey_F10,
            .f11 => c.ImGuiKey_F11,
            .f12 => c.ImGuiKey_F12,
            .comma => c.ImGuiKey_Comma,
            .period => c.ImGuiKey_Period,
            .slash => c.ImGuiKey_Slash,
            .backslash => c.ImGuiKey_Backslash,
            .semicolon => c.ImGuiKey_Semicolon,
            .apostrophe => c.ImGuiKey_Apostrophe,
            .minus => c.ImGuiKey_Minus,
            .equal => c.ImGuiKey_Equal,
            .left_bracket => c.ImGuiKey_LeftBracket,
            .right_bracket => c.ImGuiKey_RightBracket,
            .grave => c.ImGuiKey_GraveAccent,
            .enter => c.ImGuiKey_Enter,
            .escape => c.ImGuiKey_Escape,
            .tab => c.ImGuiKey_Tab,
            .space => c.ImGuiKey_Space,
            .backspace => c.ImGuiKey_Backspace,
            .delete => c.ImGuiKey_Delete,
            .insert => c.ImGuiKey_Insert,
            .home => c.ImGuiKey_Home,
            .end => c.ImGuiKey_End,
            .page_up => c.ImGuiKey_PageUp,
            .page_down => c.ImGuiKey_PageDown,
            .up => c.ImGuiKey_UpArrow,
            .down => c.ImGuiKey_DownArrow,
            .left => c.ImGuiKey_LeftArrow,
            .right => c.ImGuiKey_RightArrow,
        };
    }

    /// The key ImGui reports as `which`, if a chord can end in it.
    pub fn fromImgui(which: c.ImGuiKey) ?Key {
        for (std.enums.values(Key)) |key| {
            if (key.imgui() == which) return key;
        }
        return null;
    }
};

fn upper(comptime text: []const u8) []const u8 {
    comptime {
        var made: [text.len]u8 = undefined;
        for (&made, text) |*out, in| out.* = std.ascii.toUpper(in);
        const final = made;
        return &final;
    }
}

/// A key with the modifiers held down with it.
pub const Chord = struct {
    key: Key,
    /// Ctrl on Windows and Linux, Cmd on macOS.
    primary: bool = false,
    shift: bool = false,
    /// Alt, Option on macOS.
    alt: bool = false,
    /// The Windows key on Windows and Linux, Ctrl on macOS.
    secondary: bool = false,

    pub fn eql(a: Chord, b: Chord) bool {
        return a.key == b.key and a.primary == b.primary and a.shift == b.shift and a.alt == b.alt and a.secondary == b.secondary;
    }

    /// The chord as ImGui takes it.
    pub fn imgui(held: Chord) c.ImGuiKeyChord {
        var made: c.ImGuiKeyChord = held.key.imgui();
        if (held.primary) made |= c.ImGuiMod_Ctrl;
        if (held.shift) made |= c.ImGuiMod_Shift;
        if (held.alt) made |= c.ImGuiMod_Alt;
        if (held.secondary) made |= c.ImGuiMod_Super;
        return made;
    }

    /// The chord as `system` writes it: `Ctrl+Shift+P`, or `Ctrl+Cmd+Y` on macOS.
    pub fn written(held: Chord, system: System) Written {
        return .{ .chord = held, .system = system };
    }

    /// Reads a chord as `system` writes it, such as `Cmd+Option+F`, in any case.
    pub fn parse(text: []const u8, system: System) ?Chord {
        var made: Chord = .{ .key = .a };
        var parts = std.mem.splitScalar(u8, std.mem.trim(u8, text, " "), '+');
        var last: ?[]const u8 = null;
        while (parts.next()) |part| {
            if (last) |modifier| if (!made.setModifier(modifier, system)) return null;
            last = std.mem.trim(u8, part, " ");
        }
        made.key = Key.parse(last orelse return null) orelse return null;
        return made;
    }

    fn setModifier(made: *Chord, name: []const u8, system: System) bool {
        const flag: *bool = switch (system) {
            .windows_linux => if (std.ascii.eqlIgnoreCase(name, "Ctrl")) &made.primary else if (std.ascii.eqlIgnoreCase(name, "Alt")) &made.alt else if (std.ascii.eqlIgnoreCase(name, "Win") or std.ascii.eqlIgnoreCase(name, "Super")) &made.secondary else if (std.ascii.eqlIgnoreCase(name, "Shift")) &made.shift else return false,
            .macos => if (std.ascii.eqlIgnoreCase(name, "Cmd")) &made.primary else if (std.ascii.eqlIgnoreCase(name, "Option")) &made.alt else if (std.ascii.eqlIgnoreCase(name, "Ctrl")) &made.secondary else if (std.ascii.eqlIgnoreCase(name, "Shift")) &made.shift else return false,
        };
        if (flag.*) return false;
        flag.* = true;
        return true;
    }

    pub const Written = struct {
        chord: Chord,
        system: System,

        pub fn format(shown: Written, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            const held = shown.chord;
            switch (shown.system) {
                .windows_linux => {
                    if (held.secondary) try writer.writeAll("Win+");
                    if (held.primary) try writer.writeAll("Ctrl+");
                    if (held.alt) try writer.writeAll("Alt+");
                    if (held.shift) try writer.writeAll("Shift+");
                },
                .macos => {
                    if (held.secondary) try writer.writeAll("Ctrl+");
                    if (held.primary) try writer.writeAll("Cmd+");
                    if (held.alt) try writer.writeAll("Option+");
                    if (held.shift) try writer.writeAll("Shift+");
                },
            }
            try writer.writeAll(held.key.name());
        }
    };
};

/// The chord `text` names on `system`, read while the editor compiles, for the default keys.
pub fn chord(comptime text: []const u8, comptime system: System) Chord {
    const made = comptime blk: {
        @setEvalBranchQuota(20_000);
        break :blk Chord.parse(text, system) orelse @compileError("not a chord: " ++ text);
    };
    return made;
}

/// Whether `a` differs from `b`, the same action's keys on the other system, by more than Cmd for
/// Ctrl: the Keys page marks such an action.
pub fn differBeyondModifier(a: []const Chord, b: []const Chord) bool {
    if (a.len != b.len) return true;
    for (a, b) |one, other| if (!one.eql(other)) return true;
    return false;
}

test "chords read and write as each system writes them" {
    var buffer: [64]u8 = undefined;
    for ([_]struct { []const u8, System }{
        .{ "Ctrl+Shift+P", .windows_linux },
        .{ "Alt+F4", .windows_linux },
        .{ "Shift+F5", .windows_linux },
        .{ "Ctrl+/", .windows_linux },
        .{ "Ctrl+Cmd+Y", .macos },
        .{ "Cmd+Option+F", .macos },
        .{ "Cmd+\\", .macos },
        .{ "Cmd+.", .macos },
        .{ "F6", .macos },
    }) |case| {
        const read = Chord.parse(case[0], case[1]).?;
        try std.testing.expectEqualStrings(case[0], try std.fmt.bufPrint(&buffer, "{f}", .{read.written(case[1])}));
    }
    try std.testing.expect(Chord.parse("Cmd+B", .windows_linux) == null);
    try std.testing.expect(Chord.parse("Ctrl+Ctrl+B", .windows_linux) == null);
    try std.testing.expect(Chord.parse("Ctrl+Nothing", .windows_linux) == null);
}

test "Cmd on macOS is Ctrl on the others" {
    try std.testing.expect(chord("Cmd+B", .macos).eql(chord("Ctrl+B", .windows_linux)));
    try std.testing.expect(!differBeyondModifier(&.{chord("Cmd+B", .macos)}, &.{chord("Ctrl+B", .windows_linux)}));
    try std.testing.expect(differBeyondModifier(&.{chord("F6", .macos)}, &.{chord("F10", .windows_linux)}));
}
