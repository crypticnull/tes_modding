#Requires -Version 5.1
<#
  face_variants.ps1 - collect every face diffuse BnP offers, somewhere readable.

    X:\MODDING\SKYRIM\tools\face_variants.ps1            report
    X:\MODDING\SKYRIM\tools\face_variants.ps1 -Apply     fetch and collect

  WHY IT COPIES INSTEAD OF POINTING

  The mods tree is eight folders below the connected root and the device bridge
  stops at seven, so nothing under mods\<mod>\textures\actors\character\female
  can be read from here at all. Everything worth looking at gets copied into one
  shallow folder with a flattened name that still says where it came from.

  WHAT IT GATHERS

    CURRENT_*      the face textures actually in use right now
    <variant>_*    every femalehead / head-detail texture inside the Extra
                   Options archive, named after the folder it sat in

  Head DETAIL maps are collected too, not just the diffuses. The detail map is
  the complexion layer, and on this install RaceMenu exposes no complexion
  control at all, so if the freckles live there they cannot be switched off in
  game and that is worth knowing before picking a face.
#>

[CmdletBinding()]
param(
    [string]$Root    = 'X:\MODDING\SKYRIM',
    [int]$Mod        = 65274,
    [int]$File       = 405689,          # Extra Options 2k CBBE
    [string]$Skin    = 'BnP female skin 2k (CBBE Player and Replacer)',
    [string]$Out     = 'X:\MODDING\SKYRIM\_incoming\facecheck',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Instance = Join-Path $Root 'SKYRIM_SE'
$Live     = Join-Path (Join-Path (Join-Path $Instance 'mods') $Skin) 'textures\actors\character\female'
$Incoming = Join-Path $Root '_incoming'
$Get      = Join-Path $Root 'tools\nexus_get.ps1'
$mode     = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to do it' }

# only the head, and only colour/detail - normals and speculars say nothing
# about how freckled a face looks
$Wanted = @('femalehead.dds','femaleheaddetail_frekles.dds','femaleheaddetail_rough.dds',
            'femaleheaddetail_age40.dds','femaleheaddetail_age50.dds','blankdetailmap.dds')

Write-Host ""
Write-Host "=== face variants ($mode) ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath $Get))  { throw "not found: $Get" }
if (-not (Test-Path -LiteralPath $Live)) { throw "not found: $Live  (is -Skin the right mod folder name?)" }

Write-Host ("  live skin   {0}" -f $Skin)
Write-Host ("  collecting  {0}" -f $Out)
Write-Host ("  fetching    mod {0} file {1}" -f $Mod, $File)
Write-Host ""

if (-not $Apply) {
    Write-Host "  Nothing fetched or copied. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null

# ---- what is in use right now ----------------------------------------------
$n = 0
foreach ($w in $Wanted) {
    $src = Join-Path $Live $w
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $Out ("CURRENT_" + $w)) -Force
        $n++
    }
}
Write-Host ("  {0} file(s) copied from the live skin" -f $n) -ForegroundColor Green

# ---- the alternatives ------------------------------------------------------
# Snapshot first so the extract folder is found by observation rather than by
# rebuilding the name nexus_get chose.
$before = @{}
foreach ($d in @(Get-ChildItem -LiteralPath $Incoming -Directory -ErrorAction SilentlyContinue)) {
    $before[$d.FullName] = $true
}

& $Get -Mod $Mod -File $File -Extract -Dest $Incoming

$fresh = @(Get-ChildItem -LiteralPath $Incoming -Directory -ErrorAction SilentlyContinue |
           Where-Object { -not $before.ContainsKey($_.FullName) })

if (-not $fresh.Count) {
    # already extracted on an earlier run - match on the mod id nexus_get prefixes
    $fresh = @(Get-ChildItem -LiteralPath $Incoming -Directory -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like ("{0}_*" -f $Mod) })
}
if (-not $fresh.Count) { throw "no extracted folder appeared under $Incoming" }
if ($fresh.Count -gt 1) {
    Write-Host ("  {0} candidate extract folders - using the newest:" -f $fresh.Count) -ForegroundColor Yellow
    foreach ($f in $fresh) { Write-Host ("      {0}" -f $f.Name) -ForegroundColor Yellow }
    $fresh = @($fresh | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}
$ex = $fresh[0].FullName
Write-Host ("  extract     {0}" -f $ex)

$hits = @(Get-ChildItem -LiteralPath $ex -Recurse -File -ErrorAction SilentlyContinue |
          Where-Object { $Wanted -contains $_.Name.ToLower() })

$copied = 0
$names  = @{}
foreach ($h in $hits) {
    # flatten the path into the filename so the variant is still identifiable
    $rel = $h.FullName.Substring($ex.Length).TrimStart('\')
    $rel = $rel -replace '\\textures\\actors\\character\\female\\','\'
    $flat = ($rel -replace '[\\/]','__')
    if ($names.ContainsKey($flat)) { continue }   # same path twice cannot happen, but be sure
    $names[$flat] = $true
    Copy-Item -LiteralPath $h.FullName -Destination (Join-Path $Out $flat) -Force
    $copied++
}

Write-Host ("  {0} variant file(s) copied" -f $copied) -ForegroundColor Green
Write-Host ""

$all = @(Get-ChildItem -LiteralPath $Out -File | Sort-Object Name)
$mb  = [math]::Round((($all | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host ("  {0} file(s) in {1}, {2} MB" -f $all.Count, $Out, $mb)
foreach ($f in $all) { Write-Host ("      {0}" -f $f.Name) }
Write-Host ""
