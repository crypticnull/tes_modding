#Requires -Version 5.1
<#
  make_preset.ps1 - build a BodySlide preset that is your body shape PLUS the
  CT77 panty zap, instead of having to choose between them.

    X:\MODDING\SKYRIM\tools\make_preset.ps1            report what it finds
    X:\MODDING\SKYRIM\tools\make_preset.ps1 -Apply     write the new preset

  THE PROBLEM

  "CT77 Zeroed Sliders - Zap Panties" does two unrelated things at once. The zap
  is what you want - it deletes the underwear geometry from the Remodeled Armor
  outfits. The zeroed sliders are just how that preset happens to ship, and they
  flatten every shape slider to 0, which is why the last batch build came out
  with a stock CBBE body under everything.

  A zap is not a shape slider. It is a boolean that removes geometry, stored in
  the preset file next to the shape values, so a preset can carry one without
  the other. Nothing stops you having Fetish v2's numbers and the zap together -
  there just is not a shipped preset that does.

  HOW THE ZAP IS FOUND

  Not by guessing at slider names. CT77 ships two presets that differ ONLY in
  the underwear: "CT77 SE" and "CT77 SE Without Panties". Diff them and whatever
  comes out IS the zap, by definition, whatever the author called it. Those
  entries then go on top of your preset and nothing else changes.

  GROUPS

  A preset only appears for an outfit whose groups it claims. The new one claims
  the union of both sources' groups, so it shows up for the body and for the
  CT77 outfits rather than only one of them.

  It writes into overwrite\, so no mod folder is touched and MO2 sees it at the
  highest priority. Delete the file to undo.
#>

[CmdletBinding()]
param(
    [string]$Root       = 'X:\MODDING\SKYRIM',
    [string]$BaseName   = 'CBBE Fetish v2',
    [string]$WithName   = 'CT77 SE',
    [string]$WithoutName= 'CT77 SE Without Panties',
    [string]$NewName    = 'CBBE Fetish v2 - Zap Panties',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$ModsDir = Join-Path $Root 'SKYRIM_SE\mods'
$OutDir  = Join-Path $Root 'SKYRIM_SE\overwrite\CalienteTools\BodySlide\SliderPresets'
$OutFile = Join-Path $OutDir 'ZapPanties-merged.xml'
$mode    = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' }

Write-Host ""
Write-Host "=== preset merge ($mode) ===" -ForegroundColor Cyan
Write-Host ""

foreach ($p in @('BodySlide','OutfitStudio')) {
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) {
        throw "$p is running. Close it - it will not see a new preset added underneath it anyway."
    }
}

# ---- collect every preset in every mod -------------------------------------
$files = @(Get-ChildItem -LiteralPath $ModsDir -Directory -ErrorAction SilentlyContinue |
           ForEach-Object {
               $d = Join-Path $_.FullName 'CalienteTools\BodySlide\SliderPresets'
               if (Test-Path -LiteralPath $d) { Get-ChildItem -LiteralPath $d -File -Filter '*.xml' -ErrorAction SilentlyContinue }
           })
Write-Host ("  {0} preset file(s) across all mods" -f $files.Count)

$found = @{}
foreach ($f in $files) {
    try { [xml]$x = Get-Content -LiteralPath $f.FullName -Raw } catch { continue }
    foreach ($pr in @($x.SliderPresets.Preset)) {
        if (-not $pr) { continue }
        $n = "" + $pr.name
        if (-not $n) { continue }
        if (-not $found.ContainsKey($n)) { $found[$n] = [pscustomobject]@{ Node = $pr; File = $f.FullName } }
    }
}
Write-Host ("  {0} distinct preset name(s)" -f $found.Count)
Write-Host ""

function Get-Sliders {
    param($Node)
    $h = @{}
    foreach ($s in @($Node.SetSlider)) {
        if (-not $s) { continue }
        # a slider is keyed by name AND size - "big" and "small" are separate
        # entries for the same slider and a preset can set one without the other
        $h[("" + $s.name) + '|' + ("" + $s.size)] = "" + $s.value
    }
    return $h
}
function Get-Groups {
    param($Node)
    $l = @()
    foreach ($g in @($Node.Group)) { if ($g -and $g.name) { $l += ("" + $g.name) } }
    return $l
}

foreach ($want in @($BaseName, $WithName, $WithoutName)) {
    if ($found.ContainsKey($want)) {
        $n = $found[$want].Node
        Write-Host ("  FOUND  {0,-32} {1,3} slider(s), groups: {2}" -f `
            $want, (Get-Sliders $n).Count, ((Get-Groups $n) -join ', ')) -ForegroundColor Green
        Write-Host ("         {0}" -f $found[$want].File) -ForegroundColor DarkGray
    } else {
        Write-Host ("  MISSING {0}" -f $want) -ForegroundColor Red
    }
}

$missing = @(@($BaseName, $WithName, $WithoutName) | Where-Object { -not $found.ContainsKey($_) })
if ($missing.Count) {
    Write-Host ""
    Write-Host "Cannot continue. Preset names on this install that look relevant:" -ForegroundColor Yellow
    foreach ($k in ($found.Keys | Sort-Object)) {
        if ($k -match '(?i)ct77|panty|panties|zap|fetish') { Write-Host ("    {0}" -f $k) }
    }
    Write-Host ""
    Write-Host "Re-run naming the right ones, e.g. -BaseName `"...`" -WithoutName `"...`"" -ForegroundColor Yellow
    Write-Host ""
    return
}

# ---- the diff IS the zap ---------------------------------------------------
$sWith    = Get-Sliders $found[$WithName].Node
$sWithout = Get-Sliders $found[$WithoutName].Node
$sBase    = Get-Sliders $found[$BaseName].Node

$zap = @{}
foreach ($k in $sWithout.Keys) {
    if (-not $sWith.ContainsKey($k) -or $sWith[$k] -ne $sWithout[$k]) { $zap[$k] = $sWithout[$k] }
}
foreach ($k in $sWith.Keys) {
    # set in the panties version and absent from the without version: turn it off
    if (-not $sWithout.ContainsKey($k)) { $zap[$k] = '0' }
}

Write-Host ""
Write-Host ("--- the difference between '{0}' and '{1}' ---" -f $WithName, $WithoutName) -ForegroundColor Cyan
if (-not $zap.Count) {
    Write-Host "  nothing differs. Those two presets are identical, so the zap is not" -ForegroundColor Red
    Write-Host "  carried in the preset at all - it is a per-outfit checkbox instead." -ForegroundColor Red
    Write-Host "  Say so and I will take the other route."
    Write-Host ""
    return
}
foreach ($k in ($zap.Keys | Sort-Object)) {
    $nm, $sz = $k -split '\|'
    $was = if ($sWith.ContainsKey($k)) { $sWith[$k] } else { '(unset)' }
    Write-Host ("  {0,-34} {1,-6}  {2}  ->  {3}" -f $nm, $sz, $was, $zap[$k])
}

# ---- merge -----------------------------------------------------------------
$merged = @{}
foreach ($k in $sBase.Keys) { $merged[$k] = $sBase[$k] }
$over = 0
foreach ($k in $zap.Keys) {
    if ($merged.ContainsKey($k) -and $merged[$k] -ne $zap[$k]) { $over++ }
    $merged[$k] = $zap[$k]
}
$groups = @(@((Get-Groups $found[$BaseName].Node) + (Get-Groups $found[$WithoutName].Node)) |
            Select-Object -Unique | Sort-Object)

Write-Host ""
Write-Host ("  result: {0} slider(s) - {1} from {2}, {3} zap entr(ies) ({4} overriding)" -f `
    $merged.Count, $sBase.Count, $BaseName, $zap.Count, $over)
Write-Host ("  groups: {0}" -f ($groups -join ', '))
Write-Host ("  name:   {0}" -f $NewName)

if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing written. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ---- write -----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (Test-Path -LiteralPath $OutFile) { Copy-Item -LiteralPath $OutFile -Destination "$OutFile.bak-$Stamp" -Force }

# Built as text, not through XmlDocument. Passing a freshly created XmlElement
# to AppendChild trips PowerShell's XML adapter, which stringifies it and then
# complains it was handed a String. The file is four kinds of line long; there
# is nothing here worth an object model.
function Esc { param([string]$v) return ($v -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;') }

$setAttr = "" + $found[$BaseName].Node.set
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('<?xml version="1.0" encoding="UTF-8"?>')
$lines.Add('<SliderPresets>')
$lines.Add(('    <Preset name="{0}"{1}>' -f (Esc $NewName),
            $(if ($setAttr) { ' set="' + (Esc $setAttr) + '"' } else { '' })))
foreach ($g in $groups) { $lines.Add(('        <Group name="{0}"/>' -f (Esc $g))) }
foreach ($k in ($merged.Keys | Sort-Object)) {
    $nm, $sz = $k -split '\|'
    $lines.Add(('        <SetSlider name="{0}" size="{1}" value="{2}"/>' -f (Esc $nm), (Esc $sz), (Esc $merged[$k])))
}
$lines.Add('    </Preset>')
$lines.Add('</SliderPresets>')
[IO.File]::WriteAllLines($OutFile, $lines.ToArray(), (New-Object Text.UTF8Encoding $false))

# read it back and check it is what we meant to write
[xml]$chk = Get-Content -LiteralPath $OutFile -Raw
$back = Get-Sliders $chk.SliderPresets.Preset
if ($back.Count -ne $merged.Count) { throw "wrote $($merged.Count) sliders but read back $($back.Count)" }
foreach ($k in $zap.Keys) {
    if ($back[$k] -ne $zap[$k]) { throw "zap entry '$k' did not survive the write" }
}

Write-Host ""
Write-Host ("written and verified: {0}" -f $OutFile) -ForegroundColor Green
Write-Host ""
Write-Host "In BodySlide:" -ForegroundColor Cyan
Write-Host ("  1. Outfit/Body: CBBE 3BBB Body Amazing    Preset: {0}" -f $NewName)
Write-Host "  2. Build Morphs ticked, hit Build. That is the nude body."
Write-Host "  3. Batch Build with the same preset still selected, so the outfits"
Write-Host "     get the same shape and the same zap."
Write-Host ""
