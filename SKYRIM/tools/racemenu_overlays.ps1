#Requires -Version 5.1
<#
  racemenu_overlays.ps1 - raise RaceMenu's overlay slot counts.

    X:\MODDING\SKYRIM\tools\racemenu_overlays.ps1            report
    X:\MODDING\SKYRIM\tools\racemenu_overlays.ps1 -Apply     do it

  WHY

  RaceMenu ships skee64.ini with three face, six body, three hand and three
  feet overlay slots, and bPlayerOnly=1. Every overlay mod you install shares
  those slots, so with six packs installed most of what you own is simply not
  addressable - it is not a missing texture, there is nowhere to put it.

  bPlayerOnly=1 also means overlay nodes only exist on the player. Overlay
  Distribution Framework hands overlays to NPCs, so it does nothing at all
  until that is 0.

  COST

  Every slot is a NiTriShape built on the actor. With bPlayerOnly=0 that is
  per humanoid actor, not just you, so the counts here are deliberately
  moderate rather than the 30-40 people paste around. Raise them later if you
  actually run out; there is no reason to pay for slots nothing addresses.

  WHICH FILE

  Several mods can ship a skee64.ini. MO2 gives the file to the mod with the
  highest priority, which is the one listed EARLIEST in modlist.txt. This
  finds every copy, says which one wins, and edits only that one.
#>

[CmdletBinding()]
param(
    [string]$Root       = 'X:\MODDING\SKYRIM',
    [int]$Face          = 10,
    [int]$Body          = 15,
    [int]$Hands         = 5,
    [int]$Feet          = 5,
    [switch]$PlayerOnly,          # keep bPlayerOnly=1 (ODF will then do nothing)
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$Instance  = Join-Path $Root 'SKYRIM_SE'
$ModsDir   = Join-Path $Instance 'mods'
$Over      = Join-Path $Instance 'overwrite'
$MlPath    = Join-Path $Instance 'profiles\Default\modlist.txt'
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$mode      = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to do it' }

# section name in skee64.ini -> wanted count
$Want = [ordered]@{
    'Overlays/Face'  = $Face
    'Overlays/Body'  = $Body
    'Overlays/Hands' = $Hands
    'Overlays/Feet'  = $Feet
}

Write-Host ""
Write-Host "=== racemenu overlay slots ($mode) ===" -ForegroundColor Cyan
Write-Host ""

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. Close it and re-run."
}
if (-not (Test-Path -LiteralPath $MlPath))  { throw "not found: $MlPath" }
if (-not (Test-Path -LiteralPath $ModsDir)) { throw "not found: $ModsDir" }

# ---- who owns skee64.ini ---------------------------------------------------
# modlist.txt line 1 is the HIGHEST priority, so the first enabled mod in that
# file that has the ini is the one the game actually reads.
$order   = @()
$enabled = @{}
foreach ($ln in @(Get-Content -LiteralPath $MlPath)) {
    if ($ln -match '^\+(.+)$') { $n = $Matches[1].TrimEnd(); $order += $n; $enabled[$n] = $true }
}

$owners = New-Object System.Collections.Generic.List[object]
foreach ($n in $order) {
    $p = Join-Path (Join-Path $ModsDir $n) 'SKSE\Plugins\skee64.ini'
    if (Test-Path -LiteralPath $p) { $owners.Add([pscustomobject]@{ Mod = $n; Path = $p }) }
}
$overIni = Join-Path $Over 'SKSE\Plugins\skee64.ini'
if (Test-Path -LiteralPath $overIni) {
    # Overwrite beats every mod, so it goes to the front of the list.
    $owners.Insert(0, [pscustomobject]@{ Mod = '<Overwrite>'; Path = $overIni })
}

if (-not $owners.Count) { throw "no enabled mod contains SKSE\Plugins\skee64.ini - is RaceMenu enabled?" }

$target = $owners[0]
Write-Host ("  editing  {0}" -f $target.Mod) -ForegroundColor Green
Write-Host ("           {0}" -f $target.Path)
foreach ($o in $owners | Select-Object -Skip 1) {
    Write-Host ("  shadowed {0}   (lower priority, MO2 ignores its copy)" -f $o.Mod) -ForegroundColor DarkGray
}
Write-Host ""

# ---- edit ------------------------------------------------------------------
$lines   = @(Get-Content -LiteralPath $target.Path)
$section = ''
$changes = New-Object System.Collections.Generic.List[object]
$out     = New-Object System.Collections.Generic.List[string]
$seen    = @{}

for ($i = 0; $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]

    if ($ln -match '^\s*\[([^\]]+)\]') { $section = $Matches[1].Trim() }

    $new = $ln

    if ($section -eq 'Overlays' -and $ln -match '^\s*bPlayerOnly\s*=\s*([01])') {
        $old = $Matches[1]
        $wantPO = if ($PlayerOnly) { '1' } else { '0' }
        if ($old -ne $wantPO) {
            $new = $ln -replace '^(\s*bPlayerOnly\s*=\s*)[01]', ('${1}' + $wantPO)
            $changes.Add([pscustomobject]@{ Section = 'Overlays'; Key = 'bPlayerOnly'; From = $old; To = $wantPO })
        } else {
            $changes.Add([pscustomobject]@{ Section = 'Overlays'; Key = 'bPlayerOnly'; From = $old; To = "$old (already)" })
        }
        $seen['bPlayerOnly'] = $true
    }
    elseif ($Want.Contains($section) -and $ln -match '^\s*iNumOverlays\s*=\s*(\d+)') {
        $old = $Matches[1]
        $wantN = [string]$Want[$section]
        if ($old -ne $wantN) {
            $new = $ln -replace '^(\s*iNumOverlays\s*=\s*)\d+', ('${1}' + $wantN)
            $changes.Add([pscustomobject]@{ Section = $section; Key = 'iNumOverlays'; From = $old; To = $wantN })
        } else {
            $changes.Add([pscustomobject]@{ Section = $section; Key = 'iNumOverlays'; From = $old; To = "$old (already)" })
        }
        $seen[$section] = $true
    }

    $out.Add($new)
}

foreach ($s in $Want.Keys) {
    if (-not $seen.ContainsKey($s)) {
        Write-Host ("  WARNING: no iNumOverlays found under [{0}] - that section is missing from the ini" -f $s) -ForegroundColor Yellow
    }
}
if (-not $seen.ContainsKey('bPlayerOnly')) {
    Write-Host "  WARNING: no bPlayerOnly found under [Overlays] - Overlay Distribution Framework will not reach NPCs" -ForegroundColor Yellow
}

Write-Host ("  {0,-16} {1,-14} {2,6}  ->  {3}" -f 'SECTION','KEY','FROM','TO')
foreach ($c in $changes) {
    Write-Host ("  {0,-16} {1,-14} {2,6}  ->  {3}" -f $c.Section, $c.Key, $c.From, $c.To)
}
Write-Host ""

$real = @($changes | Where-Object { $_.To -notmatch '\(already\)$' })
if (-not $real.Count) {
    Write-Host "  Nothing to change - the ini already says all of this." -ForegroundColor Green
    Write-Host ""
    return
}

if (-not $Apply) {
    Write-Host ("  {0} line(s) would change. Re-run with -Apply." -f $real.Count) -ForegroundColor Yellow
    Write-Host ""
    return
}

Copy-Item -LiteralPath $target.Path -Destination ("{0}.bak-{1}" -f $target.Path, $Stamp) -Force
[IO.File]::WriteAllLines($target.Path, $out, $Utf8NoBom)

# ---- verify by reading it back ---------------------------------------------
$back    = @(Get-Content -LiteralPath $target.Path)
$section = ''
$bad     = 0
for ($i = 0; $i -lt $back.Count; $i++) {
    $ln = $back[$i]
    if ($ln -match '^\s*\[([^\]]+)\]') { $section = $Matches[1].Trim() }
    if ($section -eq 'Overlays' -and $ln -match '^\s*bPlayerOnly\s*=\s*([01])') {
        $wantPO = if ($PlayerOnly) { '1' } else { '0' }
        if ($Matches[1] -ne $wantPO) { $bad++; Write-Host ("  VERIFY FAIL bPlayerOnly is {0}" -f $Matches[1]) -ForegroundColor Red }
    }
    if ($Want.Contains($section) -and $ln -match '^\s*iNumOverlays\s*=\s*(\d+)') {
        if ($Matches[1] -ne [string]$Want[$section]) {
            $bad++; Write-Host ("  VERIFY FAIL [{0}] iNumOverlays is {1}" -f $section, $Matches[1]) -ForegroundColor Red
        }
    }
}
if ($bad) { throw "$bad value(s) did not stick" }

Write-Host ("  backup   {0}.bak-{1}" -f $target.Path, $Stamp) -ForegroundColor DarkGray
Write-Host "  verified - all values read back correctly." -ForegroundColor Green
Write-Host ""
Write-Host "Slots are allocated when an actor loads, so this needs a fresh game or a cell reload to show up." -ForegroundColor Cyan
Write-Host ""
