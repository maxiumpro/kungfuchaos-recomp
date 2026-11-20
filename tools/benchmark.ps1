# Kung Fu Chaos performance test: runs the Championship route (until it fights in the cymbal and rooftop stages)
# through the package's launcher, once per configuration, and leaves the table in <package>\performance.txt.
# Usage (in the package folder): powershell -ExecutionPolicy Bypass -File benchmark.ps1 [-Secs 200] [-Configs '1:none','4:fsr']
#   Config = scale:postprocessing[:aniso[:VAR=v+VAR2=v]] (post: none | fsr | crt-lottes | crt-lottes-fast; aniso 0-16, 16 by
#   default; extra variables for the game, for diagnosis only). Window -WinSize (1440x1080), one virtual controller.
# Metric: interval between presented frames (ms) over the 600-frame windows already in a fight; 60 FPS = 16.7 ms.
param([int]$Secs = 200, [string[]]$Configs = @('1:none', '2:none', '3:none', '4:none', '2:fsr', '4:fsr'), [string]$WinSize = '1440x1080')
$Pkg = $PSScriptRoot
$Configs = @($Configs | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # -File passes '3:none,4:none' as one string
$pad = "$env:TEMP\kfc-bench-pad.txt"
$ini = "$Pkg\KFCLauncher.ini"; $iniBak = "$Pkg\KFCLauncher.ini.bench-bak"
if (Get-Process kfc_recomp -ErrorAction SilentlyContinue) { 'Kung Fu Chaos is already open: close it and run again.'; return }
if (Test-Path $ini) { Copy-Item $ini $iniBak -Force }
$gpu = (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Parsec|Virtual|Basic' } | Select-Object -First 1).Name
$cpu = (Get-CimInstance Win32_Processor).Name.Trim()
$out = @("Kung Fu Chaos - performance $(Get-Date -Format 'yyyy-MM-dd HH:mm')", "GPU: $gpu | CPU: $cpu",
         'scale post | resolution | ms p50 | ms p95 (median) | ms p95 (worst) | windows >20 ms | process CPU | verdict')

function P([string[]]$keys, [double]$gap = 1.2) { foreach ($k in $keys) { [IO.File]::AppendAllText($pad, "$k`r`n"); Start-Sleep -Milliseconds ([int](1000 * $gap)) } }
function Med([double[]]$v) { if (-not $v) { return $null }; $s = $v | Sort-Object; $s[[int][math]::Floor(($s.Count - 1) / 2)] }

foreach ($c in $Configs) {
    $f = $c -split ':'; $scale = $f[0]; $post = $f[1]; $aniso = if ($f.Count -gt 2 -and $f[2]) { $f[2] } else { '16' }
    $extra = if ($f.Count -gt 3) { @($f[3] -split '\+' | Where-Object { $_ -match '=' }) } else { @() }
    foreach ($kv in $extra) { $k, $v = $kv -split '=', 2; Set-Item "Env:$k" $v }
    $tag = "$scale $post a$aniso$(if ($extra) { ' ' + ($extra -join ' ') })"
    Set-Content $ini "# temporary, from benchmark.ps1`r`nscale=$scale`r`npost=$post`r`naniso=$aniso`r`npads=1`r`nwindow=window`r`nwinsize=$WinSize`r`nvsync=0`r`nfps=60" -Encoding ascii
    Set-Content $pad $null
    $env:RECOMP_PAD_LIVE = $pad; $env:KFC_TRACE = 'pacing'
    Start-Process "$Pkg\KFCLauncher.exe" -ArgumentList '--play' -WorkingDirectory $Pkg
    $p = $null
    for ($i = 0; $i -lt 30 -and -not $p; $i++) { Start-Sleep 1; $p = Get-Process kfc_recomp -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Pkg*" } | Select-Object -First 1 }
    if (-not $p) { $out += "$tag | did not start"; continue }
    $t0 = Get-Date
    Start-Sleep -Seconds 13
    P @('start', 'start', 'a', 'start', 'a', 'b', 'b', 'b') 1.3
    P @('down', 'down', 'a'); Start-Sleep 1.5; P @('a'); Start-Sleep 1
    P @('a'); P @('right', 'right', 'right', 'right') 0.6; P @('a', 'a')
    P @('start', 'right', 'a', 'start', 'right', 'right', 'right', 'a', 'start', 'right', 'right', 'right', 'right', 'right', 'right', 'a') 0.9
    P @('a') 2
    while (-not $p.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt $Secs) { P @('a', 'x', 'white', 'x', 'black') 0.6 }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    foreach ($kv in $extra) { Remove-Item "Env:$(($kv -split '=', 2)[0])" -ErrorAction SilentlyContinue }
    Start-Sleep 2
    $log = Get-Content "$Pkg\log.txt" -ErrorAction SilentlyContinue
    Copy-Item "$Pkg\log.txt" "$Pkg\log-bench-$scale-$post-a$aniso$(if ($extra) { '-x' }).txt" -Force -ErrorAction SilentlyContinue
    # Windows in a fight: those after the first fight stage loaded (scifi/rooftop...), or else the second half.
    $lines = @($log | Where-Object { $_ -match '^\[PACING\] flips' })
    $k = [array]::IndexOf(@($log), ($log | Where-Object { $_ -match '\b(scifi|rooftop|wildwest|western|haunted|jungle|kitchen)\w*\.level' } | Select-Object -First 1))
    $fight = if ($k -ge 0) { @($log[$k..($log.Count - 1)] | Where-Object { $_ -match '^\[PACING\] flips' }) } else { $lines[[int]($lines.Count / 2)..($lines.Count - 1)] }
    $p50 = @(); $p95 = @(); $cpuP = @()
    foreach ($l in $fight) {
        if ($l -match 'p50 ([\d.]+) p95 ([\d.]+)') { $p50 += [double]$Matches[1]; $p95 += [double]$Matches[2] }
        if ($l -match 'cpu process (\d+)%') { $cpuP += [double]$Matches[1] }
    }
    $res = "$([int]$scale * 640)x$([int]$scale * 480)"
    if (-not $p95) { $out += "$tag | $res | no windows in a fight (see log-bench-$scale-$post-a$aniso$(if ($extra) { '-x' }).txt)"; continue }
    $bad = @($p95 | Where-Object { $_ -gt 20 }).Count
    $ver = if ((Med $p95) -le 18.5 -and $bad -le 1) { 'steady 60 FPS' } elseif ((Med $p50) -le 17.5) { '60 with hitches' } else { 'does NOT reach 60' }
    $out += "$tag | $res | $(Med $p50) | $(Med $p95) | $(($p95 | Measure-Object -Maximum).Maximum) | $bad of $($p95.Count) | $(Med $cpuP)% | $ver"
}
Remove-Item Env:RECOMP_PAD_LIVE, Env:KFC_TRACE -ErrorAction SilentlyContinue
if (Test-Path $iniBak) { Move-Item $iniBak $ini -Force } else { Remove-Item $ini -ErrorAction SilentlyContinue }
$out | Set-Content "$Pkg\performance.txt" -Encoding utf8
$out
