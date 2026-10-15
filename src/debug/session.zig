//! The debugging session (design/debugger.md): the editor's side of the editor link while it
//! waits for a game or is linked to one. It takes the game's messages from the connection, matches
//! the mission the game plays with the open mission's build, keeps the game's breakpoints the
//! editor's, keeps where the script is held and the script's state, and runs the debugger's
//! actions: Continue, the steps, Run to cursor, Pause and Unlink.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const openreliant = @import("openreliant");
const link = openreliant.engine.link;

const game = @import("../game.zig");
const connection_mod = @import("../link/connection.zig");
const Connection = connection_mod.Connection;
const MessageKind = @import("../toasts.zig").Kind;

pub const LinkState = enum {
    /// No game linked, and none waited for.
    off,
    /// Connecting to a game as it starts, or waiting for one to listen.
    waiting,
    /// Linked: the game greeted the editor.
    linked,
};

/// Whether the mission the game plays is the open mission's build.
pub const Match = enum {
    /// The game plays the open mission built from its text as it is: the breakpoints hold.
    this_build,
    /// The game plays the open mission, built from other text: the next attempt reads the new
    /// build.
    older_build,
    /// The game plays another mission.
    other_mission,
    /// Not known yet: the game hasn't sent the mission's file, or the text doesn't build.
    unknown,
};

/// The open mission, as the session aims at it (`Session.aim`).
pub const Target = struct {
    /// Its number; null for none, or a mission without one.
    number: ?u32,
    /// The build of its text as it is, with the map of its script's statements; null where the
    /// text doesn't build.
    mission: ?game.Mission,
    /// Where its breakpoints hold the script (`breakpoints.offsets`).
    offsets: []const u32,
};

/// The game's greeting.
pub const Greeting = struct {
    /// The game's name, its script's dialect and OpenReliant's version, in `text`.
    game: []const u8,
    vm: []const u8,
    openreliant: []const u8,
    /// The text, the session's.
    text: []const u8,
};

/// The mission the game plays.
pub const Playing = struct {
    number: u32,
    /// Its file's name, such as `mission90.dte`, the session's.
    file: []const u8,
    /// Its file as the game sent it, the session's; null until it comes.
    image: ?[]const u8 = null,
    match: Match = .unknown,
};

/// Where the game holds the script.
pub const Held = struct {
    /// The offset in the script of the instruction it holds before.
    offset: u32,
};

/// The script's state as the game sent it, with its text, in an arena of its own.
pub const Snapshot = struct {
    arena: std.heap.ArenaAllocator,
    state: link.State,

    /// The state in `payload`, which it copies; null where it can't be read.
    fn read(gpa: Allocator, payload: []const u8) ?Snapshot {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        // The state's names are its text's.
        const text = arena.allocator().dupe(u8, payload) catch {
            arena.deinit();
            return null;
        };
        const state = link.State.read(arena.allocator(), text) catch {
            arena.deinit();
            return null;
        };
        return .{ .arena = arena, .state = state };
    }

    fn free(snapshot: *?Snapshot) void {
        if (snapshot.*) |*kept| kept.arena.deinit();
        snapshot.* = null;
    }
};

/// A line for Output.
pub const Note = struct {
    kind: MessageKind,
    text: []const u8,
};

/// How often the session asks for the state while the script runs.
pub const StateRate = enum {
    off,
    one_hz,
    four_hz,

    /// The time between two asks, in milliseconds; null for never.
    pub fn interval(rate: StateRate) ?u64 {
        return switch (rate) {
            .off => null,
            .one_hz => 1000,
            .four_hz => 250,
        };
    }
};

pub const Session = struct {
    gpa: Allocator,
    profile: *const game.Profile,
    connection: Connection,
    link_state: LinkState = .off,
    /// The port the session connects to.
    port: u16 = link.default_port,
    greeting: ?Greeting = null,
    playing: ?Playing = null,
    held: ?Held = null,
    /// Whether the editor paused the mission (run control 0).
    paused: bool = false,
    first_finished: bool = false,
    /// The script's state as the game last sent it.
    state: ?Snapshot = null,
    /// The state at the last hold, and at the hold before it, for the values that changed since
    /// the last hold; and whether the next state is a new hold's.
    hold_state: ?Snapshot = null,
    earlier: ?Snapshot = null,
    hold_state_due: bool = false,
    /// When the editor last asked for the state, and whether an answer is due.
    asked_ms: u64 = 0,
    asking: bool = false,
    /// The offset that Run to cursor flags until the next hold.
    run_to: ?u32 = null,
    /// The open mission (`aim`): its number, the build of its text and its breakpoints' offsets,
    /// the session's.
    target_number: ?u32 = null,
    target_file: ?[]const u8 = null,
    target_statements: []const game.Statement = &.{},
    target_offsets: []const u32 = &.{},
    /// The generation of the flags armed for the task to answer the next mission's file with.
    armed: u64 = 0,
    /// The lines for Output that the editor hasn't taken (`takeNotes`), in their arena.
    notes: std.ArrayList(Note) = .empty,
    notes_arena: std.heap.ArenaAllocator,
    /// Set as the game newly holds the script, for the editor to show the line.
    revealed: bool = false,

    pub fn init(gpa: Allocator, io: Io, profile: *const game.Profile, wake: *const fn () void) Session {
        return .{
            .gpa = gpa,
            .profile = profile,
            .connection = .init(gpa, io, profile, wake),
            .notes_arena = .init(gpa),
        };
    }

    pub fn deinit(session: *Session) void {
        session.connection.deinit();
        session.forgetLink();
        session.freeTarget();
        session.notes_arena.deinit();
    }

    // The link.

    /// Connects to the game at `port`, with `patience`: while it starts, or until it listens.
    pub fn connect(session: *Session, port: u16, patience: connection_mod.Patience) void {
        session.connection.close();
        session.forgetLink();
        session.port = port;
        session.connection.open(port, patience) catch |err| {
            session.note(.failure, "Can't link: {t}", .{err});
            return;
        };
        session.link_state = .waiting;
        session.armTask();
    }

    /// Unlinks: the link closes, and the game lets the script run on. The breakpoints stay in the
    /// editor.
    pub fn unlink(session: *Session) void {
        if (session.link_state == .off) return;
        const was_linked = session.link_state == .linked;
        session.connection.close();
        session.forgetLink();
        session.note(.info, "{s}", .{if (was_linked) "Unlinked" else "Stopped waiting"});
    }

    /// Takes what the connection heard, and asks for the state while the script runs every
    /// `rate`, `now_ms` being the time in milliseconds.
    pub fn update(session: *Session, now_ms: u64, rate: StateRate) void {
        while (session.connection.next()) |event| {
            defer session.connection.release(event);
            session.handle(event, now_ms);
        }
        if (session.held == null and session.playing != null and session.link_state == .linked and !session.asking) {
            if (rate.interval()) |interval| if (now_ms -% session.asked_ms >= interval) session.askState(now_ms);
        }
    }

    fn handle(session: *Session, event: connection_mod.Event, now_ms: u64) void {
        switch (event) {
            .connected => session.note(.info, "Connected · 127.0.0.1:{d}", .{session.port}),
            .gave_up => {
                session.forgetLink();
                session.note(.failure, "No game at 127.0.0.1:{d}", .{session.port});
            },
            .disconnected => {
                session.forgetLink();
                session.note(.info, "Game closed · unlinked", .{});
            },
            .message => |message| session.receive(message, now_ms),
        }
    }

    fn receive(session: *Session, message: connection_mod.Event.Message, now_ms: u64) void {
        const tags = session.profile.link;
        if (link.Own.of(message.tag)) |own| return switch (own) {
            .hello => session.greet(message.payload),
            .mission_started => session.missionStarted(message.payload),
            .mission_file => session.missionFile(message.payload, message.answered),
            .mission_ended => {
                if (session.playing) |playing| session.note(.info, "Mission {d} ended", .{playing.number});
                session.forgetMission();
            },
            .state => session.takeState(message.payload),
            // What only the editor sends.
            .get_mission, .get_state, .console_line, _ => {},
        };
        if (message.tag == tags.stopped and message.payload.len >= @sizeOf(u32)) {
            session.hold(std.mem.readInt(u32, message.payload[0..4], .little), now_ms);
        } else if (message.tag == tags.first_finished and message.payload.len >= @sizeOf(u32)) {
            session.first_finished = std.mem.readInt(u32, message.payload[0..4], .little) != 0;
        }
    }

    fn greet(session: *Session, payload: []const u8) void {
        const hello = link.Hello.read(payload) catch {
            session.note(.failure, "Unreadable Hello · unlinked", .{});
            return session.closeLink();
        };
        if (game.named(hello.game.name) != session.profile) {
            session.note(.failure, "No profile for {s} · unlinked", .{hello.game.name});
            return session.closeLink();
        }
        // Each version of the protocol only adds messages and keys, which a reader passes over, so
        // a newer game links as it is. An older one lacks what the editor reads.
        if (hello.protocol < link.protocol_version) {
            session.note(.failure, "Link protocol {d}, editor's {d} · update OpenReliant", .{ hello.protocol, link.protocol_version });
        }
        const text = std.mem.concat(session.gpa, u8, &.{ hello.game.name, hello.game.vm, hello.openreliant }) catch return;
        const vm_end = hello.game.name.len + hello.game.vm.len;
        const greeting: Greeting = .{ .game = text[0..hello.game.name.len], .vm = text[hello.game.name.len..vm_end], .openreliant = text[vm_end..], .text = text };
        session.freeGreeting();
        session.greeting = greeting;
        session.link_state = .linked;
        session.note(.success, "Linked · {s} · OpenReliant {s}", .{ greeting.game, greeting.openreliant });
    }

    fn missionStarted(session: *Session, payload: []const u8) void {
        session.forgetMission();
        const started = link.MissionStarted.read(payload) catch return;
        const file = session.gpa.dupe(u8, started.file) catch return;
        session.playing = .{ .number = started.number, .file = file };
        session.note(.info, "Mission {d} started · {s}", .{ started.number, file });
    }

    /// The mission's file, which the task answered with the flags armed for it, `answered` their
    /// generation. Where the game has the mission's build and other flags than the latest, it's
    /// sent the latest.
    fn missionFile(session: *Session, file: []const u8, answered: ?u64) void {
        const playing = &(session.playing orelse return);
        const image = session.gpa.dupe(u8, file) catch return;
        if (playing.image) |old| session.gpa.free(old);
        playing.image = image;
        session.matchMission();
        switch (playing.match) {
            .this_build => {
                if (answered != session.armed) session.sendFlags();
                session.note(.info, "Mission {d} · this build · breakpoints set", .{playing.number});
            },
            .older_build => session.note(.info, "Mission {d} · older build · rebuild, restart mission", .{playing.number}),
            .other_mission => session.note(.info, "Mission {d} · other mission · breakpoints wait", .{playing.number}),
            .unknown => {},
        }
    }

    fn hold(session: *Session, offset: u32, now_ms: u64) void {
        session.held = .{ .offset = offset };
        session.revealed = true;
        session.hold_state_due = true;
        if (session.run_to != null) {
            session.run_to = null;
            session.sendFlags();
        }
        session.askState(now_ms);
        if (session.heldStatement()) |statement| {
            session.note(.info, "Held · line {d} · offset {d}", .{ statement.at.line + 1, offset });
        } else session.note(.info, "Held · offset {d}", .{offset});
    }

    fn takeState(session: *Session, payload: []const u8) void {
        session.asking = false;
        const fresh = Snapshot.read(session.gpa, payload) orelse return;
        if (session.hold_state_due) {
            // The first state of a new hold: the last hold's becomes the one before.
            session.hold_state_due = false;
            if (Snapshot.read(session.gpa, payload)) |copy| {
                Snapshot.free(&session.earlier);
                session.earlier = session.hold_state;
                session.hold_state = copy;
            }
        }
        Snapshot.free(&session.state);
        session.state = fresh;
        session.paused = fresh.state.paused;
        session.first_finished = fresh.state.first_finished;
    }

    /// Asks the game for the script's state.
    fn askState(session: *Session, now_ms: u64) void {
        if (!session.connection.send(@backingInt(link.Own.get_state), "")) return;
        session.asking = true;
        session.asked_ms = now_ms;
    }

    // The open mission.

    /// Aims the session at `target`, the open mission: the task answers its file with its
    /// breakpoints, and a game that plays its build gets them now.
    pub fn aim(session: *Session, target: Target) void {
        session.freeTarget();
        session.target_number = target.number;
        if (target.mission) |mission| {
            session.target_file = session.gpa.dupe(u8, mission.file) catch null;
            session.target_statements = session.gpa.dupe(game.Statement, mission.statements) catch &.{};
        }
        session.target_offsets = session.gpa.dupe(u32, target.offsets) catch &.{};
        session.armTask();
        const was = if (session.playing) |playing| playing.match else .unknown;
        session.matchMission();
        const now = if (session.playing) |playing| playing.match else .unknown;
        if (now == .this_build) session.sendFlags();
        if (was == .this_build and now != .this_build) session.note(.info, "Script changed · rebuild, restart mission", .{});
    }

    /// Sets what the task answers the next mission's file with.
    fn armTask(session: *Session) void {
        if (session.link_state == .off) return;
        session.armed = session.connection.arm(session.target_number, session.target_file orelse &.{}, session.target_offsets) catch return;
    }

    fn matchMission(session: *Session) void {
        const playing = &(session.playing orelse return);
        playing.match = match: {
            const image = playing.image orelse break :match .unknown;
            const number = session.target_number orelse break :match .other_mission;
            if (number != playing.number) break :match .other_mission;
            const built = session.target_file orelse break :match .unknown;
            break :match if (session.profile.sameScript(built, image)) .this_build else .older_build;
        };
    }

    /// Sends the game the breakpoints' flags, with Run to cursor's, where it plays the open
    /// mission's build.
    fn sendFlags(session: *Session) void {
        const playing = session.playing orelse return;
        if (playing.match != .this_build) return;
        const image = playing.image orelse return;
        var arena: std.heap.ArenaAllocator = .init(session.gpa);
        defer arena.deinit();
        var offsets: std.ArrayList(u32) = .empty;
        offsets.appendSlice(arena.allocator(), session.target_offsets) catch return;
        if (session.run_to) |offset| offsets.append(arena.allocator(), offset) catch return;
        const flags = session.profile.scriptFlags(arena.allocator(), image, offsets.items) catch return orelse return;
        _ = session.connection.send(session.profile.link.script_flags, flags);
    }

    // The actions.

    /// Lets the script go on with `control`: on to the next breakpoint, or a step.
    pub fn release(session: *Session, control: game.Control) void {
        if (!session.sendControl(control)) return;
        session.held = null;
    }

    /// Lets the held script run on to `offset`, which holds it until the next hold.
    pub fn runTo(session: *Session, offset: u32) void {
        session.run_to = offset;
        session.sendFlags();
        session.release(.run_on);
    }

    /// Pauses the whole mission, or lets it go on.
    pub fn togglePause(session: *Session) void {
        if (!session.sendControl(.{ .pause = !session.paused })) return;
        session.paused = !session.paused;
        session.note(.info, "{s}", .{if (session.paused) "Mission paused" else "Mission resumed"});
    }

    fn sendControl(session: *Session, control: game.Control) bool {
        const payload = session.profile.link.runControl(control);
        return session.connection.send(session.profile.link.run_control, &payload);
    }

    // What the editor shows.

    /// Whether the game plays a mission, linked.
    pub fn playingMission(session: *const Session) bool {
        return session.link_state == .linked and session.playing != null;
    }

    /// Whether the game plays the open mission's build, whose map gives the lines.
    pub fn mapped(session: *const Session) bool {
        const playing = session.playing orelse return false;
        return playing.match == .this_build;
    }

    /// The statement the game holds the script before, where the map gives it.
    pub fn heldStatement(session: *const Session) ?game.Statement {
        const held = session.held orelse return null;
        return session.statementAt(held.offset);
    }

    /// The statement at `offset`, where the game plays the open mission's build.
    pub fn statementAt(session: *const Session, offset: u32) ?game.Statement {
        if (!session.mapped()) return null;
        const mission: game.Mission = .{ .file = session.target_file orelse return null, .statements = session.target_statements };
        return mission.statementAt(offset);
    }

    /// The line the statement holding `offset` is on, for a thread's place: the statement that
    /// ends there, or else the last one before it.
    pub fn lineOf(session: *const Session, offset: u32) ?u32 {
        if (!session.mapped()) return null;
        var line: ?u32 = null;
        for (session.target_statements) |statement| {
            if (statement.offset > offset) break;
            line = statement.at.line;
        }
        return line;
    }

    /// The state the values are compared with, for the ones that changed since the last hold:
    /// while held, the hold before; while the script runs, the last hold.
    fn lastHoldState(session: *const Session) ?link.State {
        const kept = if (session.held != null) session.earlier else session.hold_state;
        return if (kept) |snapshot| snapshot.state else null;
    }

    /// Whether global `index` changed since the last hold.
    pub fn globalChanged(session: *const Session, index: usize) bool {
        const now = session.state orelse return false;
        const before = session.lastHoldState() orelse return false;
        if (index >= now.state.globals.len or index >= before.globals.len) return false;
        return now.state.globals[index] != before.globals[index];
    }

    /// Whether the game's variable `name` changed since the last hold.
    pub fn variableChanged(session: *const Session, name: []const u8) bool {
        const now = session.state orelse return false;
        const before = session.lastHoldState() orelse return false;
        return (now.state.variable(name) orelse 0) != (before.variable(name) orelse 0);
    }

    /// Takes the lines for Output since the last time, valid until the next call.
    pub fn takeNotes(session: *Session) []const Note {
        const taken = session.notes.items;
        session.notes = .empty;
        return taken;
    }

    /// Lets go of the notes taken.
    pub fn freeNotes(session: *Session) void {
        _ = session.notes_arena.reset(.retain_capacity);
    }

    /// Whether the game newly holds the script since the last call.
    pub fn takeRevealed(session: *Session) bool {
        defer session.revealed = false;
        return session.revealed;
    }

    fn note(session: *Session, kind: MessageKind, comptime format: []const u8, args: anytype) void {
        const arena = session.notes_arena.allocator();
        const text = std.fmt.allocPrint(arena, format, args) catch return;
        session.notes.append(arena, .{ .kind = kind, .text = text }) catch {};
    }

    // Forgetting.

    fn closeLink(session: *Session) void {
        session.connection.close();
        session.forgetLink();
    }

    fn forgetLink(session: *Session) void {
        session.link_state = .off;
        session.freeGreeting();
        session.forgetMission();
    }

    fn forgetMission(session: *Session) void {
        if (session.playing) |playing| {
            session.gpa.free(playing.file);
            if (playing.image) |image| session.gpa.free(image);
        }
        session.playing = null;
        session.held = null;
        session.paused = false;
        session.first_finished = false;
        session.run_to = null;
        session.asking = false;
        session.hold_state_due = false;
        Snapshot.free(&session.state);
        Snapshot.free(&session.hold_state);
        Snapshot.free(&session.earlier);
    }

    fn freeGreeting(session: *Session) void {
        const greeting = session.greeting orelse return;
        session.gpa.free(greeting.text);
        session.greeting = null;
    }

    fn freeTarget(session: *Session) void {
        if (session.target_file) |file| session.gpa.free(file);
        session.gpa.free(session.target_statements);
        session.gpa.free(session.target_offsets);
        session.target_file = null;
        session.target_statements = &.{};
        session.target_offsets = &.{};
    }
};

/// A game made of messages, for the tests: it listens on a free port of this computer's own
/// address as OpenReliant does, and writes and reads the link's messages as the game does.
const FakeGame = struct {
    io: Io,
    listener: Io.net.Server,
    stream: ?Io.net.Stream = null,
    write_buffer: [4096]u8 = undefined,
    read_buffer: [64 * 1024]u8 = undefined,
    writer: Io.net.Stream.Writer = undefined,
    reader: Io.net.Stream.Reader = undefined,

    fn listen(game_io: Io) !FakeGame {
        const address: Io.net.IpAddress = .{ .ip4 = .loopback(0) };
        return .{ .io = game_io, .listener = try address.listen(game_io, .{ .reuse_address = true }) };
    }

    fn deinit(fake: *FakeGame) void {
        if (fake.stream) |stream| stream.close(fake.io);
        fake.listener.deinit(fake.io);
    }

    fn port(fake: *const FakeGame) u16 {
        return fake.listener.socket.address.getPort();
    }

    /// Takes the editor's connection. The game mustn't move after.
    fn accept(fake: *FakeGame) !void {
        const stream = try fake.listener.accept(fake.io);
        fake.stream = stream;
        fake.writer = stream.writer(fake.io, &fake.write_buffer);
        fake.reader = stream.reader(fake.io, &fake.read_buffer);
    }

    fn send(fake: *FakeGame, tag: u16, payload: []const u8) !void {
        try link.writeMessage(&fake.writer.interface, tag, payload);
        try fake.writer.interface.flush();
    }

    fn sendRecord(fake: *FakeGame, tag: link.Own, record: anytype) !void {
        var buffer: [1024]u8 = undefined;
        var text: Io.Writer = .fixed(&buffer);
        try record.write(&text);
        try fake.send(@backingInt(tag), text.buffered());
    }

    fn sendWord(fake: *FakeGame, tag: u16, word: u32) !void {
        var payload: [4]u8 = undefined;
        std.mem.writeInt(u32, &payload, word, .little);
        try fake.send(tag, &payload);
    }

    /// The editor's next message, which the caller frees.
    fn hear(fake: *FakeGame, gpa: Allocator) !link.Message {
        return link.readMessage(&fake.reader.interface, gpa);
    }
};

/// Runs the session's frames until `done` says what the test waits for, for two seconds at most.
fn settle(session: *Session, io: Io, comptime done: fn (*const Session) bool) !void {
    var frames: u32 = 0;
    while (frames < 2000) : (frames += 1) {
        session.update(frames, .off);
        if (done(session)) return;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    return error.TestTimedOut;
}

test "a session with a game made of messages" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const profile = &game.starlancer.profile;
    const source = game.starlancer.first_mission;
    const mission = (try profile.build(arena, source)).mission;
    const outline = try profile.outline(arena, source);
    // A breakpoint on the Sabres' attack, line 46 counting from 1.
    const attack = mission.statementOn(45).?;
    const offsets = try @import("breakpoints.zig").offsets(arena, mission, outline, &.{45});

    var fake: FakeGame = try .listen(io);
    defer fake.deinit();
    var session: Session = .init(gpa, io, profile, connection_mod.testing.noWake);
    defer session.deinit();
    session.aim(.{ .number = 90, .mission = mission, .offsets = offsets });
    session.connect(fake.port(), .{ .starting = 5000 });
    try std.testing.expectEqual(LinkState.waiting, session.link_state);
    try fake.accept();

    // The game greets the editor, starts mission 90 and sends its file, as it plays this build.
    try fake.sendRecord(.hello, link.Hello{ .protocol = link.protocol_version, .openreliant = "0.15.0", .game = .{ .name = "StarLancer", .vm = "starlancer" } });
    try fake.sendRecord(.mission_started, link.MissionStarted{ .number = 90, .file = "mission90.dte" });
    try fake.send(@backingInt(link.Own.mission_file), mission.file);

    // The editor's task answers the file at once with the breakpoint's flag.
    const flags = try fake.hear(gpa);
    defer gpa.free(flags.payload);
    try std.testing.expectEqual(profile.link.script_flags, flags.tag);
    try std.testing.expectEqual(1, std.mem.count(u8, flags.payload, &.{1}));
    try std.testing.expectEqual(1, flags.payload[attack.offset]);

    try settle(&session, io, struct {
        fn done(s: *const Session) bool {
            return s.mapped();
        }
    }.done);
    try std.testing.expectEqual(LinkState.linked, session.link_state);
    try std.testing.expectEqualStrings("0.15.0", session.greeting.?.openreliant);

    // The game holds the script before the attack, and the editor asks for the state.
    try fake.sendWord(profile.link.stopped, attack.offset);
    try settle(&session, io, struct {
        fn done(s: *const Session) bool {
            return s.held != null;
        }
    }.done);
    try std.testing.expectEqual(45, session.heldStatement().?.at.line);
    try std.testing.expect(session.takeRevealed());
    const asked = try fake.hear(gpa);
    defer gpa.free(asked.payload);
    try std.testing.expectEqual(@backingInt(link.Own.get_state), asked.tag);

    // The state comes, with the thread held on the attack's line.
    const thread: link.State.Thread = .{ .slot = 0, .at = attack.offset, .depth = 0, .wake = 0, .interrupted = false, .trigger = 0 };
    try fake.sendRecord(.state, link.State{ .clock = 41, .hold = .held, .step = .none, .paused = false, .first_finished = true, .threads = &.{thread}, .globals = &.{}, .variables = &.{.{ .name = "mission_success", .value = 0 }} });
    try settle(&session, io, struct {
        fn done(s: *const Session) bool {
            return s.state != null;
        }
    }.done);
    try std.testing.expectEqual(41, session.state.?.state.clock);
    try std.testing.expectEqual(45, session.lineOf(attack.offset).?);

    // Step over sends run control 3, and the script runs on.
    session.release(.step_over);
    try std.testing.expectEqual(null, session.held);
    const step = try fake.hear(gpa);
    defer gpa.free(step.payload);
    try std.testing.expectEqual(profile.link.run_control, step.tag);
    try std.testing.expectEqualSlices(u8, &profile.link.runControl(.step_over), step.payload);

    // A breakpoint taken away goes to the game at once, as flags without it.
    session.aim(.{ .number = 90, .mission = mission, .offsets = &.{} });
    const cleared = try fake.hear(gpa);
    defer gpa.free(cleared.payload);
    try std.testing.expectEqual(profile.link.script_flags, cleared.tag);
    try std.testing.expectEqual(0, std.mem.count(u8, cleared.payload, &.{1}));

    // Text that builds another script: the game plays an older build.
    const changed = try std.mem.replaceOwned(u8, arena, source, "Wait(5)", "Wait(6)");
    session.aim(.{ .number = 90, .mission = (try profile.build(arena, changed)).mission, .offsets = &.{} });
    try std.testing.expectEqual(Match.older_build, session.playing.?.match);
    try std.testing.expectEqual(null, session.statementAt(attack.offset));

    // Unlinking closes the link.
    session.unlink();
    try std.testing.expectEqual(LinkState.off, session.link_state);
    try std.testing.expectError(error.EndOfStream, fake.hear(gpa));
    const notes = session.takeNotes();
    try std.testing.expect(notes.len > 0);
    session.freeNotes();
}

test "the editor answers a mission it has no build of with no flags" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const profile = &game.starlancer.profile;
    const mission = (try profile.build(arena, game.starlancer.first_mission)).mission;

    var fake: FakeGame = try .listen(io);
    defer fake.deinit();
    var session: Session = .init(gpa, io, profile, connection_mod.testing.noWake);
    defer session.deinit();
    // The editor has mission 91 open, and the game plays mission 90.
    session.aim(.{ .number = 91, .mission = mission, .offsets = &.{mission.statementOn(45).?.offset} });
    session.connect(fake.port(), .waiting);
    try fake.accept();
    try fake.sendRecord(.hello, link.Hello{ .protocol = link.protocol_version, .openreliant = "0.15.0", .game = .{ .name = "StarLancer", .vm = "starlancer" } });
    try fake.sendRecord(.mission_started, link.MissionStarted{ .number = 90, .file = "mission90.dte" });
    try fake.send(@backingInt(link.Own.mission_file), mission.file);
    const flags = try fake.hear(gpa);
    defer gpa.free(flags.payload);
    try std.testing.expectEqual(profile.link.script_flags, flags.tag);
    try std.testing.expectEqual(0, std.mem.count(u8, flags.payload, &.{1}));
    try settle(&session, io, struct {
        fn done(s: *const Session) bool {
            return if (s.playing) |playing| playing.match != .unknown else false;
        }
    }.done);
    try std.testing.expectEqual(Match.other_mission, session.playing.?.match);

    // The game goes: the link closes by itself.
    fake.stream.?.close(io);
    fake.stream = null;
    try settle(&session, io, struct {
        fn done(s: *const Session) bool {
            return s.link_state == .off;
        }
    }.done);
    session.freeNotes();
}

test "a newer game links quietly, and an older one says to update" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    for ([_]struct { protocol: u32, failures: usize }{
        .{ .protocol = link.protocol_version + 1, .failures = 0 },
        .{ .protocol = link.protocol_version - 1, .failures = 1 },
    }) |case| {
        var fake: FakeGame = try .listen(io);
        defer fake.deinit();
        var session: Session = .init(gpa, io, &game.starlancer.profile, connection_mod.testing.noWake);
        defer session.deinit();
        session.connect(fake.port(), .waiting);
        try fake.accept();
        try fake.sendRecord(.hello, link.Hello{ .protocol = case.protocol, .openreliant = "9.9.9", .game = .{ .name = "StarLancer", .vm = "starlancer" } });
        try settle(&session, io, struct {
            fn done(s: *const Session) bool {
                return s.link_state == .linked;
            }
        }.done);
        var failures: usize = 0;
        for (session.takeNotes()) |note| failures += @intFromBool(note.kind == .failure);
        try std.testing.expectEqual(case.failures, failures);
        session.freeNotes();
    }
}

test "a game that isn't there: the editor gives up" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    // A port that nothing listens at: one the system gave and took back.
    var fake: FakeGame = try .listen(io);
    const free_port = fake.port();
    fake.deinit();
    var session: Session = .init(gpa, io, &game.starlancer.profile, connection_mod.testing.noWake);
    defer session.deinit();
    session.connect(free_port, .{ .starting = 50 });
    try settle(&session, io, struct {
        fn done(s: *const Session) bool {
            return s.link_state == .off;
        }
    }.done);
    try std.testing.expectEqual(MessageKind.failure, session.takeNotes()[0].kind);
    session.freeNotes();
}
