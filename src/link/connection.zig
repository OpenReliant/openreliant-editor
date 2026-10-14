//! The editor link's connection to OpenReliant (design/debugger.md): a TCP connection to a game
//! started with `--editor-link`, on this computer's own address. A task of its own connects,
//! trying again while the game starts, and reads the game's messages into a queue that the frame
//! takes from. The task answers the mission's file itself with the breakpoints' flags, as the frame
//! last armed them, since the game holds the mission's start until they come: a busy frame, or a
//! window waiting for events, never holds up the game.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const openreliant = @import("openreliant");
const link = openreliant.engine.link;

const game = @import("../game.zig");

/// How long the task waits before it tries to connect again.
const retry_ms = 100;

/// How many bytes a read or a write of the connection takes at most.
const read_size = 16 * 1024;
const write_size = 4096;

/// How long the connection keeps trying to connect.
pub const Patience = union(enum) {
    /// For a game being started: this many milliseconds.
    starting: i64,
    /// Until a game started some other way listens, or the editor lets it go.
    waiting,
};

/// What the task heard, in order, for the frame.
pub const Event = union(enum) {
    /// A game took the connection.
    connected,
    /// A message from the game. Its payload is the connection's until the frame lets it go
    /// (`Connection.release`).
    message: Message,
    /// The connection ended: the game went.
    disconnected,
    /// No game took the connection in time.
    gave_up,

    pub const Message = struct {
        tag: u16,
        payload: []const u8,
        /// For a mission's file, the generation of the flags the task answered it with (`arm`),
        /// where they were armed for it.
        answered: ?u64 = null,
    };
};

pub const Connection = struct {
    gpa: Allocator,
    io: Io,
    profile: *const game.Profile,
    /// Called from the task as an event comes, to wake a window that waits for events.
    wake: *const fn () void,
    /// Guards what follows, which the task and the frame share.
    mutex: Io.Mutex = .init,
    /// The game's connection; null while none is.
    stream: ?Io.net.Stream = null,
    /// What the task heard that the frame hasn't taken.
    events: std.ArrayList(Event) = .empty,
    /// Set as the editor lets the connection go, which ends the task.
    stopping: bool = false,
    /// The flags the task answers the mission's file with.
    armed: Armed = .{},
    /// Held while a message is written, so that the task's and the frame's messages don't mix,
    /// and the task waits for it before it closes the connection.
    writing: Io.Mutex = .init,
    task: Io.Group = .init,

    /// What the task answers the mission's file with: the flags of `offsets` where the game plays
    /// mission `number` with the script of `mission`, and no flags otherwise.
    const Armed = struct {
        number: ?u32 = null,
        mission: []u8 = &.{},
        offsets: []u32 = &.{},
        /// Counts the times the frame armed the task, so that the frame can tell whether the game
        /// has the flags it armed last.
        generation: u64 = 0,
    };

    pub fn init(gpa: Allocator, io: Io, profile: *const game.Profile, wake: *const fn () void) Connection {
        return .{ .gpa = gpa, .io = io, .profile = profile, .wake = wake };
    }

    pub fn deinit(connection: *Connection) void {
        connection.close();
        connection.gpa.free(connection.armed.mission);
        connection.gpa.free(connection.armed.offsets);
    }

    /// Starts the task, which connects to a game at `port` with `patience`. The connection mustn't
    /// move while it runs.
    pub fn open(connection: *Connection, port: u16, patience: Patience) Io.ConcurrentError!void {
        connection.close();
        connection.stopping = false;
        try connection.task.concurrent(connection.io, run, .{ connection, port, patience });
    }

    /// Ends the task and the connection, and forgets what the frame hasn't taken. The game's
    /// connection shut down ends the task's read, and its next try to connect finds it stopping.
    pub fn close(connection: *Connection) void {
        const io = connection.io;
        connection.mutex.lockUncancelable(io);
        connection.stopping = true;
        if (connection.stream) |stream| stream.shutdown(io, .both) catch {};
        connection.mutex.unlock(io);
        connection.task.await(io) catch {};
        for (connection.events.items) |event| connection.release(event);
        connection.events.clearAndFree(connection.gpa);
    }

    /// The next thing the task heard, which the frame lets go once it's done with it (`release`).
    pub fn next(connection: *Connection) ?Event {
        connection.mutex.lockUncancelable(connection.io);
        defer connection.mutex.unlock(connection.io);
        if (connection.events.items.len == 0) return null;
        return connection.events.orderedRemove(0);
    }

    pub fn release(connection: *Connection, event: Event) void {
        switch (event) {
            .message => |message| connection.gpa.free(message.payload),
            .connected, .disconnected, .gave_up => {},
        }
    }

    /// Sends a message to the game; false where none is connected or the connection fails.
    pub fn send(connection: *Connection, tag: u16, payload: []const u8) bool {
        const io = connection.io;
        connection.writing.lockUncancelable(io);
        defer connection.writing.unlock(io);
        connection.mutex.lockUncancelable(io);
        const current = connection.stream;
        connection.mutex.unlock(io);
        const stream = current orelse return false;
        var buffer: [write_size]u8 = undefined;
        var writer = stream.writer(io, &buffer);
        link.writeMessage(&writer.interface, tag, payload) catch return false;
        writer.interface.flush() catch return false;
        return true;
    }

    /// Sets what the task answers the next mission's file with: the flags of `offsets` where the
    /// game plays mission `number` with the script of `mission`. Gives the generation armed.
    pub fn arm(connection: *Connection, number: ?u32, mission: []const u8, offsets: []const u32) Allocator.Error!u64 {
        const mission_copy = try connection.gpa.dupe(u8, mission);
        errdefer connection.gpa.free(mission_copy);
        const offsets_copy = try connection.gpa.dupe(u32, offsets);
        connection.mutex.lockUncancelable(connection.io);
        defer connection.mutex.unlock(connection.io);
        const armed = &connection.armed;
        connection.gpa.free(armed.mission);
        connection.gpa.free(armed.offsets);
        armed.* = .{ .number = number, .mission = mission_copy, .offsets = offsets_copy, .generation = armed.generation + 1 };
        return armed.generation;
    }

    /// The task: connects, with `patience`, reads the game's messages until it goes, and stops.
    /// The editor never links again by itself.
    fn run(connection: *Connection, port: u16, patience: Patience) Io.Cancelable!void {
        const io = connection.io;
        const address: Io.net.IpAddress = .{ .ip4 = .loopback(port) };
        const started = Io.Clock.awake.now(io);
        const stream = while (true) {
            if (connection.isStopping()) return;
            if (address.connect(io, .{ .mode = .stream })) |stream| break stream else |_| {}
            switch (patience) {
                .starting => |limit_ms| if (started.durationTo(Io.Clock.awake.now(io)).toMilliseconds() >= limit_ms) {
                    connection.push(.gave_up);
                    return;
                },
                .waiting => {},
            }
            try io.sleep(.fromMilliseconds(retry_ms), .awake);
        };
        if (!connection.attach(stream)) return stream.close(io);
        connection.push(.connected);
        connection.read(stream);
        connection.detach(stream);
        if (!connection.isStopping()) connection.push(.disconnected);
    }

    fn isStopping(connection: *Connection) bool {
        connection.mutex.lockUncancelable(connection.io);
        defer connection.mutex.unlock(connection.io);
        return connection.stopping;
    }

    /// Takes `stream` as the game's connection; false as the editor lets it go.
    fn attach(connection: *Connection, stream: Io.net.Stream) bool {
        connection.mutex.lockUncancelable(connection.io);
        defer connection.mutex.unlock(connection.io);
        if (connection.stopping) return false;
        connection.stream = stream;
        return true;
    }

    /// Lets the game's connection go once nothing writes to it, and closes it.
    fn detach(connection: *Connection, stream: Io.net.Stream) void {
        const io = connection.io;
        connection.writing.lockUncancelable(io);
        defer connection.writing.unlock(io);
        connection.mutex.lockUncancelable(io);
        connection.stream = null;
        connection.mutex.unlock(io);
        stream.close(io);
    }

    /// Reads the game's messages until it goes, answering each mission's file.
    fn read(connection: *Connection, stream: Io.net.Stream) void {
        var buffer: [read_size]u8 = undefined;
        var reader = stream.reader(connection.io, &buffer);
        // The mission whose file comes next, as `Mission started` gives it.
        var number: ?u32 = null;
        while (true) {
            const message = link.readMessage(&reader.interface, connection.gpa) catch return;
            var answered: ?u64 = null;
            if (link.Own.of(message.tag)) |own| switch (own) {
                .mission_started => number = if (link.MissionStarted.read(message.payload)) |started| started.number else |_| null,
                .mission_file => answered = connection.answer(number, message.payload),
                else => {},
            };
            connection.push(.{ .message = .{ .tag = message.tag, .payload = message.payload, .answered = answered } });
        }
    }

    /// Sends the game the script's flags for mission `number`'s file `file`, which the game holds
    /// the mission's start for: the armed flags where they were armed for its script, and no flags
    /// otherwise, which lets the start go on at once. The generation of the flags sent, where they
    /// were armed for it.
    fn answer(connection: *Connection, number: ?u32, file: []const u8) ?u64 {
        var arena: std.heap.ArenaAllocator = .init(connection.gpa);
        defer arena.deinit();
        connection.mutex.lockUncancelable(connection.io);
        const armed = connection.armed;
        const matches = number != null and armed.number == number and connection.profile.sameScript(armed.mission, file);
        const flags = connection.profile.scriptFlags(arena.allocator(), file, if (matches) armed.offsets else &.{}) catch null;
        connection.mutex.unlock(connection.io);
        if (flags) |bytes| _ = connection.send(connection.profile.link.script_flags, bytes);
        return if (matches) armed.generation else null;
    }

    /// Queues `event` for the frame, and wakes the window. A message that can't be queued is lost.
    fn push(connection: *Connection, event: Event) void {
        connection.mutex.lockUncancelable(connection.io);
        const kept = if (connection.events.append(connection.gpa, event)) true else |_| false;
        connection.mutex.unlock(connection.io);
        if (!kept) connection.release(event);
        connection.wake();
    }
};

pub const testing = struct {
    /// A wake for the tests, which have no window to wake.
    pub fn noWake() void {}
};
