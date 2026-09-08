#Requires -Version 5.1
<#
  working_config.ps1 - snapshot and restore the known-good Skyrim DLSS 5 setup.

      working_config.ps1 -Save                 snapshot the current settings
      working_config.ps1 -Save -Label "note"   ...with a name you'll recognise
      working_config.ps1 -List                 show the snapshots on disk
      working_config.ps1 -Restore              restore the newest snapshot
      working_config.ps1 -Restore -Name <dir>  restore a specific one
      working_config.ps1 -Check                compare current files to newest

  WHY THIS EXISTS

  Getting Community Shaders, DLSS 5 neural rendering and a correct 4K borderless
  window to coexist took most of a day, and the settings that make it work live
  in six different files owned by four different programs. Any one of them
  getting rewritten - by the game on exit, by MO2, by a mod update, by the CS
  menu - silently breaks the stack, and the symptom (the picture looks wrong)
  does not point at the file. This copies all six somewhere safe and puts them
  back on demand.

  Snapshots go to backups\known_good\<timestamp>[-label]\ and are never deleted
  by this script.
#>

[CmdletBinding(DefaultParameterSetName = 'Save')]
param(
    [Parameter(ParameterSetName='Save')]    [switch]$Save,
    [Parameter(ParameterSetName='Save')]    [string]$Label = '',
    [Parameter(ParameterSetName='List')]    [switch]$List,
    [Parameter(ParameterSetName='Restore')] [switch]$Restore,
    [Parameter(ParameterSetName='Restore')] [string]$Name = '',
    [Parameter(ParameterSetName='Check')]   [switch]$Check,
    [string]$Root = 'X:\MODDING\SKYRIM'
)

$ErrorActionPreference = 'Stop'

$Store   = Join-Path $Root 'backups\known_good'
$Stock   = Join-Path $Root 'STOCK GAME'
$Profile = Join-Path $Root 'SKYRIM_SE\profiles\Default'
$Mods    = Join-Path $Root 'SKYRIM_SE\mods'

# Each entry: the file, and the short name it is stored under. The short name is
# flat so a snapshot folder is readable at a glance.
$Over = Join-Path $Root 'SKYRIM_SE\overwrite'

# Paths is a candidate list, first existing wins. MO2 redirects a write aimed at
# the game's Data folder into overwrite\, so a file the program's own log says it
# wrote to STOCK GAME\Data is usually not there at all - Community Shaders is
# exactly that case. Listing both means the snapshot finds it either way.
$Files = @(
    @{ Key = 'dlss5-bridge.cfg';     Paths = @((Join-Path $Stock   'dlss5-bridge.cfg')) },
    @{ Key = 'ReShade.ini';          Paths = @((Join-Path $Stock   'ReShade.ini')) },
    @{ Key = 'SkyrimPrefs.ini';      Paths = @((Join-Path $Profile 'SkyrimPrefs.ini')) },
    @{ Key = 'Skyrim.ini';           Paths = @((Join-Path $Profile 'Skyrim.ini')) },
    @{ Key = 'modlist.txt';          Paths = @((Join-Path $Profile 'modlist.txt')) },
    @{ Key = 'plugins.txt';          Paths = @((Join-Path $Profile 'plugins.txt')) },
    @{ Key = 'loadorder.txt';        Paths = @((Join-Path $Profile 'loadorder.txt')) },
    @{ Key = 'SSEDisplayTweaks.ini'; Paths = @((Join-Path $Mods    'SSE Display Tweaks\SKSE\Plugins\SSEDisplayTweaks.ini')) },
    @{ Key = 'GrassControl.ini';     Paths = @((Join-Path $Mods    'NGIO - GrassControl Config\SKSE\Plugins\GrassControl.ini')) },
    @{ Key = 'GrassCacheHelperNG.ini'; Paths = @((Join-Path $Mods  'Grass Cache Helper NG\SKSE\Plugins\GrassCacheHelperNG.ini')) },
    @{ Key = 'CS-SettingsUser.json'; Paths = @((Join-Path $Over    'SKSE\Plugins\CommunityShaders\SettingsUser.json'),
                                               (Join-Path $Stock   'Data\SKSE\Plugins\CommunityShaders\SettingsUser.json'),
                                               (Join-Path $Mods    'Community Shaders\SKSE\Plugins\CommunityShaders\SettingsUser.json')) }
)

# Where the file is now, for reading. $null when none of the candidates exist.
function Resolve-Existing {
    param($Entry)
    foreach ($c in $Entry.Paths) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}

# Where a restore should put it back: wherever it currently is, else the first
# candidate, which is the location the program actually writes to.
function Resolve-Target {
    param($Entry)
    $e = Resolve-Existing $Entry
    if ($e) { return $e }
    return $Entry.Paths[0]
}

function Get-Snapshots {
    if (-not (Test-Path -LiteralPath $Store)) { return @() }
    return @(Get-ChildItem -LiteralPath $Store -Directory | Sort-Object Name -Descending)
}

# The undo copies written by -Restore are snapshots too, but they hold the state
# that was being thrown away. Picking one as "newest" would restore the fault.
# They stay visible to -List and addressable by -Name, never chosen by default.
function Get-DefaultSnapshot {
    $all = Get-Snapshots
    $good = @($all | Where-Object { $_.Name -notlike '*-before-restore' })
    if ($good.Count) { return $good[0] }
    return $null
}

function Get-Hash {
    param([string]$P)
    if (-not (Test-Path -LiteralPath $P)) { return '(missing)' }
    return (Get-FileHash -LiteralPath $P -Algorithm SHA256).Hash.Substring(0,12)
}

# ---------------------------------------------------------------- SAVE --------
if ($PSCmdlet.ParameterSetName -eq 'Save') {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    if ($Label) {
        $clean = ($Label -replace '[^A-Za-z0-9\-_ ]','').Trim() -replace '\s+','-'
        if ($clean) { $stamp = "$stamp-$clean" }
    }
    $dest = Join-Path $Store $stamp
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    $manifest = New-Object System.Collections.ArrayList
    $saved = 0; $missing = 0

    Write-Host ""
    Write-Host "=== saving snapshot $stamp ===" -ForegroundColor Cyan
    foreach ($f in $Files) {
        $src = Resolve-Existing $f
        if ($src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $dest $f.Key) -Force
            $h = Get-Hash $src
            [void]$manifest.Add(("{0}`t{1}`t{2}" -f $f.Key, $h, $src))
            Write-Host ("  saved    {0,-26} {1}" -f $f.Key, $h)
            $saved++
        } else {
            [void]$manifest.Add(("{0}`t(missing)`t{1}" -f $f.Key, $f.Paths[0]))
            Write-Host ("  MISSING  {0,-26} {1}" -f $f.Key, $f.Paths[0]) -ForegroundColor Yellow
            $missing++
        }
    }
    $manifest | Set-Content -LiteralPath (Join-Path $dest 'manifest.tsv') -Encoding UTF8
    Write-Host ""
    Write-Host ("  {0} file(s) saved, {1} missing" -f $saved, $missing)
    Write-Host ("  {0}" -f $dest)
    return
}

# ---------------------------------------------------------------- LIST --------
if ($PSCmdlet.ParameterSetName -eq 'List') {
    $snaps = Get-Snapshots
    Write-Host ""
    if (-not $snaps.Count) { Write-Host "no snapshots in $Store"; return }
    Write-Host "=== snapshots (newest first) ===" -ForegroundColor Cyan
    foreach ($s in $snaps) {
        $n = @(Get-ChildItem -LiteralPath $s.FullName -File | Where-Object { $_.Name -ne 'manifest.tsv' }).Count
        Write-Host ("  {0,-34} {1} file(s)   {2}" -f $s.Name, $n, $s.LastWriteTime)
    }
    return
}

# ------------------------------------------------------------- CHECK ---------
if ($PSCmdlet.ParameterSetName -eq 'Check') {
    $src = Get-DefaultSnapshot
    if (-not $src) { throw "no snapshots to compare against - run with -Save first" }
    Write-Host ""
    Write-Host ("=== current vs {0} ===" -f $src.Name) -ForegroundColor Cyan
    $diff = 0
    foreach ($f in $Files) {
        $stored = Join-Path $src.FullName $f.Key
        if (-not (Test-Path -LiteralPath $stored)) { continue }
        $cur = Resolve-Existing $f
        $a = if ($cur) { Get-Hash $cur } else { '(missing)' }
        $b = Get-Hash $stored
        if ($a -eq $b) {
            Write-Host ("  same     {0}" -f $f.Key)
        } else {
            Write-Host ("  CHANGED  {0,-26} now {1}  snapshot {2}" -f $f.Key, $a, $b) -ForegroundColor Yellow
            $diff++
        }
    }
    Write-Host ""
    Write-Host ("  {0} file(s) differ" -f $diff)
    return
}

# ----------------------------------------------------------- RESTORE ---------
if ($PSCmdlet.ParameterSetName -eq 'Restore') {
    if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
        throw "Mod Organizer is running. It rewrites modlist.txt and plugins.txt on exit and would discard this. Close it first."
    }
    if (Get-Process -Name 'SkyrimSE' -ErrorAction SilentlyContinue) {
        throw "Skyrim is running. Close it first."
    }

    $snaps = Get-Snapshots
    if (-not $snaps.Count) { throw "no snapshots in $Store" }
    if ($Name) {
        $src = $snaps | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if (-not $src) { throw "no snapshot named '$Name' - run -List to see what exists" }
    } else {
        $src = Get-DefaultSnapshot
        if (-not $src) { throw "no snapshot to restore - every one on disk is a -before-restore undo copy; name one explicitly with -Name" }
    }

    # never restore without first preserving what is being overwritten
    $undo = Join-Path $Store ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-before-restore')
    New-Item -ItemType Directory -Path $undo -Force | Out-Null

    Write-Host ""
    Write-Host ("=== restoring {0} ===" -f $src.Name) -ForegroundColor Cyan
    $done = 0
    foreach ($f in $Files) {
        $stored = Join-Path $src.FullName $f.Key
        if (-not (Test-Path -LiteralPath $stored)) {
            Write-Host ("  skip     {0} - not in this snapshot" -f $f.Key)
            continue
        }
        $target = Resolve-Target $f
        if (Test-Path -LiteralPath $target) {
            Copy-Item -LiteralPath $target -Destination (Join-Path $undo $f.Key) -Force
        }
        $dir = Split-Path $target -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $stored -Destination $target -Force
        Write-Host ("  restored {0}" -f $f.Key)
        $done++
    }
    Write-Host ""
    Write-Host ("  {0} file(s) restored" -f $done)
    Write-Host ("  previous state kept at {0}" -f $undo)
    return
}
