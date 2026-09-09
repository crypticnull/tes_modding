<#
.SYNOPSIS
    Diff the running plan against what is actually installed, by Nexus mod id.

.DESCRIPTION
    The plan names hundreds of mods across F, R, V, U, X, Y, Z, P, C, W and M.
    Working out what is still missing by reading it is how you end up believing
    a phase is finished when it is not. This parses every mod link out of
    build-plan.html, groups them by the item id they sit under, and reports what
    is not installed.

.TRAPS
    - Matching is by MOD ID from each mod's meta.ini, never by name. A mod with a
      blank or wrong modid reads as "not installed" here even when it is on disk,
      so the summary counts those separately. fix_modids.ps1 repairs them.
    - A plan entry is not automatically a want. Plenty are listed as rejected,
      deferred or "one per domain" alternatives. This tells you what is ABSENT,
      not what to install. Read the item before acting.
    - Report only. Installs nothing.

.EXAMPLE
    & 'X:\MODDING\SKYRIM\tools\plan_gap.ps1'
    & 'X:\MODDING\SKYRIM\tools\plan_gap.ps1' -Item F-1
    & 'X:\MODDING\SKYRIM\tools\plan_gap.ps1' -MissingOnly -Csv 'X:\MODDING\SKYRIM\logs\plan_gap.csv'
#>
[CmdletBinding()]
param(
    [string] $Root = 'X:\MODDING\SKYRIM',
    [string] $Plan = '',
    [string] $Item = '',
    [switch] $MissingOnly,
    [string] $Csv = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Plan) { $Plan = Join-Path $Root 'build-plan.html' }
if (-not (Test-Path -LiteralPath $Plan)) { throw "plan not found: $Plan" }

# ---- what is installed, by mod id
$modsRoot = Join-Path $Root 'SKYRIM_SE\mods'
$installed = @{}
$blankId   = New-Object Collections.ArrayList
foreach ($d in (Get-ChildItem -Path $modsRoot -Directory -ErrorAction SilentlyContinue)) {
    $meta = Join-Path $d.FullName 'meta.ini'
    if (-not (Test-Path -LiteralPath $meta)) { continue }
    $m = Select-String -Path $meta -Pattern '^modid\s*=\s*(\d+)' | Select-Object -First 1
    if ($m -and [int]$m.Matches[0].Groups[1].Value -gt 0) {
        $installed[[int]$m.Matches[0].Groups[1].Value] = $d.Name
    } else {
        [void]$blankId.Add($d.Name)
    }
}

# ---- every mod link in the plan, grouped by the item id above it
$text = [IO.File]::ReadAllText($Plan)
$rows = New-Object Collections.ArrayList

# split on item markers so each chunk carries its own id
$chunks = [regex]::Split($text, '(?=<div class="id">)')
foreach ($c in $chunks) {
    $idm = [regex]::Match($c, '^<div class="id">([^<]+)</div>')
    if (-not $idm.Success) { continue }
    $itemId = $idm.Groups[1].Value.Trim()
    if ($Item -and $itemId -notlike "*$Item*") { continue }
    foreach ($lm in [regex]::Matches($c, '<a class="mod" href="[^"]*?/mods/(\d+)"[^>]*>([^<]+)</a>')) {
        $mid  = [int]$lm.Groups[1].Value
        $name = ($lm.Groups[2].Value -replace '&#x27;', "'" -replace '&amp;', '&').Trim()
        [void]$rows.Add([pscustomobject]@{
            Item      = $itemId
            ModId     = $mid
            Name      = $name
            Installed = $installed.ContainsKey($mid)
            As        = $(if ($installed.ContainsKey($mid)) { $installed[$mid] } else { '' })
        })
    }
}

# dedupe: a mod can be linked several times
$uniq = $rows | Group-Object Item, ModId | ForEach-Object { $_.Group[0] }

Write-Host ""
Write-Host ("plan_gap  {0} mod reference(s) across {1} item(s)" -f @($uniq).Count, (@($uniq | Select-Object -ExpandProperty Item -Unique).Count))
Write-Host ("installed set: {0} mods with a usable modid, {1} with a blank one" -f $installed.Count, $blankId.Count)

$order = @($uniq | Select-Object -ExpandProperty Item -Unique | Sort-Object)
foreach ($it in $order) {
    $g = @($uniq | Where-Object { $_.Item -eq $it })
    $miss = @($g | Where-Object { -not $_.Installed })
    if ($MissingOnly -and $miss.Count -eq 0) { continue }
    $col = if ($miss.Count -eq 0) { 'Green' } elseif ($miss.Count -eq $g.Count) { 'Red' } else { 'Yellow' }
    Write-Host ""
    Write-Host ("  {0,-8} {1} of {2} installed" -f $it, ($g.Count - $miss.Count), $g.Count) -ForegroundColor $col
    foreach ($r in ($g | Sort-Object Installed, Name)) {
        $mark = if ($r.Installed) { 'ok  ' } else { 'MISS' }
        if ($MissingOnly -and $r.Installed) { continue }
        Write-Host ("      {0} {1,-7} {2}" -f $mark, $r.ModId, $r.Name)
    }
}

Write-Host ""
Write-Host "SUMMARY"
$allMiss = @($uniq | Where-Object { -not $_.Installed })
Write-Host ("  referenced   " + @($uniq).Count)
Write-Host ("  installed    " + (@($uniq).Count - $allMiss.Count))
Write-Host ("  missing      " + $allMiss.Count)
if ($blankId.Count) {
    Write-Host ""
    Write-Host ("  {0} installed mod(s) have no usable modid, so they can read as MISSING here:" -f $blankId.Count) -ForegroundColor Yellow
    $blankId | Select-Object -First 12 | ForEach-Object { Write-Host ("      " + $_) }
    if ($blankId.Count -gt 12) { Write-Host ("      ... and " + ($blankId.Count - 12) + " more") }
    Write-Host "  run fix_modids.ps1 to repair them before trusting a MISS."
}

if ($Csv) {
    $dir = Split-Path -Parent $Csv
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $uniq | Sort-Object Item, Name | Export-Csv -LiteralPath $Csv -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Host ("  csv -> " + $Csv)
}
