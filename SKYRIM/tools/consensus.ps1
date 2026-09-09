#Requires -Version 5.1
<#
  consensus.ps1 - what do independently curated modlists AGREE on that we lack?

    X:\MODDING\SKYRIM\tools\consensus.ps1
    X:\MODDING\SKYRIM\tools\consensus.ps1 -MinLists 3
    X:\MODDING\SKYRIM\tools\consensus.ps1 -Filter 'clutter|alchemy|forge'

  WHY AGREEMENT BEATS ENDORSEMENTS

  Endorsement count measures age and install base as much as quality. A mod
  from 2016 that every list shipped for a decade will out-endorse a better mod
  released last year, and a mod nobody can run alongside anything else can still
  collect endorsements from people who tried it alone.

  A mod appearing in SEVERAL independently curated lists has passed somebody
  else's compatibility testing several separate times. That is the property that
  matters when the load order is about to be baked into a multi hour LOD
  generation, because the expensive failure is not "this mod is mediocre", it is
  "this mod fights three others and I find out after the chain has run".

  So this counts, per mod, how many collection_diff reports name it, and reports
  what we do NOT have sorted by that count first and endorsements second.

  INPUT

  Every logs\*.txt written by collection_diff.ps1. Add another list by running
  that script with a new -Slug and re-running this. Nothing is hardcoded.

  Report only. Installs nothing.
#>
[CmdletBinding()]
param(
    [string]$Root     = 'X:\MODDING\SKYRIM',
    [int]$MinLists    = 2,
    [string]$Filter   = '',
    [string]$Category = '',
    [int]$Top         = 60,
    [string]$Out      = ''
)

$ErrorActionPreference = 'Stop'
$logs = Join-Path $Root 'logs'

# every collection_diff report, identified by its own header line
$reports = @(Get-ChildItem -LiteralPath $logs -Filter '*.txt' -File -ErrorAction SilentlyContinue |
             Where-Object { (Get-Content -LiteralPath $_.FullName -TotalCount 1) -match '^Collection diff' })
if (-not $reports.Count) { throw "no collection_diff reports in $logs - run collection_diff.ps1 first" }

$mods = @{}
$names = @()
foreach ($rp in $reports) {
    $lines = Get-Content -LiteralPath $rp.FullName
    $listName = ($lines[0] -replace '^Collection diff - ', '' -replace '\s*\(revision.*$', '').Trim()
    $names += $listName
    $cat = ''
    foreach ($l in $lines) {
        if ($l -match '^---\s+(.+?)\s+---$') { $cat = $Matches[1]; continue }
        if ($l -notmatch '^\s{2,}(\d+)\s+(\d+)\s+(.+?)\s*$') { continue }
        $id = [int]$Matches[2]
        if (-not $mods.ContainsKey($id)) {
            $mods[$id] = [pscustomobject]@{
                Id = $id; Name = $Matches[3].Trim(); End = [int]$Matches[1]
                Cat = $cat; Lists = (New-Object Collections.Generic.HashSet[string])
            }
        }
        # keep the highest endorsement figure seen, reports are dated differently
        if ([int]$Matches[1] -gt $mods[$id].End) { $mods[$id].End = [int]$Matches[1] }
        [void]$mods[$id].Lists.Add($listName)
    }
}

# what is on disk right now, by mod id
$landed = @{}
foreach ($d in (Get-ChildItem (Join-Path $Root 'SKYRIM_SE\mods') -Directory -ErrorAction SilentlyContinue)) {
    $mi = Join-Path $d.FullName 'meta.ini'
    if (-not (Test-Path -LiteralPath $mi)) { continue }
    foreach ($l in (Get-Content -LiteralPath $mi)) {
        if ($l -match '^\s*modid\s*=\s*(\d+)') { $landed[[int]$Matches[1]] = $d.Name }
    }
}

Write-Host ""
Write-Host ("consensus  {0} list(s): {1}" -f $reports.Count, (($names | Sort-Object) -join ', ')) -ForegroundColor Cyan
Write-Host ("           {0} distinct mod(s) across them, {1} installed here" -f $mods.Count, @($mods.Keys | Where-Object { $landed.ContainsKey($_) }).Count)

$rows = $mods.Values |
        Where-Object { -not $landed.ContainsKey($_.Id) } |
        Where-Object { $_.Lists.Count -ge $MinLists } |
        Where-Object { -not $Filter   -or $_.Name -match $Filter } |
        Where-Object { -not $Category -or $_.Cat  -match $Category } |
        Sort-Object @{e={$_.Lists.Count};d=$true}, @{e={$_.End};d=$true}

Write-Host ("           {0} not installed here and named by {1}+ list(s)" -f @($rows).Count, $MinLists) -ForegroundColor Yellow
Write-Host ""
foreach ($r in ($rows | Select-Object -First $Top)) {
    $bar = ('#' * $r.Lists.Count).PadRight($reports.Count)
    "  [{0}] {1,7}  {2,-8} {3,-48} [{4}]" -f $bar, $r.End, $r.Id, $r.Name.Substring(0, [Math]::Min(46, $r.Name.Length)), $r.Cat
}

if ($Out) {
    $rows | Select-Object @{n='Lists';e={$_.Lists.Count}}, @{n='In';e={($_.Lists | Sort-Object) -join '; '}}, Id, Name, End, Cat |
        Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Host ("  csv -> " + $Out) -ForegroundColor Green
}
