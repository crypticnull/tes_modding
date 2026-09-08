#Requires -Version 5.1
<#
  enable_plugins.ps1 - activate every plugin belonging to an enabled mod.

    enable_plugins.ps1              report what is off and would be turned on
    enable_plugins.ps1 -Apply       turn them on

  WHY THIS IS A SEPARATE STEP FROM INSTALLING

  In Skyrim's plugins.txt a leading '*' marks a plugin ACTIVE. No asterisk means
  the game knows the plugin exists and does not load it - which looks identical
  to "installed correctly" everywhere except in the game.

  install_mod.ps1 writes the asterisk. MO2 then throws it away the first time it
  indexes a mod it has not seen before, because MO2 keeps its own idea of which
  plugins are known and defaults anything new to disabled. So the asterisk has
  to go back AFTER MO2 has seen the mod, not before.

  The working order is therefore:

      1. install_mod.ps1 -Apply        files, modlist.txt
      2. open MO2, then close it       MO2 indexes the new plugins (as disabled)
      3. enable_plugins.ps1 -Apply     asterisks back on
      4. open MO2, Sort, play          MO2 now keeps them, because it knows them

  Step 2 feels redundant and is not. Skipping it is why Alternate Start
  installed cleanly and then did nothing.

  This never reorders anything - LOOT owns the order. It only sets active flags.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$Instance  = Join-Path $Root 'SKYRIM_SE'
$ModsDir   = Join-Path $Instance 'mods'
$ProfileD  = Join-Path $Instance 'profiles\Default'
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$mode      = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to enable' }

Write-Host ""
Write-Host "=== enable managed plugins ($mode) ===" -ForegroundColor Cyan
Write-Host ""

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. It rewrites plugins.txt on exit and would undo this. Close it and re-run."
}
foreach ($p in @($ModsDir, $ProfileD)) { if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" } }

# ---- every plugin provided by an ENABLED mod -------------------------------
$mlPath = Join-Path $ProfileD 'modlist.txt'
$enabled = @()
foreach ($l in (Get-Content -LiteralPath $mlPath)) {
    # '+' is an enabled managed mod. '*' is unmanaged content MO2 found in the
    # game folder (the Creation Club plugins), which the game loads on its own.
    if ($l -match '^\+(.+)$') { $enabled += $Matches[1].TrimEnd() }
}

$want = New-Object System.Collections.Generic.List[string]
foreach ($m in $enabled) {
    $md = Join-Path $ModsDir $m
    if (-not (Test-Path -LiteralPath $md)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $md -File -ErrorAction SilentlyContinue)) {
        if ($f.Extension.ToLower() -in @('.esp','.esm','.esl')) { $want.Add($f.Name) }
    }
}

Write-Host ("  {0} enabled mod(s) provide {1} plugin(s)" -f $enabled.Count, $want.Count)
if (-not $want.Count) { Write-Host ""; Write-Host "Nothing to do."; Write-Host ""; return }

# ---- what plugins.txt says now ---------------------------------------------
$ppath = Join-Path $ProfileD 'plugins.txt'
$lines = @()
if (Test-Path -LiteralPath $ppath) { $lines = @(Get-Content -LiteralPath $ppath) }

$state = @{}
foreach ($l in $lines) {
    if ($l -match '^\s*#' -or -not $l.Trim()) { continue }
    $n = $l.TrimStart('*').Trim()
    $state[$n.ToLower()] = $l.TrimStart().StartsWith('*')
}

$off = @(); $on = @(); $absent = @()
foreach ($p in $want) {
    $k = $p.ToLower()
    if (-not $state.ContainsKey($k)) { $absent += $p }
    elseif ($state[$k])              { $on += $p }
    else                             { $off += $p }
}

Write-Host ""
Write-Host ("  already active   {0}" -f $on.Count)
foreach ($p in $on) { Write-Host ("      {0}" -f $p) -ForegroundColor DarkGray }
Write-Host ("  inactive         {0}" -f $off.Count) -ForegroundColor $(if ($off.Count) { 'Yellow' } else { 'DarkGray' })
foreach ($p in $off) { Write-Host ("      {0}" -f $p) -ForegroundColor Yellow }
if ($absent.Count) {
    Write-Host ("  not listed yet   {0}" -f $absent.Count) -ForegroundColor Yellow
    foreach ($p in $absent) { Write-Host ("      {0}" -f $p) -ForegroundColor Yellow }
    Write-Host  "      -> MO2 has not indexed these. Open MO2 once, close it, re-run."
}

if (-not ($off.Count -or $absent.Count)) {
    Write-Host ""
    Write-Host "Every managed plugin is already active." -ForegroundColor Green
    Write-Host ""
    return
}
if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing changed. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ------------------------------------------------------------------ apply ----
$wantSet = @{}; foreach ($p in $want) { $wantSet[$p.ToLower()] = $p }

$out = New-Object System.Collections.Generic.List[string]
$seen = @{}
foreach ($l in $lines) {
    if ($l -match '^\s*#' -or -not $l.Trim()) { $out.Add($l); continue }
    $n = $l.TrimStart('*').Trim()
    if ($wantSet.ContainsKey($n.ToLower())) {
        $out.Add('*' + $n)                       # force active, keep its position
        $seen[$n.ToLower()] = $true
    } else {
        $out.Add($l)                             # leave everything else exactly as-is
    }
}
# anything MO2 has not listed at all goes on the end; LOOT will place it properly
foreach ($p in $want) {
    if (-not $seen.ContainsKey($p.ToLower()) -and -not $state.ContainsKey($p.ToLower())) {
        $out.Add('*' + $p); $seen[$p.ToLower()] = $true
    }
}

Copy-Item -LiteralPath $ppath -Destination "$ppath.bak-$Stamp" -Force -ErrorAction SilentlyContinue
[IO.File]::WriteAllLines($ppath, $out, $Utf8NoBom)
Write-Host ""
Write-Host ("  plugins.txt   {0} plugin(s) set active" -f ($off.Count + $absent.Count)) -ForegroundColor Green

# loadorder.txt must know about every plugin too - it is the order half of the
# pair, and MO2 reconciles the two by dropping whatever it cannot match.
$lpath = Join-Path $ProfileD 'loadorder.txt'
if (Test-Path -LiteralPath $lpath) {
    $ll = @(Get-Content -LiteralPath $lpath)
    $have = @{}; foreach ($l in $ll) { if ($l.Trim() -and $l -notmatch '^\s*#') { $have[$l.Trim().ToLower()] = $true } }
    $add = @($want | Where-Object { -not $have.ContainsKey($_.ToLower()) })
    if ($add.Count) {
        Copy-Item -LiteralPath $lpath -Destination "$lpath.bak-$Stamp" -Force
        [IO.File]::WriteAllLines($lpath, ($ll + $add), $Utf8NoBom)
        Write-Host ("  loadorder.txt +{0} plugin(s)" -f $add.Count)
    } else {
        Write-Host "  loadorder.txt already lists them all"
    }
}

Write-Host ""
Write-Host "Now open MO2 and Sort with LOOT before launching." -ForegroundColor Green
Write-Host "MO2 keeps the active flags from here on - it only discards them for a"
Write-Host "plugin it is seeing for the very first time."
Write-Host ""
