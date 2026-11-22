# Kung Fu Chaos launcher for Mac

A one-file SwiftUI app. It picks the options, saves them and starts `~/Games/KFC/game-src/build/kfc_recomp`
(Metal backend).

## Build (on the Mac, macOS 14+, Apple Silicon)

    zsh build.sh      # produces ./KFCLauncher
    ./KFCLauncher

## Where it saves

- `~/Games/KFC/config.toml`: render, present and display. It is the same config the in-game menu uses (the
  game is started with `RECOMP_CONFIG`). The launcher only updates its own keys and keeps the rest of the file.
- `~/Games/KFC/launcher.ini`: upscaler, progressive, audio DSP, controls, rumble and frame rate (passed as
  environment variables).
- `~/Games/KFC/log.txt`: the game's stderr (the "Open log" button).

Your game files go in `~/Games/KFC/game/Kung Fu Chaos` (your own copy of the disc).

## Game Mode

With `gamemode=1` (the default) the launcher runs the game as its own app bundle, `~/Games/KFC/KFC Game.app`,
so macOS turns Game Mode on for it. The bundle holds a copy of `build/kfc_recomp`, an `Info.plist` with
`LSSupportsGameMode`, `GCSupportsGameMode` and the action-games category, and the launcher's icon if it has
one; it is signed ad hoc and opened through LaunchServices (`open -W -n -a`), with the `RECOMP_`, `MTL_` and
`SDL_` variables passed as `--env`. It is rebuilt only when the SHA-256 of `build/kfc_recomp` changes (the
hash is kept next to the bundle, in `KFC Game.app.src`). Game Mode turns on with the game's own borderless
full screen; the system's full-screen Space is not needed. A bundle that lives under `~/Desktop` is ignored
by Game Mode, so keep `~/Games/KFC` where it is (a link on the desktop to the launcher is fine).

The first launch of a new bundle, or after an update of the game, compiles its Metal shaders again: expect
a slower first load and some stutter in the first fight. If the bundle cannot be made, the launcher logs a
`[launcher]` line in `log.txt` and runs the plain binary. `gamemode=0` always runs the plain binary.

## Switches in launcher.ini

The PERFORMANCE section has VSync, Game Mode and Metal HUD toggles and the frame rate. Keys, with the default
first (each one maps to an environment variable or a `RECOMP_DEBUG` entry of the kfc-v2 toolkit):

| Key | Default | Other value |
|---|---|---|
| `gamemode` | `1`: the game runs as `KFC Game.app` (Game Mode) | `0`: the plain binary |
| `vsync` | `0`: the window's layer without display sync | `1`: display-synced layer |
| `hud` | `0` | `1`: Apple's Metal HUD (`MTL_HUD_ENABLED=1`) |
| `fps` | `60` | `120`, `144`, `240`: not tested on the Mac yet (game speed, sound and hits unchecked) |
| `directcache` | `1`: the Metal translator's direct lookups (`metal_direct_cache=1`) | `0` |
| `aliascheck` | `sync`: a stale render target is dropped at a texture-decode sync (`rt_alias_check=sync`) | `0` |
| `fastshaders` | `1`: combiner fragments without discard where no kill can fire, and fast math (`metal_nodiscard=1,metal_fs_fastmath=1`) | `0` |

Rescue: open the app holding the Option key and it loads the defaults instead of the files (nothing is saved
until PLAY).

## Quick manual test

1. Open `./KFCLauncher`: the dark "Kung Fu Chaos" window shows with its four sections.
2. Set "Internal resolution" to 3x.
3. Press PLAY: the window hides and the game starts.
4. Quit the game: the launcher comes back by itself.
5. Close and reopen the launcher: it still says 3x. Then change something in the game's menu (the scale, say),
   quit, reopen the launcher and check that it shows it.
