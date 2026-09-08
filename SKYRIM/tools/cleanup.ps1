#Requires -Version 5.1
<#
  cleanup.ps1 - retire the things this build no longer uses.

    cleanup.ps1            report
    cleanup.ps1 -Apply     move them

  NOTHING IS DELETED. Everything goes to X:\MODDING\SKYRIM\_retired\<timestamp>\
  with its original folder shape, so putting any of it back is a drag. Delete
  that folder yourself once you are happy.

  WHAT IT RETIRES

  1. The BTPS-NG DLL mod. A 2022 fork of a DLL whose parent mod ships a 2025
     one, which is what crashed the game on load. Its modlist line goes too.

  2. The Blended Roads archive. Never installed - Skyland AIO supplies its own
     blended roads tuned to its landscape textures, so the standalone would put
     seams where road meets dirt.

  3. Superseded archives of mods that are installed at a different version:
     JContainers 4.3.2 and 4.2.9, PapyrusUtil 4.7 and 4.8. All four are builds
     for the wrong runtime, kept only because I wanted to read their headers.
     Leaving them in downloads is how install_mod picks the wrong one later.

  4. Profile backups beyond the newest three of each kind. Those .bak-* files
     are mine - every script that touches modlist.txt or plugins.txt drops one -
     and there are now enough to bury the real files.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [int]$KeepBackups = 3,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$Instance  = Join-Path $Root 'SKYRIM_SE'
$ModsDir   = Join-Path $Instance 'mods'
$Dloads    = Join-Path $Instance 'downloads'
$ProfileD  = Join-Path $Instance 'profiles\Default'
$MlPath    = Join-Path $ProfileD 'modlist.txt'
$Retire    = Join-Path $Root ("_retired\" + $Stamp)
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$mode      = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to move' }

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. It rewrites modlist.txt from memory on exit. Close it and re-run."
}

Write-Host ""
Write-Host "=== cleanup ($mode) ===" -ForegroundColor Cyan
Write-Host ""

$plan = New-Object System.Collections.Generic.List[object]

function Add-Item2 {
    param([string]$Kind, [string]$Path, [string]$Why)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $it = Get-Item -LiteralPath $Path
    $bytes = if ($it.PSIsContainer) {
        (@(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue) |
            Measure-Object -Property Length -Sum).Sum
    } else { $it.Length }
    $plan.Add([pscustomobject]@{ Kind = $Kind; Path = $it.FullName; Name = $it.Name
                                 Bytes = [int64]$bytes; Why = $Why })
}

# 1. the NG DLL mod
Add-Item2 'mod' (Join-Path $ModsDir 'Better Third Person Selection - BTPS-NG DLL') `
    '2022 fork DLL over a 2025 mod - this is what crashed the game'

# 2 + 3. archives that are not the installed version
$arcs = @(
 @{ pat = 'Blended Roads-8834*';                              why = 'never installed, Skyland supplies its own' }
 @{ pat = 'JContainers SE 16495 4.3.2*';                      why = 'built for 1.7.104, you run 1.6.1170' }
 @{ pat = 'JContainers SE-16495-4-2-9*';                      why = 'superseded by 4.2.13.1, which is installed' }
 @{ pat = 'PapyrusUtil*4.7*';                                 why = 'built for 1.7.99, you run 1.6.1170' }
 @{ pat = 'PapyrusUtil*4.8*';                                 why = 'built for 1.7.104, you run 1.6.1170' }
)
foreach ($a in $arcs) {
    foreach ($f in @(Get-ChildItem -LiteralPath $Dloads -File -Filter $a.pat -ErrorAction SilentlyContinue)) {
        Add-Item2 'archive' $f.FullName $a.why
    }
}

# 4. profile backups past the newest few, grouped by which file they back up
$baks = @(Get-ChildItem -LiteralPath $ProfileD -File -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match '^(.+?)\.bak-\d{8}-\d{6}$' })
$groups = $baks | Group-Object { ($_.Name -split '\.bak-')[0] }
foreach ($g in $groups) {
    $old = @($g.Group | Sort-Object LastWriteTime -Descending | Select-Object -Skip $KeepBackups)
    foreach ($f in $old) { Add-Item2 'backup' $f.FullName ("keeping the newest $KeepBackups of " + $g.Name) }
}

if (-not $plan.Count) {
    Write-Host "Nothing to retire." -ForegroundColor Green
    Write-Host ""
    return
}

foreach ($kind in @('mod','archive','backup')) {
    $rows = @($plan | Where-Object { $_.Kind -eq $kind })
    if (-not $rows.Count) { continue }
    $mb = [math]::Round((($rows | Measure-Object -Property Bytes -Sum).Sum) / 1MB, 1)
    Write-Host ("  {0,-8} {1,3} item(s), {2} MB" -f $kind, $rows.Count, $mb) -ForegroundColor Cyan
    if ($kind -eq 'backup') {
        $byWhy = $rows | Group-Object Why
        foreach ($w in $byWhy) { Write-Host ("      {0,3} x  {1}" -f $w.Count, $w.Name) -ForegroundColor DarkGray }
    } else {
        foreach ($r in $rows) {
            Write-Host ("      {0}" -f $r.Name)
            Write-Host ("          {0}" -f $r.Why) -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

$totalMb = [math]::Round((($plan | Measure-Object -Property Bytes -Sum).Sum) / 1MB, 1)
Write-Host ("  total {0} item(s), {1} MB -> {2}" -f $plan.Count, $totalMb, $Retire)

# the modlist line for the retired mod
$ml = @(Get-Content -LiteralPath $MlPath)
$mlHits = @($ml | Where-Object { $_ -match '^[+\-]Better Third Person Selection - BTPS-NG DLL\s*$' })
if ($mlHits.Count) { Write-Host ("  modlist line to remove: {0}" -f $mlHits[0]) }

if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing moved. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ---- move --------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $Retire | Out-Null
$moved = 0
foreach ($r in $plan) {
    # keep the original shape under _retired so anything can be put back by hand
    $rel = $r.Path.Substring($Root.Length).TrimStart('\')
    $dst = Join-Path $Retire $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
    Move-Item -LiteralPath $r.Path -Destination $dst -Force
    $moved++
}

if ($mlHits.Count) {
    Copy-Item -LiteralPath $MlPath -Destination "$MlPath.bak-$Stamp" -Force
    $kept = @($ml | Where-Object { $_ -notmatch '^[+\-]Better Third Person Selection - BTPS-NG DLL\s*$' })
    [IO.File]::WriteAllLines($MlPath, $kept, $Utf8NoBom)
}

# ---- verify ------------------------------------------------------------------
$left = @($plan | Where-Object { Test-Path -LiteralPath $_.Path })
$ml2  = @(Get-Content -LiteralPath $MlPath)
$stillListed = @($ml2 | Where-Object { $_ -match 'BTPS-NG' }).Count

Write-Host ""
if ($left.Count) {
    Write-Host ("  WARNING: {0} item(s) did not move" -f $left.Count) -ForegroundColor Yellow
    foreach ($l in $left) { Write-Host ("      {0}" -f $l.Name) -ForegroundColor Yellow }
}
if ($stillListed) { throw "modlist.txt still references BTPS-NG" }
Write-Host ("  {0} item(s) moved, modlist now {1} line(s)" -f $moved, $ml2.Count) -ForegroundColor Green
Write-Host ("  everything is under {0} - delete that folder when you are happy." -f $Retire)
Write-Host ""
