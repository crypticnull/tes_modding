<#
.SYNOPSIS
    Close Mod Organizer WITHOUT corrupting the profile, and verify afterwards.

.DESCRIPTION
    Scripts here close MO2 constantly, because install_mod.ps1 refuses to run
    while it is up. Doing that with Stop-Process -Force is how you lose a
    profile file.

    On 2026-09-08 that happened for real. MO2 started at 22:19:20, archives.txt
    was emptied at 22:19:46, and it stayed at 0 bytes. MO2 truncates a file to
    zero as step ONE of rewriting it, so a force-kill inside that window leaves
    an empty file rather than a partial one. The result in game was no sound at
    all and dialogue that could not advance: archives.txt is what tells the game
    which mod BSAs to load, and Skyrim - Sounds.bsa, Skyrim - Voices_en0.bsa and
    alternate start - live another life.bsa are all in it. Skyrim advances
    dialogue when a voice line finishes, so a missing voice file hangs the
    conversation. Two symptoms, one truncated file.

    So: ask MO2 to close, give it time, and only escalate if it will not go.
    Then CHECK the profile files are non-empty and say so.

.TRAPS
    - CloseMainWindow sends WM_CLOSE, which is what clicking the X does. It lets
      MO2 finish writing. Stop-Process -Force does not.
    - A zero-byte profile file is the signature of this bug. A missing file is a
      different problem; a zero-byte one means something was interrupted.
    - Restore from git rather than guessing: these files are all tracked.
        git -C X:\MODDING checkout HEAD -- SKYRIM/SKYRIM_SE/profiles/Default/archives.txt

.EXAMPLE
    & 'X:\MODDING\SKYRIM\tools\mo2_close.ps1'
    & 'X:\MODDING\SKYRIM\tools\mo2_close.ps1' -AlsoGame
#>
[CmdletBinding()]
param(
    [string] $Root = 'X:\MODDING\SKYRIM',
    [string] $ProfileName = 'Default',
    [int]    $GraceSeconds = 20,
    [switch] $AlsoGame
)

$ErrorActionPreference = 'Stop'
$prof = Join-Path $Root ("SKYRIM_SE\profiles\{0}" -f $ProfileName)

if ($AlsoGame) {
    $g = Get-Process -Name 'SkyrimSE' -ErrorAction SilentlyContinue
    if ($g) { Write-Host "  closing SkyrimSE"; $g | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
}

$mo = Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue
if ($mo) {
    Write-Host ("  asking MO2 to close (pid {0})..." -f ($mo.Id -join ',')) -ForegroundColor Cyan
    foreach ($p in $mo) { [void]$p.CloseMainWindow() }
    $waited = 0
    while ($waited -lt $GraceSeconds -and (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue)) {
        Start-Sleep -Seconds 1; $waited++
    }
    $still = Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue
    if ($still) {
        Write-Host ("  did not close in {0}s - forcing. Profile will be checked below." -f $GraceSeconds) -ForegroundColor Yellow
        $still | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Write-Host ("  closed cleanly after {0}s" -f $waited) -ForegroundColor Green
    }
} else {
    Write-Host "  MO2 was not running"
}

# ---- integrity check. A zero-byte profile file is the signature of an
# interrupted write, and it fails silently in game.
Write-Host ""
Write-Host "  profile integrity:"
$bad = @()
foreach ($f in @('archives.txt','loadorder.txt','plugins.txt','modlist.txt','settings.ini')) {
    $p = Join-Path $prof $f
    if (-not (Test-Path -LiteralPath $p)) { Write-Host ("    MISSING  " + $f) -ForegroundColor Red; $bad += $f; continue }
    $len = (Get-Item -LiteralPath $p).Length
    if ($len -eq 0) {
        Write-Host ("    EMPTY    {0}" -f $f) -ForegroundColor Red
        $bad += $f
    } else {
        Write-Host ("    ok       {0,-16} {1:N0} bytes" -f $f, $len)
    }
}
if ($bad.Count) {
    Write-Host ""
    Write-Host "  A ZERO-BYTE PROFILE FILE WILL BREAK THE GAME SILENTLY." -ForegroundColor Red
    Write-Host "  archives.txt in particular controls BSA loading - empty means no mod" -ForegroundColor Red
    Write-Host "  sound, no mod voices, and dialogue that cannot advance." -ForegroundColor Red
    Write-Host "  Restore from git:" -ForegroundColor Yellow
    foreach ($f in $bad) {
        Write-Host ("    git -C X:\MODDING checkout HEAD -- SKYRIM/SKYRIM_SE/profiles/{0}/{1}" -f $ProfileName, $f)
    }
    exit 1
}
