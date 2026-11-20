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

Rescue: open the app holding the Option key and it loads the defaults instead of the files (nothing is saved
until PLAY).

## Quick manual test

1. Open `./KFCLauncher`: the dark "Kung Fu Chaos" window shows with its four sections.
2. Set "Internal resolution" to 3x.
3. Press PLAY: the window hides and the game starts.
4. Quit the game: the launcher comes back by itself.
5. Close and reopen the launcher: it still says 3x. Then change something in the game's menu (the scale, say),
   quit, reopen the launcher and check that it shows it.
