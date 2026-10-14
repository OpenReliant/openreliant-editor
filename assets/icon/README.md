# The editor's icon

OpenReliant's icon with EDITOR under it: the letters OR in Newtown, the O in the website's
off-white (`#e8eaf0`) and the R in its orange (`#f08a2c`), raised, and EDITOR in IBM Plex Sans
SemiBold, the interface's font, in its grey (`#8a93a6`) and spaced 0.14 em as in the menu bar, as
wide as OR. They stand on OpenReliant's dark sky: `#07080c`, with a warm glow from the top right
(`#3a1d0c`), a blue one from the bottom left (`#101a3a`) and a few faint stars, which fade out at
the smaller sizes.

| File | What it is |
|---|---|
| `openreliant-editor.svg` | The source, 1024 by 1024. The letters are Newtown's and Plex's outlines, so it needs no font. |
| `openreliant-editor-16.png` to `openreliant-editor-1024.png` | The icon at 16, 32, 48, 64, 128, 256, 512 and 1024 pixels. |
| `openreliant-editor.ico` | For Windows: 16, 20, 24, 32, 40, 48 and 64 pixels as bitmaps, and 256 as a PNG. |
| `openreliant-editor.icns` | For macOS: 16, 32, 128, 256 and 512 points, each at 1x and 2x. |

`openreliant-editor.exe` carries the `.ico` (`build.zig`), and Windows shows it for the file, the
editor's window and its taskbar button. On macOS and Linux, the editor gives its window the 256 and
512 pixel PNGs, which macOS shows in the Dock ([`icon.zig`](../../src/platform/icon.zig)).

`make icon` makes the PNGs, the `.ico` and the `.icns` from the SVG again
([`icon.sh`](../../scripts/icon.sh)). It needs `rsvg-convert` (librsvg), `icotool` (icoutils) and
macOS's `iconutil`.

## Credits and licence

Newtown is by Roger White, from Roger's Fonts, and is in the public domain
([fonts](../../design/fonts/README.md)). IBM Plex Sans is under the SIL Open Font License. The icon
is the editor's own work, under the [Mozilla Public License 2.0](../../LICENSE) like the rest of the
repository.
