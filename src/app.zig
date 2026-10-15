//! The editor's state, its commands and its frame: which screen and mode it shows, the open mod
//! and mission, the panels, and the actions every button, menu, key and palette entry runs.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const c = @import("c");

const breakpoints = @import("debug/breakpoints.zig");
const commands = @import("commands.zig");
const Command = commands.Command;
const session_mod = @import("debug/session.zig");
const Session = session_mod.Session;
const document_mod = @import("mission/document.zig");
const Document = document_mod.Document;
const game = @import("game.zig");
const keys = @import("keys.zig");
const palette = @import("palette.zig");
const panels = @import("panels.zig");
const project = @import("project.zig");
const Project = project.Project;
const settings_mod = @import("settings.zig");
const Settings = settings_mod.Settings;
const script_view = @import("views/script.zig");
const shell = @import("shell.zig");
const start_screen = @import("screens/start.zig");
const settings_screen = @import("screens/settings.zig");
const toasts = @import("toasts.zig");
const ui = @import("ui.zig");
const gui = ui.gui;
const text_editor = ui.text_editor;
const theme = ui.theme;
const widgets = ui.widgets;
const Window = @import("platform/window.zig").Window;

pub const Screen = enum { start, workspace, settings };

pub const Mode = enum { mission, mod };

/// The three views of a mission.
pub const MissionView = enum { script, scene, blocks };

/// The tabs of the source panel.
pub const SourceTab = enum { source, listing };

/// The settings' pages.
pub const SettingsPage = enum { general, appearance, keys, game, editor_link };

/// The dockable panels.
pub const Panel = enum {
    mission,
    find,
    source,
    threads,
    breakpoints,
    output,
    problems,
    variables,
    watch,
    inspector,
    reference,
    live_scene,

    /// The window's title, with an ID that stays the same as the label changes. ImGui makes a
    /// panel's tab as wide as its title, and the editor draws the tab over it, so the title holds
    /// the label with the tab's room in spaces, which are 2.95 pixels in the interface's font: 12
    /// pixels of padding on each side, 21 for an icon before the label, and 25 for a count's pill
    /// after it.
    pub fn title(panel: Panel) [:0]const u8 {
        return switch (panel) {
            inline else => |known| comptime blk: {
                const padding = spaces(4);
                const icon_room = if (known.icon() != null) spaces(7) else spaces(0);
                const pill_room = switch (known) {
                    .problems, .breakpoints => spaces(8),
                    else => spaces(0),
                };
                break :blk padding ++ icon_room ++ labelOf(known) ++ pill_room ++ padding ++ "###" ++ @tagName(known);
            },
        };
    }

    fn spaces(comptime count: usize) [count]u8 {
        return @splat(' ');
    }

    /// The icon before a panel's name on its tab, where the design gives one.
    pub fn icon(panel: Panel) ?ui.icons.Icon {
        return switch (panel) {
            .mission => .flag,
            else => null,
        };
    }

    pub fn label(panel: Panel) []const u8 {
        return switch (panel) {
            inline else => |known| labelOf(known),
        };
    }

    fn labelOf(comptime panel: Panel) []const u8 {
        return switch (panel) {
            .mission => "Mission",
            .find => "Find",
            .source => "Source",
            .threads => "Threads",
            .breakpoints => "Breakpoints",
            .output => "Output",
            .problems => "Problems",
            .variables => "Variables",
            .watch => "Watch",
            .inspector => "Inspector",
            .reference => "Reference",
            .live_scene => "Live scene",
        };
    }

    /// The Window menu's action that shows the panel.
    pub fn command(panel: Panel) ?Command {
        return switch (panel) {
            .mission => .show_mission_panel,
            .find => .show_find_panel,
            .source => null,
            .threads => .show_threads,
            .breakpoints => .show_breakpoints,
            .output => .show_output,
            .problems => .show_problems,
            .variables => .show_variables,
            .watch => .show_watch,
            .inspector => .show_inspector,
            .reference => .show_reference,
            .live_scene => .show_live_scene,
        };
    }
};

/// A line of the Output panel.
pub const OutputLine = struct {
    time: [8]u8,
    text: []const u8,
    kind: toasts.Kind = .info,
};

/// The outline's selection: a record, by its section and the line its declaration starts on.
pub const Selection = struct {
    section: game.Section,
    line: u32,
};

pub const App = struct {
    gpa: Allocator,
    io: Io,
    window: *Window,
    settings: *Settings,
    profile: *const game.Profile,
    language_arena: std.heap.ArenaAllocator,
    language: game.Language,
    editor_language: text_editor.Language,
    /// The read-only view of the script listing.
    listing_view: text_editor.TextEditor,

    screen: Screen = .start,
    mode: Mode = .mission,
    view: MissionView = .script,
    source_tab: SourceTab = .source,
    settings_page: SettingsPage = .keys,
    /// The system whose keys the Keys page shows in front.
    keys_system: keys.System = keys.System.current,
    project: ?Project = null,
    document: ?*Document = null,
    selection: ?Selection = null,
    /// Whether the menu of records to add opens on the next frame, as + and Add a record ask, and
    /// the name a Problems card's Declare gives the new record, `declare_name[0..declare_length]`.
    add_menu: bool = false,
    declare_name: [128]u8 = undefined,
    declare_length: ?usize = null,
    /// The word whose reference the Reference panel shows.
    reference_word: ?[]const u8 = null,
    reference_buffer: [64]u8 = undefined,
    open_panels: std.EnumArray(Panel, bool) = .initFill(true),
    /// Whether the dock layout is to be set to the full layout, and whether the panels the
    /// design shows in front are to be brought there.
    layout_due: bool = false,
    front_tabs_due: bool = false,
    /// Whether the source panel has the keyboard's focus.
    source_focused: bool = false,
    palette: palette.State = .{},
    toasts: toasts.Toasts = .{},
    output_arena: std.heap.ArenaAllocator,
    output: std.ArrayList(OutputLine) = .empty,
    /// The mods of the game's folder, for the start screen, and the game's own missions, for
    /// Edit a game mission, read once each.
    mods_arena: std.heap.ArenaAllocator,
    mods: ?[]const project.Summary = null,
    game_missions: ?[]const game.GameMission = null,
    /// A folder the system's dialog chose, which the next frame opens.
    chosen: Chosen = .{},
    quit: bool = false,
    /// Whether the window should close once unsaved changes are dealt with.
    closing: bool = false,
    /// The debugger: the editor link to the game, and what it holds.
    session: Session,
    /// Each source file's breakpoints, kept in the settings folder.
    breakpoint_store: breakpoints.Store,
    /// What the session was last aimed at (`aimSession`): the open mission, the version of its
    /// text checked and its breakpoints, hashed.
    aimed: u64 = 0,

    /// A folder chosen in the system's dialog, which may answer on another thread: the path, a
    /// copy SDL made, passed over once.
    const Chosen = struct {
        path: std.atomic.Value(?[*:0]u8) = .init(null),
        purpose: Purpose = .mod,

        const Purpose = enum { mod, file, game_folder, program };
    };

    pub fn init(gpa: Allocator, io: Io, window: *Window, settings: *Settings, profile: *const game.Profile) !App {
        var language_arena: std.heap.ArenaAllocator = .init(gpa);
        errdefer language_arena.deinit();
        const language = try profile.language(language_arena.allocator());
        const editor_language = try editorLanguage(language_arena.allocator(), language);
        const listing_view: text_editor.TextEditor = .init();
        listing_view.setReadOnly(true);
        var app: App = .{
            .gpa = gpa,
            .io = io,
            .window = window,
            .settings = settings,
            .profile = profile,
            .language_arena = language_arena,
            .language = language,
            .editor_language = editor_language,
            .listing_view = listing_view,
            .output_arena = .init(gpa),
            .mods_arena = .init(gpa),
            .session = .init(gpa, io, profile, wakeWindow),
            .breakpoint_store = .load(gpa, io, settings.folder),
        };
        if (settings.game_folder == null) {
            if (project.findGameFolder(io, app.mods_arena.allocator(), profile)) |found| settings.setGameFolder(io, found);
        }
        return app;
    }

    pub fn deinit(app: *App) void {
        // Quitting has already asked about unsaved changes.
        if (app.document) |document| {
            app.keepBreakpoints();
            document.close();
        }
        app.document = null;
        app.closeMod();
        app.session.deinit();
        app.breakpoint_store.deinit();
        app.listing_view.deinit();
        app.editor_language.deinit();
        app.language_arena.deinit();
        app.output_arena.deinit();
        app.mods_arena.deinit();
    }

    /// Draws a frame of the editor and runs what it asks for.
    pub fn frame(app: *App) void {
        gui.newFrame();
        app.takeChosen();
        if (app.window.dropped) |path| app.openFile(path);
        if (app.window.close_asked) {
            app.window.close_asked = false;
            app.run(.quit);
        }
        if (app.document) |document| {
            if (document.checkPending()) app.window.keepBusy();
            if (document.update(c.SDL_GetTicks())) app.clampSelection();
        }
        app.debugFrame();
        switch (app.screen) {
            .start => start_screen.draw(app),
            .settings => settings_screen.draw(app),
            .workspace => shell.draw(app),
        }
        palette.draw(app);
        app.toasts.draw(app.window);
        app.drawCloseConfirmation();
        app.makeQueued();
    }

    /// The shortcuts of the actions, run while the editor's windows have the keyboard.
    pub fn shortcuts(app: *App) void {
        if (app.palette.open or c.ImGui_IsPopupOpen("", c.ImGuiPopupFlags_AnyPopupId | c.ImGuiPopupFlags_AnyPopupLevel)) return;
        for (std.enums.values(Command)) |command| {
            const known = commands.info(command);
            switch (known.when) {
                .always => {},
                .held => if (!app.held()) continue,
                .not_held => if (app.held()) continue,
            }
            for (app.settings.keymap.chords(command, keys.System.current)) |chord| {
                const repeat: c.ImGuiInputFlags = if (repeats(command)) c.ImGuiInputFlags_Repeat else 0;
                if (c.ImGui_Shortcut(chord.imgui(), c.ImGuiInputFlags_RouteGlobal | c.ImGuiInputFlags_RouteOverFocused | repeat)) {
                    if (app.unavailable(command) == null) app.run(command);
                }
            }
        }
    }

    fn repeats(command: Command) bool {
        return switch (command) {
            .undo, .redo, .find_next, .step_over, .step_into => true,
            else => false,
        };
    }

    /// Why `command` can't run now, or null when it can.
    pub fn unavailable(app: *const App, command: Command) ?widgets.Disabled {
        if (commands.info(command).planned) |plan| return .{ .reason = gui.print("Planned · {f}", .{plan}) };
        const needs_document = "Open a mission first";
        return switch (command) {
            .add_record, .save, .build, .show_source, .show_listing, .clear_breakpoints, .go_to_line, .find, .find_next, .replace, .undo, .redo => if (app.document == null) .{ .reason = needs_document } else null,
            // These act on the source's cursor and selection, which only the Script view shows.
            .toggle_breakpoint, .comment_line, .cut, .copy, .paste, .select_all => if (app.document == null)
                .{ .reason = needs_document }
            else if (app.view != .script)
                .{ .reason = "Script view only" }
            else
                null,
            .play, .play_from_part => if (app.document == null) .{ .reason = needs_document } else if (app.settings.game_folder == null) .{ .reason = "Set the game's folder in Game settings" } else null,
            .new_mission => if (app.settings.game_folder == null and app.project == null) .{ .reason = "Set the game's folder in Game settings" } else null,
            .edit_game_mission => if (app.settings.game_folder == null) .{ .reason = "Set the game's folder in Game settings" } else null,
            .save_all => if (app.document == null) .{ .reason = needs_document } else null,
            .close_mod => if (app.project == null) .{ .reason = "No mod open" } else null,
            .go_to => if (app.document == null) .{ .reason = needs_document } else null,
            .@"continue" => if (!app.held()) .{ .reason = "Not held" } else null,
            .step_over, .step_into, .pause => app.debugUnavailable(),
            .run_to_cursor => if (!app.held()) .{ .reason = "Not held" } else if (!app.session.mapped()) .{ .reason = "Other build playing" } else null,
            .unlink => if (app.session.link_state == .off) .{ .reason = "Not linked" } else null,
            .link => switch (app.session.link_state) {
                .off => null,
                .waiting => .{ .reason = "Waiting for game" },
                .linked => .{ .reason = "Linked" },
            },
            .view_1, .view_2, .view_3, .view_4 => if (app.screen != .workspace) .{ .reason = "Open a mission first" } else app.viewUnavailable(command),
            .layout_full, .reset_layout => if (app.screen != .workspace) .{ .reason = "Open a mission first" } else null,
            else => null,
        };
    }

    /// Why the steps and Pause can't run now, or null when they can: while the game plays a
    /// mission, linked.
    fn debugUnavailable(app: *const App) ?widgets.Disabled {
        return switch (app.session.link_state) {
            .off => .{ .reason = "Not linked" },
            .waiting => .{ .reason = "Waiting for game" },
            .linked => if (app.session.playing == null) .{ .reason = "No mission" } else null,
        };
    }

    fn viewUnavailable(app: *const App, command: Command) ?widgets.Disabled {
        return switch (app.mode) {
            .mission => switch (command) {
                .view_3 => .{ .reason = gui.print("Planned · {f}", .{commands.plans.blocks}) },
                .view_4 => .{ .reason = "Mission mode has three views" },
                else => null,
            },
            .mod => .{ .reason = gui.print("Planned · {f}", .{commands.plans.mod_mode}) },
        };
    }

    /// The label an action shows, which for the views depends on the mode.
    pub fn label(app: *const App, command: Command) []const u8 {
        const views: [4][]const u8 = switch (app.mode) {
            .mission => .{ "Script", "Scene", "Blocks", "View 4" },
            .mod => .{ "Manifest", "Code", "Game files", "Share" },
        };
        return switch (command) {
            .view_1 => views[0],
            .view_2 => views[1],
            .view_3 => views[2],
            .view_4 => views[3],
            else => commands.info(command).label,
        };
    }

    /// The keys of `command` on this system, as it writes them: the first chord.
    pub fn keyText(app: *const App, command: Command) ?[:0]const u8 {
        const chords = app.settings.keymap.chords(command, keys.System.current);
        if (chords.len == 0) return null;
        return gui.print("{f}", .{chords[0].written(keys.System.current)});
    }

    /// Runs `command`.
    pub fn run(app: *App, command: Command) void {
        switch (command) {
            .new_mod, .open_hog, .switch_mode, .layout_guided => {},
            .add_record => app.askToAdd(null),
            .open_file => app.chooseFile(),
            .edit_game_mission => app.palette.show(.game_missions),
            .@"continue" => app.session.release(.run_on),
            .step_over => app.session.release(.step_over),
            .step_into => app.session.release(.step_into),
            .run_to_cursor => app.runToCursor(),
            .pause => app.session.togglePause(),
            .unlink => app.session.unlink(),
            .link => app.session.connect(app.settings.link.port, .waiting),
            .play_mod_only, .reload_scripts => {},
            .new_mission => app.newMission(),
            .play => app.play(.{}),
            .play_from_part => app.palette.show(.play_from_part),
            .open_mod => app.chooseFolder(.mod),
            .save => app.save(),
            .save_all => app.save(),
            .close_mod => app.closeMod(),
            .start_screen => app.showStart(),
            .settings => app.screen = .settings,
            .game_settings => {
                app.screen = .settings;
                app.settings_page = .game;
            },
            .help_keys => {
                app.screen = .settings;
                app.settings_page = .keys;
            },
            .quit => app.askQuit(),
            .undo => if (app.document) |document| document.editor.undo(),
            .redo => if (app.document) |document| document.editor.redo(),
            .cut => if (app.document) |document| document.editor.cut(),
            .copy => if (app.document) |document| document.editor.copy(),
            .paste => if (app.document) |document| document.editor.paste(),
            .select_all => if (app.document) |document| document.editor.selectAll(),
            .find, .replace => if (app.document) |document| {
                app.showSource(.source);
                document.editor.openFind();
            },
            .find_next => if (app.document) |document| {
                app.showSource(.source);
                document.editor.findNext();
            },
            .comment_line => if (app.document) |document| document.editor.toggleComments(),
            .go_to_line => app.palette.show(.line),
            .palette => app.palette.show(.commands),
            .go_to => app.palette.show(.records),
            .view_1 => app.view = .script,
            .view_2 => app.view = .scene,
            .view_3, .view_4 => {},
            .layout_full, .reset_layout => {
                app.open_panels = .initFill(true);
                app.layout_due = true;
            },
            .full_screen => app.window.toggleFullScreen(),
            .build => app.build(),
            .show_source => app.showSource(.source),
            .show_listing => app.showSource(.listing),
            .toggle_breakpoint => if (app.document) |document| app.toggleBreakpoint(document.editor.cursor().line),
            .clear_breakpoints => if (app.document) |document| {
                document.clearBreakpoints();
                app.keepBreakpoints();
            },
            .show_mission_panel => app.showPanel(.mission),
            .show_find_panel => app.showPanel(.find),
            .show_problems => app.showPanel(.problems),
            .show_output => app.showPanel(.output),
            .show_threads => app.showPanel(.threads),
            .show_breakpoints => app.showPanel(.breakpoints),
            .show_variables => app.showPanel(.variables),
            .show_watch => app.showPanel(.watch),
            .show_inspector => app.showPanel(.inspector),
            .show_reference => app.showPanel(.reference),
            .show_live_scene => app.showPanel(.live_scene),
            .help_missions => openGuide("missions.md"),
            .help_reference => openGuide("mission-reference.md"),
            .help_mods => openGuide("what-mods-can-do.md"),
            .help_modding => openGuide("modding.md"),
            .help_scripting => openGuide("scripting.md"),
            .about => _ = c.SDL_OpenURL("https://github.com/OpenReliant/openreliant-editor"),
        }
    }

    fn openGuide(comptime page: []const u8) void {
        _ = c.SDL_OpenURL("https://github.com/OpenReliant/openreliant/blob/main/docs/guide/" ++ page);
    }

    /// Shows `panel`, and brings it to the front of its group.
    pub fn showPanel(app: *App, panel: Panel) void {
        app.open_panels.set(panel, true);
        c.ImGui_SetWindowFocusStr(panel.title());
    }

    pub fn log(app: *App, kind: toasts.Kind, comptime format: []const u8, args: anytype) void {
        const text = std.fmt.allocPrint(app.output_arena.allocator(), format, args) catch return;
        app.output.append(app.output_arena.allocator(), .{ .time = document_mod.clockNow(), .text = text, .kind = kind }) catch {};
    }

    fn save(app: *App) void {
        const document = app.document orelse return;
        document.save(app.io) catch |err| {
            app.log(.failure, "Can't save {s}: {t}", .{ document.file, err });
            app.toasts.push(.failure, gui.print("Can't save {s}", .{document.file}), @errorName(err));
            return;
        };
        // The breakpoints are kept on their lines as saved.
        app.keepBreakpoints();
        app.log(.info, "Saved {s}", .{document.file});
    }

    /// Saves the source and builds the mission beside it.
    pub fn build(app: *App) void {
        const document = app.document orelse return;
        if (document.dirty()) app.save();
        const result = document.build(app.io) catch |err| {
            app.log(.failure, "Can't build {s}: {t}", .{ document.file, err });
            app.toasts.push(.failure, gui.print("Can't build {s}", .{document.file}), @errorName(err));
            return;
        };
        switch (result) {
            .built => |file| {
                app.log(.success, "Built {s}", .{file});
                const detail = if (app.session.playingMission()) "Game reads it next attempt" else "Game reads it next play";
                app.toasts.push(.success, gui.print("Built {s}", .{file}), detail);
            },
            .problems => |found| {
                const first = found[0];
                app.log(.failure, "{s}:{d}:{d}: {s}", .{ document.file, first.at.line + 1, first.at.column + 1, first.message });
                app.showPanel(.problems);
                app.toasts.push(.failure, gui.print("{d} problem{s}", .{ found.len, if (found.len == 1) "" else "s" }), "The mission file is as it was");
            },
            .no_number => {
                app.log(.failure, "{s} has no mission number: name it like mission90{s}", .{ document.file, app.profile.source_extension });
                app.toasts.push(.failure, "No mission number", "Name it like mission90.mission.luau");
            },
        }
    }

    /// Adds a new mission to the open mod, or makes a mod for it in the game's `mods` folder, and
    /// opens it.
    fn newMission(app: *App) void {
        var arena_state: std.heap.ArenaAllocator = .init(app.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const number = app.freeMissionNumber(arena);
        const file = std.fmt.allocPrint(arena, "mission{d}{s}", .{ number, app.profile.source_extension }) catch return;
        const name = if (number == app.profile.first_new_mission) "New Mission" else std.fmt.allocPrint(arena, "New Mission {d}", .{number}) catch return;
        const text = app.profile.newMission(arena, name) catch return;
        const folder = if (app.project) |opened| arena.dupe(u8, opened.path) catch return else app.newModFolder(arena) orelse return;
        const path = std.fs.path.join(arena, &.{ folder, file }) catch return;
        Io.Dir.cwd().writeFile(app.io, .{ .sub_path = path, .data = text }) catch |err| {
            app.toasts.push(.failure, gui.print("Can't write {s}", .{file}), @errorName(err));
            return;
        };
        app.log(.info, "Made {s}", .{file});
        app.openMod(folder);
        if (app.project) |opened| for (opened.missions, 0..) |mission, index| {
            if (std.mem.eql(u8, mission.file, file)) app.openMission(index);
        };
    }

    /// A new folder in the game's `mods` folder, `new-mission` or the first `new-mission-2` and so
    /// on that's free, with a manifest.
    fn newModFolder(app: *App, arena: Allocator) ?[]const u8 {
        const game_folder = app.settings.game_folder orelse return null;
        var attempt: u32 = 1;
        while (attempt < 100) : (attempt += 1) {
            const name = if (attempt == 1) "new-mission" else std.fmt.allocPrint(arena, "new-mission-{d}", .{attempt}) catch return null;
            const path = std.fs.path.join(arena, &.{ game_folder, "mods", name }) catch return null;
            Io.Dir.cwd().access(app.io, path, .{}) catch {
                Io.Dir.cwd().createDirPath(app.io, path) catch |err| {
                    app.toasts.push(.failure, "Can't make the mod's folder", @errorName(err));
                    return null;
                };
                const manifest = std.fs.path.join(arena, &.{ path, "mod.ini" }) catch return null;
                Io.Dir.cwd().writeFile(app.io, .{ .sub_path = manifest, .data = "[Mod]\nName=New Mission\nVersion=1.0\n" }) catch {};
                return path;
            };
        }
        return null;
    }

    /// The first mission number from the profile's first new one that no mod's mission takes.
    fn freeMissionNumber(app: *App, arena: Allocator) u32 {
        var taken: std.AutoHashMapUnmanaged(u32, void) = .empty;
        if (app.settings.game_folder) |game_folder| {
            const mods_path = std.fs.path.join(arena, &.{ game_folder, "mods" }) catch return app.profile.first_new_mission;
            if (Io.Dir.cwd().openDir(app.io, mods_path, .{ .iterate = true })) |mods_dir| {
                var mods = mods_dir;
                defer mods.close(app.io);
                var each = mods.iterate();
                while (each.next(app.io) catch null) |entry| {
                    if (entry.kind != .directory) continue;
                    var mod = mods.openDir(app.io, entry.name, .{ .iterate = true }) catch continue;
                    defer mod.close(app.io);
                    var files = mod.iterate();
                    while (files.next(app.io) catch null) |found| {
                        if (app.profile.missionNumber(found.name)) |number| taken.put(arena, number, {}) catch {};
                    }
                }
            } else |_| {}
        }
        if (app.project) |opened| for (opened.missions) |mission| {
            if (mission.number) |number| taken.put(arena, number, {}) catch {};
        };
        var number = app.profile.first_new_mission;
        while (taken.contains(number)) number += 1;
        return number;
    }

    /// Builds the mission, then starts OpenReliant on it, linked to the editor where the settings
    /// say so. A game linked already plays the new build from the mission's next attempt, and no
    /// other starts; a link that waits for a game takes the one started.
    pub fn play(app: *App, asked: game.Play) void {
        const document = app.document orelse return;
        const number = document.number orelse {
            app.toasts.push(.failure, "No mission number", "Name it like mission90.mission.luau");
            return;
        };
        app.build();
        if (document.problems().len > 0 or document.built == null) return;
        if (app.session.link_state == .linked) return;
        const game_folder = app.settings.game_folder orelse return;
        var arena_state: std.heap.ArenaAllocator = .init(app.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const program = app.findOpenReliant(arena);
        var options = asked;
        if (app.settings.link.when_playing) options.link = app.settings.link.port;
        const arguments = app.profile.playArguments(arena, game_folder, number, options) catch return;
        const argv = std.mem.concat(arena, []const u8, &.{ &.{program}, arguments }) catch return;
        _ = std.process.spawn(app.io, .{ .argv = argv, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore }) catch |err| {
            app.log(.failure, "Can't start {s}: {t}", .{ program, err });
            app.toasts.push(.failure, "Can't start openreliant", "Set where it is in Game settings");
            return;
        };
        app.log(.info, "Playing mission {d}: {s} {s}", .{ number, std.fs.path.basename(program), std.mem.join(arena, " ", arguments) catch "" });
        app.toasts.push(.success, gui.print("Playing mission {d}", .{number}), if (options.link != null) "OpenReliant started · linking" else "OpenReliant started");
        if (options.link) |port| if (app.session.link_state == .off) app.session.connect(port, .{ .starting = starting_patience_ms });
    }

    /// How long the editor tries to link to a game it started, while the game starts.
    const starting_patience_ms = 30_000;

    /// The debugger's part of the frame: the session aimed at the open mission, what the game sent
    /// taken, the held line shown, and the session's lines written to Output.
    fn debugFrame(app: *App) void {
        app.aimSession();
        app.session.update(c.SDL_GetTicks(), app.settings.link.state_rate);
        for (app.session.takeNotes()) |note| app.log(note.kind, "{s}", .{note.text});
        app.session.freeNotes();
        const document = app.document orelse return;
        const held_line = if (app.session.heldStatement()) |statement| statement.at.line else null;
        document.setHeldLine(held_line);
        if (app.session.takeRevealed()) {
            if (held_line) |line| app.goTo(line, 0);
            app.window.raise();
        }
    }

    /// Aims the session at the open mission whenever it, the text's build or the breakpoints
    /// change.
    fn aimSession(app: *App) void {
        var buffer: [document_mod.max_breakpoints]usize = undefined;
        var hasher: std.hash.Wyhash = .init(0);
        const lines: []const usize = if (app.document) |document| document.breakpoints(&buffer) else &.{};
        if (app.document) |document| {
            hasher.update(std.mem.asBytes(&@intFromPtr(document)));
            hasher.update(std.mem.asBytes(&document.checked_version));
        }
        hasher.update(std.mem.sliceAsBytes(lines));
        const key = hasher.final();
        if (key == app.aimed) return;
        app.aimed = key;
        const document = app.document orelse return app.session.aim(.{ .number = null, .mission = null, .offsets = &.{} });
        var arena: std.heap.ArenaAllocator = .init(app.gpa);
        defer arena.deinit();
        const mission = document.mission();
        const offsets = if (mission) |built| breakpoints.offsets(arena.allocator(), built, document.outline(), lines) catch &.{} else &.{};
        app.session.aim(.{ .number = document.number, .mission = mission, .offsets = offsets });
    }

    /// Whether the game holds the script.
    pub fn held(app: *const App) bool {
        return app.session.held != null;
    }

    /// Sets or clears the breakpoint on `line`. One set where the script can't hold goes to the
    /// next line that holds, as the build's map says.
    pub fn toggleBreakpoint(app: *App, line: usize) void {
        const document = app.document orelse return;
        if (document.hasBreakpoint(line)) {
            document.setBreakpoint(line, false);
        } else if (document.mission()) |mission| {
            const statement = breakpoints.place(mission, document.outline(), @intCast(line)) orelse {
                app.toasts.push(.info, "Can't hold here", "return and end can't hold");
                return;
            };
            document.setBreakpoint(statement.at.line, true);
        } else document.setBreakpoint(line, true);
        app.keepBreakpoints();
    }

    /// Removes the breakpoints of every source file, the open mission's too.
    pub fn removeAllBreakpoints(app: *App) void {
        if (app.document) |document| document.clearBreakpoints();
        app.breakpoint_store.removeAll(app.io);
        app.log(.info, "Removed all breakpoints", .{});
    }

    /// Keeps the open mission's breakpoints in the settings folder.
    fn keepBreakpoints(app: *App) void {
        const document = app.document orelse return;
        var buffer: [document_mod.max_breakpoints]usize = undefined;
        app.breakpoint_store.keep(app.io, document.path, document.breakpoints(&buffer));
    }

    /// Lets the held script run on to the cursor's line.
    fn runToCursor(app: *App) void {
        const document = app.document orelse return;
        const mission = document.mission() orelse return;
        const statement = breakpoints.place(mission, document.outline(), @intCast(document.editor.cursor().line)) orelse {
            app.toasts.push(.info, "Can't hold here", "Cursor on a statement");
            return;
        };
        app.session.runTo(statement.offset);
    }

    /// Where `openreliant` is: where the settings say, beside the editor, beside the game's folder
    /// as the installation guide puts it, or wherever the system finds it.
    pub fn findOpenReliant(app: *App, arena: Allocator) []const u8 {
        const name = if (builtin.target.os.tag == .windows) "openreliant.exe" else "openreliant";
        if (app.settings.openreliant) |path| return path;
        const own = std.process.executableDirPathAlloc(app.io, arena) catch null;
        const game_parent = if (app.settings.game_folder) |folder| std.fs.path.dirname(folder) else null;
        for ([_]?[]const u8{ own, game_parent }) |known| {
            const folder = known orelse continue;
            const path = std.fs.path.join(arena, &.{ folder, name }) catch continue;
            Io.Dir.cwd().access(app.io, path, .{}) catch continue;
            return path;
        }
        return name;
    }

    /// Opens the mod in `path` and its first mission.
    pub fn openMod(app: *App, path: []const u8) void {
        app.closeMod();
        app.project = Project.open(app.gpa, app.io, path, app.profile) catch |err| {
            app.toasts.push(.failure, "Can't open the mod", @errorName(err));
            return;
        };
        app.settings.remember(app.io, app.project.?.path);
        app.log(.info, "Opened {s}", .{app.project.?.name});
        if (app.project.?.missions.len > 0) {
            app.openMission(0);
        } else {
            app.toasts.push(.info, "No missions in this mod", "Mod mode comes later: add a .mission.luau file");
            app.showStart();
            return;
        }
        app.screen = .workspace;
        app.mode = .mission;
        app.view = .script;
    }

    /// Opens the mod's `index`th mission, in place of the one open.
    pub fn openMission(app: *App, index: usize) void {
        const opened = &(app.project orelse return);
        const mission = opened.missions[index];
        const path = opened.pathOf(app.gpa, mission.file) catch return;
        defer app.gpa.free(path);
        const document = Document.open(app.gpa, app.io, path, app.profile, app.editor_language) catch |err| {
            app.toasts.push(.failure, gui.print("Can't open {s}", .{mission.file}), @errorName(err));
            return;
        };
        app.releaseDocument();
        app.document = document;
        app.selection = null;
        app.source_tab = .source;
        for (app.breakpoint_store.lines(document.path)) |line| document.setBreakpoint(line, true);
        script_view.attach(app, document);
        app.updateTitle();
    }

    /// Closes the open mission, saved first if it changed, so that switching missions or mods
    /// never loses work.
    fn releaseDocument(app: *App) void {
        const document = app.document orelse return;
        if (document.dirty()) app.save();
        app.keepBreakpoints();
        document.close();
        app.document = null;
    }

    fn closeMod(app: *App) void {
        app.releaseDocument();
        if (app.project) |*opened| opened.close();
        app.project = null;
        app.selection = null;
        app.updateTitle();
    }

    fn showStart(app: *App) void {
        app.screen = .start;
        app.forgetListings();
    }

    /// Forgets the mods and the game's missions read, which are read again when shown.
    fn forgetListings(app: *App) void {
        app.mods = null;
        app.game_missions = null;
        _ = app.mods_arena.reset(.retain_capacity);
    }

    /// The game's own missions, read once.
    pub fn listedGameMissions(app: *App) []const game.GameMission {
        if (app.game_missions) |known| return known;
        const folder = app.settings.game_folder orelse return &.{};
        app.game_missions = app.profile.gameMissions(app.mods_arena.allocator(), app.io, folder) catch &.{};
        return app.game_missions.?;
    }

    /// The mods of the game's folder, read again when the start screen opens.
    pub fn listedMods(app: *App) []const project.Summary {
        if (app.mods) |known| return known;
        const folder = app.settings.game_folder orelse return &.{};
        app.mods = project.listMods(app.mods_arena.allocator(), app.io, folder, app.profile) catch &.{};
        return app.mods.?;
    }

    pub fn updateTitle(app: *App) void {
        if (app.document) |document| {
            const name = if (app.project) |opened| opened.name else "";
            app.window.setTitle(gui.print("{s} · {s} · OpenReliant Editor", .{ document.file, name }));
        } else {
            app.window.setTitle("OpenReliant Editor");
        }
    }

    /// Asks the system's dialog for a folder, a mod's or the game's.
    pub fn chooseFolder(app: *App, purpose: Chosen.Purpose) void {
        app.chosen.purpose = purpose;
        const start = switch (purpose) {
            .mod, .file => if (app.settings.game_folder) |folder| gui.print("{s}{s}mods", .{ folder, std.fs.path.sep_str }) else null,
            .game_folder, .program => if (app.settings.game_folder) |folder| gui.z(folder) else null,
        };
        c.SDL_ShowOpenFolderDialog(folderChosen, app, app.window.handle, if (start) |path| path.ptr else null, false);
    }

    /// Asks the system's dialog for a mission file, a mission's source or a mod's manifest.
    pub fn chooseFile(app: *App) void {
        app.chosen.purpose = .file;
        const filters = [_]c.SDL_DialogFileFilter{
            .{ .name = "Missions and mods", .pattern = "dte;luau;ini" },
            .{ .name = "Mission files", .pattern = "dte" },
            .{ .name = "Mission source", .pattern = "luau" },
        };
        const start = if (app.settings.game_folder) |folder| gui.print("{s}{s}mods", .{ folder, std.fs.path.sep_str }) else null;
        c.SDL_ShowOpenFileDialog(folderChosen, app, app.window.handle, &filters, filters.len, if (start) |path| path.ptr else null, false);
    }

    /// Asks the system's dialog where `openreliant` is.
    pub fn chooseProgram(app: *App) void {
        app.chosen.purpose = .program;
        c.SDL_ShowOpenFileDialog(folderChosen, app, app.window.handle, null, 0, null, false);
    }

    /// Opens `path`: a mission's source, a mission file, which opens as source written beside it,
    /// or a mod's manifest, which opens its mod.
    pub fn openFile(app: *App, path: []const u8) void {
        const folder = std.fs.path.dirname(path) orelse ".";
        const name = std.fs.path.basename(path);
        if (std.ascii.endsWithIgnoreCase(name, app.profile.source_extension)) return app.openModAt(folder, name);
        if (std.ascii.endsWithIgnoreCase(name, app.profile.mission_extension)) return app.openMissionFile(path);
        if (std.ascii.eqlIgnoreCase(name, "mod.ini")) return app.openMod(folder);
        app.toasts.push(.failure, gui.print("Can't open {s}", .{name}), "Open a mission file, a mission's source or a mod.ini");
    }

    /// Opens the mod in `folder` at its mission `file`.
    fn openModAt(app: *App, folder: []const u8, file: []const u8) void {
        app.openMod(folder);
        const opened = app.project orelse return;
        for (opened.missions, 0..) |mission, index| {
            if (std.ascii.eqlIgnoreCase(mission.file, file)) return app.openMission(index);
        }
    }

    /// Opens a mission file as source: the source beside it if there is one, or else the source
    /// written for it there.
    fn openMissionFile(app: *App, path: []const u8) void {
        var arena_state: std.heap.ArenaAllocator = .init(app.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const folder = std.fs.path.dirname(path) orelse ".";
        const name = std.fs.path.basename(path);
        const stem = name[0 .. name.len - app.profile.mission_extension.len];
        const source_name = std.fmt.allocPrint(arena, "{s}{s}", .{ stem, app.profile.source_extension }) catch return;
        const source_path = std.fs.path.join(arena, &.{ folder, source_name }) catch return;
        if (Io.Dir.cwd().access(app.io, source_path, .{})) |_| {
            app.toasts.push(.info, gui.print("Opened {s}", .{source_name}), gui.print("The source beside {s}", .{name}));
        } else |_| {
            const image = Io.Dir.cwd().readFileAlloc(app.io, path, arena, .limited(16 * 1024 * 1024)) catch |err| {
                app.toasts.push(.failure, gui.print("Can't read {s}", .{name}), @errorName(err));
                return;
            };
            if (!app.writeSource(arena, image, name, source_path)) return;
        }
        app.openModAt(folder, source_name);
    }

    /// Writes the mission file `image`, named `name`, as source at `path`. False when it can't.
    fn writeSource(app: *App, arena: Allocator, image: []const u8, name: []const u8, path: []const u8) bool {
        const text = app.profile.decompile(arena, image) catch |err| {
            app.toasts.push(.failure, gui.print("Can't read {s}", .{name}), if (err == error.NotAMission) "Not a mission file" else @errorName(err));
            return false;
        };
        const header = std.fmt.allocPrint(arena, "-- {s} as mission source, written by OpenReliant Editor.\n", .{name}) catch return false;
        const file = std.mem.concat(arena, u8, &.{ header, text }) catch return false;
        Io.Dir.cwd().writeFile(app.io, .{ .sub_path = path, .data = file }) catch |err| {
            app.toasts.push(.failure, gui.print("Can't write {s}", .{std.fs.path.basename(path)}), @errorName(err));
            return false;
        };
        app.log(.info, "Wrote {s} from {s}", .{ std.fs.path.basename(path), name });
        return true;
    }

    /// Opens the game's mission `number` as the source of a new mod, `mission<number>` in the
    /// game's `mods` folder, which replaces the game's mission by name once it's built.
    pub fn editGameMission(app: *App, number: u32) void {
        const game_folder = app.settings.game_folder orelse return;
        var arena_state: std.heap.ArenaAllocator = .init(app.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const image = app.profile.readGameMission(arena, app.io, game_folder, number) catch |err| {
            app.toasts.push(.failure, gui.print("Can't read mission {d}", .{number}), @errorName(err));
            return;
        } orelse {
            app.toasts.push(.failure, gui.print("No mission {d}", .{number}), "The game has no such mission");
            return;
        };
        // A folder of its own in the mods folder, the first of mission5, mission5-2 and so on that's free.
        var attempt: u32 = 1;
        const folder = while (attempt < 100) : (attempt += 1) {
            const mod_name = if (attempt == 1) std.fmt.allocPrint(arena, "mission{d}", .{number}) catch return else std.fmt.allocPrint(arena, "mission{d}-{d}", .{ number, attempt }) catch return;
            const path = std.fs.path.join(arena, &.{ game_folder, "mods", mod_name }) catch return;
            Io.Dir.cwd().access(app.io, path, .{}) catch break path;
        } else return;
        Io.Dir.cwd().createDirPath(app.io, folder) catch |err| {
            app.toasts.push(.failure, "Can't make the mod's folder", @errorName(err));
            return;
        };
        const manifest = std.fmt.allocPrint(arena, "[Mod]\nName=Mission {d}\nVersion=1.0\n", .{number}) catch return;
        Io.Dir.cwd().writeFile(app.io, .{ .sub_path = std.fs.path.join(arena, &.{ folder, "mod.ini" }) catch return, .data = manifest }) catch {};
        const mission_name = std.fmt.allocPrint(arena, "mission{d}{s}", .{ number, app.profile.mission_extension }) catch return;
        const source_name = std.fmt.allocPrint(arena, "mission{d}{s}", .{ number, app.profile.source_extension }) catch return;
        if (!app.writeSource(arena, image, mission_name, std.fs.path.join(arena, &.{ folder, source_name }) catch return)) return;
        app.openModAt(folder, source_name);
        app.toasts.push(.success, gui.print("Mission {d} as source", .{number}), gui.print("In mods/{s}: its build replaces the game's", .{std.fs.path.basename(folder)}));
    }

    fn folderChosen(user: ?*anyopaque, list: [*c]const [*c]const u8, filter: c_int) callconv(.c) void {
        _ = filter;
        const app: *App = @ptrCast(@alignCast(user.?));
        if (list == null or list[0] == null) return;
        const copy: ?[*:0]u8 = @ptrCast(c.SDL_strdup(list[0]));
        if (app.chosen.path.swap(copy, .acq_rel)) |old| c.SDL_free(old);
    }

    fn takeChosen(app: *App) void {
        const path = app.chosen.path.swap(null, .acq_rel) orelse return;
        defer c.SDL_free(path);
        const chosen = std.mem.span(path);
        switch (app.chosen.purpose) {
            .mod => app.openMod(chosen),
            .file => app.openFile(chosen),
            .game_folder => {
                app.settings.setGameFolder(app.io, chosen);
                app.forgetListings();
            },
            .program => {
                app.settings.openreliant = app.settings.arena.allocator().dupe(u8, chosen) catch return;
                app.settings.save(app.io);
            },
        }
    }

    /// Keeps the selection on a record the outline still has.
    fn clampSelection(app: *App) void {
        const selected = app.selection orelse return;
        const document = app.document orelse return;
        if (document.outline().find(selected.section, selected.line) == null) app.selection = null;
    }

    /// Opens the menu of records to add, which declares the record chosen under `name` where one
    /// is given, as a Problems card's Declare asks.
    pub fn askToAdd(app: *App, name: ?[]const u8) void {
        app.add_menu = true;
        app.declare_length = null;
        const given = name orelse return;
        if (given.len > app.declare_name.len) return;
        @memcpy(app.declare_name[0..given.len], given);
        app.declare_length = given.len;
    }

    /// The name the menu of records to add declares the new one under, where a Declare asked.
    pub fn declaring(app: *const App) ?[]const u8 {
        return app.declare_name[0 .. app.declare_length orelse return null];
    }

    /// Makes the change to the source that the interface asked for during the frame
    /// (`Document.queue`), now that nothing drawn holds on to the outline it replaces: says where
    /// it can't be made, and selects a record added.
    fn makeQueued(app: *App) void {
        const document = app.document orelse return;
        const asked = document.queued orelse return;
        const made = document.flush() catch {
            app.toasts.push(.failure, "Can't change the source", "Out of memory");
            return;
        };
        const reason = if (document.outline_stale) "Fix the source's problems first" else switch (asked) {
            .add => "The name is taken",
            else => "The declaration has no place for it",
        };
        switch (made) {
            .none => {},
            .edited => |done| if (!done) app.toasts.push(.info, "Can't change it here", reason),
            .added => |added| {
                const line = added.line orelse return app.toasts.push(.info, gui.print("Can't add {s}", .{asked.add.name orelse asked.add.kind.label}), reason);
                app.selection = .{ .section = added.section, .line = line };
                // The map shows the new record selected, and the Script view its line.
                if (app.view == .script) app.goTo(line, 0) else app.placeCursor(line, 0);
            },
        }
    }

    /// The record the inspector shows and the map marks: the one selected, or else the one the
    /// source's cursor is in.
    pub fn inspected(app: *const App) ?*const game.Record {
        const document = app.document orelse return null;
        const known = document.outline();
        if (app.selection) |chosen| return known.find(chosen.section, chosen.line);
        return known.at(@intCast(document.editor.cursor().line));
    }

    pub fn select(app: *App, record: game.Record) void {
        app.selection = .{ .section = record.section, .line = record.first_line };
    }

    /// Moves the source's cursor to `line` and `column`, counting from 0, and shows it in the
    /// Script view, switching to it from another view.
    pub fn goTo(app: *App, line: u32, column: u32) void {
        const document = app.document orelse return;
        app.showSource(.source);
        app.placeCursor(line, column);
        document.editor.focus();
    }

    /// Moves the source's cursor to `line` and `column`, counting from 0, and scrolls the source
    /// to it, without switching views.
    fn placeCursor(app: *App, line: u32, column: u32) void {
        const document = app.document orelse return;
        document.editor.setCursor(.{ .line = line, .index = column });
        document.editor.scrollToLine(line);
    }

    /// Shows the source panel's `tab` in the Script view, switching to it from another view.
    fn showSource(app: *App, tab: SourceTab) void {
        app.screen = .workspace;
        app.view = .script;
        app.source_tab = tab;
    }

    fn askQuit(app: *App) void {
        if (app.document) |document| if (document.dirty()) {
            app.closing = true;
            return;
        };
        app.quit = true;
    }

    fn drawCloseConfirmation(app: *App) void {
        if (app.closing) {
            _ = c.ImGui_OpenPopup("Unsaved changes", 0);
            app.closing = false;
        }
        const viewport = c.ImGui_GetMainViewport();
        c.ImGui_SetNextWindowPosEx(c.ImGuiViewport_GetCenter(viewport), c.ImGuiCond_Appearing, .{ .x = 0.5, .y = 0.5 });
        gui.pushVar2(c.ImGuiStyleVar_WindowPadding, .{ .x = gui.px(16), .y = gui.px(14) });
        defer gui.popVar(1);
        if (c.ImGui_BeginPopupModal("Unsaved changes", null, c.ImGuiWindowFlags_AlwaysAutoResize | c.ImGuiWindowFlags_NoTitleBar)) {
            const document = app.document.?;
            widgets.caption(gui.print("{s}: unsaved changes", .{document.file}), theme.text_strong, ui.fonts.size.body, .semibold);
            gui.space(10);
            if (widgets.toolButton("save and quit", .{ .label = "Save and quit", .style = .primary, .weight = .semibold })) {
                app.save();
                app.quit = true;
                c.ImGui_CloseCurrentPopup();
            }
            gui.sameLine(6);
            if (widgets.toolButton("quit", .{ .label = "Quit without saving" })) {
                app.quit = true;
                c.ImGui_CloseCurrentPopup();
            }
            gui.sameLine(6);
            if (widgets.toolButton("cancel", .{ .label = "Cancel" }) or c.ImGui_IsKeyPressed(c.ImGuiKey_Escape)) {
                c.ImGui_CloseCurrentPopup();
            }
            c.ImGui_EndPopup();
        }
    }
};

/// Wakes the window from its wait for events: the editor link's task calls it as the game's
/// messages come.
fn wakeWindow() void {
    var event = std.mem.zeroes(c.SDL_Event);
    event.type = c.SDL_EVENT_USER;
    _ = c.SDL_PushEvent(&event);
}

/// The text editor's language from the game's words: its keywords, its declarations, its
/// commands, and the name its variables are read under.
fn editorLanguage(arena: Allocator, language: game.Language) Allocator.Error!text_editor.Language {
    var keywords: std.ArrayList([]const u8) = .empty;
    var declarations: std.ArrayList([]const u8) = .empty;
    var known: std.ArrayList([]const u8) = .empty;
    for (language.words) |word| switch (word.kind) {
        .keyword => try keywords.append(arena, word.name),
        .declaration => if (!std.mem.eql(u8, word.name, language.variables)) try declarations.append(arena, word.name),
        .command => try known.append(arena, word.name),
        .condition, .game_variable, .value => {},
    };
    return .init(language.name, .{
        .keywords = keywords.items,
        .declarations = declarations.items,
        .known = known.items,
        .special = &.{language.variables},
    });
}
