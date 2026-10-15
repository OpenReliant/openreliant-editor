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
| [`mission/document.zig`](../src/mission/document.zig) | An open mission: its source, its checks, its build and its breakpoints, and the changes the interface asks for |
| [`mission/edit.zig`](../src/mission/edit.zig) | Changes to spans of mission source: a field of a record's table set, added or taken out, an argument replaced |
| [`link/connection.zig`](../src/link/connection.zig) | The editor link's connection to the game, on a task of its own |
| [`debug/session.zig`](../src/debug/session.zig) | The debugger: the link's state, the game's mission matched with the build, the holds, the state and the actions |
| [`debug/breakpoints.zig`](../src/debug/breakpoints.zig) | Where each breakpoint holds the script, and each source file's breakpoints kept in the settings folder |
| [`shell.zig`](../src/shell.zig) | The workspace's menu bar, toolbar, dock space and status bar |
| [`panels.zig`](../src/panels.zig) | The dockable panels: the outline, problems, the inspector and the others |
| [`forms.zig`](../src/forms.zig) | The inspector's forms: a record's fields as controls that write the source |
| [`views/script.zig`](../src/views/script.zig) | The Script view: the source, its gutter, help and completion, and the listing |
| [`views/scene.zig`](../src/views/scene.zig) | The Scene view: the map of the mission's ships and markers, its ranges, curves and routes, and moving them |
| [`views/scene/drawing.zig`](../src/views/scene/drawing.zig) | How the map draws its parts: the grid, rings, legs, marks, names and notes |
| [`palette.zig`](../src/palette.zig) | The command palette, Play from part, and the game's missions |
| [`screens/`](../src/screens) | The start screen and the settings |
| [`toasts.zig`](../src/toasts.zig) | Short messages that fade out |
| [`ui/`](../src/ui) | The interface kit: colours, fonts, icons, widgets, the text editor, and the map's plot (ImPlot, through a C shim) |
| [`platform/`](../src/platform) | The window, SDL_GPU, ImGui's backends, and the C header the build translates |

## The game profile

The interface never names a game's commands, conditions, records or files. It asks the game's
profile, a `game.Profile`:

- the game's name, its script's dialect, and its files' extensions;
- the words of mission source, from the game's own tables: the language's keywords, mission
  source's declarations, the game's commands and conditions with their descriptions and
  parameters, the game's variables, and the names of its values;
- the records a mission's source declares, for the outline and the inspector, the fields each
  record's table can give, and the changes that edit them or declare a new record;
- what the map shows of a mission: where its records start and which way its ships point, the
  ranges its triggers watch, and its curves;
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

## Editing records

The inspector shows the selected record as a form ([Editing records](editing.md)). The profile gives
the fields each record's table can give, from OpenReliant's tables of the language
(`dte.source.language`), each with its kind, which picks its control: a list of the mission's
records or of the game's values, X, Y and Z for a vector, a box for a number, a checkbox, or the
value's source for the rest. A few hints lay out a ship's place as the design does, under a heading
with its angles on one row.

A change, from a form, the outline's + or a Problems card's fix, is a change to one span of the
source, made as one step of the editor's undo. OpenReliant's syntax tree gives where each node
starts; `mission/edit.zig` reads the text from there for where the value ends, and sets, adds or
takes out a field in the table's own layout: on its line, or on a line of its own where the items
are each on one. While drawing, the interface only queues the change (`Document.queue`). The app
makes it once the frame is drawn, since making it checks the text again, which replaces the outline
the frame drew from.

## The map

The Scene view's map draws on ImPlot, which gives it equal axes, the pointer's pan and dragging; the
editor reaches it through a C shim (`ui/plot/plot_shim.h`), as it reaches the text editor. The
editor zooms the map itself, around the pointer, and switches ImPlot's zoom off, since ImPlot
doesn't zoom while the pointer is over a marker.

The profile says what the map shows (`Profile.scene`). StarLancer's places each ship and marker by
its `position`, and says which are scenery: the planets of the original's table
(`create.planets.original`) and the sun's and nebulae's markers. It points a ship as OpenReliant
turns it by its angles (`mission.recordOrientation`), rings each ShipReached trigger's nav point or
waypoint at the 4000 the game watches within, rings each ship the script's `SetFlybackMarker`
names at its range, and draws each curve as the director's camera runs it
(`executor.curves.point`). It reads the routes from the script's syntax tree, in the order the
source gives it: the orders that `SetAI` gives, found by the command catalogue's parameters and
sorted by OpenReliant's order table (`ai.orders.Order`) into flying, jumping and coming in, and the
patrol routes `SetPatrolRoute` sets. A branch that leaves a ship in different places stops its
route. The document keeps the scene until its text or its outline changes, since reading it parses
the whole script.

The map fits the mission without its scenery, which lies far off. Each frame it gathers the things
that would overlap on the screen into one mark, the most important first: the selection, the player,
the ships, the markers, the camera's points and the scenery. Names then go in the same order, each
on the first side of its mark where it covers no mark, no name and none of the notes over the map,
such as the legend and the scale. A side where the name also crosses no route comes first. The map
draws its own grid, so that its scale is always a cell, and draws only the part of a range's ring or
a route's leg that shows. A dragged ship or marker is queued as an edit of its place, as the forms'
edits are, when it's let go.

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

- the Blocks view ([#3](https://github.com/OpenReliant/openreliant-editor/issues/3));
- Mod mode, with Reload scripts and Play with this mod only
  ([#4](https://github.com/OpenReliant/openreliant-editor/issues/4));
- the debugger's conditions, log points, Watch, values inline and Debugging screen
  ([#19](https://github.com/OpenReliant/openreliant-editor/issues/19)), its timeline
  ([#20](https://github.com/OpenReliant/openreliant-editor/issues/20)), the live scene
  ([#21](https://github.com/OpenReliant/openreliant-editor/issues/21)) and live changes
  ([#22](https://github.com/OpenReliant/openreliant-editor/issues/22));
- the guided first mission ([#6](https://github.com/OpenReliant/openreliant-editor/issues/6));
- new mods from templates ([#7](https://github.com/OpenReliant/openreliant-editor/issues/7));
- opening `.hog` mods ([#9](https://github.com/OpenReliant/openreliant-editor/issues/9));
- the General and Appearance settings
  ([#10](https://github.com/OpenReliant/openreliant-editor/issues/10)).
