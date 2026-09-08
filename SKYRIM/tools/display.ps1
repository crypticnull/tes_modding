#Requires -Version 5.1
<#
  display.ps1 - diagnose and fix Skyrim's window being larger than the screen.

    X:\MODDING\SKYRIM\tools\display.ps1                  diagnose only
    X:\MODDING\SKYRIM\tools\display.ps1 -Apply           mark Skyrim DPI-aware, keep borderless
    X:\MODDING\SKYRIM\tools\display.ps1 -Apply -Exclusive    exclusive fullscreen instead
    X:\MODDING\SKYRIM\tools\display.ps1 -Apply -Width 2560 -Height 1440    force a size
    X:\MODDING\SKYRIM\tools\display.ps1 -Undo            remove the DPI flag again

  THE PROBLEM

  SkyrimSE.exe does not declare itself DPI-aware. On a display running Windows
  scaling above 100%, the game asks for a window of iSize W x iSize H in
  LOGICAL pixels, and Windows then multiplies that by the scale factor to get
  physical pixels. At 3840x2160 with 150% scaling that is a 5760x3240 window on
  a 3840x2160 monitor, so roughly a third of it hangs off the right and bottom
  edges. Nothing is broken and the game is running fine - you just cannot see
  most of it.

  THREE WAYS OUT, in order of preference:

  1. Tell Windows the application handles its own scaling (what -Apply does).
     This is the same thing as ticking "Override high DPI scaling behaviour -
     Scaling performed by: Application" in the exe's Properties > Compatibility
     tab. It writes one per-user value under AppCompatFlags\Layers, which is a
     per-application compatibility shim, and -Undo removes it. Keeps borderless
     windowed, which is what behaves with an injected ReShade overlay.

  2. Exclusive fullscreen (-Exclusive). The game sets the display mode itself
     and DPI scaling never enters into it. Reliable, but alt-tab is worse and
     it is a slightly less friendly host for an injected overlay.

  3. Just render smaller (-Width/-Height). Worth knowing that this is not only
     a workaround here: DLSS 5 neural rendering costs a fixed amount per OUTPUT
     pixel and cannot be tuned down, so 1440p output may end up being the
     setting you want anyway.

  Close MO2 and Skyrim before running with -Apply - MO2 owns the profile's
  SkyrimPrefs.ini while it is open and will write its own copy back over yours.
#>

[CmdletBinding()]
param(
    [string]$Root      = 'X:\MODDING\SKYRIM',
    [string]$MyGames   = "$env:USERPROFILE\Documents\My Games\Skyrim Special Edition",
    [int]$Width        = 0,
    [int]$Height       = 0,
    [switch]$Exclusive,
    [switch]$Apply,
    [switch]$Undo
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$StockGame = Join-Path $Root 'STOCK GAME'
$ProfileD  = Join-Path $Root 'SKYRIM_SE\profiles\Default'
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$LayersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$Targets   = @((Join-Path $StockGame 'SkyrimSE.exe'), (Join-Path $StockGame 'skse64_loader.exe'))

Write-Host ""
Write-Host "=== Skyrim display check ===" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------- measurement --
# Win32_VideoController reports the mode the GPU is actually scanning out -
# real pixels. System.Windows.Forms reports what a non-DPI-aware process is
# told the screen is, which is the physical size divided by the scale factor.
# Comparing the two IS the diagnosis: if they differ, scaling is on.
$vc = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.CurrentHorizontalResolution -gt 0 } |
        Sort-Object { [int]$_.CurrentHorizontalResolution } -Descending)
$physW = if ($vc.Count) { [int]$vc[0].CurrentHorizontalResolution } else { 0 }
$physH = if ($vc.Count) { [int]$vc[0].CurrentVerticalResolution }   else { 0 }

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$logW = $b.Width; $logH = $b.Height

Write-Host ("  physical (GPU scanout)   {0}x{1}   {2}" -f $physW, $physH, $(if ($vc.Count) { $vc[0].Name } else { '?' }))
Write-Host ("  logical (unaware app)    {0}x{1}" -f $logW, $logH)

$scale = 1.0
if ($logW -gt 0 -and $physW -gt 0) { $scale = [math]::Round($physW / $logW, 3) }
Write-Host ("  scale factor             {0}   ({1}%)" -f $scale, [math]::Round($scale * 100))

if ($scale -gt 1.001) {
    Write-Host ""
    Write-Host ("  -> Windows scaling is on. A non-aware app asking for {0}x{1} gets a" -f $physW, $physH) -ForegroundColor Yellow
    Write-Host ("     {0}x{1} window on a {2}x{3} screen. That is the overflow." -f `
                [int]($physW * $scale), [int]($physH * $scale), $physW, $physH) -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "  -> No scaling detected, so DPI is probably not the cause here." -ForegroundColor Yellow
    Write-Host "     Check iSize below against the physical size instead."
}

# ---- what the inis currently say -------------------------------------------
Write-Host ""
Write-Host "--- current SkyrimPrefs.ini [Display] ---"
$prefFiles = @((Join-Path $ProfileD 'SkyrimPrefs.ini'), (Join-Path $MyGames 'SkyrimPrefs.ini'))
foreach ($f in $prefFiles) {
    if (-not (Test-Path -LiteralPath $f)) { Write-Host ("  {0}  MISSING" -f $f) -ForegroundColor Red; continue }
    $vals = @{}
    foreach ($l in (Get-Content -LiteralPath $f)) {
        if ($l -match '^\s*(iSize W|iSize H|bFull Screen|bBorderless)\s*=\s*(\S+)') { $vals[$Matches[1]] = $Matches[2] }
    }
    Write-Host ("  {0}" -f $f)
    Write-Host ("      iSize {0}x{1}   bFull Screen={2}  bBorderless={3}" -f `
                $vals['iSize W'], $vals['iSize H'], $vals['bFull Screen'], $vals['bBorderless'])
}

# ---- current flag state ----------------------------------------------------
Write-Host ""
Write-Host "--- DPI compatibility flag ---"
foreach ($t in $Targets) {
    $cur = $null
    if (Test-Path -LiteralPath $LayersKey) {
        $p = Get-ItemProperty -LiteralPath $LayersKey -ErrorAction SilentlyContinue
        if ($p -and $p.PSObject.Properties.Name -contains $t) { $cur = $p.$t }
    }
    Write-Host ("  {0,-52} {1}" -f (Split-Path $t -Leaf), $(if ($cur) { $cur } else { '(not set)' }))
}

# ------------------------------------------------------------------- undo ----
if ($Undo) {
    if (-not (Test-Path -LiteralPath $LayersKey)) { Write-Host ""; Write-Host "Nothing to undo."; return }
    foreach ($t in $Targets) {
        Remove-ItemProperty -LiteralPath $LayersKey -Name $t -ErrorAction SilentlyContinue
        Write-Host ("  removed flag for {0}" -f (Split-Path $t -Leaf))
    }
    Write-Host ""
    Write-Host "DPI flags removed." -ForegroundColor Green
    Write-Host ""
    return
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "Diagnosis only. To fix, close MO2 and Skyrim, then one of:" -ForegroundColor Yellow
    Write-Host "    X:\MODDING\SKYRIM\tools\display.ps1 -Apply                  keep borderless (preferred)"
    Write-Host "    X:\MODDING\SKYRIM\tools\display.ps1 -Apply -Exclusive       exclusive fullscreen"
    Write-Host "    X:\MODDING\SKYRIM\tools\display.ps1 -Apply -Width 2560 -Height 1440"
    Write-Host ""
    return
}

# ------------------------------------------------------------------ apply ----
foreach ($n in @('ModOrganizer','SkyrimSE')) {
    if (Get-Process -Name $n -ErrorAction SilentlyContinue) {
        throw "$n is running. Close it - MO2 writes its own copy of the profile ini back on exit."
    }
}

Write-Host ""
Write-Host "--- applying ---"

# 1. the DPI shim, unless we are going exclusive (where it is irrelevant)
if (-not $Exclusive) {
    if (-not (Test-Path -LiteralPath $LayersKey)) { New-Item -Path $LayersKey -Force | Out-Null }
    foreach ($t in $Targets) {
        # "~" is the standard leading token for this value; HIGHDPIAWARE is the
        # "scaling performed by: application" shim from the Compatibility tab.
        New-ItemProperty -LiteralPath $LayersKey -Name $t -Value '~ HIGHDPIAWARE' `
                         -PropertyType String -Force | Out-Null
        Write-Host ("  DPI-aware flag set for {0}" -f (Split-Path $t -Leaf))
    }
}

# 2. resolution / window mode
if ($Width -le 0 -or $Height -le 0) { $Width = $physW; $Height = $physH }
if ($Width -le 0 -or $Height -le 0) { throw "no resolution to write - pass -Width and -Height" }

function Set-IniValue {
    param([string[]]$Lines, [string]$Section, [string]$Key, [string]$Value)
    $out = New-Object System.Collections.Generic.List[string]
    $inSec = $false; $done = $false; $secSeen = $false
    foreach ($l in $Lines) {
        if ($l -match '^\s*\[(.+?)\]\s*$') {
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

foreach ($f in $prefFiles) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    Copy-Item -LiteralPath $f -Destination "$f.bak-$Stamp" -Force
    $L = @(Get-Content -LiteralPath $f)
    $L = Set-IniValue $L 'Display' 'iSize W' "$Width"
    $L = Set-IniValue $L 'Display' 'iSize H' "$Height"
    $L = Set-IniValue $L 'Display' 'bFull Screen' $(if ($Exclusive) { '1' } else { '0' })
    $L = Set-IniValue $L 'Display' 'bBorderless'  $(if ($Exclusive) { '0' } else { '1' })
    [IO.File]::WriteAllLines($f, $L, $Utf8NoBom)
    Write-Host ("  {0}x{1} {2} -> {3}" -f $Width, $Height,
                $(if ($Exclusive) { 'exclusive' } else { 'borderless' }), $f)
}

# 3. silence MO2's "missing skyrimcustom.ini" warning while we are here
$custom = Join-Path $ProfileD 'SkyrimCustom.ini'
if (-not (Test-Path -LiteralPath $custom)) {
    [IO.File]::WriteAllLines($custom, @('[General]'), $Utf8NoBom)
    Write-Host "  SkyrimCustom.ini created (silences MO2's missing-file warning)"
}

Write-Host ""
Write-Host "Done. Start MO2, run SKSE, and check the window fits." -ForegroundColor Green
Write-Host "If it still overflows, run:  X:\MODDING\SKYRIM\tools\display.ps1 -Apply -Exclusive"
Write-Host ""
