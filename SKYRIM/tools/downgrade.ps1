#Requires -Version 5.1
<#
  downgrade.ps1 - run wSkeever's Best of Both Worlds patcher against STOCK GAME.

    X:\MODDING\SKYRIM\tools\downgrade.ps1            report only
    X:\MODDING\SKYRIM\tools\downgrade.ps1 -Apply     copy the patcher in, run it, verify

  The patcher works out which game folder to patch from its OWN location, not
  from an argument, so it has to sit next to SkyrimSE.exe while it runs. This
  copies it in, runs it there, checks the result, and then takes it back out
  again so the stock copy does not accumulate loose tools.

  It is interactive - the patcher asks before it writes and makes its own
  backup. Answer its prompts in this window.

  Target is 1.6.1170, not 1.5.97. 1.5.97 is the old PureDark-era runtime that
  Nolvus uses; Community Shaders and the Open Shaders fork the DLSS 5 route
  needs are built for 1.6.x, so 1.5.97 would close the door we are opening.
#>

[CmdletBinding()]
param(
    [string]$Root      = 'X:\MODDING\SKYRIM',
    [string]$Target    = '1.6.1170',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$StockGame = Join-Path $Root 'STOCK GAME'
$Incoming  = Join-Path $Root '_incoming'
$Exe       = Join-Path $StockGame 'SkyrimSE.exe'
$mode      = if ($Apply) { 'APPLY' } else { 'REPORT ONLY - pass -Apply to run it' }

Write-Host ""
Write-Host "=== Skyrim downgrade to $Target ($mode) ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath $Exe)) { throw "not found: $Exe" }
if (Get-Process -Name 'SkyrimSE' -ErrorAction SilentlyContinue) { throw "Skyrim is running - close it." }

$before = (Get-Item -LiteralPath $Exe).VersionInfo.FileVersion
Write-Host ("  current version   {0}" -f $before)

if ($before -like "$Target*") {
    Write-Host "  already at the target version. Nothing to do." -ForegroundColor Green
    Write-Host ""
    return
}

# find the patcher wherever nexus_get dropped it
# Match "_to_1_6_1170_patcher", not just "1_6_1170" - the optional
# "1.6.1170 to 1.5.97" patcher on that same mod page also contains the target
# string, and picking it would take a 1.7.104 install nowhere.
$needle = "_to_" + $Target.Replace('.','_') + "_patcher"
$pat = @(Get-ChildItem -LiteralPath $Incoming -Recurse -File -Filter '*_patcher.exe' -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like ("*" + $needle + "*") })

if (-not $pat.Count) {
    Write-Host ""
    Write-Host ("  no patcher for {0} found under {1}" -f $Target, $Incoming) -ForegroundColor Red
    Write-Host  "  get it with:"
    Write-Host  "     X:\MODDING\SKYRIM\tools\nexus_get.ps1 -Mod 169962 -Main -Extract"
    Write-Host ""
    return
}
if ($pat.Count -gt 1) {
    Write-Host ("  {0} candidate patchers found - using the newest:" -f $pat.Count) -ForegroundColor Yellow
    foreach ($p in $pat) { Write-Host ("     {0}" -f $p.FullName) }
}
$patcher = ($pat | Sort-Object LastWriteTime -Descending)[0]

Write-Host ("  patcher           {0}" -f $patcher.Name)
Write-Host ("  game folder       {0}" -f $StockGame)

if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing done. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ---------------------------------------------------------------------------
$landed = Join-Path $StockGame $patcher.Name
Copy-Item -LiteralPath $patcher.FullName -Destination $landed -Force
Write-Host ""
Write-Host "--- running the patcher (answer its prompts below) ---" -ForegroundColor Cyan
Write-Host ""

# -PassThru because Start-Process does not set $LASTEXITCODE
$proc = Start-Process -FilePath $landed -WorkingDirectory $StockGame -Wait -NoNewWindow -PassThru
$rc = $proc.ExitCode

Write-Host ""
Write-Host "--- result ---"
$after = (Get-Item -LiteralPath $Exe).VersionInfo.FileVersion
Write-Host ("  before   {0}" -f $before)
Write-Host ("  after    {0}" -f $after)

if ($after -like "$Target*") {
    Remove-Item -LiteralPath $landed -Force -ErrorAction SilentlyContinue
    Write-Host "  patcher removed from the game folder"
    Write-Host ""
    Write-Host ("SkyrimSE.exe is now {0}. That is what SKSE 2.2.6 targets." -f $after) -ForegroundColor Green
    Write-Host ""
    Write-Host "Stop here - do not install SKSE or anything else yet."
    Write-Host "Next step sets MO2 up against this folder and wants it untouched."
} else {
    Write-Host ""
    Write-Host ("The exe did not change to {0}. Patcher exit code {1}." -f $Target, $rc) -ForegroundColor Red
    Write-Host ("The patcher has been left at {0} so you can run it by hand." -f $landed)
    Write-Host "Do not run the 1_5_97 one instead - tell me what it said."
}
Write-Host ""
