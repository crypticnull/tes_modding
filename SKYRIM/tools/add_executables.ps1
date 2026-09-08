#Requires -Version 5.1
<#
  add_executables.ps1 - register the mod-supplied tools in MO2's run dropdown.

    X:\MODDING\SKYRIM\tools\add_executables.ps1            report
    X:\MODDING\SKYRIM\tools\add_executables.ps1 -Apply     write them

  MO2 does not add tools that arrive inside a mod. BodySlide is installed as a
  mod like any other, so its exe sits in mods\ and nothing in the interface
  points at it until you say so.

  It matters that these run THROUGH MO2 rather than by double-clicking the exe.
  Only inside the virtual filesystem does BodySlide see every mod's SliderSets
  and ShapeData at once - CBBE's, 3BA's, TAWoBA's, Remodeled Armor's. Run
  standalone it sees its own folder and offers almost nothing to build.

  WHY THIS REFUSES TO WRITE A BLANK PATH

  The first version of this wrote the titles correctly and the binary paths as
  empty strings, which MO2 accepts into its config and then fails on at launch
  with "Cannot start" and a dialog blaming your antivirus. The path never
  reached the file and nothing said so.

  So now every path is resolved and checked before a single line is written, it
  refuses outright rather than writing a half-entry, and it clears out any
  existing entry whose binary is blank - including the ones the earlier version
  left behind.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [string[]]$Extra = @(),   # 'Title|C:\absolute\path\to.exe' - for tools outside mods\
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$MO2     = Join-Path $Root 'MO2\Mod.Organizer-2.5.3'
$Ini     = Join-Path $MO2 'ModOrganizer.ini'
$ModsDir = Join-Path $Root 'SKYRIM_SE\mods'
$mode    = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' }

Write-Host ""
Write-Host "=== MO2 executables ($mode) ===" -ForegroundColor Cyan
Write-Host ""

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. It rewrites ModOrganizer.ini from memory on exit. Close it and re-run."
}
if (-not (Test-Path -LiteralPath $Ini)) { throw "not found: $Ini" }
if (-not (Test-Path -LiteralPath $ModsDir)) { throw "not found: $ModsDir" }

# ---- resolve each exe to a real, verified, absolute path -------------------
# One mod folder at a time rather than a recursive sweep of every mod: mods\
# holds hundreds of thousands of texture files and a -Recurse -Filter across
# all of it is both slow and easy to get wrong.
$Targets = New-Object System.Collections.Generic.List[object]
$Targets.Add([pscustomobject]@{ Title = 'BodySlide';     Rel = 'CalienteTools\BodySlide\BodySlide.exe';    Path = $null })
$Targets.Add([pscustomobject]@{ Title = 'Outfit Studio'; Rel = 'CalienteTools\BodySlide\OutfitStudio.exe'; Path = $null })

# -Extra takes tools that do NOT live under mods\ - generators like DynDOLOD sit
# in tools\ because their output is the mod, not themselves. Path is already
# absolute so the mods\ search below skips them.
foreach ($e in $Extra) {
    $parts = $e -split '\|', 2
    if ($parts.Count -ne 2) { throw "bad -Extra entry '$e' - expected 'Title|C:\path\to.exe'" }
    $title = $parts[0].Trim()
    $path  = $parts[1].Trim()
    if (-not (Test-Path -LiteralPath $path)) { throw "-Extra '$title': not found: $path" }
    $Targets.Add([pscustomobject]@{ Title = $title; Rel = $null; Path = (Get-Item -LiteralPath $path).FullName })
}

$modDirs = @(Get-ChildItem -LiteralPath $ModsDir -Directory -ErrorAction SilentlyContinue)
foreach ($t in $Targets) {
    if (-not $t.Path) {
        foreach ($m in $modDirs) {
            $cand = Join-Path $m.FullName $t.Rel
            if (Test-Path -LiteralPath $cand) { $t.Path = (Get-Item -LiteralPath $cand).FullName; break }
        }
    }
    if ($t.Path) { Write-Host ("  {0,-15} {1}" -f $t.Title, $t.Path) -ForegroundColor Green }
    else         { Write-Host ("  {0,-15} NOT FOUND under any mod" -f $t.Title) -ForegroundColor Red }
}

$ok = @($Targets | Where-Object { $_.Path -and (Test-Path -LiteralPath $_.Path) })
if (-not $ok.Count) {
    Write-Host ""
    Write-Host "Nothing resolved, so nothing will be written." -ForegroundColor Red
    Write-Host "Is the tool actually installed? Check mods\ for a CalienteTools folder."
    Write-Host ""
    return
}

# ---- read the section ------------------------------------------------------
$lines = @(Get-Content -LiteralPath $Ini)
$secStart = -1; $secEnd = $lines.Count
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '(?i)^\s*\[customExecutables\]\s*$') { $secStart = $i; continue }
    if ($secStart -ge 0 -and $lines[$i] -match '^\s*\[') { $secEnd = $i; break }
}
if ($secStart -lt 0) { throw "no [customExecutables] section in $Ini" }

# gather every slot as title + binary so broken ones can be spotted
$slots = @{}
for ($i = $secStart + 1; $i -lt $secEnd; $i++) {
    if ($lines[$i] -match '^\s*(\d+)\\(\w+)\s*=\s*(.*)$') {
        $n = [int]$Matches[1]
        if (-not $slots.ContainsKey($n)) { $slots[$n] = @{} }
        $slots[$n][$Matches[2]] = $Matches[3].Trim()
    }
}

$broken = @($slots.Keys | Where-Object { -not $slots[$_]['binary'] } | Sort-Object)
$byTitle = @{}
foreach ($n in $slots.Keys) { $t = $slots[$n]['title']; if ($t) { $byTitle[$t] = $n } }

Write-Host ""
Write-Host ("  section holds {0} slot(s)" -f $slots.Count)
if ($broken.Count) {
    Write-Host ("  {0} slot(s) have an EMPTY binary and will be removed:" -f $broken.Count) -ForegroundColor Yellow
    foreach ($n in $broken) { Write-Host ("      slot {0}  '{1}'" -f $n, $slots[$n]['title']) -ForegroundColor Yellow }
}

# ---- rebuild the section from scratch, renumbered --------------------------
$keep = @($slots.Keys | Where-Object { $slots[$_]['binary'] } | Sort-Object)
$final = New-Object System.Collections.Generic.List[object]
foreach ($n in $keep) {
    $final.Add([pscustomobject]@{ Title = $slots[$n]['title']; Props = $slots[$n] })
}
foreach ($t in $ok) {
    if ($byTitle.ContainsKey($t.Title) -and $slots[$byTitle[$t.Title]]['binary']) {
        Write-Host ("  {0,-15} already registered with a real path - left alone" -f $t.Title)
        continue
    }
    $final.Add([pscustomobject]@{
        Title = $t.Title
        Props = @{
            arguments = ''; binary = ($t.Path -replace '\\','/'); hide = 'false'
            minimizeToSystemTray = 'false'; ownicon = 'true'; steamAppID = ''
            title = $t.Title; toolbar = 'false'
            workingDirectory = ((Split-Path $t.Path -Parent) -replace '\\','/')
        }
    })
    Write-Host ("  {0,-15} will be added" -f $t.Title) -ForegroundColor Green
}

# the guard the first version lacked
$empty = @($final | Where-Object { -not $_.Props['binary'] })
if ($empty.Count) { throw "refusing to write: $($empty.Count) entr(ies) still have an empty binary" }

Write-Host ""
Write-Host ("  result: {0} executable(s)" -f $final.Count)
foreach ($f in $final) { Write-Host ("      {0,-28} {1}" -f $f.Title, $f.Props['binary']) }

if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing written. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

Copy-Item -LiteralPath $Ini -Destination "$Ini.bak-$Stamp" -Force
$new = New-Object System.Collections.Generic.List[string]
$new.Add('[customExecutables]')
$new.Add("size=$($final.Count)")
for ($i = 0; $i -lt $final.Count; $i++) {
    $n = $i + 1
    $p = $final[$i].Props
    foreach ($k in @('arguments','binary','hide','minimizeToSystemTray','ownicon','steamAppID','title','toolbar','workingDirectory')) {
        $v = if ($p.ContainsKey($k)) { $p[$k] } else { '' }
        $new.Add("$n\$k=$v")
    }
}

$out = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($i -eq $secStart) { foreach ($l in $new) { $out.Add($l) } }
    if ($i -ge $secStart -and $i -lt $secEnd) { continue }
    $out.Add($lines[$i])
}
[IO.File]::WriteAllLines($Ini, $out, (New-Object Text.UTF8Encoding $false))

Write-Host ""
Write-Host ("written, {0} executable(s)  (backup: {1})" -f $final.Count, (Split-Path "$Ini.bak-$Stamp" -Leaf)) -ForegroundColor Green
Write-Host ""
Write-Host "Open MO2 and pick BodySlide from the dropdown." -ForegroundColor Cyan
Write-Host "Choose a preset, hit Preview to see the body, then tick 'Build Morphs'"
Write-Host "and Batch Build. Build Morphs is what makes the RaceMenu sliders work."
Write-Host ""
