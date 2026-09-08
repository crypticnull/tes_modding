#Requires -Version 5.1
<#
  check_active.ps1 - prove every enabled mod is actually doing something.

    X:\MODDING\OBLIVION\tools\check_active.ps1              summary + problems
    X:\MODDING\OBLIVION\tools\check_active.ps1 -All         also list every mod and its channels

  Read-only. Writes nothing. Safe with MO2 open.

  WHY THIS EXISTS

  A mod in this game reaches the engine through exactly one of six channels:

     Data\*.esp|esm     record edits    - only live if listed in plugins.txt
     Data\* (loose)     meshes, textures, MagicLoader json, SyncMap - always deploy
     Paks\**\*.pak      UE5 assets      - deploy via MO2's Paks mapping
     UE4SS\<name>\      script mods     - only live if listed in mods.txt
     OBSE\Plugins\**    extender plugins and their data - load if deployed
     Root\**            game-folder files - MO2 does NOT deploy these at all;
                        only deploy_external.ps1 does, and this checks the game
                        folder directly rather than trusting any bookkeeping

  A mod that is ticked in MO2 but appears in none of these is doing nothing, and
  nothing in MO2's interface says so. That is how Extended Races shipped four
  playable races that never appeared: its OBRPlayableRaces component is DLL-only
  (dlls\main.dll, no Scripts\main.lua), and MO2's game plugin only writes UE4SS
  mods to mods.txt when it finds Scripts\main.lua. Silent, total, invisible.

  This checks all six channels for all enabled mods and reports the gaps.
#>

[CmdletBinding()]
param(
    [string]$Instance = 'X:\MODDING\OBLIVION\OBLIVION_REMASTERED',
    [string]$GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Oblivion Remastered',
    [switch]$All
)

$ErrorActionPreference = 'Stop'

$ModsDir    = Join-Path $Instance 'mods'
$ProfileDir = Join-Path $Instance 'profiles\Default'
foreach ($p in @($ModsDir, $ProfileDir)) { if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" } }

function Read-Lines { param([string]$P)
    $o = @()
    if (Test-Path -LiteralPath $P) {
        foreach ($l in (Get-Content -LiteralPath $P)) {
            if ($l -match '^\s*#' -or -not $l.Trim()) { continue }
            $o += $l.Trim()
        }
    }
    return ,$o
}

# ---- what the profile says is live ----------------------------------------
$activeEsp = @{}
foreach ($l in (Read-Lines (Join-Path $ProfileDir 'plugins.txt'))) { $activeEsp[$l.TrimStart('*').ToLower()] = $true }

$activeUe4 = @{}
foreach ($l in (Read-Lines (Join-Path $ProfileDir 'mods.txt'))) {
    # format is "ModName : 1"
    if ($l -match '^(.+?)\s*:\s*(\d+)\s*$') { if ([int]$Matches[2] -ne 0) { $activeUe4[$Matches[1].Trim().ToLower()] = $true } }
}

# Root\ deployment is checked against the GAME FOLDER, not the manifest. The
# manifest only records what a given run wrote, so files copied by an earlier
# run - or by an earlier version of the script - are absent from it while being
# perfectly well deployed. The question is "is it there", not "did we log it".

$enabled = @()
foreach ($l in (Get-Content -LiteralPath (Join-Path $ProfileDir 'modlist.txt'))) {
    if ($l -match '^\+(.+)$') { $enabled += $Matches[1].TrimEnd() }
}

Write-Host "=== active-content check ==="
Write-Host ("{0} enabled mod(s)   |   plugins.txt: {1} active   mods.txt: {2} enabled" -f `
            $enabled.Count, $activeEsp.Count, $activeUe4.Count)
Write-Host ""

# ---- walk every mod --------------------------------------------------------
$rows = @()
$dead = @(); $espOff = @(); $ue4Off = @(); $rootOff = @(); $spaced = @(); $mlJson = @()

foreach ($m in $enabled) {
    $md = Join-Path $ModsDir $m
    if (-not (Test-Path -LiteralPath $md)) {
        $dead += ("{0}   <- listed in modlist.txt but no folder on disk" -f $m); continue
    }

    $dataDir = Join-Path $md 'Data'
    $esps = @(); $loose = 0
    if (Test-Path -LiteralPath $dataDir) {
        # a plugin only counts if it sits at the root of Data\ - nested one deeper
        # it is invisible to MO2 as a plugin even though the file exists
        $dataRoot = (Get-Item -LiteralPath $dataDir).FullName
        foreach ($f in @(Get-ChildItem -LiteralPath $dataDir -Recurse -File -ErrorAction SilentlyContinue)) {
            if ($f.Extension -in @('.esp','.esm') -and $f.Directory.FullName -eq $dataRoot) {
                $esps += $f.Name
            } else { $loose++ }
            if ($f.Extension -eq '.json' -and $f.FullName -match '(?i)\\Data\\MagicLoader\\') {
                if ($mlJson -notcontains $m) { $mlJson += $m }
            }
        }
    }

    $paks = @(Get-ChildItem -LiteralPath $md -Recurse -File -Filter '*.pak' -ErrorAction SilentlyContinue).Count

    $ue4Dir = Join-Path $md 'UE4SS'
    $ue4 = @()
    if (Test-Path -LiteralPath $ue4Dir) { $ue4 = @(Get-ChildItem -LiteralPath $ue4Dir -Directory -ErrorAction SilentlyContinue) }

    $obseDir = Join-Path $md 'OBSE'
    $obse = 0
    if (Test-Path -LiteralPath $obseDir) {
        # not just *.dll - Address Library ships .bin version databases and
        # nothing else, and it is very much doing something
        $obse = @(Get-ChildItem -LiteralPath $obseDir -Recurse -File -ErrorAction SilentlyContinue).Count
    }

    $rootDir = Join-Path $md 'Root'
    $rootFiles = @()
    if (Test-Path -LiteralPath $rootDir) {
        $rootFiles = @(Get-ChildItem -LiteralPath $rootDir -Recurse -File -ErrorAction SilentlyContinue)
    }

    $other = 0
    foreach ($d in @('GameSettings','Movies')) {
        $p = Join-Path $md $d
        if (Test-Path -LiteralPath $p) { $other += @(Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue).Count }
    }

    # ---- per-channel problems ---------------------------------------------
    foreach ($e in $esps) {
        if (-not $activeEsp[$e.ToLower()]) { $espOff += ("{0}   ->  {1}" -f $m, $e) }
    }
    foreach ($u in $ue4) {
        if ($u.Name -match '\s') { $spaced += ("{0}   ->  {1}" -f $m, $u.Name) }
        # UE4SS keeps shared libraries under Mods\shared - it is a library path,
        # not a mod, and correctly never appears in mods.txt
        if ($u.Name.ToLower() -in @('shared')) { continue }
        if (-not $activeUe4[$u.Name.ToLower()]) {
            $hasLua = Test-Path -LiteralPath (Join-Path $u.FullName 'Scripts\main.lua')
            $hasDll = @(Get-ChildItem -LiteralPath $u.FullName -Recurse -File -Filter '*.dll' -ErrorAction SilentlyContinue).Count -gt 0
            $why = 'has Scripts\main.lua but is absent from mods.txt - restart MO2 to regenerate'
            if (-not $hasLua) {
                if ($hasDll) { $why = 'DLL-only, MO2 will not list it (needs a Scripts\main.lua stub)' }
                else         { $why = 'no Scripts\main.lua and no dll - is this a UE4SS mod at all?' }
            }
            $ue4Off += ("{0}   ->  {1}   [{2}]" -f $m, $u.Name, $why)
        }
    }
    foreach ($rf in $rootFiles) {
        $rel = $rf.FullName.Substring($rootDir.Length).TrimStart('\')
        # Engine.ini is deployed to Documents by deploy_external step 1, not the game tree
        if ($rel -match '(?i)^OblivionRemastered\\Saved\\Config\\') { continue }
        $dst = Join-Path $GamePath $rel
        if (-not (Test-Path -LiteralPath $dst)) {
            $rootOff += ("{0}   ->  {1}   [absent from the game folder]" -f $m, $rel)
        } elseif ((Get-Item -LiteralPath $dst).Length -ne $rf.Length) {
            $rootOff += ("{0}   ->  {1}   [deployed copy differs - mod was updated?]" -f $m, $rel)
        }
    }

    $channels = @()
    if ($esps.Count)      { $channels += "esp:$($esps.Count)" }
    if ($loose)           { $channels += "data:$loose" }
    if ($paks)            { $channels += "pak:$paks" }
    if ($ue4.Count)       { $channels += "ue4ss:$($ue4.Count)" }
    if ($obse)            { $channels += "obse:$obse" }
    if ($rootFiles.Count) { $channels += "root:$($rootFiles.Count)" }
    if ($other)           { $channels += "other:$other" }

    if (-not $channels.Count) { $dead += ("{0}   <- folder exists but contains nothing the game reads" -f $m) }
    $rows += [pscustomobject]@{ Mod = $m; Channels = ($channels -join '  ') }
}

# ---- report ----------------------------------------------------------------
function Section { param([string]$Title, [string[]]$Items, [string]$Colour, [string]$Note)
    if (-not $Items -or $Items.Count -eq 0) { Write-Host ("  {0,-34} none" -f $Title) -ForegroundColor DarkGray; return }
    Write-Host ("  {0,-34} {1}" -f $Title, $Items.Count) -ForegroundColor $Colour
    foreach ($i in $Items) { Write-Host ("      {0}" -f $i) -ForegroundColor $Colour }
    if ($Note) { Write-Host ("      -> {0}" -f $Note) }
    Write-Host ""
}

Write-Host "--- problems ---"
Section 'contributing nothing'        $dead    'Red'    'either the install failed or the archive had no game content'
Section 'ESP present but not enabled' $espOff  'Red'    'run loadorder.ps1 -Apply -EnablePlugins, then sort with LOOT'
Section 'UE4SS mod not in mods.txt'   $ue4Off  'Red'    'this mod loads nothing until it appears there'
Section 'Root file not deployed'      $rootOff 'Red'    'run deploy_external.ps1 -Apply'
Section 'UE4SS name contains a space' $spaced  'Yellow' 'UE4SS strips spaces when parsing mods.txt and then fails to match'

if ($mlJson.Count) {
    Write-Host ("  {0,-34} {1}" -f 'ships MagicLoader JSON', $mlJson.Count)
    foreach ($i in $mlJson) { Write-Host ("      {0}" -f $i) }
    Write-Host "      -> these only take effect after MagicLoader is re-run. Re-cook whenever this set changes."
    Write-Host ""
}

$bad = $dead.Count + $espOff.Count + $ue4Off.Count + $rootOff.Count
if ($bad -eq 0) { Write-Host "Every enabled mod reaches the game through at least one live channel." -ForegroundColor Green }
else { Write-Host ("{0} mod component(s) are installed but inert." -f $bad) -ForegroundColor Red }
Write-Host ""

if ($All) {
    Write-Host "--- every enabled mod ---"
    foreach ($r in $rows) { Write-Host ("  {0,-72} {1}" -f $r.Mod, $r.Channels) }
}
