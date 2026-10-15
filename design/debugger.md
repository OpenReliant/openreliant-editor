# The debugger

The design of the editor's debugger and its link to the game
([#5](https://github.com/OpenReliant/openreliant-editor/issues/5)): what it does, what it shows,
how it talks to OpenReliant, what OpenReliant still needs, and the order to make it in. The screens
it fills are [Script](README.md#script), held at a breakpoint, and [Debugging](README.md#debugging).

## What it does

- **Links to the game.** Play starts OpenReliant linked to the editor, and Link to game links to one
  already running. The link is OpenReliant's editor link, which carries the original's own
  messages to its mission editor and debugger
  ([The editor link](https://github.com/OpenReliant/openreliant/blob/main/docs/engine/editor-link.md)).
- **Holds the script at breakpoints.** A breakpoint on a line of the source stops the game's script
  before that line's statement runs. The editor shows where it stopped, the script's threads, the
  mission's globals and the game's variables.
- **Steps through the script** a statement at a time, into or over the parts it calls, or runs on
  to the next breakpoint or to the cursor.
- **Checks conditions and counts hits**, and writes log points to Output without stopping.
- **Shows the script listing beside the source**, with the held instruction and the breakpoints in
  both.

Later: a timeline of the run and the live scene, which OpenReliant carries from 0.16.0, and live
changes, which send each build into the running game once OpenReliant takes them.

## The link

OpenReliant listens for an editor when it starts with `--editor-link`, at 127.0.0.1, port 22539 or
the port `--editor-link-port` gives. It takes one editor at a time. Each message is an 8-byte
header, its tag, a halfword of 0 and its payload's size, then the payload. The editor reads and
writes them with OpenReliant's own definitions (`engine.link`, `engine.game.mission.editor`), which
its library exports, so the two can't drift apart.

| Tag | From | What it says | What the editor does with it |
|---|---|---|---|
| `0x100` Hello | Game | The link's protocol, OpenReliant's version, the game, its script VM | Picks the game's profile, and says it's linked |
| `0x101` Mission started | Game | The mission's number and file | Says the mission plays |
| `0x104` Mission file | Game | The mission's file as the game runs it, its globals as they stand | Matches it with the build, and sends the breakpoints |
| `0x09` Script flags | Editor | A byte for each byte of the script, bit 0 set where it stops | Sent for each attempt at the mission, and as breakpoints change |
| `0x1A` Stopped | Game | The offset in the script of the byte it stopped before | Holds: the line, then the state |
| `0x105` Get state | Editor | | Sent on each hold, and for watches while the script runs |
| `0x106` State | Game | The script's clock, hold, step and pause, threads, globals and variables. From OpenReliant 0.16.0, also each ship's order and target, and the triggers fired and the commands run since the last state | Fills Threads, Variables, Watch, the values shown inline, the timeline, and the live scene's orders |
| `0x103` Get mission | Editor | | Sent for the live scene, a few times a second while it shows. Only the file that comes with `Mission started` is answered with the flags |
| `0x15` Run control | Editor | Pause or go on, run on, step into, step over, run a part | Continue, the steps, Pause |
| `0x1B` First finished | Game | Whether the start parts' first thread has finished | Says when the start parts are done |
| `0x102` Mission ended | Game | | Says no mission plays, and keeps the link |

### A session

1. **Play** builds the mission, starts OpenReliant on it with `--editor-link`, and connects once the
   game listens; it tries again for half a minute while the game starts. **Link to game** waits for
   a game started some other way with `--editor-link`, and connects as it listens. While a game is
   linked, Play only builds: the game reads the new build at the mission's next attempt.
2. The game greets the editor (`Hello`). A game the editor has no profile for gets a toast, and the
   link closes.
3. As the mission starts, the game sends its file. The editor matches it with the build of its text,
   and sends the script's flags at once: the game holds its start parts until they come, for a
   second at most, so a breakpoint in a start part can stop it. The editor answers from the task
   that reads the link, not from the frame, so a busy frame doesn't hold the game up, and answers a
   mission it has no build of with no flags, so that its start goes on at once.
4. Each new attempt at the mission reads its file again, and the editor sends the flags again.
5. **Unlink** closes the link. The game lets the script go as the editor goes: its hold, its step
   and the pause clear, and it plays on. The breakpoints stay in the editor, and come back with the
   next Play or Link to game; the editor never links again on its own.

### Matching the game's mission with the build

Breakpoints and the held line need the map of the build's source lines to the script's statements
(below). The build is of the text as it is, which the editor checks as it's typed. The editor uses
the map only while the game runs that build: the mission's number is the document's, and the
scripts and their routines are the same bytes as the build's. Otherwise:

| The game plays | Toolbar chip | Breakpoints |
|---|---|---|
| Another mission | `StarLancer · mission 12` | Not sent |
| An older build of this mission | `Older build · restart mission` | Not sent; the next attempt reads the new file |
| This build | `StarLancer · mission 90` | Sent |

The globals the game sends are its current values, so the match leaves them out.

## What the editor shows

### The link's states

| State | Toolbar chip | Status bar | Start screen's game |
|---|---|---|---|
| Not linked | `OpenReliant · not linked` | `Live changes: not linked` | `OpenReliant · not linked` |
| Waiting for the game | `OpenReliant · waiting` | | |
| Linked, no mission | `StarLancer · linked` | `Live changes: planned` | `StarLancer · linked · OpenReliant 0.15.0 · port 22539` |
| A mission playing | `StarLancer · mission 90` | | |
| Held | `Held · line 46 · 41 s` | `Held` and the debugging keys | |
| Paused | `Paused · 41 s` | `Paused` | |

The chip of a held script names the line, and the condition where one held it:
`Held · line 53 · condition true`. The clock beside it is the script's, from the state.

### Breakpoints

A breakpoint stops the script before the statement it's on. The gutter draws it in red; one the
game doesn't hold yet, because no build of this mission plays, is a red ring.

| Kind | Set by | Gutter | Sent as |
|---|---|---|---|
| Line | A click in the gutter, or F9 (Cmd+\\ on macOS) | Red dot | The flag of the line's first statement |
| Condition | The breakpoint's editor: `Break if` and an expression | Red dot with a bar | The same flag; the editor checks the condition |
| Hit count | The breakpoint's editor: `Hit count` and a number | Red dot with a number | The same flag; the editor counts |
| Log point | The breakpoint's editor: `Log point` and a message with `{expressions}` | Red diamond | The same flag; the editor logs and runs on |
| Offset | The listing's gutter, or `break @<offset>` in the palette | Red dot in the listing | The byte's flag |
| Also break on | The Breakpoints panel: trigger entry, part entry, a command | | Each matching statement's flag |

A line holds only where a statement starts. A breakpoint set on a blank line or a comment moves to
the next line with a statement, as the build's map says. Breakpoints stay with their lines as the
text changes, and the editor keeps them for each source file in its settings folder, not in the
mod.

The breakpoint's editor opens from the gutter's context menu or a double click on the dot, as the
[Debugging](README.md#debugging) page draws it: Always, Condition, Hit count or Log point, and the
expression or message. Expressions use mission source's own words: the globals by their names,
`game.` and the game's variables, numbers, comparisons, `and`, `or` and `not`.

**Checked by the editor.** The game stops at every flag. On a stop, the editor asks for the state,
works out the condition or the count, and sends Continue at once where it doesn't hold; a log point
writes its message to Output and does the same. While it decides, the game holds as it does at any
stop, so a condition on a line that runs often slows the mission. The Breakpoints panel says so for
a condition that has held up the game for more than a second in all.

### Holding and stepping

| Action | Windows and Linux | macOS | What the game does |
|---|---|---|---|
| Play in game, linked | F5 | Cmd+R | Starts, linked |
| Continue | F5 | Ctrl+Cmd+Y | Runs on to the next breakpoint (run control 1) |
| Step over | F10 | F6 | Stops before the next statement of the same block, or the block a return goes back to (3) |
| Step into | F11 | F7 | Stops before the next statement any thread runs (2) |
| Run to cursor | Ctrl+F10 | Ctrl+Cmd+C | Runs on to the cursor's line: the editor sets a flag there, and takes it away at the next hold |
| Pause mission | F6 | F8 | Stops the whole mission, ships and all, or lets it go on (run control 0) |
| Unlink | Shift+F5 | Cmd+. | Closes the link; the script plays on |
| Link to game | | | Connects to a game already running |

A held script holds up the mission's own work: the ships' orders, the controls, the script's other
threads, its timers and its clock wait, while the ships fly on as their orders last left them. Pause
stops the mission whole. A held start part holds up the mission's start, and the game shows its
loading screen. The status bar and the Debugging screen say this in a line, so that a held mission
doesn't look broken.

### While the script is held

As the [Script](README.md#script) page draws it:

- **The source** scrolls to the held line, marked in orange in the gutter and across the line. The
  breadcrumbs end with the statement and the offset: `statement 1 of 2 · script offset 10`.
- **The game's values inline**, after each line that sets or reads a global or a game variable:
  `now 0`.
- **The outline** marks the trigger or part that holds with a `HELD` badge.
- **The inspector** of the held record has a line for its thread: `Thread 0 · held · statement 1`.
- **Threads**, from the state: the slot, its state (Held, Waiting, Ready), where it is (`line 46 ·
  offset 10`), what started it (the trigger, written as in the source, or the start part), its
  depth, and what it waits for (`nothing`, `clock 45.0 s`, or `its trigger`). A last line says
  whether the start parts are done. A double click goes to the thread's line.
- **Variables**: the game's variables, then the mission's globals by their names. A value that
  changed since the last hold is orange.
- **Watch**: expressions, each worked out on each hold. A new watch is typed at the end of the list.
- **Output**: the link's messages and the log points' lines, with the script's clock.
- **The Blocks view**, once it's made
  ([#3](https://github.com/OpenReliant/openreliant-editor/issues/3)), marks the breakpoints and the
  held statement on the blocks.

The values are the state as of the hold. While the script runs, Variables and Watch poll the state,
4 times a second by default, which costs the game nothing it would notice.

### The Debugging screen

The [Debugging](README.md#debugging) layout of the same panels: the Breakpoints panel on the left,
the source and the script listing side by side, Watch, Variables and Threads on the right, and the
timeline under them. The listing marks the held instruction and the breakpoints' bytes, and a click
on a line of either side selects its counterpart in the other. Its own gutter sets breakpoints by
offset. `@@` and an offset in the command palette goes to the offset's line.

The timeline has a row each for the triggers fired, the commands run and the holds, on the script's
clock. Each state gives the triggers and commands since the one before; the holds are the editor's
own.

### Settings: Editor link

The Settings' Editor link page, which the [Keys](README.md#keys) page's layout gives:

| Setting | Default |
|---|---|
| Link on Play: Play adds `--editor-link` | On |
| Port: `--editor-link-port` | 22539 |
| State polling: Off, 1 Hz or 4 Hz | 4 Hz |
| Breakpoints: per source file, with Remove all | |
| Live changes | Off, until OpenReliant takes them |

## In the editor

| Module | What it does |
|---|---|
| `link/connection.zig` | The connection: connects, reads the messages on a task of its own into a queue the frame takes from, and writes them. It answers `Mission file` with the flags itself, through the session's breakpoints. |
| `debug/session.zig` | The debugging session: the link's state, the match with the build, the flags, the holds, conditions, counts and log points, and the actions |
| `debug/breakpoints.zig` | The breakpoints of each source file: kind, condition, count, message, enabled; kept in the settings folder |
| `debug/expression.zig` | Stage 2: conditions, watches and log points' expressions, read with OpenReliant's Luau parser and worked out over the state |
| `panels.zig` | Threads, Breakpoints, Variables, Watch and Output |

OpenReliant's library reads the text payloads of its own messages, `key=value` lines, into
records (`Hello`, `MissionStarted`, `State`), which the session takes as they are.

What's the game's goes in its profile (`game.Profile`), so that the session never names
StarLancer's offsets or opcodes:

- the build's map of source lines to the script's statements, which `build` gives with the file;
- the flags for a set of offsets, as the game's VM reads them;
- whether two mission files have the same script and routines;
- the statements a kind of entry starts: each trigger's first, each part's first, each command of a
  kind;
- the names of the state's globals, from the outline.

## What OpenReliant gives

| What | For | In OpenReliant |
|---|---|---|
| The compiler's map of source lines to the script's statements, from its library | Line breakpoints, the held line, the listing's lines | 0.15.0 ([#1206](https://github.com/OpenReliant/openreliant/issues/1206)) |
| The link's text payloads read into records in its library, which `openreliant debug` reads them with too | The editor and `openreliant debug` reading them alike | 0.15.0 ([#1206](https://github.com/OpenReliant/openreliant/issues/1206)) |
| The start of a mission waiting for the editor's flags, rather than for a fifth of a second | Breakpoints in the start parts, on a slow computer too | 0.15.0 ([#1206](https://github.com/OpenReliant/openreliant/issues/1206)) |
| The script's events in `State`: the triggers fired and the commands run | The timeline | 0.16.0 ([#1207](https://github.com/OpenReliant/openreliant/issues/1207)) |
| Each ship's place and heading in `Mission file`, kept up to date every frame, and its order and target in `State` | The Live scene panel, the inspector's Live section, watches of ranges | 0.16.0 ([#1059](https://github.com/OpenReliant/openreliant/issues/1059)) |
| The editor's live changes to the mission | Live changes, the status bar's switch | Not yet ([#1057](https://github.com/OpenReliant/openreliant/issues/1057)) |
| Starting a mission partway through, with the variables the earlier parts set | The `earlier parts` box of Play from part | Not yet ([#577](https://github.com/OpenReliant/openreliant/issues/577)) |

The compiler keeps each statement's place in the source until the script is written, and writes
down the offset of the instruction the VM stops before. The start's wait is an improvement on the
original's fixed one: the game waits for the editor's flags, or for a second at most, while an
editor is linked, and doesn't wait without one.

## In stages

Each stage is a release of its own, with OpenReliant's part merged first.

1. **Holding** ([#5](https://github.com/OpenReliant/openreliant-editor/issues/5)). OpenReliant: the
   compiler's map, the payloads' records, and the start's wait. Editor: the connection, Play
   linked, Link to game, Unlink, line breakpoints, the held line, Continue, the steps, Run to cursor
   and Pause, Threads, Variables and Output, the link's states, and the Editor link settings.
2. **Conditions and watches** ([#19](https://github.com/OpenReliant/openreliant-editor/issues/19)).
   Conditions, hit counts, log points, breakpoints by offset and the kinds of entry, the
   breakpoint's editor, Watch, the values shown inline, the Debugging screen with the listing
   beside the source, and `@@` offsets in the palette.
3. **The timeline** ([#20](https://github.com/OpenReliant/openreliant-editor/issues/20)), from the
   script's events in OpenReliant 0.16.0's `State`.
4. **The live scene** ([#21](https://github.com/OpenReliant/openreliant-editor/issues/21)), from
   OpenReliant 0.16.0's `Mission file` and `State`: the Live scene panel, the inspector's Live
   section, watches of ranges, and the Scene view's ships where they are now in the game.
5. **Live changes** ([#22](https://github.com/OpenReliant/openreliant-editor/issues/22)), once
   OpenReliant takes them: each build sent into the running game, with the status bar's switch.

## Checking it

- **Tests** with inputs made by hand: the payloads read into records, the flags for a set of
  offsets, the map from lines to offsets and back, conditions and log messages worked out over a
  state, and the session's steps from one message to the next.
- **A game made of messages**: a test that listens on a free port as OpenReliant does, greets the
  editor, sends a mission's file and a stop, and checks what the editor sends back, without the
  game.
- **The real game**, headless: `openreliant --editor-link --mission 90 --no-sound` with the editor
  linked, for each stage's new actions, on a mission of the guide to writing missions.

## Open questions

- **Unlink closes the link.** It could instead keep the link and only clear the breakpoints in the
  game, as a debugger's detach without leaving.
- **The editor checks conditions.** OpenReliant could check them in the game later, so that a
  condition on a line that runs often costs nothing; the link would need a message for it.
- **Breakpoints are kept in the settings folder.** They could go in the mod, to share them, but a
  mod would then carry the editor's files.
