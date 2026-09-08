#Requires -Version 5.1
<#
  toggle_mods.ps1 - turn mods off and on without clicking, for bisecting a crash.

    toggle_mods.ps1 -Off "Better Third Person"          show what it would do
    toggle_mods.ps1 -Off "Better Third Person" -Apply   do it
    toggle_mods.ps1 -On  "Better Third Person" -Apply   put them back
    toggle_mods.ps1 -List                               show what is currently off

  Names are matched as substrings, case-insensitive, so one word is usually
  enough. Every match is printed before anything is written.

  WHY IT TOUCHES plugins.txt TOO

  Disabling a mod in modlist.txt makes its files vanish from the virtual
  filesystem, but plugins.txt would still list any plugin it supplied. Skyrim
  then has an entry pointing at a file that is not there. So this scans each
  affected mod folder for .esp/.esm/.esl and removes those lines as well, and
  re-adds them on the way back. That is exactly what MO2 does for you when you
  tick the box, and skipping it is how you end up chasing a second fault that
  you caused yourself while chasing the first.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [string[]]$Off,
    [string[]]$On,
    [switch]$List,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$Instance  = Join-Path $Root 'SKYRIM_SE'
$ModsDir   = Join-Path $Instance 'mods'
$ProfileD  = Join-Path $Instance 'profiles\Default'
$MlPath    = Join-Path $ProfileD 'modlist.txt'
$PlPath    = Join-Path $ProfileD 'plugins.txt'
$LoPath    = Join-Path $ProfileD 'loadorder.txt'
$Utf8NoBom = New-Object Text.UTF8Encoding $false

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. It rewrites these files from memory on exit. Close it and re-run."
}
foreach ($f in @($MlPath, $PlPath, $LoPath)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "not found: $f" }
}

$ml = @(Get-Content -LiteralPath $MlPath)

if ($List) {
    $offNow = @($ml | Where-Object { $_ -match '^-' } | ForEach-Object { $_.Substring(1) })
    Write-Host ""
    Write-Host ("=== {0} mod(s) currently OFF ===" -f $offNow.Count) -ForegroundColor Cyan
    foreach ($o in $offNow) { Write-Host ("   {0}" -f $o) }
    Write-Host ""
    return
}
if (-not $Off -and -not $On) { throw "pass -Off <name...>, -On <name...>, or -List" }

# ---- find the lines each name matches --------------------------------------
function Find-Lines {
    param([string[]]$Names, [char]$WantPrefix)
    $hits = New-Object System.Collections.Generic.List[object]
    foreach ($n in @($Names)) {
        $found = $false
        for ($i = 0; $i -lt $ml.Count; $i++) {
            if ($ml[$i] -notmatch '^[+\-](.+)$') { continue }
            $modName = $Matches[1].TrimEnd()
            if ($modName -notlike "*$n*") { continue }
            $found = $true
            $cur = $ml[$i].Substring(0,1)
            $hits.Add([pscustomobject]@{ Index = $i; Name = $modName; Cur = $cur; Skip = ($cur -eq $WantPrefix) })
        }
        if (-not $found) { Write-Host ("  no mod matches '{0}'" -f $n) -ForegroundColor Yellow }
    }
    # ToArray, not the List itself. Returning a List lets the pipeline unroll it,
    # and with exactly ONE match the caller gets a bare object rather than an
    # array - which has no .Count, so the "did anything match" guard read it as
    # zero and reported "Nothing matched" on a perfectly good match. Two matches
    # worked, which is why the test passed.
    # Plain ToArray, no comma-wrap. ,@() would hand back a one-element array
    # CONTAINING an empty array, which passes the emptiness guard and then
    # indexes modlist with a null - so "no match" turned into a crash instead
    # of a message. @() at the call site is what normalises 0/1/many.
    return $hits.ToArray()
}

$want = if ($Off) { '-' } else { '+' }
$names = if ($Off) { $Off } else { $On }
$hits  = @(Find-Lines $names $want)
if (-not $hits.Count) { Write-Host ""; Write-Host "Nothing matched." -ForegroundColor Yellow; Write-Host ""; return }

$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' }
Write-Host ""
Write-Host ("=== turning mods {0} ({1}) ===" -f $(if ($Off) { 'OFF' } else { 'ON' }), $mode) -ForegroundColor Cyan
Write-Host ""

# ---- what plugins do those mods supply? ------------------------------------
$plugins = New-Object System.Collections.Generic.List[string]
foreach ($h in $hits) {
    $dir = Join-Path $ModsDir $h.Name
    $ps = @()
    if (Test-Path -LiteralPath $dir) {
        $ps = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension.ToLower() -in @('.esp','.esm','.esl') } |
                ForEach-Object { $_.Name })
    }
    foreach ($p in $ps) { $plugins.Add($p) }
    $state = if ($h.Skip) { 'already there, no change' } else { "$($h.Cur) -> $want" }
    Write-Host ("  {0,-52} {1}" -f $h.Name, $state) -ForegroundColor $(if ($h.Skip) { 'DarkGray' } else { 'Green' })
    foreach ($p in $ps) { Write-Host ("      plugin: {0}" -f $p) -ForegroundColor DarkGray }
}

$todo = @($hits | Where-Object { -not $_.Skip })
if (-not $todo.Count) {
    Write-Host ""
    Write-Host "Everything matched is already in that state." -ForegroundColor Yellow
    Write-Host ""
    return
}
if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing written. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ---- write ------------------------------------------------------------------
foreach ($f in @($MlPath, $PlPath, $LoPath)) { Copy-Item -LiteralPath $f -Destination "$f.bak-$Stamp" -Force }

foreach ($h in $todo) { $ml[$h.Index] = $want + $h.Name }
[IO.File]::WriteAllLines($MlPath, $ml, $Utf8NoBom)

$pl = @(Get-Content -LiteralPath $PlPath)
$lo = @(Get-Content -LiteralPath $LoPath)
$names2 = @($plugins | Select-Object -Unique)

if ($want -eq '-') {
    $pl = @($pl | Where-Object { $l = $_ -replace '^\*',''; $names2 -notcontains $l.Trim() })
    $lo = @($lo | Where-Object { $names2 -notcontains $_.Trim() })
} else {
    foreach ($p in $names2) {
        if (-not (@($pl | ForEach-Object { $_ -replace '^\*','' }) -contains $p)) { $pl += "*$p" }
        if ($lo -notcontains $p) { $lo += $p }
    }
}
[IO.File]::WriteAllLines($PlPath, $pl, $Utf8NoBom)
[IO.File]::WriteAllLines($LoPath, $lo, $Utf8NoBom)

Write-Host ""
Write-Host ("written. {0} mod(s) flipped, {1} plugin line(s) adjusted." -f $todo.Count, $names2.Count) -ForegroundColor Green
Write-Host ("backups: *.bak-{0}" -f $Stamp) -ForegroundColor DarkGray
Write-Host ""
Write-Host "Launch SKSE straight from MO2. No need to open and close it first -" -ForegroundColor Cyan
Write-Host "nothing new is being introduced, only hidden."
Write-Host ""
