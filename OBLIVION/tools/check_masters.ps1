#Requires -Version 5.1
<#
  check_masters.ps1 - read every ESP/ESM header and prove the load order is
  actually loadable, before the game gets a chance to fail at it.

    X:\MODDING\OBLIVION\tools\check_masters.ps1

  Read-only. Writes nothing, changes nothing. Safe with MO2 open.

  Every Bethesda plugin declares the plugins it depends on, in its TES4 header.
  The game will not load a plugin whose masters are absent, inactive, or loaded
  after it. MO2 shows this as a small warning triangle per row, which is easy to
  miss in a list of fifty. This checks all four failure modes at once:

    MISSING   a declared master is not installed at all
    INACTIVE  it is installed but not ticked in plugins.txt
    ORDER     it is active but loads AFTER the plugin that needs it
    GHOST     plugins.txt lists a plugin that has no file behind it

  GHOST is the one that bit this setup before: Vortex left AutoUpgradeRewards.esp
  enabled pointing at a file that never existed, which silently shifts every
  plugin index after it.

    -Verbose  also print the full master list of every plugin
#>

[CmdletBinding()]
param(
    [string]$Instance = 'X:\MODDING\OBLIVION\OBLIVION_REMASTERED',
    [string]$GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Oblivion Remastered'
)

$ErrorActionPreference = 'Stop'

$ModsDir    = Join-Path $Instance 'mods'
$ProfileDir = Join-Path $Instance 'profiles\Default'
$GameData   = Join-Path $GamePath 'OblivionRemastered\Content\Dev\ObvData\Data'

foreach ($p in @($ModsDir, $ProfileDir, $GameData)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" }
}

# ---- read a plugin's declared masters out of its TES4 header --------------
# Oblivion-era format: 20-byte record header, then subrecords of
# 4-char type + UInt16 length + payload. Masters are the MAST subrecords,
# in the order the plugin expects them.
function Get-EspMasters {
    param([string]$Path)
    $fs = [IO.File]::OpenRead($Path)
    try {
        $br  = New-Object IO.BinaryReader($fs)
        $sig = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
        if ($sig -ne 'TES4') { return $null }          # not a plugin at all
        $dataSize = $br.ReadUInt32()
        $null = $br.ReadUInt32(); $null = $br.ReadUInt32(); $null = $br.ReadUInt32()
        $end = 20 + $dataSize
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

Write-Host "=== master check ==="
Write-Host ""

# ---- where every plugin actually lives ------------------------------------
# modlist.txt is highest-priority-first, so the first mod that ships a given
# plugin name is the one MO2 deploys. Later ones are shadowed.
$fileOf = [ordered]@{}
$shadow = @()

foreach ($f in @(Get-ChildItem -LiteralPath $GameData -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Extension -in @('.esp','.esm') })) {
    $fileOf[$f.Name] = @{ path = $f.FullName; src = '(game)' }
}

$mlPath = Join-Path $ProfileDir 'modlist.txt'
$enabledMods = @()
foreach ($l in (Get-Content -LiteralPath $mlPath)) {
    if ($l -match '^\+(.+)$') { $enabledMods += $Matches[1].TrimEnd() }
}
foreach ($m in $enabledMods) {
    $dd = Join-Path (Join-Path $ModsDir $m) 'Data'
    if (-not (Test-Path -LiteralPath $dd)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $dd -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Extension -in @('.esp','.esm') })) {
        if ($fileOf.Contains($f.Name)) {
            if ($fileOf[$f.Name].src -ne '(game)') { $shadow += "$($f.Name)  [$m shadowed by $($fileOf[$f.Name].src)]" }
            continue
        }
        $fileOf[$f.Name] = @{ path = $f.FullName; src = $m }
    }
}

# ---- what is active, and in what order ------------------------------------
function Read-List { param([string]$P)
    $o = @()
    if (Test-Path -LiteralPath $P) {
        foreach ($l in (Get-Content -LiteralPath $P)) {
            if ($l -match '^\s*#' -or -not $l.Trim()) { continue }
            $o += $l.Trim().TrimStart('*')
        }
    }
    return ,$o
}
$active = Read-List (Join-Path $ProfileDir 'plugins.txt')
$order  = Read-List (Join-Path $ProfileDir 'loadorder.txt')

$activeSet = @{}; foreach ($a in $active) { $activeSet[$a.ToLower()] = $true }
$pos = @{};       for ($i = 0; $i -lt $order.Count; $i++) { $pos[$order[$i].ToLower()] = $i }

Write-Host ("plugins on disk : {0}" -f $fileOf.Count)
Write-Host ("active          : {0}" -f $active.Count)
Write-Host ("in loadorder    : {0}" -f $order.Count)
Write-Host ""

# ---- the four checks ------------------------------------------------------
$missing = @(); $inactive = @(); $badOrder = @(); $ghost = @(); $unread = @()

foreach ($name in $active) {
    if (-not $fileOf.Contains($name)) { $ghost += $name }
}

foreach ($name in $active) {
    if (-not $fileOf.Contains($name)) { continue }
    $masters = $null
    try { $masters = Get-EspMasters -Path $fileOf[$name].path }
    catch { $unread += ("{0}  ({1})" -f $name, $_.Exception.Message); continue }
    if ($null -eq $masters) { $unread += ("{0}  (no TES4 header)" -f $name); continue }

    if ($VerbosePreference -eq 'Continue' -and $masters.Count) {
        Write-Host ("  {0}" -f $name) -ForegroundColor DarkGray
        foreach ($m in $masters) { Write-Host ("      {0}" -f $m) -ForegroundColor DarkGray }
    }

    foreach ($m in $masters) {
        $ml = $m.ToLower()
        if (-not $fileOf.Contains($m)) { $missing  += "$name  needs  $m"; continue }
        if (-not $activeSet[$ml])      { $inactive += "$name  needs  $m  (installed but not enabled)"; continue }
        if ($pos.ContainsKey($ml) -and $pos.ContainsKey($name.ToLower())) {
            if ($pos[$ml] -gt $pos[$name.ToLower()]) {
                $badOrder += ("{0} (#{1})  needs  {2} (#{3})  - master loads too late" -f `
                              $name, $pos[$name.ToLower()], $m, $pos[$ml])
            }
        }
    }
}

function Report { param([string]$Label, [string[]]$Items, [string]$Colour, [string]$Note)
    if (-not $Items -or $Items.Count -eq 0) { Write-Host ("  {0,-10} none" -f $Label) -ForegroundColor DarkGray; return }
    Write-Host ("  {0,-10} {1}" -f $Label, $Items.Count) -ForegroundColor $Colour
    foreach ($i in $Items) { Write-Host ("      {0}" -f $i) -ForegroundColor $Colour }
    if ($Note) { Write-Host ("      -> {0}" -f $Note) }
}

Write-Host "--- results ---"
Report 'MISSING'  $missing  'Red'    'install the missing plugin, or disable the one that needs it'
Report 'INACTIVE' $inactive 'Red'    'tick it in MO2, or re-run loadorder.ps1 -Apply -EnablePlugins'
Report 'ORDER'    $badOrder 'Yellow' 'LOOT will normally fix this - sort, then re-run this check'
Report 'GHOST'    $ghost    'Red'    'enabled with no file behind it - it shifts every later plugin index'
Report 'UNREAD'   $unread   'Yellow' 'could not parse - look at these by hand'
Write-Host ""

if ($shadow.Count) {
    Write-Host ("--- {0} plugin(s) shadowed by a higher-priority mod (usually fine) ---" -f $shadow.Count)
    foreach ($s in $shadow) { Write-Host ("  {0}" -f $s) }
    Write-Host ""
}

$hard = $missing.Count + $inactive.Count + $ghost.Count
if ($hard -eq 0 -and $badOrder.Count -eq 0) {
    Write-Host "Clean. Every active plugin has every master it needs, in the right order." -ForegroundColor Green
} elseif ($hard -eq 0) {
    Write-Host "No missing masters. Ordering issues only - sort with LOOT and re-run." -ForegroundColor Yellow
} else {
    Write-Host ("{0} problem(s) that will stop plugins loading. Fix these before launching." -f $hard) -ForegroundColor Red
}
