# OpenReliant Editor

A mission editor, script debugger and mod editor for
[OpenReliant](https://github.com/OpenReliant/openreliant), the open-source reimplementation of
StarLancer's engine. It links to the running game, so that a change to a mission or a mod shows in
the game as it's made.

**Status:** Mission mode's Script view works. It opens a mod's missions, a mission file or one of
the game's own missions as source, colours it with the game's commands, checks it as it's typed,
offers the game's commands and conditions as you type, explains them on hover and in the Reference
panel, builds the mission, and plays it in OpenReliant, from its start or from a part. The rest of
the [design](design/README.md) is in place and greyed out, each part with the issue that plans it.
The plan is OpenReliant's [#1126](https://github.com/OpenReliant/openreliant/issues/1126).

![The Script view of a mission, held at a breakpoint](design/images/mission-script.png)

## What it will do

- **Mission mode:** the Script, Scene and Blocks views of one mission, with a debugger that steps
  through the mission's script as the game plays it, and a guided path through a first mission.
- **Mod mode:** the manifest, the mod's Luau code with the game's console, the game's files to
  compare and replace, and packing for the catalogue.
- A native app in Zig, on SDL3 and Dear ImGui, that reads missions and mods exactly as OpenReliant
  does.
- Windows, macOS and Linux, on x86-64 and Arm, as OpenReliant, with each system's own keys.

It needs OpenReliant and your own copy of StarLancer.

## Building it

With [Zig 0.17](https://ziglang.org):

```bash
zig build --release=safe
zig-out/bin/openreliant-editor
```

Open a mod's folder, a mission's source or a mission file from the start screen, with Open…, or on
the command line:

```bash
zig-out/bin/openreliant-editor StarLancer/mods/first-mission
zig-out/bin/openreliant-editor StarLancer/mods/first-mission/mission90.dte
```

`--help` lists the options. [CONTRIBUTING.md](CONTRIBUTING.md) describes how to work on the editor,
and [docs/architecture.md](docs/architecture.md) how it's put together.

## Licence

[Mozilla Public License 2.0](LICENSE), as OpenReliant.
