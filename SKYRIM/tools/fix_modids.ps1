#Requires -Version 5.1
<#
  fix_modids.ps1 - put the correct Nexus mod id in every mod's meta.ini.

    fix_modids.ps1                 report what is wrong
    fix_modids.ps1 -Apply          write the corrections
    fix_modids.ps1 -MissingOnly    only touch mods with no id at all (fast)

  WHY

  MO2 stores each mod's Nexus id in mods\<mod>\meta.ini as `modid=`. Anything
  that compares this install against a Nexus collection, or checks for updates,
  matches on that number. It was wrong in two different ways:

    modid=            UIExtensions - installed from a local archive, so nothing
                      ever knew the id
    modid=4           RaceMenu - whoever wrote it parsed the archive filename
                      and took the first number after the name. That is the
                      VERSION. The real id, 19080, sits further along:
                      RaceMenu Anniversary Edition v0-4-20-0-19080-0-4-20-0-...

  The second kind is the dangerous one: a blank id is visibly unknown, a wrong
  id silently matches a different mod.

  HOW IT DECIDES - AND WHY v1 WAS WRONG

  It MD5s the archive in the instance downloads folder and asks Nexus which
  mod that file belongs to. The trap: md5_search returns EVERY mod page
  hosting a byte-identical file, not one answer. v1 took the first result and
  duly overwrote SkyUI's correct 12604 with 181278 - the same id it also gave
  UIExtensions. Two mods resolving to one id is the signature of that bug.

  So the hash proposes and the FILENAME decides. MO2 records the archive as
  installationFile, and Nexus archive names carry the mod id:

    SkyUI-12604-6-11-1778020881.zip                      -> 12604
    RaceMenu Anniversary Edition v0-4-20-0-19080-0-...   -> 19080
    UIExtensions v1-2-0-17561-1-2-0.7z                   -> 17561

  Rule: if any candidate id also appears as a number in the filename, that is
  the id. If none does and there is exactly one candidate, use it. If none
  does and there are several, WRITE NOTHING and list them - an existing id is
  never overwritten by a guess, because a wrong id is worse than a blank one.

  Archives are hashed once each. Several hundred MB apiece means the full pass
  takes a few minutes; -MissingOnly skips everything that already has an id, at
  the cost of leaving wrong ones wrong.

  Nothing is written without -Apply, and every meta.ini it edits is backed up
  first.
#>

[CmdletBinding()]
param(
    [string]$Root       = 'X:\MODDING\SKYRIM',
    [string]$KeyFile,
    [switch]$MissingOnly,
    [switch]$Restore,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Instance = Join-Path $Root 'SKYRIM_SE'
$ModsDir  = Join-Path $Instance 'mods'
$Dloads   = Join-Path $Instance 'downloads'
$MlPath   = Join-Path $Instance 'profiles\Default\modlist.txt'
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8NoBom = New-Object Text.UTF8Encoding $false
if (-not $KeyFile) { $KeyFile = Join-Path $Root 'data\.nexus_api_key' }
$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' }

Write-Host ""
Write-Host "=== fix modids ($mode) ===" -ForegroundColor Cyan
Write-Host ""

foreach ($p in @($ModsDir, $MlPath, $KeyFile)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" }
}
$key = (Get-Content -LiteralPath $KeyFile -Raw).Trim()
if (-not $key) { throw "empty key file: $KeyFile" }

# ---- restore ---------------------------------------------------------------
# Undo a previous run wholesale. Newest backup per meta.ini, so repeated runs
# cannot walk backwards through a chain of half-corrected copies.
if ($Restore) {
    $n = 0
    foreach ($d in @(Get-ChildItem -LiteralPath $ModsDir -Directory -ErrorAction SilentlyContinue)) {
        $baks = @(Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match '^meta\.ini\.bak-\d{8}-\d{6}$' } |
                  Sort-Object Name -Descending)
        if (-not $baks.Count) { continue }
        $dest = Join-Path $d.FullName 'meta.ini'
        if ($Apply) { Copy-Item -LiteralPath $baks[0].FullName -Destination $dest -Force }
        Write-Host ("  {0}  <- {1}" -f $d.Name, $baks[0].Name)
        $n++
    }
    Write-Host ""
    if ($Apply) { Write-Host ("  {0} meta.ini restored." -f $n) -ForegroundColor Green }
    else        { Write-Host ("  {0} would be restored. Add -Apply." -f $n) -ForegroundColor Yellow }
    Write-Host ""
    return
}

$enabled = @()
foreach ($ln in @(Get-Content -LiteralPath $MlPath)) {
    if ($ln -match '^\+(.+)$') { $enabled += $Matches[1].TrimEnd() }
}
Write-Host ("  {0} enabled mod(s)" -f $enabled.Count)

$md5 = [Security.Cryptography.MD5]::Create()
$cache = @{}      # md5 -> lookup result, so duplicate archives cost one call
$rows  = New-Object System.Collections.Generic.List[object]

$i = 0
foreach ($mod in $enabled) {
    $i++
    $dir  = Join-Path $ModsDir $mod
    $meta = Join-Path $dir 'meta.ini'
    $cur  = $null; $inst = $null
    if (Test-Path -LiteralPath $meta) {
        foreach ($l in @(Get-Content -LiteralPath $meta)) {
            if ($l -match '^\s*modid\s*=\s*(.*)$')            { $cur  = $Matches[1].Trim() }
            if ($l -match '^\s*installationFile\s*=\s*(.*)$') { $inst = $Matches[1].Trim() }
        }
    }
    $curN = 0
    if ($cur -and ($cur -match '^\d+$')) { $curN = [int]$cur }

    if ($MissingOnly -and $curN -gt 0) {
        $rows.Add([pscustomobject]@{ Mod=$mod; Old=$curN; New=$curN; State='skipped'; Note='has an id, -MissingOnly' })
        continue
    }
    if (-not $inst) {
        $rows.Add([pscustomobject]@{ Mod=$mod; Old=$curN; New=0; State='no archive'; Note='meta.ini has no installationFile' })
        continue
    }
    $arc = Join-Path $Dloads $inst
    if (-not (Test-Path -LiteralPath $arc)) {
        $rows.Add([pscustomobject]@{ Mod=$mod; Old=$curN; New=0; State='no archive'; Note=$inst })
        continue
    }

    Write-Progress -Activity 'Hashing archives' -Status $mod -PercentComplete (100 * $i / $enabled.Count)
    $fs = [IO.File]::OpenRead($arc)
    try { $hash = ([BitConverter]::ToString($md5.ComputeHash($fs)) -replace '-','').ToLower() }
    finally { $fs.Dispose() }

    if ($cache.ContainsKey($hash)) {
        $res = $cache[$hash]
    } else {
        $u = "https://api.nexusmods.com/v1/games/skyrimspecialedition/mods/md5_search/$hash.json"
        try {
            $res = Invoke-RestMethod -Uri $u -Headers @{ apikey = $key } -TimeoutSec 60
        } catch {
            $res = $null
        }
        $cache[$hash] = $res
        Start-Sleep -Milliseconds 120     # be polite to the API
    }

    # EVERY candidate, not the first one. See the header.
    $cands = @()
    foreach ($m in @($res)) {
        if ($m.mod -and $m.mod.mod_id) {
            $cands += [pscustomobject]@{ Id = [int]$m.mod.mod_id; Name = [string]$m.mod.name }
        }
    }
    $cands = @($cands | Sort-Object Id -Unique)

    # numbers in the archive filename - the mod id is one of them
    $fileIds = @([regex]::Matches($inst, '(?<![\d.])(\d{2,7})(?![\d.])') |
                 ForEach-Object { [int]$_.Groups[1].Value })

    $newId = 0; $newName = ''; $why = ''
    $corroborated = @($cands | Where-Object { $fileIds -contains $_.Id })

    if ($corroborated.Count -ge 1) {
        $newId = $corroborated[0].Id; $newName = $corroborated[0].Name; $why = 'hash + filename'
    } elseif ($cands.Count -eq 1) {
        $newId = $cands[0].Id; $newName = $cands[0].Name; $why = 'single hash match'
    } elseif ($cands.Count -gt 1) {
        $why = ('ambiguous: ' + (($cands | ForEach-Object { $_.Id }) -join ', '))
    }

    $state = if     ($cands.Count -gt 1 -and $newId -eq 0) { 'ambiguous' }
             elseif ($newId -eq 0)                         { 'unknown' }
             elseif ($curN -eq 0)                          { 'FILL' }
             elseif ($curN -ne $newId)                     { 'WRONG' }
             else                                          { 'ok' }

    # An existing id is never replaced on a single unverified hash match. A
    # wrong id silently matches another mod; a blank one is visibly unknown.
    if ($state -eq 'WRONG' -and $why -ne 'hash + filename') {
        $state = 'unverified'; $why = ("hash says {0}, filename does not agree - left alone" -f $newId)
    }

    $rows.Add([pscustomobject]@{ Mod=$mod; Old=$curN; New=$newId; State=$state; Note=$(if ($why) { "$newName  ($why)" } else { $newName }) })
}
Write-Progress -Activity 'Hashing archives' -Completed

$fill  = @($rows | Where-Object { $_.State -eq 'FILL' })
$wrong = @($rows | Where-Object { $_.State -eq 'WRONG' })
$unk   = @($rows | Where-Object { $_.State -eq 'unknown' })
$amb   = @($rows | Where-Object { $_.State -eq 'ambiguous' })
$unv   = @($rows | Where-Object { $_.State -eq 'unverified' })
$noarc = @($rows | Where-Object { $_.State -eq 'no archive' })
$ok    = @($rows | Where-Object { $_.State -eq 'ok' })

Write-Host ""
Write-Host ("  correct already   {0}" -f $ok.Count)    -ForegroundColor Green
Write-Host ("  missing an id     {0}" -f $fill.Count)  -ForegroundColor Yellow
Write-Host ("  WRONG id          {0}" -f $wrong.Count) -ForegroundColor Red
Write-Host ("  archive gone      {0}" -f $noarc.Count) -ForegroundColor DarkGray
Write-Host ("  not on Nexus      {0}" -f $unk.Count)   -ForegroundColor DarkGray
Write-Host ("  ambiguous         {0}   (several mods host that exact file - not written)" -f $amb.Count) -ForegroundColor DarkGray
Write-Host ("  unverified        {0}   (hash disagrees with filename - left alone)" -f $unv.Count) -ForegroundColor DarkGray
Write-Host ""

foreach ($r in $wrong) { Write-Host ("  WRONG  {0,-52} {1} -> {2}   {3}" -f $r.Mod, $r.Old, $r.New, $r.Note) -ForegroundColor Red }
foreach ($r in $fill)  { Write-Host ("  FILL   {0,-52} {1} -> {2}   {3}" -f $r.Mod, '(none)', $r.New, $r.Note) -ForegroundColor Yellow }
foreach ($r in $noarc) { Write-Host ("  ---    {0,-52} archive not in downloads" -f $r.Mod) -ForegroundColor DarkGray }
foreach ($r in $unk)   { Write-Host ("  ---    {0,-52} Nexus does not know this file" -f $r.Mod) -ForegroundColor DarkGray }
foreach ($r in $amb)   { Write-Host ("  ?      {0,-52} {1}" -f $r.Mod, $r.Note) -ForegroundColor DarkGray }
foreach ($r in $unv)   { Write-Host ("  ?      {0,-52} keeping {1}; {2}" -f $r.Mod, $r.Old, $r.Note) -ForegroundColor DarkGray }
Write-Host ""

$todo = @($fill + $wrong)
if (-not $todo.Count) { Write-Host "  Nothing to change." -ForegroundColor Green; Write-Host ""; return }
if (-not $Apply) {
    Write-Host ("  {0} meta.ini file(s) would change. Re-run with -Apply." -f $todo.Count) -ForegroundColor Yellow
    Write-Host ""
    return
}

$done = 0
foreach ($r in $todo) {
    $meta = Join-Path (Join-Path $ModsDir $r.Mod) 'meta.ini'
    if (-not (Test-Path -LiteralPath $meta)) { continue }
    Copy-Item -LiteralPath $meta -Destination "$meta.bak-$Stamp" -Force
    $lines = @(Get-Content -LiteralPath $meta)
    $hit = $false
    $out = foreach ($l in $lines) {
        if ($l -match '^\s*modid\s*=') { $hit = $true; "modid=$($r.New)" } else { $l }
    }
    if (-not $hit) {
        # no modid line at all - put it after [General] so MO2 finds it
        $out = New-Object System.Collections.Generic.List[string]
        foreach ($l in $lines) {
            $out.Add($l)
            if ($l -match '^\s*\[General\]\s*$') { $out.Add("modid=$($r.New)") }
        }
        $out = $out.ToArray()
    }
    [IO.File]::WriteAllLines($meta, $out, $Utf8NoBom)
    $done++
}

# ---- verify by reading back ------------------------------------------------
$bad = 0
foreach ($r in $todo) {
    $meta = Join-Path (Join-Path $ModsDir $r.Mod) 'meta.ini'
    $got = 0
    foreach ($l in @(Get-Content -LiteralPath $meta)) {
        if ($l -match '^\s*modid\s*=\s*(\d+)\s*$') { $got = [int]$Matches[1]; break }
    }
    if ($got -ne $r.New) { $bad++; Write-Host ("  VERIFY FAIL {0}: reads {1}, wanted {2}" -f $r.Mod, $got, $r.New) -ForegroundColor Red }
}
if ($bad) { throw "$bad meta.ini file(s) did not take" }

Write-Host ("  {0} meta.ini file(s) corrected and verified. Backups: *.bak-{1}" -f $done, $Stamp) -ForegroundColor Green
Write-Host ""
