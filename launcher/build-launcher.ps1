# Builds KFCLauncher.exe with the .NET Framework C# compiler that ships with Windows (nothing to install).
# The banner and the icon are made from two screenshots of your own copy of the game, if you add them
# (launcher\assets\menu.png: the main menu; launcher\assets\select.png: the character select, both at
# any 4:3 size). They are not in the repository; without them the launcher has a plain title.
# Usage: .\build-launcher.ps1 [-Out <folder>]
param([string]$Out = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build'))
$here = $PSScriptRoot
$res = @()
$iconArg = @()
if ((Test-Path "$here\assets\select.png") -and (Test-Path "$here\assets\menu.png")) {
    Add-Type -AssemblyName System.Drawing
    $src = [System.Drawing.Image]::FromFile("$here\assets\select.png")
    $k = $src.Width / 640.0

    # Banner, 1040x260 (shown at half size, sharp on high-DPI screens): the main menu's "KUNG FU CHAOS"
    # title over the character select's row of faces.
    $banner = New-Object System.Drawing.Bitmap 1040, 260
    $g = [System.Drawing.Graphics]::FromImage($banner)
    $g.InterpolationMode = 'HighQualityBicubic'
    $menu = [System.Drawing.Image]::FromFile("$here\assets\menu.png")
    $km = $menu.Width / 640.0
    $g.Clear([System.Drawing.Color]::Black)
    $g.DrawImage($menu, ([System.Drawing.Rectangle]::new(0, 0, 1040, 91)),
                 ([System.Drawing.Rectangle]::new(0, 0, [int](640 * $km), [int](56 * $km))), 'Pixel')
    $g.FillRectangle([System.Drawing.Brushes]::Black, 820, 0, 220, 91)   # the "100% unlocked" corner
    $g.DrawImage($src, ([System.Drawing.Rectangle]::new(0, 91, 1040, 169)),
                 ([System.Drawing.Rectangle]::new(0, [int](61 * $k), [int](640 * $k), [int](99 * $k))), 'Pixel')
    $menu.Dispose()
    $g.Dispose(); $banner.Save("$here\banner.png", [System.Drawing.Imaging.ImageFormat]::Png); $banner.Dispose()

    # Icon: one face from the row, 64x64.
    $ico = New-Object System.Drawing.Bitmap 64, 64
    $g = [System.Drawing.Graphics]::FromImage($ico)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($src, ([System.Drawing.Rectangle]::new(0, 0, 64, 64)),
                 ([System.Drawing.Rectangle]::new([int](8 * $k), [int](58 * $k), [int](46 * $k), [int](46 * $k))), 'Pixel')
    $g.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($ico.GetHicon())
    $fs = [System.IO.File]::Create("$here\icon.ico"); $icon.Save($fs); $fs.Close()
    $src.Dispose()
    $res = @("/resource:$here\banner.png,banner.png")
    $iconArg = @("/win32icon:$here\icon.ico")
}

New-Item -ItemType Directory -Force $Out | Out-Null
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /target:winexe /optimize+ "/out:$Out\KFCLauncher.exe" @iconArg @res `
    /r:System.Windows.Forms.dll /r:System.Drawing.dll "$here\KFCLauncher.cs"
if ($LASTEXITCODE -eq 0) { "OK -> $Out\KFCLauncher.exe" } else { "FAILED ($LASTEXITCODE)"; exit 1 }
