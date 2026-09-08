#Requires -Version 5.1
<#
  install_downloaded.ps1 - install a mod that had to be fetched by hand.

    X:\MODDING\SKYRIM\tools\install_downloaded.ps1 -Match 'High*Poly*Head'
    X:\MODDING\SKYRIM\tools\install_downloaded.ps1 -Match 'High*Poly*Head' -Plan
    X:\MODDING\SKYRIM\tools\install_downloaded.ps1 -Match 'High*Poly*Head' -Apply -Fomod "Group=Option; ..."

  WHY THIS EXISTS

  nexus_get.ps1 works because Nexus publishes an API and the key is on disk.
  VectorPlexus - which hosts High Poly Head, HIMBO, BHUNP, SOS and a lot of the
  body ecosystem - is an Invision Community forum. No API, and its file links
  are session-authenticated, so the only way a script could fetch one is by
  carrying a login. Not doing that.

  So the division of labour is: the browser does the one click that needs an
  account, and this does everything after it. Finds the newest archive in
  Downloads matching a pattern, files it in the instance downloads folder where
  MO2 expects archives to live, and hands it to install_mod.ps1.

  It NEVER guesses which archive you meant. Several matches means it prints
  them and stops, the same rule install_mod.ps1 uses for ambiguous mod ids.
#>

[CmdletBinding()]
param(
    [string]$Root  = 'X:\MODDING\SKYRIM',
    [Parameter(Mandatory = $true)][string]$Match,
    [string]$From  = (Join-Path $env:USERPROFILE 'Downloads'),
    [int]$Days     = 7,
    [string]$Fomod,
    [switch]$FomodDefaults,
    [switch]$Plan,
    [switch]$Bottom,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Dloads  = Join-Path $Root 'SKYRIM_SE\downloads'
$Install = Join-Path $Root 'tools\install_mod.ps1'
$Exts    = @('.7z','.zip','.rar')

Write-Host ""
Write-Host "=== install downloaded: '$Match' ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath $Install)) { throw "not found: $Install" }
if (-not (Test-Path -LiteralPath $From))    { throw "not found: $From" }
if (-not (Test-Path -LiteralPath $Dloads))  { throw "not found: $Dloads" }

$cut  = (Get-Date).AddDays(-$Days)
$hits = @(Get-ChildItem -LiteralPath $From -File -ErrorAction SilentlyContinue |
          Where-Object { $Exts -contains $_.Extension.ToLower() -and
                         $_.LastWriteTime -ge $cut -and
                         $_.Name -like "*$Match*" } |
          Sort-Object LastWriteTime -Descending)

Write-Host ("  looking in {0}, last {1} day(s)" -f $From, $Days)

if (-not $hits.Count) {
    $recent = @(Get-ChildItem -LiteralPath $From -File -ErrorAction SilentlyContinue |
                Where-Object { $Exts -contains $_.Extension.ToLower() } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 8)
    Write-Host "  no archive matches." -ForegroundColor Yellow
    if ($recent.Count) {
        Write-Host "  most recent archives there:" -ForegroundColor DarkGray
        foreach ($r in $recent) { Write-Host ("      {0}" -f $r.Name) -ForegroundColor DarkGray }
    }
    Write-Host ""
    throw "nothing to install - widen -Match, raise -Days, or pass -From"
}

if ($hits.Count -gt 1) {
    # Refuse rather than guess. Picking the newest among several builds of the
    # same mod is how you install 1.3 while believing you installed 1.4.
    Write-Host ("  {0} archives match:" -f $hits.Count) -ForegroundColor Yellow
    foreach ($h in $hits) {
        Write-Host ("      {0}   {1:yyyy-MM-dd HH:mm}  {2} MB" -f `
            $h.Name, $h.LastWriteTime, [math]::Round($h.Length/1MB,1)) -ForegroundColor Yellow
    }
    Write-Host ""
    throw "ambiguous - narrow -Match, or call install_mod.ps1 -Archive directly."
}

$src = $hits[0]
Write-Host ("  found      {0}   ({1} MB, {2:yyyy-MM-dd HH:mm})" -f `
    $src.Name, [math]::Round($src.Length/1MB,1), $src.LastWriteTime) -ForegroundColor Green

# MO2 expects archives under the instance downloads folder, so it lands there
# rather than being installed out of Downloads and then lost.
$dst = Join-Path $Dloads $src.Name
if (Test-Path -LiteralPath $dst) {
    $same = (Get-Item -LiteralPath $dst).Length -eq $src.Length
    Write-Host ("  already in downloads{0}" -f $(if ($same) { ' and the same size - reusing it' } else { ' at a DIFFERENT size - overwriting' }))
    if (-not $same) { Copy-Item -LiteralPath $src.FullName -Destination $dst -Force }
} else {
    Copy-Item -LiteralPath $src.FullName -Destination $dst -Force
    Write-Host ("  filed      {0}" -f $dst)
}

$argv = @{ Archive = $dst }
if ($Fomod)         { $argv['Fomod']         = $Fomod }
if ($FomodDefaults) { $argv['FomodDefaults'] = $true }
if ($Plan)          { $argv['FomodPlan']     = $true }
if ($Bottom)        { $argv['Bottom']        = $true }
if ($Apply)         { $argv['Apply']         = $true }

Write-Host ""
& $Install @argv
