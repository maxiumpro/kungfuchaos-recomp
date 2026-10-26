# Makes a portable folder to play on another Windows 10/11 PC: the executable, the launcher, the
# Visual C++ runtime and your game files. About 2.3 GB, most of it the game.
# Usage: .\tools\make-package.ps1 [-Out <folder>]     (default: package\KFC)
param([string]$Out = (Join-Path (Split-Path -Parent $PSScriptRoot) 'package\KFC'))
$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'build'
$game  = Join-Path $root 'game\Kung Fu Chaos'
if (-not (Test-Path "$build\kfc_recomp.exe")) { throw "build\kfc_recomp.exe not found: run build.bat first" }
if (-not (Test-Path "$game\default.xbe")) { throw "game\Kung Fu Chaos\default.xbe not found" }
New-Item -ItemType Directory -Force "$Out\game", "$Out\hdd" | Out-Null
Copy-Item "$build\kfc_recomp.exe" $Out -Force
& (Join-Path $root 'launcher\build-launcher.ps1') -Out $Out | Out-Null
# The Visual C++ runtime beside the executable: the other PC may not have it installed.
Copy-Item "$env:WINDIR\System32\vcruntime140.dll", "$env:WINDIR\System32\vcruntime140_1.dll" $Out -Force
robocopy $game "$Out\game\Kung Fu Chaos" /E /NFL /NDL /NJH /NJS /NP | Out-Null
# What a run creates, not the package: the emulated disk's partition images (Partition*.img, ~5 GB, made
# again on the next start), the shader cache and the logs. Saves (hdd\TDATA, hdd\UDATA) and the launcher's
# settings stay: a package that is also played in place keeps its progress.
Get-ChildItem "$Out\hdd" -Filter 'Partition*.img' -Force | Remove-Item -Force
Remove-Item "$Out\shadercache" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$Out\log.txt", "$Out\xbox_kernel.log", "$Out\audio.wav" -ErrorAction SilentlyContinue
@'
Kung Fu Chaos - native recompilation (xboxrecomp + D3D11 backend)

1. Plug in an Xbox (XInput) controller.
2. Open KFCLauncher.exe, pick the options, press PLAY.
   (KFCLauncher.exe --play starts straight away with the saved options: handy for a shortcut.)
3. The FPS shows in the game window's title. log.txt keeps the game's log.

Needs: Windows 10/11 64-bit with Direct3D 11. On Windows "N" editions install the Media Feature Pack.
'@ | Set-Content -Encoding utf8 "$Out\README.txt"
$mb = [math]::Round(((Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB)
"Package ready in $Out ($mb MB)"
