#Requires -Version 5.1
<#
  freckle_strength.ps1 - dial BnP's complexion freckles up or down.

    X:\MODDING\SKYRIM\tools\freckle_strength.ps1 -Level 25
    X:\MODDING\SKYRIM\tools\freckle_strength.ps1 -Level 25 -Apply
    X:\MODDING\SKYRIM\tools\freckle_strength.ps1 -Level 100 -Apply    remove the override

  WHAT THIS ACTUALLY FIXES

  The freckles are not in the skin diffuse and they are not a RaceMenu overlay -
  the co-save has no overlay textures assigned at all. They come from the
  COMPLEXION detail map, femaleheaddetail_frekles.dds, which the character's
  complexion head part points at. That choice lives in the save, and RaceMenu on
  this install exposes no complexion control, so the texture is the only lever.

  Every variant is the same map blended toward neutral grey 63,63,63 - the value
  BnP's own blankdetailmap.dds uses - so 0 is a flat no-op map and 100 is BnP
  untouched. They are 32-bit uncompressed rather than DXT5 on purpose: the map's
  whole range is 29-70, and block compression on a 41-level range bands visibly.
  16 MB of VRAM on a 5090 is not worth arguing about.

  It is a normal mod at the top of modlist.txt, so MO2 can turn it off and
  -Level 100 removes it outright.
#>

[CmdletBinding()]
param(
    [string]$Root  = 'X:\MODDING\SKYRIM',
    [ValidateSet(0,25,50,100)][int]$Level = 25,
    [string]$Name  = 'BnP Freckle Strength',
    [string]$Src   = 'X:\MODDING\SKYRIM\_incoming\freckles',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$Instance  = Join-Path $Root 'SKYRIM_SE'
$ModsDir   = Join-Path $Instance 'mods'
$MlPath    = Join-Path $Instance 'profiles\Default\modlist.txt'
$Dest      = Join-Path $ModsDir $Name
$TexDir    = Join-Path $Dest 'textures\actors\character\female'
$TexFile   = Join-Path $TexDir 'femaleheaddetail_frekles.dds'
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$mode      = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to do it' }

Write-Host ""
Write-Host "=== freckle strength: $Level% ($mode) ===" -ForegroundColor Cyan
Write-Host ""

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. It rewrites modlist.txt from memory on exit. Close it and re-run."
}
if (-not (Test-Path -LiteralPath $MlPath)) { throw "not found: $MlPath" }

$lines   = @(Get-Content -LiteralPath $MlPath)
$present = @($lines | Where-Object { $_ -match '^[+\-](.+)$' -and $Matches[1].TrimEnd() -eq $Name }).Count

if ($Level -eq 100) {
    Write-Host "  100% = BnP's own map, so the override comes out entirely."
    Write-Host ("  mod       {0}" -f $(if (Test-Path -LiteralPath $Dest) { "$Dest  (will be deleted)" } else { 'not installed' }))
    Write-Host ("  modlist   {0}" -f $(if ($present) { "lists '$Name' - line will be removed" } else { "does not list '$Name'" }))
    if (-not $Apply) { Write-Host ""; Write-Host "Nothing changed. Re-run with -Apply." -ForegroundColor Yellow; Write-Host ""; return }

    if ($present) {
        Copy-Item -LiteralPath $MlPath -Destination "$MlPath.bak-$Stamp" -Force
        $out = @($lines | Where-Object { -not ($_ -match '^[+\-](.+)$' -and $Matches[1].TrimEnd() -eq $Name) })
        [IO.File]::WriteAllLines($MlPath, $out, $Utf8NoBom)
    }
    if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
    Write-Host ""
    Write-Host "  removed. BnP's own freckle map is back in charge." -ForegroundColor Green
    Write-Host ""
    return
}

$srcFile = Join-Path $Src ("femaleheaddetail_frekles_{0:d3}.dds" -f $Level)
if (-not (Test-Path -LiteralPath $srcFile)) {
    throw ("not found: {0}`n  Levels available in {1}: {2}" -f $srcFile, $Src,
           ((Get-ChildItem -LiteralPath $Src -Filter '*.dds' -ErrorAction SilentlyContinue |
             ForEach-Object { $_.Name }) -join ', '))
}

$mb = [math]::Round((Get-Item -LiteralPath $srcFile).Length / 1MB, 1)
Write-Host ("  source    {0}   ({1} MB)" -f (Split-Path $srcFile -Leaf), $mb)
Write-Host ("  into      {0}" -f $TexFile)
Write-Host ("  modlist   {0}" -f $(if ($present) { "already lists '$Name'" } else { "will gain '+$Name' at the top" }))

if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing written. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

New-Item -ItemType Directory -Force -Path $TexDir | Out-Null
Copy-Item -LiteralPath $srcFile -Destination $TexFile -Force

$meta = Join-Path $Dest 'meta.ini'
if (-not (Test-Path -LiteralPath $meta)) {
    [IO.File]::WriteAllLines($meta, @('[General]','gameName=skyrimspecialedition','modid=0','repository='), $Utf8NoBom)
}

if (-not $present) {
    Copy-Item -LiteralPath $MlPath -Destination "$MlPath.bak-$Stamp" -Force
    $out = if ($lines.Count -and $lines[0] -match '^\s*#') {
               @($lines[0]) + @("+$Name") + @($lines[1..($lines.Count-1)])
           } else { @("+$Name") + $lines }
    [IO.File]::WriteAllLines($MlPath, $out, $Utf8NoBom)
}

# ---- verify ----------------------------------------------------------------
$landed = (Get-Item -LiteralPath $TexFile).Length
$want   = (Get-Item -LiteralPath $srcFile).Length
if ($landed -ne $want) { throw "copied file is $landed bytes, expected $want" }
$ml = @(Get-Content -LiteralPath $MlPath)
if (-not @($ml | Where-Object { $_ -match '^\+(.+)$' -and $Matches[1].TrimEnd() -eq $Name }).Count) {
    throw "modlist.txt does not list '$Name'"
}

Write-Host ""
Write-Host ("  verified - {0} bytes in place, modlist line 1: {1}" -f $landed, $ml[0]) -ForegroundColor Green
Write-Host ""
Write-Host "Head textures are cached per actor, so this needs a save reload to show up." -ForegroundColor Cyan
Write-Host ""
