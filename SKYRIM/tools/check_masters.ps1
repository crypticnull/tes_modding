#Requires -Version 5.1
<#
  check_masters.ps1 - find plugins that will be silently switched off.

    check_masters.ps1            check every active plugin
    check_masters.ps1 -All       also list the ones that are fine

  Read-only. Safe with MO2 open.

  WHY

  Skyrim does not warn you about a plugin whose masters it cannot resolve. It
  deactivates it and writes plugins.txt back without the asterisk, and the next
  time you look everything appears installed and enabled - the mod folder is
  there, the tick is there in MO2, and the mod simply does nothing in game.

  That is exactly how Alternate Start looked: installed, ticked, inert, because
  it needs unofficial skyrim special edition patch.esp and that was not present.
  A minute of parsing would have caught it before the launch.

  WHAT COUNTS AS A SATISFIED MASTER

  The file has to EXIST somewhere the game can see it, and it has to be ACTIVE,
  and it has to load BEFORE the plugin that needs it. All three, or the
  dependent plugin dies quietly.

    exists   in an enabled mod under mods\, or in the game's own Data folder
    active   listed with a leading '*' in plugins.txt, OR one of the five
             always-on vanilla masters, OR listed in Skyrim.ccc which is how
             Creation Club content loads without appearing in plugins.txt
    order    appears earlier in loadorder.txt

  TES4 HEADER FORMAT

  Skyrim's record header is 24 bytes, not the 20 that Oblivion uses - that is
  the one difference from the Oblivion version of this script. After it come
  subrecords of a 4-char type, a UInt16 length, and a payload. MAST subrecords
  are the masters, in load order.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [switch]$All
)

$ErrorActionPreference = 'Stop'
$Instance  = Join-Path $Root 'SKYRIM_SE'
$ModsDir   = Join-Path $Instance 'mods'
$ProfileD  = Join-Path $Instance 'profiles\Default'
$GameData  = Join-Path $Root 'STOCK GAME\Data'
$Ccc       = Join-Path $Root 'STOCK GAME\Skyrim.ccc'

# these load whether or not anything lists them
$AlwaysOn = @('skyrim.esm','update.esm','dawnguard.esm','hearthfires.esm','dragonborn.esm')

function Get-EspMasters {
    param([string]$Path)
    $fs = [IO.File]::OpenRead($Path)
    try {
        $br  = New-Object IO.BinaryReader($fs)
        if ([Text.Encoding]::ASCII.GetString($br.ReadBytes(4)) -ne 'TES4') { return $null }
        $dataSize = $br.ReadUInt32()
        $null = $br.ReadUInt32()   # flags
        $null = $br.ReadUInt32()   # formid
        $null = $br.ReadUInt32()   # revision
        $null = $br.ReadUInt32()   # version + unknown - Skyrim header is 24 bytes
        $end = 24 + $dataSize
        $out = New-Object System.Collections.Generic.List[string]
        while ($fs.Position -lt $end -and $fs.Position -lt $fs.Length) {
            $t  = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
            $sz = $br.ReadUInt16()
            $d  = $br.ReadBytes($sz)
            if ($t -eq 'MAST') {
                $s = [Text.Encoding]::GetEncoding(1252).GetString($d).TrimEnd([char]0)
                if ($s) { $out.Add($s) }
            }
        }
        return ,$out.ToArray()
    } finally { $fs.Dispose() }
}

Write-Host ""
Write-Host "=== master check ===" -ForegroundColor Cyan

# ---- where every plugin file lives, lowest priority first ------------------
$where = @{}
if (Test-Path -LiteralPath $GameData) {
    foreach ($f in @(Get-ChildItem -LiteralPath $GameData -File -ErrorAction SilentlyContinue)) {
        if ($f.Extension.ToLower() -in @('.esp','.esm','.esl')) { $where[$f.Name.ToLower()] = $f.FullName }
    }
}
$enabledMods = @()
foreach ($l in (Get-Content -LiteralPath (Join-Path $ProfileD 'modlist.txt'))) {
    if ($l -match '^\+(.+)$') { $enabledMods += $Matches[1].TrimEnd() }
}
foreach ($m in $enabledMods) {
    $md = Join-Path $ModsDir $m
    if (-not (Test-Path -LiteralPath $md)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $md -File -ErrorAction SilentlyContinue)) {
        if ($f.Extension.ToLower() -in @('.esp','.esm','.esl')) { $where[$f.Name.ToLower()] = $f.FullName }
    }
}

# ---- what is active --------------------------------------------------------
$active = @{}
foreach ($n in $AlwaysOn) { $active[$n] = $true }
if (Test-Path -LiteralPath $Ccc) {
    foreach ($l in (Get-Content -LiteralPath $Ccc)) {
        $n = $l.Trim(); if ($n -and $n -notmatch '^\s*#') { $active[$n.ToLower()] = $true }
    }
}
$listed = @{}
foreach ($l in (Get-Content -LiteralPath (Join-Path $ProfileD 'plugins.txt'))) {
    if ($l -match '^\s*#' -or -not $l.Trim()) { continue }
    $n = $l.TrimStart('*').Trim().ToLower()
    $listed[$n] = $true
    if ($l.TrimStart().StartsWith('*')) { $active[$n] = $true }
}

# ---- load order ------------------------------------------------------------
$order = @{}
$i = 0
$lo = Join-Path $ProfileD 'loadorder.txt'
if (Test-Path -LiteralPath $lo) {
    foreach ($l in (Get-Content -LiteralPath $lo)) {
        $n = $l.Trim(); if (-not $n -or $n -match '^\s*#') { continue }
        $order[$n.ToLower()] = $i++
    }
}

Write-Host ("  {0} plugin file(s) visible   {1} active   {2} in loadorder.txt" -f $where.Count, $active.Count, $order.Count)
Write-Host ""

# ---- check every plugin an enabled mod provides ----------------------------
$missing = @(); $inactive = @(); $badorder = @(); $unread = @(); $fine = @()

foreach ($m in $enabledMods) {
    $md = Join-Path $ModsDir $m
    if (-not (Test-Path -LiteralPath $md)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $md -File -ErrorAction SilentlyContinue)) {
        if ($f.Extension.ToLower() -notin @('.esp','.esm','.esl')) { continue }
        $name = $f.Name; $key = $name.ToLower()

        $masters = $null
        try { $masters = Get-EspMasters $f.FullName } catch { }
        if ($null -eq $masters) { $unread += ("{0}  ({1})" -f $name, $m); continue }

        $problems = @()
        foreach ($mm in $masters) {
            $mk = $mm.ToLower()
            if (-not $where.ContainsKey($mk)) { $problems += "MISSING  $mm"; continue }
            if (-not $active.ContainsKey($mk)) { $problems += "INACTIVE $mm"; continue }
            if ($order.ContainsKey($mk) -and $order.ContainsKey($key) -and $order[$mk] -gt $order[$key]) {
                $problems += "ORDER    $mm loads after it"
            }
        }
        if ($problems.Count) {
            foreach ($p in $problems) {
                if     ($p -like 'MISSING*')  { $missing  += ("{0}  needs {1}" -f $name, $p.Substring(9)) }
                elseif ($p -like 'INACTIVE*') { $inactive += ("{0}  needs {1}" -f $name, $p.Substring(9)) }
                else                          { $badorder += ("{0}  {1}"       -f $name, $p.Substring(9)) }
            }
        } else {
            $fine += ("{0,-52} {1} master(s), ok" -f $name, $masters.Count)
        }
        if (-not $active.ContainsKey($key)) {
            $why = if ($listed.ContainsKey($key)) { 'listed but not active' } else { 'not in plugins.txt at all' }
            $inactive += ("{0}  <- THIS PLUGIN ITSELF is off ({1})" -f $name, $why)
        }
    }
}

function Section { param([string]$T, [string[]]$Items, [string]$C, [string]$Note)
    if (-not $Items -or -not $Items.Count) { Write-Host ("  {0,-28} none" -f $T) -ForegroundColor DarkGray; return }
    Write-Host ("  {0,-28} {1}" -f $T, $Items.Count) -ForegroundColor $C
    foreach ($i in $Items) { Write-Host ("      {0}" -f $i) -ForegroundColor $C }
    if ($Note) { Write-Host ("      -> {0}" -f $Note) }
    Write-Host ""
}

Section 'missing master'      $missing  'Red'    'install the mod that provides it, or the dependent plugin will be silently deactivated'
Section 'inactive'            $inactive 'Red'    'run enable_plugins.ps1 -Apply with MO2 closed'
Section 'loads out of order'  $badorder 'Yellow' 'open MO2 and Sort with LOOT'
Section 'could not parse'     $unread   'Yellow' 'not a valid TES4 plugin - is it a stray file?'

if (-not ($missing.Count + $inactive.Count + $badorder.Count)) {
    Write-Host "Every managed plugin has its masters present, active and correctly ordered." -ForegroundColor Green
}
Write-Host ""
if ($All) {
    Write-Host "--- healthy ---"
    foreach ($f in $fine) { Write-Host ("  {0}" -f $f) }
    Write-Host ""
}
