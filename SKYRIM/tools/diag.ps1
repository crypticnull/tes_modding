#Requires -Version 5.1
<#
  diag.ps1 - everything needed to work out why the game crashed, in one place.

      diag.ps1              the usual: what crashed, which plugin, what changed
      diag.ps1 -Full        longer tails
      diag.ps1 -Recent 48   widen "what changed recently" to 48 hours

  WHY THIS EXISTS

  The logs that matter live in four different places, one of them behind a
  OneDrive redirect that makes "Documents" not be Documents. Nobody should have
  to remember those paths at 2am. This finds them and prints the parts that
  actually say something.

  WHAT IT LOOKS AT

    skse64.log            SKSE names each plugin as it loads it. On a load-time
                          crash the LAST one named is almost always the culprit.
    CommunityShaders.log  feature version mismatches and shader compile state
    dlss5-bridge.log      the bridge records the faulting address and a stack
    ReShade.log           add-on load order and DLSS 5 feature-18 activity
    mods\                 what was installed or changed in the last N hours
#>

[CmdletBinding()]
param(
    [string]$Root  = 'X:\MODDING\SKYRIM',
    [int]$Recent   = 12,
    [switch]$Full
)

$ErrorActionPreference = 'SilentlyContinue'
$n = if ($Full) { 120 } else { 45 }

function Head($t){ Write-Host ""; Write-Host ("=== {0} " -f $t).PadRight(78,'=') -ForegroundColor Cyan }
function Note($t){ Write-Host "  $t" -ForegroundColor DarkGray }

# ---- find the SKSE log folder. Documents may be redirected to OneDrive. ----
$cands = @(
    (Join-Path $env:USERPROFILE 'OneDrive\Documents\My Games\Skyrim Special Edition\SKSE'),
    (Join-Path $env:USERPROFILE 'Documents\My Games\Skyrim Special Edition\SKSE'),
    (Join-Path $env:USERPROFILE 'OneDrive\Documents\My Games\Skyrim Special Edition GOG\SKSE')
)
$SkseLogs = $null
foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { $SkseLogs = $c; break } }

$Stock = Join-Path $Root 'STOCK GAME'
$Mods  = Join-Path $Root 'SKYRIM_SE\mods'

Head "where the logs are"
Note ("skse logs : {0}" -f $(if ($SkseLogs) { $SkseLogs } else { 'NOT FOUND - is Documents redirected somewhere unusual?' }))
Note ("stock game: {0}" -f $Stock)

# ---- the one that usually answers it -------------------------------------
if ($SkseLogs) {
    $skse = Join-Path $SkseLogs 'skse64.log'
    if (Test-Path -LiteralPath $skse) {
        Head "skse64.log - plugins in load order (LAST ONE IS THE SUSPECT)"
        $lines = Get-Content -LiteralPath $skse
        $plug = @($lines | Select-String -Pattern 'plugin (.+) \((.+)\)|checking plugin|loaded plugin|could not load|disabled|reported as incompatible|version' |
                  ForEach-Object { $_.Line })
        if ($plug.Count) { $plug | Select-Object -Last $n | ForEach-Object { Write-Host "  $_" } }
        else { Note "no plugin lines matched - dumping the tail instead" }

        Head "skse64.log - tail"
        $lines | Select-Object -Last $n | ForEach-Object { Write-Host "  $_" }
        Note ("last written: {0}" -f (Get-Item -LiteralPath $skse).LastWriteTime)
    } else { Head "skse64.log"; Note "not present" }

    $cs = Join-Path $SkseLogs 'CommunityShaders.log'
    if (Test-Path -LiteralPath $cs) {
        Head "CommunityShaders.log - errors, versions, feature state"
        Get-Content -LiteralPath $cs |
            Select-String -Pattern '\[E\]|\[W\]|version|requires|missing|not installed|failed|Feature' |
            Select-Object -Last $n | ForEach-Object { Write-Host ("  " + $_.Line) }
    }

    $dt = Join-Path $SkseLogs 'SSEDisplayTweaks.log'
    if (Test-Path -LiteralPath $dt) {
        Head "SSEDisplayTweaks.log - resolution and window"
        Select-String -Path $dt -Pattern 'Requesting mode|Window created|Resolution override|upscal' |
            ForEach-Object { Write-Host ("  " + $_.Line) }
    }
}

# ---- the bridge records the fault itself ----------------------------------
$bridge = Join-Path $Stock 'dlss5-bridge.log'
if (Test-Path -LiteralPath $bridge) {
    $b = Get-Content -LiteralPath $bridge
    $i = -1
    for ($k = $b.Count - 1; $k -ge 0; $k--) { if ($b[$k] -match 'CRASH RECORDED') { $i = $k; break } }
    if ($i -ge 0) {
        Head "dlss5-bridge.log - CRASH RECORDED"
        $b[$i..([math]::Min($i + 40, $b.Count - 1))] | ForEach-Object { Write-Host "  $_" }
    } else {
        Head "dlss5-bridge.log - no crash block; render state"
        $b | Select-String -Pattern 'back buffer|feature ready|rebuilding|arming|frames:|already used DLSS' |
            Select-Object -Last 12 | ForEach-Object { Write-Host ("  " + $_.Line) }
    }
}

$rs = Join-Path $Stock 'ReShade.log'
if (Test-Path -LiteralPath $rs) {
    Head "ReShade.log - add-ons and DLSS 5 neural rendering"
    Get-Content -LiteralPath $rs |
        Select-String -Pattern 'Registered add-on|feature 18|feature create intercepted|ERROR|failed' |
        Select-Object -Last 20 | ForEach-Object { Write-Host ("  " + $_.Line) }
}

# ---- what changed lately ---------------------------------------------------
Head ("mods added or changed in the last {0} hour(s)" -f $Recent)
$since = (Get-Date).AddHours(-$Recent)
$changed = @(Get-ChildItem -LiteralPath $Mods -Directory | Where-Object { $_.LastWriteTime -gt $since } |
             Sort-Object LastWriteTime -Descending)
if ($changed.Count) {
    foreach ($m in $changed) {
        $dll = @(Get-ChildItem -LiteralPath $m.FullName -Recurse -Filter *.dll -ErrorAction SilentlyContinue).Count
        Write-Host ("  {0:MM-dd HH:mm}  {1,-46} {2}" -f $m.LastWriteTime, $m.Name,
            $(if ($dll) { "$dll DLL(s) - can crash at load" } else { "no DLL" }))
    }
} else { Note "nothing changed in that window" }

Head "enabled mods carrying an SKSE DLL"
$ml = Join-Path $Root 'SKYRIM_SE\profiles\Default\modlist.txt'
$on = @(Get-Content -LiteralPath $ml | Where-Object { $_ -like '+*' } | ForEach-Object { $_.Substring(1) })
foreach ($m in $on) {
    $p = Join-Path $Mods $m
    $d = @(Get-ChildItem -LiteralPath $p -Recurse -Filter *.dll -ErrorAction SilentlyContinue)
    if ($d.Count) {
        foreach ($f in $d) { Write-Host ("  {0,-46} {1}" -f $m, $f.Name) }
    }
}
Write-Host ""
