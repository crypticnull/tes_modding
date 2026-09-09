#Requires -Version 5.1
<#
  prechain_check.ps1 - the last gate before the generation chain.

    X:\MODDING\SKYRIM\tools\prechain_check.ps1

  WHY THIS EXISTS

  The chain is hours, not minutes, once Seasons multiplies the terrain pass by
  five. Everything it consumes has to be correct BEFORE it starts, because a
  mod added afterwards costs the whole run again. This is the one place that
  asks every question at once instead of relying on remembering to run six
  scripts.

  It runs the existing checks, then adds the ones nothing else covers:

    - EMPTY MOD FOLDERS. A FOMOD whose groups are all optional installs zero
      files and reports ok. That happened twice on 9 September, Hidden Hideouts
      and Missives Worldspace. An enabled mod with no files is always a bug.
    - WRONG-LANGUAGE ARCHIVES. Project AHO shipped (RU) as its primary file and
      installed silently. VIGILANT and Animated Ships list Japanese first in
      their FOMODs. Nothing downstream can see this, so the filename is checked.
    - ZERO-BYTE PROFILE FILES. The archives.txt signature, see section 6.
    - PLUGIN BUDGET, counting only non-ESL plugins against the 254 limit.
    - STALE LOD, meaning DynDOLOD output older than the newest world mod.

  Report only. Changes nothing. Exit 1 if anything would waste a chain run.
#>
[CmdletBinding()]
param([string]$Root = 'X:\MODDING\SKYRIM', [string]$ProfileName = 'Default')

$ErrorActionPreference = 'Stop'
$Inst = Join-Path $Root 'SKYRIM_SE'
$Prof = Join-Path $Inst ("profiles\{0}" -f $ProfileName)
$Mods = Join-Path $Inst 'mods'
$fail = 0

function Head($t) { Write-Host ""; Write-Host ("=== " + $t + " ===") -ForegroundColor Cyan }

Head 'profile integrity'
foreach ($f in 'archives.txt','loadorder.txt','plugins.txt','modlist.txt') {
    $p = Join-Path $Prof $f
    if (-not (Test-Path -LiteralPath $p)) { Write-Host ("  MISSING  " + $f) -ForegroundColor Red; $script:fail++; continue }
    $len = (Get-Item -LiteralPath $p).Length
    if ($len -eq 0) { Write-Host ("  EMPTY    {0}  <- interrupted write, restore from git" -f $f) -ForegroundColor Red; $script:fail++ }
    else { "  ok       {0,-16} {1:N0} bytes" -f $f, $len }
    $b = [IO.File]::ReadAllBytes($p)
    if ($b.Length -ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191) {
        Write-Host ("  BOM      {0}  <- MO2 cannot read this" -f $f) -ForegroundColor Red; $script:fail++
    }
}

Head 'enabled mods that installed EMPTY'
$enabled = @(Get-Content (Join-Path $Prof 'modlist.txt') | Where-Object { $_ -match '^\+' } | ForEach-Object { $_.Substring(1) })
$empty = @()
foreach ($n in $enabled) {
    $d = Join-Path $Mods $n
    if (-not (Test-Path -LiteralPath $d)) { continue }
    $n2 = @(Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'meta.ini' }).Count
    if ($n2 -eq 0) { $empty += $n }
}
if ($empty.Count) { $empty | ForEach-Object { Write-Host ("  EMPTY  " + $_) -ForegroundColor Red }; $script:fail += $empty.Count }
else { Write-Host "  none" -ForegroundColor Green }

Head 'wrong-language archives'
$lang = @()
foreach ($n in $enabled) {
    $mi = Join-Path (Join-Path $Mods $n) 'meta.ini'
    if (-not (Test-Path -LiteralPath $mi)) { continue }
    foreach ($l in (Get-Content -LiteralPath $mi)) {
        if ($l -match '(?i)^installationFile=.*(\(RU\)|_RU_|Russian|Japanese|\(JP\)|Chinese|\(CN\)|German|\(DE\)|French|\(FR\)|Polish|Spanish|Italian)') { $lang += "{0}  ->  {1}" -f $n, ($l -replace '^installationFile=','') }
    }
}
if ($lang.Count) { $lang | ForEach-Object { Write-Host ("  CHECK  " + $_) -ForegroundColor Yellow } }
else { Write-Host "  none" -ForegroundColor Green }

Head 'plugin budget'
$act = @(Get-Content (Join-Path $Prof 'plugins.txt') | Where-Object { $_ -match '^\*' } | ForEach-Object { $_.Substring(1) })
$map = @{}
foreach ($d in (Get-ChildItem -LiteralPath $Mods -Directory -ErrorAction SilentlyContinue)) {
    foreach ($f in (Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue)) {
        if ($f.Extension -match '^\.es[pml]$' -and -not $map.ContainsKey($f.Name)) { $map[$f.Name] = $f.FullName }
    }
}
$reg = 0; $esl = 0
foreach ($p in $act) {
    if ($p -match '\.esl$') { $esl++; continue }
    if (-not $map.ContainsKey($p)) { continue }
    $b = [IO.File]::ReadAllBytes($map[$p])[0..23]
    if ([BitConverter]::ToUInt32($b, 8) -band 0x200) { $esl++ } else { $reg++ }
}
"  active        {0}" -f $act.Count
"  ESL-flagged   {0}   (free)" -f $esl
$col = if ($reg -ge 254) { 'Red' } elseif ($reg -gt 220) { 'Yellow' } else { 'Green' }
Write-Host ("  regular       {0}  of 254, {1} spare" -f $reg, (254 - $reg)) -ForegroundColor $col
if ($reg -ge 254) { $script:fail++ }

Head 'is the LOD stale? (it should be - the chain has not run yet)'
$dd = Join-Path $Mods 'DynDOLOD Output'
if (Test-Path -LiteralPath $dd) {
    $ddT = (Get-Item -LiteralPath $dd).LastWriteTime
    "  DynDOLOD Output   {0:yyyy-MM-dd HH:mm}" -f $ddT
    $newer = @(Get-ChildItem -LiteralPath $Mods -Directory | Where-Object { $_.LastWriteTime -gt $ddT -and $enabled -contains $_.Name })
    Write-Host ("  {0} enabled mod(s) are NEWER than the LOD" -f $newer.Count) -ForegroundColor $(if ($newer.Count) { 'Yellow' } else { 'Green' })
    $newer | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object { "      {0:MM-dd HH:mm}  {1}" -f $_.LastWriteTime, $_.Name }
    if ($newer.Count -gt 5) { "      ... and {0} more" -f ($newer.Count - 5) }
}

Head 'the other checks'
# These have to FAIL this script, not just print. On the first run this said
# "PRE-CHAIN: clear" while check_masters was reporting 13 missing masters
# underneath it, which is the section 6 lesson happening inside the tool
# written to prevent it. Parse the counts and treat them as results.
foreach ($s in 'check_masters.ps1','check_order.ps1','runtime_check.ps1') {
    $p = Join-Path $Root ("tools\" + $s)
    if (-not (Test-Path -LiteralPath $p)) { continue }
    Write-Host ("  -- " + $s) -ForegroundColor Yellow
    $out = (& $p *>&1 | Out-String)

    $mm = [regex]::Match($out, 'missing master\s+(\d+)')
    if ($mm.Success -and [int]$mm.Groups[1].Value -gt 0) {
        # stale DynDOLOD and Occlusion are EXPECTED before the chain runs, and
        # a deliberately disabled plugin cannot load, so neither is a failure.
        $real = @()
        foreach ($l in ($out -split "`n")) {
            if ($l -notmatch '^\s+(\S+\.es[pml])\s+needs\s+(.+?)\s*$') { continue }
            $dep = $Matches[1]
            if ($dep -match '^(DynDOLOD|Occlusion)\.esp$') { continue }
            if ($out -match [regex]::Escape($dep) + '\s+<- THIS PLUGIN ITSELF is off') { continue }
            $real += $l.Trim()
        }
        if ($real.Count) {
            Write-Host ("      {0} REAL missing master(s):" -f $real.Count) -ForegroundColor Red
            $real | Select-Object -First 10 | ForEach-Object { Write-Host ("        " + $_) -ForegroundColor Red }
            $script:fail += $real.Count
        } else { Write-Host '      missing masters: only the stale LOD, expected' -ForegroundColor Green }
    } else { Write-Host '      missing masters: none' -ForegroundColor Green }

    $oo = [regex]::Match($out, 'loads out of order\s+(\d+)')
    if ($oo.Success) { Write-Host ("      out of order: {0}  <- LOOT sort needed" -f $oo.Groups[1].Value) -ForegroundColor Yellow; $script:fail++ }

    $v = [regex]::Match($out, 'violations\s+(\d+)')
    if ($v.Success) {
        $n = [int]$v.Groups[1].Value
        Write-Host ("      order violations: {0}" -f $n) -ForegroundColor $(if ($n) { 'Red' } else { 'Green' })
        $script:fail += $n
    }
    $wr = [regex]::Match($out, 'wrong runtime\s+(\d+)')
    if ($wr.Success) {
        $n = [int]$wr.Groups[1].Value
        Write-Host ("      wrong runtime: {0}" -f $n) -ForegroundColor $(if ($n) { 'Red' } else { 'Green' })
        $script:fail += $n
    }
}

Write-Host ""
if ($fail) { Write-Host ("PRE-CHAIN: {0} problem(s). Fix before running the chain." -f $fail) -ForegroundColor Red; exit 1 }
Write-Host "PRE-CHAIN: clear." -ForegroundColor Green
