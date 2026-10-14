# How the editor is put together

The editor is a Zig program on SDL3 and Dear ImGui. It reads and builds missions with OpenReliant's
own library, which `build.zig.zon` pins, so it reads every mission exactly as the game does.

## The modules

| Module | What it does |
|---|---|
| [`main.zig`](../src/main.zig) | The command line, and the window's frames |
| [`app.zig`](../src/app.zig) | The editor's state, what each action does, and the frame |
| [`commands.zig`](../src/commands.zig) | Every action: label, icon, menu, keys, and the issue of one not made yet |
| [`keys.zig`](../src/keys.zig) | Keys as each system writes them, and the chords ImGui reads |
| [`settings.zig`](../src/settings.zig) | `editor.ini` and `keys.ini`, kept for each user |
| [`game.zig`](../src/game.zig) | What the editor asks of a game: the profile |
| [`game/starlancer.zig`](../src/game/starlancer.zig) | StarLancer's profile, on OpenReliant's tables and compiler |
| [`project.zig`](../src/project.zig) | A mod folder and its missions, and the mods of a game folder |
| [`mission/document.zig`](../src/mission/document.zig) | An open mission: its source, its checks, its build and its breakpoints |
| [`link/connection.zig`](../src/link/connection.zig) | The editor link's connection to the game, on a task of its own |
| [`debug/session.zig`](../src/debug/session.zig) | The debugger: the link's state, the game's mission matched with the build, the holds, the state and the actions |
| [`debug/breakpoints.zig`](../src/debug/breakpoints.zig) | Where each breakpoint holds the script, and each source file's breakpoints kept in the settings folder |
| [`shell.zig`](../src/shell.zig) | The workspace's menu bar, toolbar, dock space and status bar |
| [`panels.zig`](../src/panels.zig) | The dockable panels: the outline, problems, the inspector and the others |
| [`views/script.zig`](../src/views/script.zig) | The Script view: the source, its gutter, help and completion, and the listing |
| [`palette.zig`](../src/palette.zig) | The command palette, Play from part, and the game's missions |
| [`screens/`](../src/screens) | The start screen and the settings |
| [`toasts.zig`](../src/toasts.zig) | Short messages that fade out |
| [`ui/`](../src/ui) | The interface kit: colours, fonts, icons, widgets, the text editor |
| [`platform/`](../src/platform) | The window, SDL_GPU, ImGui's backends, and the C header the build translates |

## The game profile

The interface never names a game's commands, conditions, records or files. It asks the game's
profile, a `game.Profile`:

- the game's name, its script's dialect, and its files' extensions;
- the words of mission source, from the game's own tables: the language's keywords, mission
  source's declarations, the game's commands and conditions with their descriptions and
  parameters, the game's variables, and the names of its values;
- the records a mission's source declares, for the outline and the inspector;
- building source into a mission file, with the map of its script's statements to the source's
  lines, decompiling a mission file into source, and comparing two missions and their scripts;
- the game's messages on the editor link, and the script's flags for a set of offsets;
- the game's own missions in its folder, and the command line that plays one.

StarLancer's profile reads all of it from OpenReliant's library: the command and condition
catalogues, `dte.source` for the language, `source_parser` to parse and build, and the game's
archive for its missions. A game OpenReliant plays later is a profile of its own; once games are
made on OpenReliant from data, profiles become files a Game mode edits.

## Missions

A mission opens as its source, a `.mission.luau` file. A mission file, a `.dte`, opens as the source
written beside it, decompiled by OpenReliant's decompiler; a game's own mission opens as the source
of a new mod, `mods/mission<number>`, whose build replaces the game's mission by name. Every stock
mission comes back from its source as the same mission, which `--check-missions` checks.

The source is checked as it's typed: once the text rests for a moment, the profile reads its outline
and builds it in memory, and the problems show in the gutter, under the text and in the Problems
panel. While the source doesn't parse, the outline is the last one that did. Build writes the
mission file beside the source and keeps its script's listing.

## The debugger

The debugger links to the game over OpenReliant's editor link ([Debugging a mission](debugging.md)).
`link/connection.zig` connects on a task of its own, which reads the game's messages into a queue
that each frame takes from, and wakes the window as they come. The task answers each mission's file
itself with the breakpoints' flags, since the game holds the mission's start until they come.

`debug/session.zig` takes the messages each frame. It matches the mission the game plays with the
build of the open mission's text: the same number, and the same script with the same routines
(`Profile.sameScript`). While they match, the build's map turns breakpoints' lines into the
offsets the game's flags hold at, and the offset of each hold back into a line. The session asks for
the script's state on each hold, and polls it while the script runs. It reads OpenReliant's own
messages with the records of OpenReliant's library (`engine.link`), and the game's own through its
profile (`Profile.link`), so that it never names StarLancer's tags or opcodes.

## What isn't made yet

Each shows in the interface, greyed out, with its issue:

- the Scene view ([#2](https://github.com/OpenReliant/openreliant-editor/issues/2)) and the Blocks
  view ([#3](https://github.com/OpenReliant/openreliant-editor/issues/3));
- Mod mode ([#4](https://github.com/OpenReliant/openreliant-editor/issues/4));
- the debugger's conditions, log points, Watch, values inline and Debugging screen
  ([#19](https://github.com/OpenReliant/openreliant-editor/issues/19)), its timeline
  ([#20](https://github.com/OpenReliant/openreliant-editor/issues/20)), the live scene
  ([#21](https://github.com/OpenReliant/openreliant-editor/issues/21)) and live changes
  ([#22](https://github.com/OpenReliant/openreliant-editor/issues/22));
- the guided first mission ([#6](https://github.com/OpenReliant/openreliant-editor/issues/6));
- new mods from templates ([#7](https://github.com/OpenReliant/openreliant-editor/issues/7));
- adding and editing records with forms
  ([#8](https://github.com/OpenReliant/openreliant-editor/issues/8));
- opening `.hog` mods ([#9](https://github.com/OpenReliant/openreliant-editor/issues/9));
- the General and Appearance settings
  ([#10](https://github.com/OpenReliant/openreliant-editor/issues/10)).
