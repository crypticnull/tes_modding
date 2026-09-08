#Requires -Version 5.1
<#
  move_root.ps1 - relocate the Skyrim setup from X:\SKYRIM to X:\MODDING\SKYRIM.

    X:\MODDING\tools\move_root.ps1            report what it would do
    X:\MODDING\tools\move_root.ps1 -Apply     do it

  Same volume, so the move itself is a rename and takes no time regardless of
  the 20 GiB sitting in STOCK GAME. Everything expensive here is the bookkeeping
  afterwards.

  THREE THINGS HOLD ABSOLUTE PATHS AND ALL THREE BREAK ON A PLAIN MOVE:

    1. ModOrganizer.ini - gamePath, base_directory and every registered
       executable. Rewritten here. Note the two spellings in that file:
       @ByteArray() and base_directory use doubled backslashes, while binary
       and workingDirectory use forward slashes. Both are handled.

    2. The DPI compatibility flags, which are keyed by the full exe path in
       AppCompatFlags\Layers. A moved exe silently loses its flag - the game
       still runs, the window is just wrong again. Old entries removed, new
       ones written only if the old ones existed.

    3. The tools' own default paths. Not touched here; those scripts get
       replaced wholesale after the move.

  This script deliberately lives in X:\MODDING\tools, NOT in the folder being
  moved, so it is not pulled out from under itself mid-run.
#>

[CmdletBinding()]
param(
    [string]$From = 'X:\SKYRIM',
    [string]$To   = 'X:\MODDING\SKYRIM',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$LayersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$mode      = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to move' }

Write-Host ""
Write-Host "=== relocate Skyrim root ($mode) ===" -ForegroundColor Cyan
Write-Host ("  {0}  ->  {1}" -f $From, $To)
Write-Host ""

# ---------------------------------------------------------------- preflight --
$fail = @()
if (-not (Test-Path -LiteralPath $From)) { $fail += "source not found: $From" }
if (Test-Path -LiteralPath $To) {
    $n = @(Get-ChildItem -LiteralPath $To -Force -ErrorAction SilentlyContinue).Count
    if ($n) { $fail += "$To already exists and is not empty ($n entries). Sort that out first." }
}
foreach ($p in @('ModOrganizer','SkyrimSE','skse64_loader')) {
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) { $fail += "$p is running - close it." }
}
if ((Split-Path -Qualifier $From) -ne (Split-Path -Qualifier $To)) {
    Write-Host "  NOTE: different volumes - this will be a real copy, not a rename." -ForegroundColor Yellow
}

if ($fail.Count) {
    Write-Host "--- cannot continue ---" -ForegroundColor Red
    foreach ($f in $fail) { Write-Host ("  {0}" -f $f) -ForegroundColor Red }
    Write-Host ""
    return
}

$sz = ($(Get-ChildItem -LiteralPath $From -Recurse -File -Force -ErrorAction SilentlyContinue) |
       Measure-Object -Property Length -Sum)
Write-Host ("  {0:N0} files, {1:N2} GiB" -f $sz.Count, ($sz.Sum / 1GB))

# which DPI flags exist right now
$flagged = @()
if (Test-Path -LiteralPath $LayersKey) {
    $props = Get-ItemProperty -LiteralPath $LayersKey
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -like "$From*") { $flagged += @{ old = $p.Name; value = $p.Value } }
    }
}
Write-Host ("  DPI flags to re-point: {0}" -f $flagged.Count)
foreach ($f in $flagged) { Write-Host ("      {0}  =  {1}" -f $f.old, $f.value) }

$mo2Ini = Join-Path $From 'MO2\Mod.Organizer-2.5.3\ModOrganizer.ini'
Write-Host ("  ModOrganizer.ini: {0}" -f $(if (Test-Path -LiteralPath $mo2Ini) { 'present, will be rewritten' } else { 'not found, nothing to rewrite' }))

if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing moved. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ------------------------------------------------------------------- move ----
Write-Host ""
Write-Host "--- moving ---"
New-Item -ItemType Directory -Force -Path (Split-Path $To -Parent) | Out-Null
Move-Item -LiteralPath $From -Destination $To -Force
Write-Host ("  moved to {0}" -f $To)

if (Test-Path -LiteralPath $From) { throw "source still exists after the move - stopping before anything else is changed." }

# --------------------------------------------------------- ModOrganizer.ini --
Write-Host ""
Write-Host "--- ModOrganizer.ini ---"
$newIni = Join-Path $To 'MO2\Mod.Organizer-2.5.3\ModOrganizer.ini'
if (Test-Path -LiteralPath $newIni) {
    Copy-Item -LiteralPath $newIni -Destination "$newIni.bak-$Stamp" -Force

    # Both spellings, longest first so neither replacement can eat the other's
    # prefix. Doubled-backslash form is what @ByteArray() and base_directory
    # use; forward-slash form is what binary/workingDirectory use.
    $fromEsc = $From -replace '\\', '\\'
    $toEsc   = $To   -replace '\\', '\\'
    $fromFwd = $From -replace '\\', '/'
    $toFwd   = $To   -replace '\\', '/'

    $hits = 0
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in (Get-Content -LiteralPath $newIni)) {
        $o = $l
        $o = $o.Replace($fromEsc, $toEsc)
        $o = $o.Replace($fromFwd, $toFwd)
        $o = $o.Replace($From,    $To)      # plain form, if any slipped in
        if ($o -ne $l) { $hits++ }
        $out.Add($o)
    }
    [IO.File]::WriteAllLines($newIni, $out, $Utf8NoBom)
    Write-Host ("  {0} line(s) re-pointed" -f $hits)

    # prove it: nothing may still refer to the old root
    $stale = @(Get-Content -LiteralPath $newIni |
               Select-String -SimpleMatch -Pattern @($fromFwd, $fromEsc, $From))
    if ($stale.Count) {
        Write-Host "  STALE PATHS REMAIN:" -ForegroundColor Red
        foreach ($s in $stale) { Write-Host ("      {0}" -f $s.Line) -ForegroundColor Red }
    } else {
        Write-Host "  verified: no references to the old root remain" -ForegroundColor Green
    }
} else {
    Write-Host "  not found - skipped"
}

# ---------------------------------------------------------------- DPI flags --
Write-Host ""
Write-Host "--- DPI compatibility flags ---"
if (-not $flagged.Count) {
    Write-Host "  none were set - nothing to move (display.ps1 -Apply sets them)"
} else {
    foreach ($f in $flagged) {
        $new = $f.old.Replace($From, $To)
        Remove-ItemProperty -LiteralPath $LayersKey -Name $f.old -ErrorAction SilentlyContinue
        New-ItemProperty -LiteralPath $LayersKey -Name $new -Value $f.value -PropertyType String -Force | Out-Null
        Write-Host ("  {0}" -f $new)
    }
}

# --------------------------------------------------- self-contained root -----
# Each game root owns its own tools and its own data, so nothing reaches across
# into another game's folders. nexus_get.ps1 was reading the API key out of the
# Oblivion install, which is exactly the kind of cross-root dependency this
# layout is meant to remove.
Write-Host ""
Write-Host "--- making the root self-contained ---"

$toolsDir = Join-Path $To 'tools'
$dataDir  = Join-Path $To 'data'
New-Item -ItemType Directory -Force -Path $toolsDir, $dataDir | Out-Null

$srcKey = 'X:\MODDING\data\.nexus_api_key'
$dstKey = Join-Path $dataDir '.nexus_api_key'
if ((Test-Path -LiteralPath $srcKey) -and -not (Test-Path -LiteralPath $dstKey)) {
    Copy-Item -LiteralPath $srcKey -Destination $dstKey -Force
    Write-Host ("  Nexus API key copied to {0}" -f $dstKey)
} elseif (Test-Path -LiteralPath $dstKey) {
    Write-Host "  Nexus API key already present"
} else {
    Write-Host "  no API key found at $srcKey - nexus_get.ps1 will need one" -ForegroundColor Yellow
}

# setup_skyrim.ps1 was written to X:\MODDING\tools before the Skyrim root
# existed, and move_root.ps1 is running from there right now. Both belong with
# the rest of the Skyrim tools.
$boot = 'X:\MODDING\tools\setup_skyrim.ps1'
if (Test-Path -LiteralPath $boot) {
    Move-Item -LiteralPath $boot -Destination (Join-Path $toolsDir 'setup_skyrim.ps1') -Force
    Write-Host "  setup_skyrim.ps1 moved out of the Oblivion tools folder"
}
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $toolsDir 'move_root.ps1') -Force -ErrorAction SilentlyContinue
Write-Host "  move_root.ps1 copied across (a running script cannot delete itself)"

Write-Host ""
Write-Host "=== done ===" -ForegroundColor Green
Write-Host ""
Write-Host ("  root      {0}" -f $To)
Write-Host ("  game      {0}\STOCK GAME" -f $To)
Write-Host ("  MO2       {0}\MO2\Mod.Organizer-2.5.3\ModOrganizer.exe" -f $To)
Write-Host ""
Write-Host "The tool scripts in there still default to X:\SKYRIM - they are being"
Write-Host "replaced, so do not run them until the new copies land."
Write-Host ""
Write-Host "Then remove the stale copy this ran from:"
Write-Host "    Remove-Item X:\MODDING\tools\move_root.ps1"
Write-Host ""
