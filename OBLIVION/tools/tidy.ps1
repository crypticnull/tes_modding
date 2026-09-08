#Requires -Version 5.1
<#
  Housekeeping for X:\MODDING\OBLIVION.

    X:\MODDING\OBLIVION\tools\tidy.ps1            report only, changes nothing
    X:\MODDING\OBLIVION\tools\tidy.ps1 -Apply     do it

  Retires superseded scripts, prunes old backups keeping the newest few, and
  reports what is safe to delete. Nothing is deleted - things move to _archive
  or _DELETE_ME so any of it can be walked back.
#>

[CmdletBinding()]
param([switch]$Apply, [int]$KeepBackups = 3)

$ErrorActionPreference = 'Stop'

$Root     = 'X:\MODDING\OBLIVION'
$Instance = Join-Path $Root 'OBLIVION_REMASTERED'
$Archive  = Join-Path $Root 'archive'
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$mode     = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to act' }

Write-Host "=== tidy ($mode) ==="
Write-Host ""

function Do-Move {
    param([string]$Src, [string]$Dst, [string]$Why)
    if (-not (Test-Path -LiteralPath $Src)) { return $false }
    Write-Host ("  {0,-42}  {1}" -f (Split-Path $Src -Leaf), $Why)
    if ($Apply) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Dst -Parent) | Out-Null
        Move-Item -LiteralPath $Src -Destination $Dst -Force
    }
    return $true
}

# --- 1. superseded scripts --------------------------------------------------
Write-Host "--- superseded scripts ---"
$dead = @(
    @{ F='nexus.ps1';              W='UNSAFE - v1, can move the whole mods folder. Replaced by nexus2.ps1' }
    @{ F='install_mods.ps1';       W='replaced by nexus2.ps1 (its naming created the RAO duplicate)' }
    @{ F='fix_mo2_plugins.ps1';    W='one-shot, already run' }
    @{ F='fix_motw_and_import.ps1';W='one-shot, already run' }
    @{ F='prep_for_unbse.ps1';     W='one-shot, already run' }
    @{ F='cleanup_stale.ps1';      W='one-shot, already run' }
)
$n = 0
foreach ($d in $dead) {
    if (Do-Move -Src (Join-Path $Root ('tools\'+$d.F)) -Dst (Join-Path $Archive $d.F) -Why $d.W) { $n++ }
}
if (-not $n) { Write-Host "  none left" }
Write-Host ""

# --- 2. prune backups -------------------------------------------------------
Write-Host "--- backups (keeping newest $KeepBackups of each) ---"
$sets = @(
    @{ Path=(Join-Path $Root 'data');           Filter='nexus_picks.txt.bak-*' }
    @{ Path=(Join-Path $Instance 'profiles\Default'); Filter='modlist.txt.bak-*' }
    @{ Path=(Join-Path $Root 'logs');           Filter='nexus_*_*.txt' }
)
foreach ($s in $sets) {
    if (-not (Test-Path -LiteralPath $s.Path)) { continue }
    $all = @(Get-ChildItem -LiteralPath $s.Path -File -Filter $s.Filter -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending)
    $old = @($all | Select-Object -Skip $KeepBackups)
    Write-Host ("  {0}: {1} found, {2} to prune" -f $s.Filter, $all.Count, $old.Count)
    foreach ($f in $old) {
        if ($Apply) {
            $dst = Join-Path $Root ('_DELETE_ME\old-backups\' + $f.Name)
            New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
            Move-Item -LiteralPath $f.FullName -Destination $dst -Force
        }
    }
}
# profile snapshots
$snaps = @(Get-ChildItem -LiteralPath (Join-Path $Root 'backups') -Directory -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending)
$oldSnaps = @($snaps | Select-Object -Skip $KeepBackups)
Write-Host ("  profile snapshots: {0} found, {1} to prune" -f $snaps.Count, $oldSnaps.Count)
foreach ($f in $oldSnaps) {
    if ($Apply) { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $Root ('_DELETE_ME\old-backups\' + $f.Name)) -Force }
}
Write-Host ""

# --- 3. abandoned work folders ---------------------------------------------
Write-Host "--- abandoned work folders ---"
$work = @(Get-ChildItem -LiteralPath $Instance -Directory -Filter '_work_*' -ErrorAction SilentlyContinue)
Write-Host ("  {0} found" -f $work.Count)
foreach ($w in $work) {
    Write-Host ("    {0}  ({1:N0} MB)" -f $w.Name,
        ((Get-ChildItem -LiteralPath $w.FullName -Recurse -File -ErrorAction SilentlyContinue |
          Measure-Object Length -Sum).Sum / 1MB))
    if ($Apply) { Remove-Item -LiteralPath $w.FullName -Recurse -Force }
}
Write-Host ""

# --- 4. what is safe to delete ---------------------------------------------
Write-Host "--- reclaimable space ---"
foreach ($p in @((Join-Path $Root '_DELETE_ME'), $Archive)) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $sz = (Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue |
           Measure-Object Length -Sum).Sum
    Write-Host ("  {0,-34} {1,8:N0} MB" -f (Split-Path $p -Leaf), ($sz / 1MB))
}
Write-Host ""
Write-Host "_DELETE_ME holds replaced mod folders and old backups. Delete it yourself"
Write-Host "once the modlist is running the way you want."
if (-not $Apply) { Write-Host ""; Write-Host "Nothing changed. Re-run with -Apply." }
