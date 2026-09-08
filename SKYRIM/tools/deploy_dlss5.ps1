#Requires -Version 5.1
<#
  deploy_dlss5.ps1 - assemble the DLSS 5 neural rendering stack in STOCK GAME.

    ...\tools\deploy_dlss5.ps1              report what it would copy, verify sources
    ...\tools\deploy_dlss5.ps1 -Apply       do it
    ...\tools\deploy_dlss5.ps1 -Undo -Apply remove every file it added

  WHAT GOES WHERE, AND WHY IT IS ALL IN THE GAME ROOT

  None of this goes through MO2. Every file here sits beside SkyrimSE.exe
  because it is loaded by the Windows loader or by ReShade, not by the game's
  archive system - MO2's virtual filesystem never sees it. Same reason UNBSE
  needed deploy_external.ps1 on the Oblivion side.

    dxgi.dll                 ReShade 6.8 with addon support. Copied from the
                             working Oblivion install so the version is
                             identical to the one your stack already runs on.
                             dxgi rather than d3d11 deliberately: ENB claims
                             d3d11.dll, so this leaves that slot free.
    renodx-dlss5.addon64     the neural rendering addon
    dlss5-bridge.addon64     YOU SUPPLY THIS - see below
    nvngx_dlssnr.dll         the NR runtime, signature-checked by the addon
    nvngx_dlss.dll           needed by the bridge's synthetic path
    nvngx_dlssg.dll, sl.*    the rest of the Streamline runtime
    ReShade.ini              with your tuned [RenoDX.DLSS5] block carried over
    dlss5-bridge.cfg         source=synth for first light

  WHY THE BRIDGE IS NEEDED AT ALL

  renodx-dlss5 works by detouring NVSDK_NGX_D3D12_CreateFeature/EvaluateFeature
  and riding whatever DLSS or DLAA call the game already makes, injecting NGX
  feature 18 inline on the same command list. Oblivion Remastered is D3D12 and
  has native DLSS, so there is something to ride. Skyrim is D3D11 and vanilla
  makes no NGX call at all, so the addon alone arms its hooks and then reports
  "no DLSS create seen" forever. The bridge mirrors the game onto a private
  D3D12 session and, in synth mode, manufactures a DLSS contract from optical
  flow so there is a call to attach to.

  Synth is the lower-quality path - a real DLSS call mirrored is better. It is
  the right FIRST test because it needs no SKSE upscaler mod, so if it fails we
  know the failure is in this stack and not in something else we just installed.
  Once it works, an upscaler mod plus source=mirror is the quality route.

  YOU SUPPLY: dlss5-bridge.addon64

  From github.com/NIGos/dlss5-bridge releases. Put it in _incoming\ and this
  will pick it up. It is an unsigned binary from a personal repo that gets
  injected into your game - your call to make, not one to be made quietly on
  your behalf. The same is true of the leaked NR runtime you are already
  running in Oblivion.
#>

[CmdletBinding()]
param(
    [string]$Root      = 'X:\MODDING\SKYRIM',
    [string]$Streamline = 'C:\Users\mr\Downloads\streamline\streamline',
    [string]$OblivionBin = 'C:\Program Files (x86)\Steam\steamapps\common\Oblivion Remastered\OblivionRemastered\Binaries\Win64',
    [string]$Downloads = 'C:\Users\mr\Downloads',
    [switch]$Undo,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$StockGame = Join-Path $Root 'STOCK GAME'
$Incoming  = Join-Path $Root '_incoming'
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$mode      = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' }

# every file this script is responsible for, so -Undo knows exactly what to remove
$Owned = @(
    'dxgi.dll','renodx-dlss5.addon64','dlss5-bridge.addon64','dlss5-bridge.cfg',
    'ReShade.ini','ReShade.log','dlss5-bridge.log',
    'nvngx_dlss.dll','nvngx_dlssg.dll','nvngx_dlssnr.dll',
    'nvngx_dlss.license.txt','nis.license.txt','reflex.license.txt',
    'sl.common.dll','sl.dlss.dll','sl.dlss_g.dll','sl.dlss_nr.dll',
    'sl.interposer.dll','sl.nis.dll','sl.pcl.dll','sl.reflex.dll'
)

Write-Host ""
Write-Host "=== DLSS 5 stack ($mode) ===" -ForegroundColor Cyan
Write-Host ("  target  {0}" -f $StockGame)
Write-Host ""

if (Get-Process -Name 'SkyrimSE' -ErrorAction SilentlyContinue) { throw "Skyrim is running - close it." }
if (-not (Test-Path -LiteralPath $StockGame)) { throw "not found: $StockGame" }

# ------------------------------------------------------------------- undo ----
if ($Undo) {
    Write-Host "--- removing ---"
    $n = 0
    foreach ($f in $Owned) {
        $p = Join-Path $StockGame $f
        if (Test-Path -LiteralPath $p) {
            Write-Host ("  {0}" -f $f)
            if ($Apply) { Remove-Item -LiteralPath $p -Force }
            $n++
        }
    }
    $sh = Join-Path $StockGame 'reshade-shaders'
    if (Test-Path -LiteralPath $sh) {
        Write-Host "  reshade-shaders\"
        if ($Apply) { Remove-Item -LiteralPath $sh -Recurse -Force }
        $n++
    }
    Write-Host ""
    Write-Host ("{0} item(s) {1}." -f $n, $(if ($Apply) { 'removed' } else { 'would be removed' }))
    Write-Host ""
    return
}

# ---------------------------------------------------------------- sources ----
# Each entry: destination name, where it comes from, whether it is required.
$plan = New-Object System.Collections.Generic.List[object]
function Add-Src { param($Name, $Path, [bool]$Req = $true)
    $plan.Add([pscustomobject]@{ Name = $Name; Src = $Path; Required = $Req })
}

Add-Src 'dxgi.dll'             (Join-Path $OblivionBin 'dxgi.dll')
Add-Src 'renodx-dlss5.addon64' (Join-Path $OblivionBin 'renodx-dlss5.addon64')

foreach ($f in @('nvngx_dlss.dll','nvngx_dlssg.dll','nvngx_dlssnr.dll',
                 'sl.common.dll','sl.dlss.dll','sl.dlss_g.dll','sl.dlss_nr.dll',
                 'sl.interposer.dll','sl.nis.dll','sl.pcl.dll','sl.reflex.dll')) {
    Add-Src $f (Join-Path $Streamline $f)
}
foreach ($f in @('nvngx_dlss.license.txt','nis.license.txt','reflex.license.txt')) {
    Add-Src $f (Join-Path $Streamline $f) $false
}

# The bridge, wherever the browser dropped it. Searches _incoming first, then
# Downloads, and takes the newest - so it does not matter which one you saved
# it to, or whether it is still inside an extracted release folder.
$bridge = @()
foreach ($dir in @($Incoming, $Downloads)) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    $bridge += @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter 'dlss5-bridge*.addon64' -ErrorAction SilentlyContinue)
}
$bridge = @($bridge | Sort-Object LastWriteTime -Descending)
if ($bridge.Count) {
    Add-Src 'dlss5-bridge.addon64' $bridge[0].FullName
    if ($bridge.Count -gt 1) {
        Write-Host ("  note: {0} copies of the bridge found, using the newest" -f $bridge.Count) -ForegroundColor Yellow
    }
} else {
    Add-Src 'dlss5-bridge.addon64' (Join-Path $Incoming 'dlss5-bridge.addon64')
}

Write-Host "--- sources ---"
$missing = @()
foreach ($p in $plan) {
    if (Test-Path -LiteralPath $p.Src) {
        $sz = (Get-Item -LiteralPath $p.Src).Length
        Write-Host ("  {0,-24} {1,13:N0}  {2}" -f $p.Name, $sz, $p.Src)
    } else {
        Write-Host ("  {0,-24} {1,13}  {2}" -f $p.Name, 'MISSING', $p.Src) -ForegroundColor $(if ($p.Required) { 'Red' } else { 'DarkGray' })
        if ($p.Required) { $missing += $p.Name }
    }
}

# ---- the NR runtime must be the exact signed build --------------------------
# renodx-dlss5 hashes nvngx_dlssnr.dll and refuses anything that is not the
# build it knows (it fails with 0xBAD00002). The copy running in Oblivion is
# known good - its log says "signed runtime sha256 ... (reference match)" - so
# compare against that rather than trusting the Downloads copy blindly.
Write-Host ""
Write-Host "--- NR runtime signature ---"
$nrNew = Join-Path $Streamline 'nvngx_dlssnr.dll'
$nrRef = Join-Path $OblivionBin 'nvngx_dlssnr.dll'
if ((Test-Path -LiteralPath $nrNew) -and (Test-Path -LiteralPath $nrRef)) {
    $hNew = (Get-FileHash -LiteralPath $nrNew -Algorithm SHA256).Hash
    $hRef = (Get-FileHash -LiteralPath $nrRef -Algorithm SHA256).Hash
    Write-Host ("  Downloads copy  {0}" -f $hNew)
    Write-Host ("  Oblivion copy   {0}" -f $hRef)
    if ($hNew -eq $hRef) { Write-Host "  identical to the one that already works" -ForegroundColor Green }
    else {
        Write-Host "  DIFFERENT - using the Oblivion copy instead, it is the proven one" -ForegroundColor Yellow
        ($plan | Where-Object { $_.Name -eq 'nvngx_dlssnr.dll' }) | ForEach-Object { $_.Src = $nrRef }
    }
} else {
    Write-Host "  cannot compare - one of the two is missing" -ForegroundColor Yellow
}

# ---- the bridge is the one file from outside this machine -------------------
# NIGos publishes a SHA256 on the release page. Checking it does not make an
# unsigned binary from a personal repo trustworthy - it only proves the bytes
# are the ones the maintainer published, and not something a mirror or a
# lookalike repo substituted. That distinction is worth keeping straight.
$BridgeKnown = @{
    '4F2ACECC1026AE89AC0B92767BE66CEEA2662AD0EF88710B89C7DA7840D548D4' = 'v1.4.12 (5 Sep 2026)'
}
$bridgeSrc = ($plan | Where-Object { $_.Name -eq 'dlss5-bridge.addon64' }).Src
if (Test-Path -LiteralPath $bridgeSrc) {
    Write-Host ""
    Write-Host "--- bridge addon ---"
    $bh = (Get-FileHash -LiteralPath $bridgeSrc -Algorithm SHA256).Hash.ToUpper()
    Write-Host ("  sha256  {0}" -f $bh)
    if ($BridgeKnown.ContainsKey($bh)) {
        Write-Host ("  matches the published hash for {0}" -f $BridgeKnown[$bh]) -ForegroundColor Green
    } else {
        Write-Host "  not a hash I have on file." -ForegroundColor Yellow
        Write-Host "  That is expected for a release newer than v1.4.12 - check it against"
        Write-Host "  the SHA256 on the release page yourself before running the game."
    }
}

if ($missing.Count) {
    Write-Host ""
    Write-Host "--- cannot continue, missing required sources ---" -ForegroundColor Red
    foreach ($m in $missing) { Write-Host ("  {0}" -f $m) -ForegroundColor Red }
    if ($missing -contains 'dlss5-bridge.addon64') {
        Write-Host ""
        Write-Host "  dlss5-bridge.addon64 is the one you supply. Get the latest release from"
        Write-Host "  github.com/NIGos/dlss5-bridge and drop the .addon64 in:"
        Write-Host ("      {0}" -f $Incoming)
    }
    Write-Host ""
    return
}

if (-not $Apply) {
    Write-Host ""
    Write-Host ("All {0} sources present. Re-run with -Apply." -f $plan.Count) -ForegroundColor Yellow
    Write-Host ""
    return
}

# ------------------------------------------------------------------ copy ----
Write-Host ""
Write-Host "--- copying ---"
$backup = Join-Path $Root ("backups\stockgame-preDLSS5-$Stamp")
foreach ($p in $plan) {
    if (-not (Test-Path -LiteralPath $p.Src)) { continue }
    $dst = Join-Path $StockGame $p.Name
    if (Test-Path -LiteralPath $dst) {
        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        Copy-Item -LiteralPath $dst -Destination (Join-Path $backup $p.Name) -Force
    }
    Copy-Item -LiteralPath $p.Src -Destination $dst -Force
    Write-Host ("  {0}" -f $p.Name)
}
if (Test-Path -LiteralPath $backup) { Write-Host ("  (replaced originals backed up to {0})" -f $backup) }

# ------------------------------------------------------------------ config --
Write-Host ""
Write-Host "--- config ---"

# ReShade.ini. The [RenoDX.DLSS5] block is your tuned Oblivion preset carried
# straight over. Those values were dialled in against an HDR D3D12 game though,
# and Skyrim here is SDR - NRPaperWhiteScale in particular may want revisiting
# once you can see the result.
$reshadeIni = Join-Path $StockGame 'ReShade.ini'
if (Test-Path -LiteralPath $reshadeIni) {
    Write-Host "  ReShade.ini already exists - left alone"
} else {
    [IO.File]::WriteAllLines($reshadeIni, @(
        '[GENERAL]',
        'EffectSearchPaths=.\reshade-shaders\Shaders\**',
        'TextureSearchPaths=.\reshade-shaders\Textures\**',
        'PerformanceMode=1',
        'PresetPath=.\ReShadePreset.ini',
        '',
        '[INPUT]',
        'KeyOverlay=36,0,0,0',
        'KeyScreenshot=44,0,0,0',
        '',
        '[OVERLAY]',
        'ShowFPS=2',
        'FPSPosition=1',
        'TutorialProgress=4',
        '',
        '[RenoDX.DLSS5]',
        'NeuralUplift=1',
        'NRAutoMask=1',
        'NRIntensity=2',
        'NRLocalStructure=1',
        'NRLocalTone=1.5',
        'NRPaperWhiteScale=1',
        'NRPreset=1',
        'NRSkinStructure=-1',
        'NRStyle=2',
        'NRTransferStrength=1',
        'NRUICorrection=1'
    ), $Utf8NoBom)
    Write-Host "  ReShade.ini written (with your Oblivion [RenoDX.DLSS5] preset)"
}

# Bridge config. synth builds a DLSS contract from optical flow, which is what
# lets this work with no upscaler mod present at all.
$cfg = Join-Path $StockGame 'dlss5-bridge.cfg'
if (Test-Path -LiteralPath $cfg) {
    Write-Host "  dlss5-bridge.cfg already exists - left alone"
} else {
    [IO.File]::WriteAllLines($cfg, @(
        '# first light: no upscaler mod present, so manufacture a DLSS contract',
        '# from optical flow. Switch to source=mirror once a DLSS mod is in.',
        'source=synth',
        'synth=1',
        'synth_after=0'
    ), $Utf8NoBom)
    Write-Host "  dlss5-bridge.cfg written (source=synth)"
}

# ----------------------------------------------------------------- report ----
Write-Host ""
Write-Host "=== deployed ===" -ForegroundColor Green
Write-Host ""
Write-Host "Launch through MO2 with the SKSE entry as usual, then read the log:"
Write-Host ""
Write-Host ("    Get-Content '{0}\ReShade.log' | Select-String 'DLSS5|bridge|feature 18|NGX'" -f $StockGame)
Write-Host ""
Write-Host "WHAT PASS LOOKS LIKE - the line your Oblivion install produces:"
Write-Host "    inline feature 18 evaluation succeeded (count=N, NR input WxH ...)"
Write-Host ""
Write-Host "WHAT THE EXPECTED FAILURE LOOKS LIKE:"
Write-Host "    hooks armed, no DLSS create seen        -> bridge is not feeding it"
Write-Host "    0xBAD00002                              -> wrong nvngx_dlssnr.dll build"
Write-Host "    guides WxH but eval at a smaller size   -> partial-screen coverage"
Write-Host ""
Write-Host "F6 toggles NR in game, F5 takes a before/after pair. Send me the log"
Write-Host "either way and I will read it rather than guess."
Write-Host ""
Write-Host ("Undo everything:  {0}\tools\deploy_dlss5.ps1 -Undo -Apply" -f $Root)
Write-Host ""
