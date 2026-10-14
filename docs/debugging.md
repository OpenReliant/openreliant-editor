# Debugging a mission

The editor links to OpenReliant over the game's editor link
([The editor link](https://github.com/OpenReliant/openreliant/blob/main/docs/engine/editor-link.md))
and holds the mission's script at breakpoints as the game plays it.
[The design](../design/debugger.md) describes the whole debugger and the stages it comes in.

## Linking

- **Play** (F5, or Cmd+R on macOS) builds the mission and starts OpenReliant on it with
  `--editor-link`, then connects as the game listens. Settings · Editor link · Link on Play turns
  this off. While a game is linked, Play only builds, and the game reads the new build at the
  mission's next attempt.
- **Game · Link to game** connects to a game started some other way with
  `openreliant --editor-link`, and waits until one listens.
- **Unlink** (Shift+F5, or Cmd+. on macOS) closes the link. The game lets the script go, and plays
  on.

The toolbar's chip shows the link: `OpenReliant · not linked` or `waiting`, then the game's name
with `linked` or the mission it plays.

## Breakpoints

A click in the gutter, or F9 (Cmd+\ on macOS), sets a breakpoint on a line, and the script holds
before the line's first statement. A line the script can't hold on, such as a `return`, an `end`, a
comment or a blank line, passes its breakpoint on to the next line that holds, in the same trigger
or part.

A breakpoint is a red dot while the game plays the mission built from the text as it is, and a red
ring otherwise: when no game is linked, when it plays another mission, or when it plays an older
build. Each attempt at a mission reads the mission's file again, so a new build holds from the
mission's next attempt.

The editor keeps each source file's breakpoints in its settings folder, in `breakpoints.ini`, not
in the mod. Settings · Editor link counts them, and removes them all.

## While the script is held

The source marks the held line in orange, the outline marks its trigger or part `HELD`, and the
inspector names its thread.

| Action | Windows and Linux | macOS | What the script does |
|---|---|---|---|
| Continue | F5 | Ctrl+Cmd+Y | Runs on to the next breakpoint |
| Step over | F10 | F6 | Runs to the next statement of the same block, past the parts it calls |
| Step into | F11 | F7 | Runs to the next statement any thread runs |
| Run to cursor | Ctrl+F10 | Ctrl+Cmd+C | Runs on to the cursor's line |
| Pause | F6 | F8 | Pauses the whole mission, ships and all, or lets it go on |

- **Threads** lists the script's threads: where each one is, what started it, its call depth and
  what it waits for. A double click goes to a thread's line.
- **Variables** shows the game's variables that the source uses and the mission's globals, with
  their values in the game. A value that changed since the last hold is orange. While the script
  runs, the editor polls the game for them, 4 times a second by default (Settings · Editor link ·
  State polling).
- **Output** lists what the link says: the game linked, each mission started, each hold.

As in the original, a held script holds up the mission's own work: the ships' orders, the script's
other threads, its timers and its clock wait, while the ships fly on as their orders last left
them. A held start part holds the mission's loading screen.

## Not made yet

- Conditions, hit counts, log points, Watch, the values inline and the Debugging screen
  ([#19](https://github.com/OpenReliant/openreliant-editor/issues/19)).
- The timeline ([#20](https://github.com/OpenReliant/openreliant-editor/issues/20)).
- The live scene ([#21](https://github.com/OpenReliant/openreliant-editor/issues/21)).
- Live changes ([#22](https://github.com/OpenReliant/openreliant-editor/issues/22)).
