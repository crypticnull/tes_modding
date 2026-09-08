<#
.SYNOPSIS
    Flag SKSE plugins installed as the wrong runtime build.

.DESCRIPTION
    NEXT.md section 1. Actor Limit Fix and Bug Fixes SSE both shipped four MAIN
    files, one per runtime, with the newest-runtime build flagged primary on
    Nexus. install_mod.ps1 -Mod took the primary and put a 1.7.99 DLL on a
    1.6.1170 game. check_masters.ps1 reports clean, because it is not a master
    problem. The only symptom is an AddressLibrary popup at launch.

    This walks every mods\*\meta.ini, pulls version-shaped tokens out of the
    installation filename and the folder name, and reports the ones that look
    like a runtime marker that does not cover the target runtime.

.TRAPS
    The naive sweep in NEXT.md is Select-String for '1\.7\.' over meta.ini. On
    the 2026-09-08 snapshot that returns two false positives, because CBPC ships
    at mod version 1.7.2 and Overlay Distribution Framework at 1.7.0. Neither is
    a runtime marker. This script scores instead of matching, so those land in
    IGNORED rather than in your face.

    It does not know the list of real Skyrim runtimes and deliberately does not
    pretend to. It reports what looks like a runtime marker and leaves the call
    to you. HIGH means go and read the mod's file list on Nexus, not that the
    mod is broken.

    Report only. It changes nothing, there is no -Apply.

.EXAMPLE
    & 'X:\MODDING\SKYRIM\tools\runtime_check.ps1'
    & 'X:\MODDING\SKYRIM\tools\runtime_check.ps1' -Csv 'X:\MODDING\SKYRIM\logs\runtime_check.csv'
#>
[CmdletBinding()]
param(
    [string] $Root = 'X:\MODDING\SKYRIM',

    # The runtime this install actually is. A marker covering this is fine.
    [string] $Runtime = '1.6.1170',

    # Only look at mods enabled in this profile. Empty means every mod folder.
    [string] $ProfileName = 'Default',

    # Optional CSV of every row, including the ignored ones.
    [string] $Csv = ''
)

$ErrorActionPreference = 'Stop'

$modsRoot = Join-Path $Root 'SKYRIM_SE\mods'
$modlist  = Join-Path $Root ("SKYRIM_SE\profiles\{0}\modlist.txt" -f $ProfileName)
if (-not (Test-Path $modsRoot)) { throw "No mods folder at $modsRoot. Pass -Root at the SKYRIM folder." }

# ---- which mods are enabled, so a disabled wrong-runtime folder is not noise
$enabled = $null
if ($ProfileName -and (Test-Path $modlist)) {
    $enabled = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($l in [System.IO.File]::ReadAllLines($modlist)) {
        if ($l.StartsWith('+')) { [void]$enabled.Add($l.Substring(1).Trim()) }
    }
}

# ---- the target runtime, as numbers, for range comparisons
$rtParts = @($Runtime -split '\.' | ForEach-Object { [int]$_ })
function ConvertTo-Rank {
    param([int[]] $Parts)
    $p = @($Parts) + @(0, 0, 0, 0)
    return ([int64]$p[0] * 1000000000) + ([int64]$p[1] * 1000000) + ([int64]$p[2])
}
$rtRank = ConvertTo-Rank $rtParts

# A version token with a 2+ digit third component is runtime shaped. Mod
# versions almost always carry a single digit there, 1.7.2 and 1.7.0 being the
# two that bit the naive sweep.
$tokenPattern = '(?<![\d.])(\d+)\.(\d+)\.(\d{2,4})(?:\.(\d+))?(?![\d])'
$contextWords = 'and\s+later|and\s+newer|or\s+newer|Anniversary|runtime|SKSE|AE\b|1\.5\.97'

$rows = @()

foreach ($dir in (Get-ChildItem -Path $modsRoot -Directory -ErrorAction SilentlyContinue)) {

    $metaPath = Join-Path $dir.FullName 'meta.ini'
    $instFile = ''
    $modId    = ''
    if (Test-Path $metaPath) {
        foreach ($l in [System.IO.File]::ReadAllLines($metaPath)) {
            if ($l -match '^\s*installationFile\s*=\s*(.+)$') { $instFile = $Matches[1].Trim() }
            elseif ($l -match '^\s*modid\s*=\s*(.+)$')        { $modId    = $Matches[1].Trim() }
        }
    }

    $isOn = if ($null -eq $enabled) { $true } else { $enabled.Contains($dir.Name) }
    $blob = ($dir.Name + ' || ' + $instFile)

    # A version token only counts as a runtime marker if it sits in brackets,
    # sits next to range wording, or is the target runtime itself. Without this
    # test JContainers 4.2.13.1 and TrueHUD 1.1.10 read as runtime markers, and
    # the report drowns in mod versions.
    $parenSpans = @()
    foreach ($pm in [regex]::Matches($blob, '\(([^)]*)\)')) {
        $parenSpans += ,@($pm.Index, $pm.Index + $pm.Length)
    }

    $tokens = @()
    foreach ($m in [regex]::Matches($blob, $tokenPattern)) {
        $rank = ConvertTo-Rank @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)

        $inParens = $false
        foreach ($sp in $parenSpans) {
            if ($sp[0] -lt $m.Index -and ($m.Index + $m.Length) -le $sp[1]) { $inParens = $true; break }
        }

        $tailLen  = [Math]::Min(24, $blob.Length - ($m.Index + $m.Length))
        $tail     = if ($tailLen -gt 0) { $blob.Substring($m.Index + $m.Length, $tailLen) } else { '' }
        $headLen  = [Math]::Min(8, $m.Index)
        $head     = if ($headLen -gt 0) { $blob.Substring($m.Index - $headLen, $headLen) } else { '' }

        $qualified = $inParens -or
                     ($tail -match '^\s*(and|or)\s+(later|newer)') -or
                     ($head -match '\bfor\s*$') -or
                     ($rank -eq $rtRank)

        if ($qualified) {
            $tokens += [pscustomobject]@{ text = $m.Value; rank = $rank; third = [int]$m.Groups[3].Value }
        }
    }

    $hasContext = [bool]([regex]::IsMatch($blob, $contextWords, 'IgnoreCase'))
    $covers     = [bool]($tokens | Where-Object { $_.rank -eq $rtRank })

    $level  = 'ignored'
    $why    = ''
    $marker = ($tokens | ForEach-Object { $_.text }) -join ', '

    if ($tokens.Count -eq 0) {
        $why = 'no runtime shaped token'
    }
    elseif ($covers) {
        $level = 'ok'
        $why   = "names the target runtime $Runtime"
    }
    else {
        $above = @($tokens | Where-Object { $_.rank -gt $rtRank })
        $below = @($tokens | Where-Object { $_.rank -lt $rtRank })

        if ($above.Count -gt 0 -and $hasContext) {
            # "1.7.99.0 And Later" on a 1.6.1170 game. This is the live bug.
            $level = 'HIGH'
            $why   = 'names a runtime ABOVE the target, with runtime wording. Wrong build unless the mod says otherwise.'
        }
        elseif ($above.Count -gt 0) {
            $level = 'check'
            $why   = 'version above the target, but no runtime wording. Could be a mod version.'
        }
        elseif ($below.Count -gt 0 -and $hasContext) {
            # "1.6.629 and newer" covers 1170. Floor, not ceiling.
            $level = 'ok'
            $why   = 'names a runtime FLOOR below the target, so the target is inside its range'
        }
        else {
            $level = 'check'
            $why   = 'version below the target with no range wording'
        }
    }

    if (-not $isOn -and $level -eq 'HIGH') { $level = 'disabled' ; $why = 'wrong runtime, but the mod is disabled' }

    $rows += [pscustomobject]@{
        level    = $level
        mod      = $dir.Name
        modid    = $modId
        enabled  = $isOn
        markers  = $marker
        why      = $why
        file     = $instFile
    }
}

# ------------------------------------------------------------------ report ---

if ($Csv) {
    $dirOut = Split-Path -Parent $Csv
    if ($dirOut -and -not (Test-Path $dirOut)) { New-Item -ItemType Directory -Path $dirOut -Force | Out-Null }
    $rows | Sort-Object level, mod | Export-Csv -LiteralPath $Csv -NoTypeInformation -Encoding UTF8
}

function Write-Block {
    param([string] $Level, [string] $Heading, [string] $Colour)
    $set = @($rows | Where-Object { $_.level -eq $Level } | Sort-Object mod)
    if ($set.Count -eq 0) { return }
    Write-Host ""
    Write-Host ("{0}  ({1})" -f $Heading, $set.Count) -ForegroundColor $Colour
    foreach ($r in $set) {
        Write-Host ("  {0}" -f $r.mod)
        Write-Host ("      marker : {0}" -f $r.markers) -ForegroundColor DarkGray
        Write-Host ("      why    : {0}" -f $r.why)     -ForegroundColor DarkGray
        if ($r.modid) { Write-Host ("      nexus  : {0}" -f $r.modid) -ForegroundColor DarkGray }
    }
}

Write-Host ""
Write-Host ("runtime_check  target {0}  profile {1}  {2} mod folders" -f $Runtime, $ProfileName, $rows.Count)

Write-Block 'HIGH'     'WRONG RUNTIME - reinstall with -File, then disable the old folder' 'Red'
Write-Block 'check'    'WORTH A LOOK - read the mod page file list'                        'Yellow'
Write-Block 'disabled' 'wrong runtime but already disabled'                                'DarkYellow'

$high  = @($rows | Where-Object { $_.level -eq 'HIGH' }).Count
$check = @($rows | Where-Object { $_.level -eq 'check' }).Count
$ok    = @($rows | Where-Object { $_.level -eq 'ok' }).Count
$ign   = @($rows | Where-Object { $_.level -eq 'ignored' }).Count
$dis   = @($rows | Where-Object { $_.level -eq 'disabled' }).Count

Write-Host ""
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host ("  wrong runtime   {0}" -f $high)
Write-Host ("  worth a look    {0}" -f $check)
Write-Host ("  covered ok      {0}" -f $ok)
Write-Host ("  disabled        {0}" -f $dis)
Write-Host ("  no marker       {0}" -f $ign)
if ($Csv) { Write-Host ("  csv             {0}" -f $Csv) }
Write-Host ""
if ($high -gt 0) {
    Write-Host "This class of bug is invisible to check_masters.ps1. Fix before launching." -ForegroundColor Red
} else {
    Write-Host "No wrong-runtime build detected." -ForegroundColor Green
}
