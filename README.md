# Elite Penguin Force – PC Port

A Godot 4 PC port of *Club Penguin: Elite Penguin Force* (Nintendo DS).

## Required ROM: USA, Revision 2

The port is built on, and **only works with**, the North American (USA) release, **Revision 2**:

| | |
|---|---|
| Game code | `CLPE` |
| ROM version (header byte 0x1E) | `2` |
| MD5 of the used data (first 0x3FCE888 bytes) | `07cda977a67a0e6f9f2d4bd76ffaf1bf` |

Trimmed and untrimmed dumps both pass. Revisions 0 and 1, other regions, and patched or damaged dumps are refused,
with a message saying which one was given.

No game data is included with the port. You need your own copy of the game.

## First boot

1. Start the port. If no `game.epf` is found, the setup screen appears.
2. Click **Select ROM** and pick your `.nds` file.
3. The ROM is checked and unpacked into `game.epf` in the game folder, with a progress bar.
4. The game starts. From then on it runs from `game.epf`, and the ROM is no longer needed.

To set it up again, delete `game.epf`. A future update that needs more data bumps the archive's format number,
and the setup screen then runs once more.

## Where files go

Everything stays in the game folder, never AppData. In a built game that's the folder with the executable; when
running from the Godot project, it's the project folder.

- `game.epf`: the game data
- `saves/save.json`, `saves/minigames.json`, `saves/settings.json`: progress, minigame scores, options

Saves left in Godot's user data folder by an older build are copied over the first time.

## The .epf archive

A zip with its own extension:

- `manifest.json`: format number, game code, ROM version and checksum, file list, overlay table
- `fs/…`: every file of the cartridge's file system, byte for byte
- `ovl/<n>.bin`: the ARM9 overlays, decompressed

## Development

`godot --path . [-- RoomPrefix]` runs the port. It always reads `game.epf`; the game never reads a ROM directly.
F1 opens the dev menu.
