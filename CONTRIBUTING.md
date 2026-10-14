# Contributing to OpenReliant Editor

OpenReliant Editor is a mission editor, script debugger and mod editor for
[OpenReliant](https://github.com/OpenReliant/openreliant). It follows OpenReliant's conventions for
its Zig, its documentation and its history, as OpenReliant's
[CONTRIBUTING.md](https://github.com/OpenReliant/openreliant/blob/main/CONTRIBUTING.md) gives them.
This guide gives what is the editor's own, and is written for people and coding agents alike:
`AGENTS.md` and `CLAUDE.md` point agents here.

## Getting started

- Install [Zig 0.17](https://ziglang.org). `zig build` builds the editor, `zig build test` runs the
  tests, and `zig build check -fincremental --watch` reports compile errors moments after a save.
  The first build fetches OpenReliant and the libraries `build.zig.zon` names, and builds the C and
  C++ ones.
- Run `make hooks` once. It installs a pre-commit hook that keeps the game's files out of the
  repository. `make help` lists the other workflows.
- `make run ARGS='<mod folder>'` opens a mod, `make run ARGS='<file>.dte'` a mission file. The editor
  needs a game folder set up by `openreliant install` for the mods list and the game's own
  missions ([installation guide](https://github.com/OpenReliant/openreliant/blob/main/docs/guide/installation.md)).

## How the editor is put together

[docs/architecture.md](docs/architecture.md) describes the modules: the platform, the interface
kit, the commands, the game profiles, the mission documents and the screens.

### The design is the reference

The screens in [`design/`](design/README.md) are what the editor looks like. A screen follows its
page in `design/screens`: its colours, sizes, text and order. Changing how a screen looks starts
with its page, whose picture is taken again in the same pull request (`make pictures`). Check a
screen against its page with `--screenshot`, which draws without a window:

```bash
zig-out/bin/openreliant-editor <mod folder> --screenshot script.png
```

Text goes where a browser puts the design's: the fonts draw at the design's exact sizes
(`src/ui/fonts.zig`), and `gui.textTop` places a line in the middle of its box as the stylesheet
does, its baseline on a whole pixel.

### Games come from their profile

OpenReliant will play other games than StarLancer, so the editor never names a game's commands,
conditions, records or files outside `src/game/`. The interface asks the game's profile
(`src/game.zig`), and a profile reads them from OpenReliant's own tables and builds missions with
OpenReliant's own compiler (`src/game/starlancer.zig`). A profile keeps its data, its names,
extensions, words and records, apart from what it asks of OpenReliant's library, so that profiles
can become files that a Game mode edits.

### Every action is a command

Each action is declared once in [`src/commands.zig`](src/commands.zig): its label, its icon, its
menu, and its default keys on Windows and Linux and on macOS. The menus, the toolbar, the command
palette and the Keys settings read that table, and the keys run the action through it, so an
action has the same name, icon and keys wherever it shows. An action that doesn't work yet still
shows, greyed out, with the issue that plans it (`commands.plans`).

### Text on screen

Labels and short fragments rather than sentences: `Held · line 46`, `1 problem`, `Use enemies`.
Technical terms are fine where they're the clearest word. The text on screen uses American spelling,
as OpenReliant's screens do; docs and comments use British spelling.

## Writing Zig

Write idiomatic Zig 0.17, as OpenReliant's guide describes: name every number, give an id space an
`enum` and switch over it exhaustively, use tagged unions for variants and optionals for "none",
check invariants with `comptime`, and share code rather than copy it.

C and C++ come in through two shims and one header: the text editor's
([`src/ui/text_editor`](src/ui/text_editor)), Dear ImGui's internal calls
([`src/ui/imgui_extras`](src/ui/imgui_extras)), and [`src/platform/c.h`](src/platform/c.h), which
the build translates into the `c` module with SDL3 and Dear Bindings' C API for Dear ImGui.

Add `test` blocks next to the code in the same change, with inputs built by hand so that they run
without the game's files. `--check-missions` opens each of a game's own missions as source and
builds it again, for checking a change against the stock missions:

```bash
zig-out/bin/openreliant-editor --check-missions --game <game folder>
```

## Documentation

Document what the editor does under [`docs/`](docs), in plain, present-tense reference style. Call
the engine OpenReliant and the original game StarLancer. The project's text uses colons, commas,
parentheses or a second sentence in place of em and en dashes, which `make check-files` refuses.

## Checks

Before you open a pull request, run:

```bash
make check
```

It checks the formatting, the repository's files and the tests. CI runs the same on Linux, macOS
and Windows, and the tests in ReleaseFast too.

## Commits and pull requests

- Branch from `main` (`feat/script-view`, `fix/...`, `docs/...`) and open a pull request. `main`
  changes only through squash-merged pull requests.
- Title the pull request in [Conventional Commits](https://www.conventionalcommits.org) form:
  `feat: the Script view builds missions as they're typed`. Keep the body short, and end it with
  `Closes #N` for each issue it finishes.
- File an issue for each gap you leave, and link it from the code where the gap is.
- Releases come from [release-please](https://github.com/googleapis/release-please), as
  OpenReliant's do ([`release.yml`](.github/workflows/release.yml),
  [`release-please-config.json`](release-please-config.json)): it keeps a release pull request open
  with the next version and its changelog, and merging it tags the version and attaches the builds
  for Windows, macOS and Linux, on x86-64 and Arm, with their checksums. `build.zig.zon` holds the
  version being worked towards, which `--version` reports; the first release is 0.0.1.
- The repository holds the editor and its design. The game's files, and everything extracted or
  derived from them, stay out: the pre-commit hook, `make check-files` and CI see to it.
