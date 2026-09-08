#Requires -Version 5.1
<#
  collection_diff.ps1 - what a Nexus collection runs that this install does not.

    collection_diff.ps1
    collection_diff.ps1 -Category gameplay,immersion,quests
    collection_diff.ps1 -Category '' -Out X:\MODDING\SKYRIM\logs\gts_all.txt
    collection_diff.ps1 -Dump          keep the raw API response

  Defaults to Gate To Sovngarde (slug qdurkx) filtered to the roleplay and
  reactivity categories. Any collection works: -Slug <slug>.

  WHY AN API AND NOT THE WEB PAGE

  A collection page renders its mod list in JavaScript, so fetching the HTML
  returns placeholders. The list only exists behind Nexus' v2 GraphQL endpoint,
  which takes the same personal API key already stored for nexus_get.ps1.

  HOW MODS ARE MATCHED

  Every mod folder MO2 created carries a meta.ini with `modid=`. That is the
  Nexus mod id, so the comparison is id against id - not names, which differ
  between the collection's title and whatever the archive happened to be
  called. Mods with modid=0 are manual or generated (BodySlide Output, DynDOLOD
  Output) and are skipped, because they have no Nexus identity to compare.

  IF THE QUERY BREAKS

  Nexus' GraphQL schema is not versioned in a way anything can rely on. If the
  request errors, the exact messages are printed and the raw response is saved
  to logs\ - and -QueryFile takes a replacement query without touching this
  script. It also checks the number of mods returned against the collection's
  own modCount and says so when they disagree, because a silently truncated
  page would look exactly like a short answer.
#>

[CmdletBinding()]
param(
    [string]$Root      = 'X:\MODDING\SKYRIM',
    [string]$Slug      = 'qdurkx',
    [string]$Game      = 'skyrimspecialedition',
    [string[]]$Category = @('gameplay','immersion','quests','npc','audio','user interface','miscellaneous'),
    [string]$Out       = 'X:\MODDING\SKYRIM\logs\collection_diff.txt',
    [string]$KeyFile,
    [string]$QueryFile,
    [switch]$Dump
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Instance = Join-Path $Root 'SKYRIM_SE'
$ModsDir  = Join-Path $Instance 'mods'
$MlPath   = Join-Path $Instance 'profiles\Default\modlist.txt'
$LogDir   = Join-Path $Root 'logs'
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $KeyFile) { $KeyFile = Join-Path $Root 'data\.nexus_api_key' }

Write-Host ""
Write-Host "=== collection diff : $Slug ===" -ForegroundColor Cyan
Write-Host ""

foreach ($p in @($MlPath, $ModsDir, $KeyFile)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" }
}
$key = (Get-Content -LiteralPath $KeyFile -Raw).Trim()
if (-not $key) { throw "empty key file: $KeyFile" }

# ---- what is installed -----------------------------------------------------
# modlist.txt line 1 is highest priority; '+' means enabled.
$enabled = @()
foreach ($ln in @(Get-Content -LiteralPath $MlPath)) {
    if ($ln -match '^\+(.+)$') { $enabled += $Matches[1].TrimEnd() }
}
$have    = @{}
$noId    = 0
foreach ($m in $enabled) {
    $meta = Join-Path (Join-Path $ModsDir $m) 'meta.ini'
    if (-not (Test-Path -LiteralPath $meta)) { $noId++; continue }
    $id = 0
    foreach ($l in @(Get-Content -LiteralPath $meta)) {
        if ($l -match '^\s*modid\s*=\s*(\d+)\s*$') { $id = [int]$Matches[1]; break }
    }
    if ($id -gt 0) { $have[$id] = $m } else { $noId++ }
}
Write-Host ("  installed  {0} enabled mod(s), {1} with a Nexus id, {2} without" -f $enabled.Count, $have.Count, $noId)

# ---- ask Nexus -------------------------------------------------------------
$defaultQuery = @'
query CollectionRevisionMods($slug: String!, $domain: String!) {
  collectionRevision(slug: $slug, domainName: $domain, viewAdultContent: true) {
    revisionNumber
    modCount
    collection { name slug }
    modFiles {
      optional
      file {
        version
        mod {
          modId
          name
          author
          endorsements
          adult
          modCategory { name }
        }
      }
    }
  }
}
'@
$query = if ($QueryFile) {
    if (-not (Test-Path -LiteralPath $QueryFile)) { throw "not found: $QueryFile" }
    Get-Content -LiteralPath $QueryFile -Raw
} else { $defaultQuery }

$body = @{
    query     = $query
    variables = @{ slug = $Slug; domain = $Game }
} | ConvertTo-Json -Depth 6 -Compress

Write-Host "  querying   https://api.nexusmods.com/v2/graphql"
$raw = $null
try {
    $raw = Invoke-RestMethod -Uri 'https://api.nexusmods.com/v2/graphql' -Method Post `
             -Headers @{ apikey = $key; 'Application-Name' = 'SkyrimDLSS5Setup'; 'Application-Version' = '1.0' } `
             -ContentType 'application/json' -Body $body -TimeoutSec 120
} catch {
    throw ("the API call failed: {0}`n  If this is 401, the key in {1} is wrong. Anything else, re-run with -Dump." -f $_.Exception.Message, $KeyFile)
}

if ($Dump -or $raw.errors) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $dp = Join-Path $LogDir ("collection_raw_{0}.json" -f $Stamp)
    [IO.File]::WriteAllText($dp, ($raw | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding $false))
    Write-Host ("  raw        {0}" -f $dp) -ForegroundColor DarkGray
}
if ($raw.errors) {
    Write-Host ""
    Write-Host "  the API returned errors:" -ForegroundColor Red
    foreach ($e in $raw.errors) { Write-Host ("      {0}" -f $e.message) -ForegroundColor Red }
    throw "GraphQL rejected the query. The schema moved - send me the messages above and I will hand back a -QueryFile."
}

$rev = $raw.data.collectionRevision
if (-not $rev) { throw "no collectionRevision in the response. Wrong slug '$Slug' or wrong game '$Game'? Re-run with -Dump." }

$files = @($rev.modFiles)
Write-Host ("  collection '{0}'  revision {1}" -f $rev.collection.name, $rev.revisionNumber) -ForegroundColor Green
Write-Host ("  returned   {0} mod file(s), collection reports modCount {1}" -f $files.Count, $rev.modCount)
if ($rev.modCount -and $files.Count -lt $rev.modCount) {
    # Say it out loud. A truncated page and a short collection look identical.
    Write-Host ("  WARNING: {0} fewer than modCount - the response may be paginated and this diff incomplete." -f ($rev.modCount - $files.Count)) -ForegroundColor Yellow
}

# ---- shape it --------------------------------------------------------------
$rows = New-Object System.Collections.Generic.List[object]
$seen = @{}
foreach ($f in $files) {
    $mod = $f.file.mod
    if (-not $mod -or -not $mod.modId) { continue }
    $id = [int]$mod.modId
    if ($seen.ContainsKey($id)) { continue }
    $seen[$id] = $true
    $rows.Add([pscustomobject]@{
        Id       = $id
        Name     = [string]$mod.name
        Author   = [string]$mod.author
        Cat      = $(if ($mod.modCategory -and $mod.modCategory.name) { [string]$mod.modCategory.name } else { '(uncategorised)' })
        Endorse  = [int]$mod.endorsements
        Adult    = [bool]$mod.adult
        Optional = [bool]$f.optional
        Have     = $have.ContainsKey($id)
    })
}

$catFilter = @($Category | Where-Object { $_ -and $_.Trim() })
$inScope = if ($catFilter.Count) {
    @($rows | Where-Object { $r = $_; ($catFilter | Where-Object { $r.Cat -like "*$_*" }).Count -gt 0 })
} else { $rows }

$missing = @($inScope | Where-Object { -not $_.Have } |
            Sort-Object @{Expression='Cat'}, @{Expression='Endorse'; Descending=$true})
$shared  = @($inScope | Where-Object { $_.Have })

Write-Host ""
Write-Host ("  {0} unique mod(s) in the collection" -f $rows.Count)
Write-Host ("  {0} in the chosen categories, {1} already installed, {2} NOT installed" -f $inScope.Count, $shared.Count, $missing.Count)
Write-Host ""

# ---- report ----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path (Split-Path $Out -Parent) | Out-Null
$w = New-Object System.Collections.Generic.List[string]
$w.Add(("Collection diff - {0} (revision {1})" -f $rev.collection.name, $rev.revisionNumber))
$w.Add((Get-Date -Format 'yyyy-MM-dd HH:mm'))
$w.Add(("https://www.nexusmods.com/games/{0}/collections/{1}" -f $Game, $Slug))
$w.Add('')
$w.Add(("categories: {0}" -f $(if ($catFilter.Count) { $catFilter -join ', ' } else { 'ALL' })))
$w.Add(("collection {0} unique mods, {1} in scope" -f $rows.Count, $inScope.Count))
$w.Add(("installed here: {0} of those; MISSING: {1}" -f $shared.Count, $missing.Count))
if ($rev.modCount -and $files.Count -lt $rev.modCount) {
    $w.Add(("WARNING: API returned {0} of {1} - this diff may be incomplete." -f $files.Count, $rev.modCount))
}
$w.Add('')
$w.Add('NOT INSTALLED, by category, most endorsed first')
$w.Add('  * = optional in the collection   [A] = adult-flagged')
$w.Add('')
$lastCat = ''
foreach ($r in $missing) {
    if ($r.Cat -ne $lastCat) { $w.Add(''); $w.Add(("--- {0} ---" -f $r.Cat)); $lastCat = $r.Cat }
    $w.Add(("{0,8}  {1,-7} {2}{3}{4}" -f $r.Endorse, $r.Id, $r.Name,
            $(if ($r.Optional) { ' *' } else { '' }), $(if ($r.Adult) { ' [A]' } else { '' })))
    $w.Add(("          {0,-7} by {1}" -f '', $r.Author))
    $w.Add(("          https://www.nexusmods.com/{0}/mods/{1}" -f $Game, $r.Id))
}
$w.Add('')
$w.Add('ALREADY INSTALLED - overlap with this collection')
$w.Add('')
foreach ($r in ($shared | Sort-Object Cat, Name)) {
    $w.Add(("  {0,-7} {1,-22} {2}" -f $r.Id, $r.Cat, $r.Name))
}
[IO.File]::WriteAllLines($Out, $w, (New-Object Text.UTF8Encoding $false))

Write-Host ("  report written: {0}   ({1} lines)" -f $Out, $w.Count) -ForegroundColor Green
Write-Host ""
$top = @($missing | Sort-Object Endorse -Descending | Select-Object -First 12)
if ($top.Count) {
    Write-Host "  most endorsed things you do not have, in scope:"
    foreach ($t in $top) { Write-Host ("      {0,8}  {1,-7} {2}  [{3}]" -f $t.Endorse, $t.Id, $t.Name, $t.Cat) }
    Write-Host ""
}
