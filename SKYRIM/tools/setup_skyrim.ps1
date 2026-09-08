#Requires -Version 5.1
<#
  setup_skyrim.ps1 - bootstrap a self-contained Skyrim SE modding root at X:\MODDING\SKYRIM.

    X:\MODDING\tools\setup_skyrim.ps1              dry run - reports, writes nothing
    X:\MODDING\tools\setup_skyrim.ps1 -Apply       do it

  WHAT IT BUILDS

    X:\MODDING\SKYRIM\
      STOCK GAME\    a byte-exact copy of the Steam install (~20 GiB)
      MO2\           its own portable Mod Organizer, cloned from the Oblivion one
      SKYRIM_SE\     the MO2 instance: mods\ downloads\ profiles\ overwrite\
      tools\ data\ logs\ backups\ _incoming\

  WHY A COPY AND NOT THE STEAM FOLDER

  Three reasons, all of which have cost people their install before:

    1. The DLSS 5 work replaces dxgi.dll and drops unsigned DLLs beside the exe.
       Steam's "verify integrity" silently deletes those, and a background game
       update overwrites the exe underneath a version-locked SKSE.
    2. The engine has to be DOWNGRADED (see below). Downgrading the Steam copy
       means every other thing that reads it - including the Nolvus install -
       is now looking at a patched exe.
    3. A stock copy can be thrown away and rebuilt in twenty minutes. That is
       the whole point: this is a test bed, and it should be cheap to burn.

  THE VERSION PROBLEM

  Steam is currently on Skyrim 1.7.104. The newest SKSE64 is 2.2.6 beta and it
  targets 1.6.1170. There is no SKSE for 1.7.104, so on the stock Steam build
  literally no SKSE mod loads - which includes every route to DLSS 5.

  So the copy gets downgraded to 1.6.1170 with the Best of Both Worlds patcher,
  which rolls the engine back but keeps all the Anniversary Edition Creation
  Club content that is already installed here (there is a lot of it - 60-odd cc
  plugins, about 6 GiB). That is what "best of both worlds" means.

  1.6.1170 rather than 1.5.97 on purpose: 1.5.97 is the old PureDark-era target
  that Nolvus uses, but the shader stack the DLSS 5 route needs - Community
  Shaders and its Open Shaders fork - is built for 1.6.x. Picking 1.5.97 here
  would close off the route we are actually trying to open.

  This script does NOT downgrade. It only makes the copy. The patcher is a
  separate download and is run by hand once, against STOCK GAME.
#>

[CmdletBinding()]
param(
    [string]$Root      = 'X:\MODDING\SKYRIM',
    [string]$Source    = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition',
    [string]$MO2Source = 'X:\MODDING\MO2\Mod.Organizer-2.5.3',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$mode  = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' }

$StockGame = Join-Path $Root 'STOCK GAME'
$MO2Dest   = Join-Path $Root 'MO2\Mod.Organizer-2.5.3'
$Instance  = Join-Path $Root 'SKYRIM_SE'

Write-Host ""
Write-Host "=== Skyrim SE stock-game bootstrap ($mode) ===" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------- preflight --
$fail = @()

$destDrive = (Split-Path -Qualifier $Root)
if (-not (Test-Path -LiteralPath ($destDrive + '\'))) { $fail += "drive $destDrive does not exist" }
if (-not (Test-Path -LiteralPath $Source)) { $fail += "source game folder not found: $Source" }
if (-not (Test-Path -LiteralPath $MO2Source)) { $fail += "MO2 build not found: $MO2Source" }
if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    $fail += "Mod Organizer is running - close it before cloning the build"
}
if (Get-Process -Name 'SkyrimSE' -ErrorAction SilentlyContinue) {
    $fail += "Skyrim is running - close it, the copy would read files mid-write"
}

$srcExe = Join-Path $Source 'SkyrimSE.exe'
$srcVer = $null
if (Test-Path -LiteralPath $srcExe) {
    $srcVer = (Get-Item -LiteralPath $srcExe).VersionInfo.FileVersion
}

Write-Host "--- source ---"
Write-Host ("  path            {0}" -f $Source)
Write-Host ("  SkyrimSE.exe    {0}" -f $(if ($srcVer) { $srcVer } else { '(missing)' }))

if ($srcVer -and $srcVer -notmatch '^1\.7\.104') {
    Write-Host ("  NOTE            expected 1.7.104.0; this is {0}." -f $srcVer) -ForegroundColor Yellow
    Write-Host  "                  If it is already 1.6.1170 the downgrade step below is done."
}

# Anything already sitting next to the exe that should not be there. A clean
# Steam install has no dlls beyond bink2w64/steam_api64, no ini overrides, and
# no script extender. If it does, this copy is not actually stock.
$dirt = @()
foreach ($n in @('skse64_loader.exe','d3d11.dll','dxgi.dll','winmm.dll','version.dll',
                 'enbseries.ini','enblocal.ini','ReShade.ini','nvngx_dlssnr.dll')) {
    if (Test-Path -LiteralPath (Join-Path $Source $n)) { $dirt += $n }
}
if ($dirt.Count) {
    Write-Host ("  NOT STOCK       found: {0}" -f ($dirt -join ', ')) -ForegroundColor Yellow
    Write-Host  "                  the Steam install has been modified; the copy inherits that."
} else {
    Write-Host  "  clean           no script extender, injector or ini overrides present"
}

# ---- size and space --------------------------------------------------------
Write-Host ""
Write-Host "--- measuring source (this takes a few seconds) ---"
$srcFiles = @(Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction SilentlyContinue)
$srcBytes = ($srcFiles | Measure-Object -Property Length -Sum).Sum
Write-Host ("  {0:N0} files, {1:N2} GiB" -f $srcFiles.Count, ($srcBytes / 1GB))

$free = $null
try {
    $d = Get-PSDrive -Name $destDrive.TrimEnd(':') -ErrorAction Stop
    $free = $d.Free
} catch { }

if ($null -ne $free) {
    $needed = $srcBytes + 2GB          # game + MO2 + working headroom
    Write-Host ("  {0} free        {1:N2} GiB   (need about {2:N2} GiB)" -f $destDrive, ($free / 1GB), ($needed / 1GB))
    if ($free -lt $needed) {
        $fail += ("not enough space on {0}: {1:N2} GiB free, need about {2:N2} GiB" -f $destDrive, ($free / 1GB), ($needed / 1GB))
    }
} else {
    Write-Host ("  {0} free        (could not read)" -f $destDrive) -ForegroundColor Yellow
}

if (Test-Path -LiteralPath $StockGame) {
    $existing = @(Get-ChildItem -LiteralPath $StockGame -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    if ($existing) {
        $fail += "$StockGame already exists and has $existing file(s). Move or delete it - this script will not merge into a half-copied game."
    }
}

if ($fail.Count) {
    Write-Host ""
    Write-Host "--- cannot continue ---" -ForegroundColor Red
    foreach ($f in $fail) { Write-Host ("  {0}" -f $f) -ForegroundColor Red }
    Write-Host ""
    return
}

# ------------------------------------------------------------------ plan -----
Write-Host ""
Write-Host "--- plan ---"
Write-Host ("  1. create   {0}\ tree" -f $Root)
Write-Host ("  2. copy     {0:N0} files -> {1}" -f $srcFiles.Count, $StockGame)
Write-Host  "  3. verify   file count, total bytes, SHA256 of SkyrimSE.exe and Skyrim.esm"
Write-Host  "  4. write    steam_appid.txt so the copy launches without bouncing to Steam"
Write-Host ("  5. clone    {0} -> {1}  (config stripped, so it does first-run setup)" -f (Split-Path $MO2Source -Leaf), $MO2Dest)

if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing written. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ------------------------------------------------------------------- 1. tree -
Write-Host ""
Write-Host "--- 1. tree ---"
foreach ($d in @($Root, $StockGame, (Join-Path $Root 'MO2'), $Instance,
                 (Join-Path $Root 'tools'), (Join-Path $Root 'data'),
                 (Join-Path $Root 'logs'), (Join-Path $Root 'backups'),
                 (Join-Path $Root '_incoming'),
                 (Join-Path $Instance 'mods'), (Join-Path $Instance 'downloads'),
                 (Join-Path $Instance 'profiles'), (Join-Path $Instance 'overwrite'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Write-Host ("  created under {0}" -f $Root)

# ------------------------------------------------------------------- 2. copy -
Write-Host ""
Write-Host "--- 2. copying the game ---"
Write-Host  "  robocopy, 8 threads, unbuffered. Expect 5-20 minutes on a spinning disk."
$log = Join-Path $Root ("logs\stockgame-copy-$Stamp.log")

# /E    subdirs including empty      /J   unbuffered - matters for multi-GB bsa
# /R:2  two retries, not a million   /MT  8 threads
# no /MIR: it deletes, and there is nothing here to mirror against
robocopy $Source $StockGame /E /J /R:2 /W:2 /MT:8 /NP /TEE /LOG:$log
$rc = $LASTEXITCODE

# robocopy: 0-7 are success bitflags, 8+ means files were actually not copied
if ($rc -ge 8) {
    Write-Host ("  robocopy exit {0} - copy FAILED. See {1}" -f $rc, $log) -ForegroundColor Red
    return
}
Write-Host ("  robocopy exit {0} (ok). log: {1}" -f $rc, (Split-Path $log -Leaf))

# ----------------------------------------------------------------- 3. verify -
Write-Host ""
Write-Host "--- 3. verifying ---"
$dstFiles = @(Get-ChildItem -LiteralPath $StockGame -Recurse -File -Force -ErrorAction SilentlyContinue)
$dstBytes = ($dstFiles | Measure-Object -Property Length -Sum).Sum

Write-Host ("  files   source {0:N0}   copy {1:N0}" -f $srcFiles.Count, $dstFiles.Count)
Write-Host ("  bytes   source {0:N0}   copy {1:N0}" -f $srcBytes, $dstBytes)

$ok = $true
if ($dstFiles.Count -ne $srcFiles.Count) { Write-Host "  FILE COUNT MISMATCH" -ForegroundColor Red; $ok = $false }
if ($dstBytes -ne $srcBytes)             { Write-Host "  BYTE TOTAL MISMATCH" -ForegroundColor Red; $ok = $false }

# A count-and-bytes match can still hide a corrupted big file, so hash the two
# that matter most: the exe the whole version lock hangs off, and the master.
foreach ($n in @('SkyrimSE.exe', 'Data\Skyrim.esm')) {
    $a = Join-Path $Source $n; $b = Join-Path $StockGame $n
    if (-not (Test-Path -LiteralPath $b)) { Write-Host ("  MISSING in copy: {0}" -f $n) -ForegroundColor Red; $ok = $false; continue }
    $ha = (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash
    $hb = (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash
    if ($ha -eq $hb) { Write-Host ("  sha256 ok   {0}" -f $n) }
    else             { Write-Host ("  SHA256 MISMATCH  {0}" -f $n) -ForegroundColor Red; $ok = $false }
}

if (-not $ok) {
    Write-Host ""
    Write-Host "The copy is not faithful. Delete '$StockGame' and re-run." -ForegroundColor Red
    return
}
Write-Host "  copy verified" -ForegroundColor Green

# ------------------------------------------------------------- 4. appid file -
# Without this the copied exe calls SteamAPI_RestartAppIfNecessary and hands
# control to the Steam install instead, so you would be launching the wrong
# game and wondering why none of this took effect.
$appid = Join-Path $StockGame 'steam_appid.txt'
[IO.File]::WriteAllText($appid, "489830", (New-Object Text.ASCIIEncoding))
Write-Host ""
Write-Host "--- 4. steam_appid.txt written (489830) ---"

# ------------------------------------------------------------------ 5. MO2 ---
Write-Host ""
Write-Host "--- 5. cloning Mod Organizer ---"
New-Item -ItemType Directory -Force -Path $MO2Dest | Out-Null
$mo2log = Join-Path $Root ("logs\mo2-clone-$Stamp.log")

# Everything except the state that belongs to the Oblivion instance. Leaving
# ModOrganizer.ini in place would make this copy open the Oblivion instance and
# then quietly write to it - the config is what makes a portable MO2 portable.
robocopy $MO2Source $MO2Dest /E /R:2 /W:2 /NP /NFL /NDL /LOG:$mo2log `
    /XF ModOrganizer.ini ModOrganizer.log usvfs*.log nxmhandler.ini `
    /XD logs webcache crashDumps overwrite mods downloads profiles
if ($LASTEXITCODE -ge 8) {
    Write-Host ("  robocopy exit {0} - MO2 clone FAILED. See {1}" -f $LASTEXITCODE, $mo2log) -ForegroundColor Red
    return
}
Write-Host ("  cloned to {0}" -f $MO2Dest)
Write-Host  "  ModOrganizer.ini deliberately not copied - it will run first-time setup."

# keep a copy of this script with the thing it built
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $Root 'tools') -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------------- report --
$dstVer = (Get-Item -LiteralPath (Join-Path $StockGame 'SkyrimSE.exe')).VersionInfo.FileVersion
Write-Host ""
Write-Host "=== done ===" -ForegroundColor Green
Write-Host ("  stock game   {0}" -f $StockGame)
Write-Host ("  version      {0}   <- still needs downgrading" -f $dstVer)
Write-Host ("  MO2          {0}" -f $MO2Dest)
Write-Host ("  instance     {0}" -f $Instance)
Write-Host ""
Write-Host "NEXT: downgrade the copy to 1.6.1170, then stop." -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Get 'Steam 1.7.104 - 1.6.1170 - 1.5.97 Best of Both Worlds Downgrade Patcher'"
Write-Host "     https://www.nexusmods.com/skyrimspecialedition/mods/169962"
Write-Host ("  2. Extract it into  {0}" -f $StockGame)
Write-Host "  3. Run  Skyrim_1_7_104_to_1_6_1170_patcher.exe  and let it make its backup."
Write-Host "     NOT the 1_5_97 one. 1.6.1170 is what the shader stack we need is built for."
Write-Host "  4. Confirm the exe now reads 1.6.1170.0:"
Write-Host ("     (Get-Item '{0}\SkyrimSE.exe').VersionInfo.FileVersion" -f $StockGame)
Write-Host ""
Write-Host "  Do not install SKSE, Address Library or anything else yet - the next"
Write-Host "  script sets MO2 up against this folder and wants it untouched."
Write-Host ""
