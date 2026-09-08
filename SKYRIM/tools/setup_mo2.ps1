#Requires -Version 5.1
<#
  setup_mo2.ps1 - create the portable MO2 instance for X:\MODDING\SKYRIM\STOCK GAME.

    X:\MODDING\SKYRIM\tools\setup_mo2.ps1            report what it would write
    X:\MODDING\SKYRIM\tools\setup_mo2.ps1 -Apply     write it

    -Width 2560 -Height 1440    override the detected resolution
    -Exclusive                  exclusive fullscreen instead of borderless

  This writes the instance by hand rather than clicking through MO2's first-run
  wizard. The ini format is copied from the working Oblivion Remastered instance
  at X:\MODDING, so the key names and the Qt escaping come from something known
  to load rather than from memory.

  IF MO2 OPENS ITS SETUP WIZARD ANYWAY, nothing is broken - answer it with:
  Portable instance / Skyrim Special Edition / game folder X:\MODDING\SKYRIM\STOCK GAME
  / instance folder X:\MODDING\SKYRIM\SKYRIM_SE. Then close MO2 and re-run this with
  -Apply to add the executables.

  THE INIs

  Skyrim will not start without Skyrim.ini and SkyrimPrefs.ini in
  Documents\My Games\Skyrim Special Edition\, and normally SkyrimSELauncher.exe
  creates them the first time it runs. On this machine the launcher exits
  silently and writes nothing, which is what a copied game folder does to its
  Steam library check.

  It does not matter, because the launcher has no secret: it copies
  Skyrim_Default.ini and Skyrim\SkyrimPrefs.ini out of the game folder and then
  writes a detected resolution over the top. Both of those files are sitting in
  STOCK GAME right now, so this does the same thing - reads the shipped
  templates, sets the resolution from the primary display, and writes the pair
  into both Documents and the MO2 profile.

  Borderless windowed by default (bFull Screen=0 + bBorderless=1) rather than
  exclusive fullscreen, because that is what behaves with an injected ReShade
  overlay - and an injected ReShade is the entire point of this install. Pass
  -Exclusive if you want the other one.

  WHAT IT DOES NOT WRITE

  plugins.txt and loadorder.txt. There are 60-odd Creation Club plugins in Data
  and MO2 enumerates them itself on first run; a hand-written list would only be
  a stale guess it has to correct.
#>

[CmdletBinding()]
param(
    [string]$Root     = 'X:\MODDING\SKYRIM',
    [string]$MO2      = 'X:\MODDING\SKYRIM\MO2\Mod.Organizer-2.5.3',
    [string]$MyGames  = "$env:USERPROFILE\Documents\My Games\Skyrim Special Edition",
    [string]$LootExe  = 'C:\Users\mr\AppData\Local\Programs\LOOT\LOOT.exe',
    [int]$Width       = 0,
    [int]$Height      = 0,
    [switch]$Exclusive,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$StockGame = Join-Path $Root 'STOCK GAME'
$Instance  = Join-Path $Root 'SKYRIM_SE'
$ProfileD  = Join-Path $Instance 'profiles\Default'
$Ini       = Join-Path $MO2 'ModOrganizer.ini'
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$mode      = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' }

Write-Host ""
Write-Host "=== MO2 instance setup ($mode) ===" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------- preflight --
$fail = @()
$warn = @()

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    $fail += "Mod Organizer is running. It rewrites ModOrganizer.ini from memory on exit and would throw this away. Close it first."
}

$exe = Join-Path $StockGame 'SkyrimSE.exe'
if (-not (Test-Path -LiteralPath $exe)) { $fail += "not found: $exe" }
else {
    $v = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
    Write-Host ("  SkyrimSE.exe        {0}" -f $v)
    if ($v -notlike '1.6.1170*') { $fail += "SkyrimSE.exe is $v, expected 1.6.1170.0. Run downgrade.ps1 -Apply first." }
}

$loader  = Join-Path $StockGame 'skse64_loader.exe'
$skseDll = Join-Path $StockGame 'skse64_1_6_1170.dll'
foreach ($p in @($loader, $skseDll)) {
    if (Test-Path -LiteralPath $p) { Write-Host ("  {0,-19} present" -f (Split-Path $p -Leaf)) }
    else { $fail += "missing script extender file: $p" }
}

if (-not (Test-Path -LiteralPath $MO2)) { $fail += "MO2 build not found: $MO2" }

# ---- where each ini comes from --------------------------------------------
# Prefer anything already in Documents - if the game or another tool has been
# run, those are real and reflect actual settings. Only fall back to the
# shipped templates when there is nothing there.
$docIni   = Join-Path $MyGames 'Skyrim.ini'
$docPref  = Join-Path $MyGames 'SkyrimPrefs.ini'
$tmplIni  = Join-Path $StockGame 'Skyrim_Default.ini'
$tmplPref = Join-Path $StockGame 'Skyrim\SkyrimPrefs.ini'

$srcIni  = if (Test-Path -LiteralPath $docIni)  { $docIni }  else { $tmplIni }
$srcPref = if (Test-Path -LiteralPath $docPref) { $docPref } else { $tmplPref }
foreach ($p in @($srcIni, $srcPref)) {
    if (-not (Test-Path -LiteralPath $p)) { $fail += "no ini source found: $p" }
}
Write-Host ("  Skyrim.ini from     {0}" -f $srcIni)
Write-Host ("  SkyrimPrefs from    {0}" -f $srcPref)

if (-not (Test-Path -LiteralPath $LootExe)) { $warn += "LOOT not found at $LootExe - skipping that executable entry." }

if ($fail.Count) {
    Write-Host ""
    Write-Host "--- cannot continue ---" -ForegroundColor Red
    foreach ($f in $fail) { Write-Host ("  {0}" -f $f) -ForegroundColor Red }
    Write-Host ""
    return
}

# ---- resolution ------------------------------------------------------------
# Win32_VideoController reports real pixels; System.Windows.Forms would hand
# back DPI-scaled numbers and quietly give a smaller window than the display.
if ($Width -le 0 -or $Height -le 0) {
    $vc = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.CurrentHorizontalResolution -gt 0 } |
            Sort-Object { [int]$_.CurrentHorizontalResolution } -Descending)
    if ($vc.Count) {
        $Width  = [int]$vc[0].CurrentHorizontalResolution
        $Height = [int]$vc[0].CurrentVerticalResolution
        Write-Host ("  display detected    {0}x{1}  ({2})" -f $Width, $Height, $vc[0].Name)
    } else {
        $Width = 1920; $Height = 1080
        $warn += "could not detect the display - defaulting to 1920x1080. Re-run with -Width/-Height to set it."
    }
} else {
    Write-Host ("  display (given)     {0}x{1}" -f $Width, $Height)
}
$modeName = if ($Exclusive) { 'exclusive fullscreen' } else { 'borderless windowed' }
Write-Host ("  window mode         {0}" -f $modeName)

foreach ($w in $warn) { Write-Host ("  NOTE  {0}" -f $w) -ForegroundColor Yellow }

# ------------------------------------------------------------------- plan ----
Write-Host ""
Write-Host "--- plan ---"
Write-Host ("  ModOrganizer.ini    {0}" -f $Ini)
Write-Host  "    gameName          Skyrim Special Edition"
Write-Host ("    gamePath          {0}" -f $StockGame)
Write-Host ("    base_directory    {0}" -f $Instance)
Write-Host ("  profile             {0}" -f $ProfileD)
Write-Host ("  documents           {0}" -f $MyGames)
$execList = 'SKSE (default), Skyrim SE (no SKSE)'
if (Test-Path -LiteralPath $LootExe) { $execList += ', LOOT' }
Write-Host ("  executables         {0}" -f $execList)

if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing written. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ------------------------------------------------------------------- inis ----
Write-Host ""
Write-Host "--- inis ---"
New-Item -ItemType Directory -Force -Path $MyGames  | Out-Null
New-Item -ItemType Directory -Force -Path $ProfileD | Out-Null

# Rewrite a key in place if the section already has it, rather than appending -
# Skyrim reads the FIRST occurrence, so a duplicate appended at the end of the
# file looks correct in a text editor and does nothing in the game.
function Set-IniValue {
    param([string[]]$Lines, [string]$Section, [string]$Key, [string]$Value)
    $out = New-Object System.Collections.Generic.List[string]
    $inSec = $false; $done = $false; $secSeen = $false
    foreach ($l in $Lines) {
        if ($l -match '^\s*\[(.+?)\]\s*$') {
            # leaving the target section without having found the key - add it
            if ($inSec -and -not $done) { $out.Add("$Key=$Value"); $done = $true }
            $inSec = ($Matches[1] -eq $Section)
            if ($inSec) { $secSeen = $true }
            $out.Add($l); continue
        }
        if ($inSec -and -not $done -and $l -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
            $out.Add("$Key=$Value"); $done = $true; continue
        }
        $out.Add($l)
    }
    if (-not $done) {
        if (-not $secSeen) { $out.Add("[$Section]") }
        $out.Add("$Key=$Value")
    }
    return ,$out.ToArray()
}

$prefLines = @(Get-Content -LiteralPath $srcPref)
$prefLines = Set-IniValue $prefLines 'Display' 'iSize W' "$Width"
$prefLines = Set-IniValue $prefLines 'Display' 'iSize H' "$Height"
$prefLines = Set-IniValue $prefLines 'Display' 'bFull Screen' $(if ($Exclusive) { '1' } else { '0' })
$prefLines = Set-IniValue $prefLines 'Display' 'bBorderless'  $(if ($Exclusive) { '0' } else { '1' })

$iniLines = @(Get-Content -LiteralPath $srcIni)

foreach ($dir in @($MyGames, $ProfileD)) {
    $a = Join-Path $dir 'Skyrim.ini'
    $b = Join-Path $dir 'SkyrimPrefs.ini'
    foreach ($f in @($a, $b)) {
        if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination "$f.bak-$Stamp" -Force }
    }
    [IO.File]::WriteAllLines($a, $iniLines,  $Utf8NoBom)
    [IO.File]::WriteAllLines($b, $prefLines, $Utf8NoBom)
    Write-Host ("  wrote Skyrim.ini + SkyrimPrefs.ini -> {0}" -f $dir)
}

# ---------------------------------------------------------------- profile ----
Write-Host ""
Write-Host "--- profile ---"
$modlist = Join-Path $ProfileD 'modlist.txt'
if (-not (Test-Path -LiteralPath $modlist)) {
    [IO.File]::WriteAllLines($modlist, @('# This file was automatically generated by Mod Organizer.'), $Utf8NoBom)
    Write-Host "  modlist.txt      created (empty)"
} else {
    Write-Host "  modlist.txt      already there - left alone"
}

# LocalSettings=true is what makes the profile use its OWN copy of the inis
# instead of the ones in Documents. That is the point of a stock-game setup:
# nothing this instance does should leak back into the shared location.
[IO.File]::WriteAllLines((Join-Path $ProfileD 'settings.ini'), @(
    '[General]', 'LocalSaves=false', 'AutomaticArchiveInvalidation=false', 'LocalSettings=true'
), $Utf8NoBom)
Write-Host "  settings.ini     written"

foreach ($d in @('mods','downloads','overwrite')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Instance $d) | Out-Null
}

# ------------------------------------------------------------ ModOrganizer ---
Write-Host ""
Write-Host "--- ModOrganizer.ini ---"
if (Test-Path -LiteralPath $Ini) {
    Copy-Item -LiteralPath $Ini -Destination "$Ini.bak-$Stamp" -Force
    Write-Host ("  existing ini backed up as {0}" -f (Split-Path "$Ini.bak-$Stamp" -Leaf))
}

# -replace: the pattern is a regex so '\\' matches ONE backslash; the
# replacement is literal, so '\\' emits TWO. That asymmetry is easy to get
# backwards and produces a path with four backslashes that MO2 silently rejects.
function ConvertTo-IniPath { param([string]$p) $p -replace '\\', '\\' }
function ConvertTo-FwdPath { param([string]$p) $p -replace '\\', '/' }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('[General]')
$lines.Add('gameName=Skyrim Special Edition')
$lines.Add('gamePath=@ByteArray(' + (ConvertTo-IniPath $StockGame) + ')')
$lines.Add('selected_profile=@ByteArray(Default)')
$lines.Add('first_start=false')
$lines.Add('version=2.5.3')
$lines.Add('')
$lines.Add('[Settings]')
$lines.Add('base_directory=' + (ConvertTo-IniPath $Instance))
$lines.Add('profile_local_inis=true')
$lines.Add('profile_local_saves=false')
$lines.Add('profile_archive_invalidation=false')
$lines.Add('')
$lines.Add('[customExecutables]')

$execs = @()
$execs += @{ title = 'SKSE';                binary = $loader; wd = $StockGame; args = '' }
$execs += @{ title = 'Skyrim SE (no SKSE)'; binary = $exe;    wd = $StockGame; args = '' }
if (Test-Path -LiteralPath $LootExe) {
    $execs += @{ title = 'LOOT'; binary = $LootExe; wd = (Split-Path $LootExe -Parent)
                 args = '"--game=\"Skyrim Special Edition\""' }
}

$lines.Add('size=' + $execs.Count)
for ($i = 0; $i -lt $execs.Count; $i++) {
    $n = $i + 1
    $e = $execs[$i]
    $lines.Add("$n\arguments=$($e.args)")
    $lines.Add("$n\binary=" + (ConvertTo-FwdPath $e.binary))
    $lines.Add("$n\hide=false")
    $lines.Add("$n\minimizeToSystemTray=false")
    $lines.Add("$n\ownicon=true")
    $lines.Add("$n\steamAppID=")
    $lines.Add("$n\title=$($e.title)")
    $lines.Add("$n\toolbar=false")
    $lines.Add("$n\workingDirectory=" + (ConvertTo-FwdPath $e.wd))
    Write-Host ("  {0}. {1,-20} {2}" -f $n, $e.title, $e.binary)
}

[IO.File]::WriteAllLines($Ini, $lines, $Utf8NoBom)
Write-Host ("  written ({0} lines)" -f $lines.Count)

# ------------------------------------------------------------------ report ---
Write-Host ""
Write-Host "=== done ===" -ForegroundColor Green
Write-Host ""
Write-Host ("Launch:  {0}\ModOrganizer.exe" -f $MO2)
Write-Host ""
Write-Host "On first start MO2 scans Data and picks up the vanilla masters plus the"
Write-Host "Creation Club plugins as unmanaged content, building plugins.txt and"
Write-Host "loadorder.txt itself. A long plugin list and zero mods is correct here."
Write-Host ""
Write-Host "Then pick SKSE in the executable dropdown and run it. Reaching the main"
Write-Host "menu through MO2 is the gate - nothing else goes in until that works."
Write-Host ""
