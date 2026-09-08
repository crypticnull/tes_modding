#Requires -Version 5.1
<#
  upgrade_mo2.ps1 - move the portable instance from Mod Organizer 2.5.2 to a
  2.5.3-beta build, because 2.5.2 does not have the two API hooks the Oblivion
  Remastered game plugin needs.

    X:\MODDING\OBLIVION\tools\upgrade_mo2.ps1 -Archive "X:\MODDING\OBLIVION\_incoming\Mod.Organizer-2.5.3.7z"
    X:\MODDING\OBLIVION\tools\upgrade_mo2.ps1 -Archive "..." -Apply

  Or, if you already extracted it yourself:

    X:\MODDING\OBLIVION\tools\upgrade_mo2.ps1 -Source "X:\MODDING\OBLIVION\_incoming\Mod.Organizer-2.5.3" -Apply

  WHY
    game_oblivion_remaster.py overrides modDataDirectory() and getModMappings().
    Those two landed in modorganizer-uibase on 2025-05-21 and first shipped in
    2.5.3-beta.2. On 2.5.2 they are dead code - MO2 never calls them - so every
    mod's Data\ Paks\ UE4SS\ OBSE\ folder maps nowhere and nothing deploys.

  WHAT THIS DOES NOT TOUCH
    X:\MODDING\OBLIVION\OBLIVION_REMASTERED  - the instance. Mods, downloads, profiles all
                                      stay exactly where they are. No reinstalling.
    The old 2.5.2 folder             - left intact. Reverting is launching its exe.

  THE GATE
    Before anything is written, the new build's mobase is checked for both symbols.
    If they are absent the build is too old and the script stops without changing
    a thing. That check is the whole point - do not remove it.
#>

[CmdletBinding()]
param(
    [string]$Archive,
    [string]$Source,
    [string]$Dest = 'X:\MODDING\OBLIVION\MO2\Mod.Organizer-2.5.3',
    [string]$OldDir = 'X:\MODDING\OBLIVION\MO2\Mod.Organizer-2.5.2',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$mode  = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' }

# The two symbols that decide whether this build can run the game plugin at all.
$RequiredSymbols = @('modDataDirectory', 'getModMappings')

Write-Host "=== MO2 upgrade ($mode) ==="
Write-Host ""

# ---- guards ---------------------------------------------------------------
if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. Close it and re-run."
}
if (-not $Archive -and -not $Source) {
    throw "Give me either -Archive <the .7z from the MO2 Discord> or -Source <an extracted folder>."
}
if ($Archive -and $Source) {
    throw "Pass -Archive or -Source, not both."
}
if (-not (Test-Path -LiteralPath $OldDir)) { throw "old install not found: $OldDir" }
# Refuse to write anywhere that isn't under X:\MODDING\OBLIVION\MO2 - this script deletes
# and replaces a directory tree, and a typo'd -Dest must not be able to reach the
# instance folder or the game.
$destFull = [IO.Path]::GetFullPath($Dest)
if ($destFull -notmatch '(?i)^X:\\MODDING\\OBLIVION\\MO2\\[^\\]+\\?$') {
    throw "-Dest must be a folder directly under X:\MODDING\OBLIVION\MO2\ - got: $destFull"
}
if ($destFull.TrimEnd('\') -ieq $OldDir.TrimEnd('\')) {
    throw "-Dest is the existing 2.5.2 install. Pick a new folder so you can roll back."
}

function Get-SevenZip {
    foreach ($c in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $c = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

# Reads a binary and looks for an exact ASCII symbol name. pybind11 stores the
# method names it binds as plain strings, so absence here is conclusive.
function Test-Symbols {
    param([string]$Pyd, [string[]]$Names)
    $bytes = [IO.File]::ReadAllBytes($Pyd)
    $text  = [Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes)
    $out = @{}
    foreach ($n in $Names) { $out[$n] = ($text.IndexOf($n, [StringComparison]::Ordinal) -ge 0) }
    return $out
}

# ---- 1. get the new build into a staging folder ---------------------------
Write-Host "--- 1. new build ---"
$Work = Join-Path $env:TEMP ("mo2up_$Stamp")
$stage = $null

if ($Source) {
    if (-not (Test-Path -LiteralPath (Join-Path $Source 'ModOrganizer.exe'))) {
        throw "no ModOrganizer.exe in -Source: $Source"
    }
    $stage = (Resolve-Path -LiteralPath $Source).Path
    Write-Host ("  using extracted folder: {0}" -f $stage)
} else {
    if (-not (Test-Path -LiteralPath $Archive)) { throw "archive not found: $Archive" }
    $sz = Get-SevenZip
    if (-not $sz) { throw "7-Zip not found. Install it, or extract the archive yourself and use -Source." }
    Write-Host ("  archive: {0} ({1:N1} MB)" -f (Split-Path $Archive -Leaf), ((Get-Item -LiteralPath $Archive).Length / 1MB))
    $ex = Join-Path $Work 'extract'
    New-Item -ItemType Directory -Force -Path $ex | Out-Null
    Write-Host "  extracting..."
    & $sz x "-o$ex" -y -bso0 -bsp0 -- "$Archive" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7-Zip failed with exit code $LASTEXITCODE" }
    # Some builds ship the exe at the root, some inside a single wrapper folder.
    $exe = @(Get-ChildItem -LiteralPath $ex -Recurse -File -Filter 'ModOrganizer.exe' |
             Sort-Object { $_.FullName.Length }) | Select-Object -First 1
    if (-not $exe) { throw "no ModOrganizer.exe anywhere in that archive - wrong file?" }
    $stage = $exe.Directory.FullName
    Write-Host ("  extracted to: {0}" -f $stage)
}

$newVer = (Get-Item -LiteralPath (Join-Path $stage 'ModOrganizer.exe')).VersionInfo.FileVersion
Write-Host ("  ModOrganizer.exe reports version: {0}" -f $newVer)
Write-Host ""

# ---- 2. THE GATE ----------------------------------------------------------
Write-Host "--- 2. API check (this is the whole reason for the upgrade) ---"
$pyd = @(Get-ChildItem -LiteralPath (Join-Path $stage 'plugins\plugin_python\libs') `
         -Filter 'mobase.cp3*-win_amd64.pyd' -File -ErrorAction SilentlyContinue) | Select-Object -First 1
if (-not $pyd) { throw "no mobase .pyd in the new build - the Python proxy is missing from that archive." }

$pyTag = if ($pyd.Name -match 'cp(\d+)') { $Matches[1] } else { '???' }
Write-Host ("  {0}   (Python 3.{1})" -f $pyd.Name, $pyTag.Substring(1))

$have = Test-Symbols -Pyd $pyd.FullName -Names $RequiredSymbols
foreach ($n in $RequiredSymbols) {
    Write-Host ("  {0,-20} {1}" -f $n, $(if ($have[$n]) { 'present' } else { 'MISSING' }))
}
$missing = @($RequiredSymbols | Where-Object { -not $have[$_] })
if ($missing.Count) {
    Write-Host ""
    $msg = "This build is still too old: {0} not exposed to Python. You need 2.5.3-beta.2 or later. Nothing was changed." -f ($missing -join ', ')
    throw $msg
}
Write-Host "  PASS - this build can run the Oblivion Remastered plugin."

# The old install runs Python 3.12. basic_games master moved to 3.13 in June 2026,
# so a 3.13 build needs a matching basic_games or the game plugin will not import.
$pyMismatch = ($pyTag -ne '312')
if ($pyMismatch) {
    Write-Host ("  NOTE: this build is Python 3.{0}, the old one was 3.12." -f $pyTag.Substring(1))
    Write-Host "        If the game plugin fails to load after this, that is why - say so and"
    Write-Host "        I will pin basic_games to the matching revision."
}
Write-Host ""

# ---- 3. what carries over -------------------------------------------------
Write-Host "--- 3. config carried across ---"
$configFiles = @('ModOrganizer.ini', 'categories.dat', 'nexuscatmap.dat', 'nxmhandler.ini')
foreach ($f in $configFiles) {
    $src = Join-Path $OldDir $f
    if (Test-Path -LiteralPath $src) {
        Write-Host ("  {0,-20} {1:N0} bytes" -f $f, (Get-Item -LiteralPath $src).Length)
    } else {
        Write-Host ("  {0,-20} not present, skipping" -f $f)
    }
}
Write-Host ("  paths inside ModOrganizer.ini rewritten: {0}  ->  {1}" -f `
            (Split-Path $OldDir -Leaf), (Split-Path $destFull -Leaf))
Write-Host ""

# ---- 4. the game plugin ---------------------------------------------------
Write-Host "--- 4. Oblivion Remastered game plugin ---"
$bgNew  = Join-Path $stage   'plugins\basic_games\games'
$bgOld  = Join-Path $OldDir  'plugins\basic_games\games'
$plugPy = 'game_oblivion_remaster.py'
$plugPk = 'oblivion_remaster'

$newHas = (Test-Path -LiteralPath (Join-Path $bgNew $plugPy))
if ($newHas) {
    $nb = (Get-Item -LiteralPath (Join-Path $bgNew $plugPy)).Length
    $ob = (Get-Item -LiteralPath (Join-Path $bgOld $plugPy)).Length
    Write-Host ("  bundled with the new build ({0:N0} bytes; yours is {1:N0})" -f $nb, $ob)
    Write-Host "  keeping the bundled one - it matches that build's API."
} else {
    Write-Host "  not bundled - copying yours across:"
    Write-Host ("    {0}" -f $plugPy)
    Write-Host ("    {0}\  (package)" -f $plugPk)
}
Write-Host "  __pycache__ will be purged (bytecode from a different Python is poison)"
Write-Host ""

if (-not $Apply) {
    Write-Host "Nothing changed. Re-run with -Apply."
    if ($Archive) { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue }
    return
}

# ---- APPLY ----------------------------------------------------------------
Write-Host "=== applying ==="

# 4a. place the build
if (Test-Path -LiteralPath $destFull) {
    $retire = "$destFull.old-$Stamp"
    Write-Host ("  {0} already exists -> {1}" -f (Split-Path $destFull -Leaf), (Split-Path $retire -Leaf))
    Move-Item -LiteralPath $destFull -Destination $retire -Force
}
Write-Host ("  installing to {0}" -f $destFull)
if ($Source) {
    Copy-Item -LiteralPath $stage -Destination $destFull -Recurse -Force
} else {
    Move-Item -LiteralPath $stage -Destination $destFull -Force
}

# 4b. config, with paths rewritten
$oldLeaf = Split-Path $OldDir  -Leaf
$newLeaf = Split-Path $destFull -Leaf
foreach ($f in $configFiles) {
    $src = Join-Path $OldDir $f
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dst = Join-Path $destFull $f
    if ($f -ieq 'ModOrganizer.ini') {
        $txt = Get-Content -LiteralPath $src -Raw
        # every spelling the ini uses: forward slash, single backslash, escaped backslash
        $txt = $txt.Replace($oldLeaf, $newLeaf)
        [IO.File]::WriteAllText($dst, $txt, (New-Object Text.UTF8Encoding $false))
        Write-Host ("  wrote {0} (path references updated)" -f $f)
    } else {
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host ("  copied {0}" -f $f)
    }
}

# 4c. game plugin
if (-not $newHas) {
    Copy-Item -LiteralPath (Join-Path $bgOld $plugPy) -Destination (Join-Path $destFull 'plugins\basic_games\games') -Force
    Copy-Item -LiteralPath (Join-Path $bgOld $plugPk) `
              -Destination (Join-Path $destFull 'plugins\basic_games\games') -Recurse -Force
    Write-Host "  copied the game plugin across"
}
$pyc = @(Get-ChildItem -LiteralPath (Join-Path $destFull 'plugins') -Recurse -Directory `
         -Filter '__pycache__' -ErrorAction SilentlyContinue)
foreach ($d in $pyc) { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ("  purged {0} __pycache__ folder(s)" -f $pyc.Count)

# 4d. Windows blocks .NET assemblies that carry a download zone marker.
Write-Host "  unblocking downloaded files..."
Get-ChildItem -LiteralPath $destFull -Recurse -File -ErrorAction SilentlyContinue |
    Unblock-File -ErrorAction SilentlyContinue

if ($Archive) { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "Done."
Write-Host ""
Write-Host ("  new:  {0}\ModOrganizer.exe" -f $destFull)
Write-Host ("  old:  {0}\ModOrganizer.exe   (untouched - this is your rollback)" -f $OldDir)
Write-Host ""
Write-Host "  Launch the NEW exe. The instance, mods and downloads are unchanged."
Write-Host "  MO2 will re-register the nxm:// handler on first launch; if Nexus"
Write-Host "  'Mod Manager Download' stops working, that is all it is."
Write-Host ""
Write-Host "  Then, without doing anything else, check the Plugins tab on the right."
Write-Host "  It should list far more than 15 entries. Tell me the count."
