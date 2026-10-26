# Kung Fu Chaos — static recompilation

A native Windows build of **Kung Fu Chaos** (Just Add Monsters / Microsoft Game Studios, Xbox, 2003),
made with the [xboxrecomp](https://github.com/sp00nznet/xboxrecomp) toolkit: the game's own x86 code
lifted to C and linked against a replacement of the Xbox kernel, GPU, audio and USB, with the D3D11
pushbuffer backend from [apexJCL's fork](https://github.com/apexJCL/xboxrecomp).

**This repository has no game data and no generated code.** You need your own copy of the game: the
build regenerates the C from your `default.xbe` (`regen.sh`), the way Burnout 3 and Wreckless do it.

## Status

Playable in every mode tested so far, at 60 FPS (or 120/144) on D3D11:

- Menus, intro, movies, character and stage select, matches with HUD, pause, saves and unlocks.
- Battle Game, Championship, Miniseries and Freestyle; up to four players.
- Up to 4x internal resolution (2560x1920), anisotropic filtering, progressive 480-line matches
  (the game itself only has 480i: see `patches/`), 4:3 or experimental widescreen.
- Sound and music, including the match effects.

What it took, with the evidence for each fix: [docs/FINDINGS.md](docs/FINDINGS.md).
Not yet checked: Rehearsal, Special Features, several physical controllers. Known cosmetic issues are at
the end of that file.

## What you need

- Windows 10/11 64-bit with Direct3D 11.
- Your own **Kung Fu Chaos (NTSC-U)** disc, its contents copied to `game\Kung Fu Chaos\` (with
  `default.xbe`).
- Visual Studio 2022 or newer (C++ workload, or the Build Tools), LLVM (`clang-cl`), Python 3.10+ with
  `capstone`, Git, and a bash (Git Bash) for `regen.sh`.

## Build

```bash
# next to this repository:
git clone https://github.com/sp00nznet/xboxrecomp.git                  # disassembler (tested at f0f8a46)
git clone -b kungfuchaos https://github.com/maxiumpro/xboxrecomp.git xboxrecomp-apex   # D3D11 runtime + lifter
cd kungfuchaos-recomp
./regen.sh            # writes src/recomp/gen from game/Kung Fu Chaos/default.xbe and applies patches/
build.bat             # build\kfc_recomp.exe
```

`regen.sh` reads `GAME`, `XBOXRECOMP`, `XBOXRECOMP_APEX` and `PYTHON` if your layout differs.
The `kungfuchaos` branch is apexJCL's `blinx2/portability` plus this port's toolkit fixes, while they are
proposed upstream.

## Play

`launcher\build-launcher.ps1` builds **KFCLauncher.exe** into `build\` (nothing to install: it uses the C#
compiler that ships with Windows). It sets the game's options and starts it; `--play` starts it straight
away with the saved ones. `tools\make-package.ps1` makes a portable folder for another PC
(executable, launcher, runtime DLLs and your game files).

| Option | What it does |
|---|---|
| Internal resolution | 1x to 4x the Xbox's 640x480 |
| Window mode, size | Window or borderless fullscreen |
| Aspect ratio | 4:3, or 16:9 / 16:10 / 21:9 (experimental) |
| Upscaling filter, overscan | How the picture reaches the window |
| VSync, frame rate | 60, 120, 144, 165, 240, your monitor's rate minus 3 for VRR, or any |
| Anisotropic filtering | Up to 16x |
| Progressive matches | 480 lines instead of the console's fields (on by default) |
| CPU threads, frame pacing, low latency | |
| Controllers, first player, keyboard, vibration | Up to four XInput pads |

The launcher's banner and icon are made from your own screenshots if you put them in
`launcher\assets\` (see `build-launcher.ps1`); otherwise it shows a plain title.

## Credits

- [sp00nznet/xboxrecomp](https://github.com/sp00nznet/xboxrecomp) and its contributors: the toolkit.
- [apexJCL](https://github.com/apexJCL/xboxrecomp): the D3D11 pushbuffer backend this port runs on.
- [xemu](https://xemu.app) as the reference for how the hardware behaves (read, not copied).

## License

MIT for what is in this repository (see LICENSE). Kung Fu Chaos and its contents belong to their owners;
none of it is included or needed here beyond your own copy. Not affiliated with Microsoft or
Just Add Monsters.
