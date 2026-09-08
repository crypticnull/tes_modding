#Requires -Version 5.1
<#
  fix_bodyslide.ps1 - point BodySlide at the right game, and clean up after the
  build that went to the wrong one.

    X:\MODDING\SKYRIM\tools\fix_bodyslide.ps1            report
    X:\MODDING\SKYRIM\tools\fix_bodyslide.ps1 -Apply     fix it

  WHAT WENT WRONG

  BodySlide's Config.xml had:

      <GameDataPath>C:\Program Files (x86)\Steam\steamapps\common\
                    Skyrim Special Edition\Data\</GameDataPath>

  That is the untouched 1.7.104 Steam copy, not the game you actually play.
  BodySlide finds it by registry on first run and never asks.

  The consequence is worse than it looks. Running BodySlide THROUGH MO2 puts it
  inside the virtual filesystem, which is why it can see every mod's slider sets
  at once. But the VFS only covers X:\MODDING\SKYRIM\STOCK GAME. A write to a
  path outside that mapping is not redirected into overwrite\ - it goes to the
  real disk. So the two body meshes it built are sitting in the Steam install,
  where nothing will ever read them, and STOCK GAME got nothing.

  Its own log says so:

      Working directory: X:\MODDING\SKYRIM\STOCK GAME\data\CalienteTools\BodySlide
      Game data path in config: C:\Program Files (x86)\Steam\...\Data\

  Right filesystem, wrong destination.

  It also explains the missing-texture warnings in the log - it was looking for
  Reverie's skin under the Steam Data folder, which of course has no mods in it.
  Fix the path and the preview gets its textures too.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$ModsDir  = Join-Path $Root 'SKYRIM_SE\mods'
$Dloads   = Join-Path $Root 'SKYRIM_SE\downloads'
$WantPath = Join-Path $Root 'STOCK GAME\Data\'
$Steam    = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data'
$Quarant  = Join-Path $Root 'data\steam-orphans'
$mode     = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to fix' }

Write-Host ""
Write-Host "=== BodySlide game path ($mode) ===" -ForegroundColor Cyan
Write-Host ""

# BodySlide rewrites Config.xml from memory when it closes, exactly like MO2
# does with its ini. Editing the file under a running instance is a guaranteed
# way to have the fix vanish and not know why.
foreach ($p in @('BodySlide','OutfitStudio')) {
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) {
        throw "$p is running. It saves Config.xml on exit and would overwrite this. Close it and re-run."
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $Root 'STOCK GAME\Data'))) {
    throw "not found: $(Join-Path $Root 'STOCK GAME\Data')"
}

# ---- 1. the config -------------------------------------------------------
$cfgPath = $null
foreach ($m in @(Get-ChildItem -LiteralPath $ModsDir -Directory -ErrorAction SilentlyContinue)) {
    $c = Join-Path $m.FullName 'CalienteTools\BodySlide\Config.xml'
    if (Test-Path -LiteralPath $c) { $cfgPath = (Get-Item -LiteralPath $c).FullName; break }
}
if (-not $cfgPath) { throw "no BodySlide Config.xml found under $ModsDir" }

# Deliberately NOT via [xml] and property assignment. That threw
#   "only strings can be used as values to set XmlNode properties"
# and even where it works it reformats the whole file on save, because loading
# drops insignificant whitespace. BodySlide's own parser reads this file; there
# is no reason to hand it back rewritten when two values need changing.
#
# So: exact text surgery on the raw string.
function Get-Elem {
    param([string]$Text, [string]$Tag, [int]$StartAt = 0)
    $o = "<$Tag>"; $c = "</$Tag>"
    $i = $Text.IndexOf($o, $StartAt)
    if ($i -lt 0) { return $null }
    $j = $Text.IndexOf($c, $i)
    if ($j -lt 0) { return $null }
    $st = $i + $o.Length
    return [pscustomobject]@{ Start = $st; End = $j; Value = $Text.Substring($st, $j - $st) }
}
function Set-Elem {
    param([string]$Text, [string]$Tag, [string]$Value, [int]$StartAt = 0)
    $e = Get-Elem $Text $Tag $StartAt
    if (-not $e) { throw "no <$Tag> in config" }
    return $Text.Substring(0, $e.Start) + $Value + $Text.Substring($e.End)
}

$raw = Get-Content -LiteralPath $cfgPath -Raw

# <GameDataPath> and <GameDataPaths> both start the same way, but IndexOf is
# looking for the literal including its '>', so "<GameDataPath>" cannot match
# inside "<GameDataPaths>".
$eMain = Get-Elem $raw 'GameDataPath'
if (-not $eMain) { throw "no <GameDataPath> in $cfgPath" }
$cur = $eMain.Value

# <SkyrimSpecialEdition> appears TWICE - once under GameDataFiles holding the
# bsa blacklist, once under GameDataPaths. Anchor to the second block or the
# blacklist gets overwritten with a folder path.
$iPaths = $raw.IndexOf('<GameDataPaths>')
if ($iPaths -lt 0) { throw "no <GameDataPaths> block in $cfgPath" }
$eSSE = Get-Elem $raw 'SkyrimSpecialEdition' $iPaths
$curS = if ($eSSE) { $eSSE.Value } else { '' }

Write-Host ("  config      {0}" -f $cfgPath)
Write-Host ("  currently   {0}" -f $(if ($cur) { $cur } else { '(empty)' })) -ForegroundColor Yellow
Write-Host ("  should be   {0}" -f $WantPath) -ForegroundColor Green
Write-Host ""

$needFix = ($cur -ne $WantPath) -or ($curS -ne $WantPath)

# ---- 2. what it built into the Steam copy --------------------------------
# Not deleted - moved. These are ordinary meshes and nothing here is urgent,
# but leaving them means the Steam install quietly has a CBBE body with no
# textures to go with it, which is the sort of thing that confuses you in six
# months when you launch it to check something.
$orphans = @()
if (Test-Path -LiteralPath $Steam) {
    $orphans = @(Get-ChildItem -LiteralPath $Steam -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Extension -eq '.nif' })
}
if ($orphans.Count) {
    Write-Host ("  {0} mesh(es) built into the Steam copy, to be moved aside:" -f $orphans.Count) -ForegroundColor Yellow
    foreach ($o in $orphans) { Write-Host ("      {0}" -f $o.FullName.Substring($Steam.Length + 1)) }
} else {
    Write-Host "  Steam copy is clean - nothing to move."
}
Write-Host ""

# ---- 3. the two mods that never installed --------------------------------
# XPMSSE matters more than it sounds. 3BA's breast, butt and belly nodes are
# skeleton bones; without XPMSSE the vanilla skeleton has no such bones and
# every bit of physics you installed does precisely nothing.
$landed = @{}
foreach ($d in @(Get-ChildItem -LiteralPath $ModsDir -Directory -ErrorAction SilentlyContinue)) {
    $mi = Join-Path $d.FullName 'meta.ini'
    if (-not (Test-Path -LiteralPath $mi)) { continue }
    foreach ($l in (Get-Content -LiteralPath $mi)) {
        if ($l -match '^\s*modid\s*=\s*(\d+)') { $landed[[int]$Matches[1]] = $d.Name }
    }
}
# @() around the whole pipeline on purpose: a bare hashtable has its own .Count
# (its key count), so an unwrapped single result would report 2 and read as two
# missing mods.
$missing = @(@(
    @{ id = 1988;  n = 'XP32 Maximum Skeleton Special Extended' }
    @{ id = 22168; n = 'Remodeled Armor SE - CBBE 3BA' }
) | Where-Object { -not $landed.ContainsKey($_.id) })

if ($missing.Count) {
    Write-Host ("  {0} mod(s) downloaded but NOT installed:" -f $missing.Count) -ForegroundColor Red
    foreach ($m in $missing) { Write-Host ("      {0,6}  {1}" -f $m.id, $m.n) -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Both have to be in before a batch build. XPMSSE carries the bones"
    Write-Host "  3BA's physics hang off, and Remodeled Armor's outfits cannot appear"
    Write-Host "  in the batch list until BodySlide can see their slider sets."
    Write-Host ""
    # print the top of each archive so the installer can be taught to handle it
    $sz = @("$env:ProgramFiles\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe") |
          Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($sz) {
        foreach ($m in $missing) {
            $arc = @(Get-ChildItem -LiteralPath $Dloads -File |
                     Where-Object { $_.Name -match ("[-\s]" + $m.id + "[-\s]") } |
                     Select-Object -First 1)
            if (-not $arc) { continue }
            Write-Host ("  --- top of {0} ---" -f $arc[0].Name) -ForegroundColor Cyan
            $names = @(& $sz l -ba -slt -- $arc[0].FullName 2>$null |
                       Where-Object { $_ -match '^Path = ' } |
                       ForEach-Object { $_.Substring(7) })
            $tops = @($names | ForEach-Object { ($_ -split '[\\/]')[0] } | Select-Object -Unique | Select-Object -First 12)
            foreach ($t in $tops) { Write-Host ("      {0}" -f $t) }
            $fm = @($names | Where-Object { $_ -match '(?i)(^|[\\/])fomod[\\/]ModuleConfig\.xml$' })
            Write-Host ("      -> {0} entries, FOMOD: {1}" -f $names.Count, $(if ($fm.Count) { 'YES  ' + $fm[0] } else { 'no' }))
            Write-Host ""
        }
    }
}

if (-not $needFix -and -not $orphans.Count) {
    Write-Host "Nothing to fix." -ForegroundColor Green
    Write-Host ""
    return
}
if (-not $Apply) {
    Write-Host "Nothing written. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ---- apply ---------------------------------------------------------------
if ($needFix) {
    Copy-Item -LiteralPath $cfgPath -Destination "$cfgPath.bak-$Stamp" -Force

    $new = Set-Elem $raw 'GameDataPath' $WantPath
    $iP2  = $new.IndexOf('<GameDataPaths>')
    $new = Set-Elem $new 'SkyrimSpecialEdition' $WantPath $iP2
    [IO.File]::WriteAllText($cfgPath, $new, (New-Object Text.UTF8Encoding $true))

    # read it back and parse it as XML rather than assume. Two separate checks:
    # the values are right, AND the file is still well formed after the surgery.
    $back = Get-Content -LiteralPath $cfgPath -Raw
    [xml]$chk = $back
    $g1 = (Get-Elem $back 'GameDataPath').Value
    $g2 = (Get-Elem $back 'SkyrimSpecialEdition' ($back.IndexOf('<GameDataPaths>'))).Value
    if ($g1 -ne $WantPath) { throw "write did not take: GameDataPath is still '$g1'" }
    if ($g2 -ne $WantPath) { throw "write did not take: GameDataPaths/SkyrimSpecialEdition is still '$g2'" }
    # and the blacklist must be untouched
    $bl = (Get-Elem $back 'SkyrimSpecialEdition').Value
    if ($bl -notmatch '(?i)\.bsa') { throw "the bsa blacklist got clobbered - restore Config.xml.bak-$Stamp" }
    Write-Host ("  config written and verified  (backup: Config.xml.bak-{0})" -f $Stamp) -ForegroundColor Green
}

if ($orphans.Count) {
    New-Item -ItemType Directory -Force -Path $Quarant | Out-Null
    foreach ($o in $orphans) {
        $rel = $o.FullName.Substring($Steam.Length + 1)
        $dst = Join-Path $Quarant $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
        Move-Item -LiteralPath $o.FullName -Destination $dst -Force
    }
    Write-Host ("  {0} mesh(es) moved to {1}" -f $orphans.Count, $Quarant) -ForegroundColor Green
}

Write-Host ""
Write-Host "=== then, in BodySlide ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Tick 'Build Morphs' (bottom left, under the preset dropdown)."
Write-Host "     That writes the .tri files. Without them the 3BA sliders you"
Write-Host "     enabled in RaceMenu exist in the menu and move nothing."
Write-Host "  2. Use 'Batch Build...', NOT 'Build'."
Write-Host "     Build does the one entry in the dropdown, which is why you got"
Write-Host "     femalebody and nothing else. Batch Build does every slider set"
Write-Host "     in the list - hands, feet, and every outfit."
Write-Host "  3. In the Batch Build list, leave everything ticked, hit Build."
Write-Host "     If it asks you to choose between two versions of the same"
Write-Host "     outfit, take the 3BA / SMP one."
Write-Host "  4. Output goes to overwrite\ in MO2. Right-click it, Create Mod,"
Write-Host "     call it 'BodySlide Output', and put it at the top of the list."
Write-Host ""
