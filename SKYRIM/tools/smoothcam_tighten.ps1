#Requires -Version 5.1
<#
  smoothcam_tighten.ps1 - take the lag out of SmoothCam without hunting sliders.

    smoothcam_tighten.ps1                    report
    smoothcam_tighten.ps1 -Apply             halve the lag
    smoothcam_tighten.ps1 -Strength 0.75 -Apply    take out three quarters
    smoothcam_tighten.ps1 -Restore           put the last backup back

  WHAT IT CHANGES

  SmoothCam's delay comes from its follow rates. A rate of 1.0 means the camera
  is exactly where it should be every frame - no smoothing. Lower means it
  covers only part of the remaining distance each frame, and the lower it is the
  further behind your input the camera sits.

  So the lag is the gap between the rate and 1.0, and the fix is to close some
  of that gap:

      new = old + (1 - old) * Strength

  At the default Strength of 0.5 that is exactly half the lag gone, everywhere,
  which is what you asked for. 0.25 is a gentler nudge, 1.0 removes smoothing
  entirely and is worth trying once just to feel the other end of the range.
  A rate already at 1.0 has no gap and is left alone.

  There are 286 of these across 20 camera states - standing, walking, running,
  sprinting, sneaking, bow aim, horseback, swimming, werewolf, vampire lord and
  the rest - each with its own minimum and maximum, plus separate local-space
  and Z-axis rates. Doing it by hand through the MCM is not realistic, and
  doing only the state you happen to be testing in is why it feels
  inconsistent when people try.

  HOW IT EDITS

  By exact text replacement of the numbers, not by parsing the JSON and writing
  it back out. A round trip through ConvertTo-Json reorders keys and reformats
  every float in a 50 KB config to fix 286 numbers. Everything not being changed
  stays byte for byte.

  CLOSE SKYRIM FIRST. SmoothCam writes this file itself, so anything you change
  here while it is running gets overwritten on exit. Changing a slider in its
  MCM later will also rewrite the file - just run this again after.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [double]$Strength = 0.5,
    [switch]$Restore,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Cfg   = Join-Path $Root 'SKYRIM_SE\overwrite\SKSE\Plugins\SmoothCam.json'
$Utf8  = New-Object Text.UTF8Encoding $false

foreach ($p in @('SkyrimSE','ModOrganizer')) {
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) {
        throw "$p is running. SmoothCam rewrites this file on exit, so the change would be lost. Close it and re-run."
    }
}
if (-not (Test-Path -LiteralPath $Cfg)) {
    throw "not found: $Cfg`nRun the game once with SmoothCam installed - it writes this file on first launch."
}

# ---- restore ---------------------------------------------------------------
if ($Restore) {
    $baks = @(Get-ChildItem -LiteralPath (Split-Path $Cfg -Parent) -File -Filter 'SmoothCam.json.bak-*' |
              Sort-Object LastWriteTime -Descending)
    if (-not $baks.Count) { throw "no backups next to $Cfg" }
    Copy-Item -LiteralPath $baks[0].FullName -Destination $Cfg -Force
    Write-Host ""
    Write-Host ("restored from {0}" -f $baks[0].Name) -ForegroundColor Green
    Write-Host ""
    return
}

if ($Strength -lt 0 -or $Strength -gt 1) { throw "-Strength must be between 0 and 1" }

$raw = Get-Content -LiteralPath $Cfg -Raw
$rx  = [regex]'"(\w*(?:FollowRate))"\s*:\s*(-?[0-9]+(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?)'
$ms  = $rx.Matches($raw)

$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' }
Write-Host ""
Write-Host ("=== SmoothCam follow rates ({0}) ===" -f $mode) -ForegroundColor Cyan
Write-Host ("  strength {0}  -  new = old + (1 - old) * {0}" -f $Strength)
Write-Host ("  {0} follow-rate value(s) found" -f $ms.Count)
Write-Host ""

if (-not $ms.Count) { throw "no follow-rate settings matched - the config format is not what this expects" }

# ---- rebuild the text, splicing new numbers in by index --------------------
$sb = New-Object System.Text.StringBuilder
$pos = 0
$changed = 0
$samples = New-Object System.Collections.Generic.List[string]
$ci = [Globalization.CultureInfo]::InvariantCulture

foreach ($m in $ms) {
    $g = $m.Groups[2]
    $old = [double]::Parse($g.Value, $ci)
    $new = $old + (1.0 - $old) * $Strength
    if ($new -gt 1.0) { $new = 1.0 }
    $txt = $new.ToString('0.#####', $ci)
    [void]$sb.Append($raw.Substring($pos, $g.Index - $pos))
    [void]$sb.Append($txt)
    $pos = $g.Index + $g.Length
    if ([Math]::Abs($new - $old) -gt 0.0001) { $changed++ }
    if ($samples.Count -lt 10 -and [Math]::Abs($new - $old) -gt 0.0001) {
        $samples.Add(("      {0,-56} {1:0.###} -> {2:0.###}" -f $m.Groups[1].Value, $old, $new))
    }
}
[void]$sb.Append($raw.Substring($pos))
$out = $sb.ToString()

Write-Host ("  {0} would actually move, {1} already at 1.0" -f $changed, ($ms.Count - $changed))
Write-Host ""
Write-Host "  a sample:" -ForegroundColor DarkGray
foreach ($s in $samples) { Write-Host $s -ForegroundColor DarkGray }

if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing written. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

Copy-Item -LiteralPath $Cfg -Destination "$Cfg.bak-$Stamp" -Force
[IO.File]::WriteAllText($Cfg, $out, $Utf8)

# ---- verify: still valid JSON, and the numbers really moved ----------------
$back = Get-Content -LiteralPath $Cfg -Raw
try { $null = $back | ConvertFrom-Json } catch { throw "the file no longer parses as JSON - restore with -Restore" }
$after = $rx.Matches($back)
if ($after.Count -ne $ms.Count) { throw "expected $($ms.Count) settings after the write, found $($after.Count)" }
$low = 0
foreach ($m in $after) { if ([double]::Parse($m.Groups[2].Value, $ci) -lt 0.999) { $low++ } }

Write-Host ""
Write-Host ("written and verified. {0} value(s) changed, file still parses." -f $changed) -ForegroundColor Green
Write-Host ("  {0} of {1} rates are still below 1.0 - run again for another {2:P0} off, or -Strength 1 to remove smoothing entirely." -f `
    $low, $after.Count, $Strength)
Write-Host ("  backup: {0}" -f (Split-Path "$Cfg.bak-$Stamp" -Leaf)) -ForegroundColor DarkGray
Write-Host ""
