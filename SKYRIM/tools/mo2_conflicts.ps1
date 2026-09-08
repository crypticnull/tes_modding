#Requires -Version 5.1
<#
  mo2_conflicts.ps1 - who overwrites whom, without opening MO2.

    mo2_conflicts.ps1 -Mod 'Bijin Wives SE'
    mo2_conflicts.ps1 -Mod 'Bijin Wives SE' -Under 'textures\actors\character\facegendata'
    mo2_conflicts.ps1 -Mod 'Bijin Wives SE' -Filter 'facegen'
    mo2_conflicts.ps1 -Mod 'Bijin Wives SE' -ShowWins
    mo2_conflicts.ps1 -File 'meshes\clothes\farmclothes04\robef_0.nif'

  WHAT MO2 ACTUALLY DOES

  Every enabled mod is a folder whose contents are overlaid onto Data. When two
  mods contain the same relative path, the one HIGHER in the left pane wins and
  the game never sees the other. modlist.txt stores that order with the FIRST
  line as HIGHEST priority, so priority is just line number - lower wins.

  That is the whole model, which is why this does not need MO2 running.

  HOW IT WORKS, AND WHY IT IS FAST

  It enumerates only the target mod, then asks Test-Path for each of those
  relative paths inside every other enabled mod. Walking all 118 mod trees
  would mean well over a million files; this is one walk plus a few thousand
  stats. On a mod with tens of thousands of files it will still be slow, so
  -Under restricts the walk to one subtree and -Filter to a regex.

  WHAT IT CANNOT SEE

  Plugin record conflicts. A black face, a wrong outfit or a missing spell is
  usually two plugins editing the same RECORD, not two mods shipping the same
  FILE. This tool answers the file half only. If it reports nothing, the
  problem is in the plugins and that needs xEdit.
#>

[CmdletBinding()]
param(
    [string]$Root   = 'X:\MODDING\SKYRIM',
    [string]$Mod,
    [string]$File,
    [string]$Under,
    [string]$Filter,
    [switch]$ShowWins,
    [string]$Out
)

$ErrorActionPreference = 'Stop'

$Instance = Join-Path $Root 'SKYRIM_SE'
$ModsDir  = Join-Path $Instance 'mods'
$MlPath   = Join-Path $Instance 'profiles\Default\modlist.txt'
foreach ($p in @($ModsDir, $MlPath)) { if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" } }
if (-not $Mod -and -not $File) { throw "give -Mod <name> or -File <relative path>" }

# modlist.txt: first line highest priority. Index 0 = wins everything.
$enabled = @(Get-Content -LiteralPath $MlPath |
             Where-Object { $_ -match '^\+(.+)$' } |
             ForEach-Object { $Matches[1].TrimEnd() })
$prio = @{}
for ($i = 0; $i -lt $enabled.Count; $i++) { $prio[$enabled[$i]] = $i }

function Show-Line { param([string]$t, [string]$c = 'Gray') Write-Host $t -ForegroundColor $c }

# ---- -File: who provides this one path, in priority order -------------------
if ($File) {
    $rel = $File.TrimStart('\')
    Write-Host ""
    Show-Line ("=== {0} ===" -f $rel) 'Cyan'
    $hits = @()
    foreach ($m in $enabled) {
        $full = Join-Path (Join-Path $ModsDir $m) $rel
        if (Test-Path -LiteralPath $full) {
            $fi = Get-Item -LiteralPath $full
            $hits += [pscustomobject]@{ Prio = $prio[$m]; Mod = $m; Size = $fi.Length; When = $fi.LastWriteTime }
        }
    }
    if (-not $hits.Count) { Show-Line "  no enabled mod provides this path" 'Yellow'; Write-Host ""; return }
    $i = 0
    foreach ($h in ($hits | Sort-Object Prio)) {
        $tag = if ($i -eq 0) { 'WINS  ' } else { 'hidden' }
        $col = if ($i -eq 0) { 'Green' } else { 'DarkGray' }
        Show-Line ("  {0}  [{1,4}]  {2,-52} {3,10} bytes  {4:yyyy-MM-dd HH:mm}" -f `
                   $tag, $h.Prio, $h.Mod, $h.Size, $h.When) $col
        $i++
    }
    Write-Host ""
    return
}

# ---- -Mod: what this mod loses and wins -------------------------------------
$modDir = Join-Path $ModsDir $Mod
if (-not (Test-Path -LiteralPath $modDir)) {
    $near = @($enabled | Where-Object { $_ -like "*$Mod*" })
    if ($near.Count) { throw ("no mod folder '{0}'. Did you mean: {1}" -f $Mod, ($near -join ' / ')) }
    throw "no mod folder '$Mod' under $ModsDir"
}
if (-not $prio.ContainsKey($Mod)) { throw "'$Mod' is not enabled in modlist.txt" }

$scanRoot = if ($Under) { Join-Path $modDir $Under.TrimStart('\') } else { $modDir }
if (-not (Test-Path -LiteralPath $scanRoot)) { throw "not found inside the mod: $Under" }

$files = @(Get-ChildItem -LiteralPath $scanRoot -Recurse -File -Force -ErrorAction SilentlyContinue)
$rels  = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
    $r = $f.FullName.Substring($modDir.Length).TrimStart('\', '/')
    if ($r -eq 'meta.ini') { continue }
    if ($Filter -and $r -notmatch $Filter) { continue }
    $rels.Add($r)
}

Write-Host ""
Show-Line ("=== {0} ===" -f $Mod) 'Cyan'
Show-Line ("  priority {0} of {1}   (0 = wins everything)" -f $prio[$Mod], $enabled.Count)
Show-Line ("  {0} file(s) in scope{1}{2}" -f $rels.Count,
           $(if ($Under)  { " under $Under" } else { '' }),
           $(if ($Filter) { " matching /$Filter/" } else { '' }))
if ($rels.Count -gt 20000) {
    Show-Line "  that is a lot of files - this will take a while. -Under or -Filter narrows it." 'Yellow'
}

$me    = $prio[$Mod]
$loses = New-Object System.Collections.Generic.List[object]
$wins  = New-Object System.Collections.Generic.List[object]

foreach ($m in $enabled) {
    if ($m -eq $Mod) { continue }
    $other = Join-Path $ModsDir $m
    $isHigher = $prio[$m] -lt $me
    foreach ($r in $rels) {
        if (Test-Path -LiteralPath (Join-Path $other $r)) {
            if ($isHigher) { $loses.Add([pscustomobject]@{ Rel = $r; Other = $m; Prio = $prio[$m] }) }
            else           { $wins.Add( [pscustomobject]@{ Rel = $r; Other = $m; Prio = $prio[$m] }) }
        }
    }
}

# Only the single highest-priority overwriter actually matters per file.
$lostBy = @{}
foreach ($l in ($loses | Sort-Object Prio)) { if (-not $lostBy.ContainsKey($l.Rel)) { $lostBy[$l.Rel] = $l } }

Write-Host ""
if ($lostBy.Count) {
    Show-Line ("  OVERWRITTEN - {0} file(s) of this mod never reach the game:" -f $lostBy.Count) 'Red'
    foreach ($g in @($lostBy.Values | Group-Object Other | Sort-Object Count -Descending)) {
        Show-Line ("    {0,5}  <-  {1}  [priority {2}]" -f $g.Count, $g.Name, $g.Group[0].Prio) 'Red'
        foreach ($e in @($g.Group | Select-Object -First 12)) { Show-Line ("            {0}" -f $e.Rel) 'DarkGray' }
        if ($g.Count -gt 12) { Show-Line ("            ... {0} more" -f ($g.Count - 12)) 'DarkGray' }
    }
} else {
    Show-Line "  nothing of this mod is overwritten by a higher-priority mod" 'Green'
}

if ($ShowWins) {
    $wonOver = @($wins | Group-Object Other | Sort-Object Count -Descending)
    Write-Host ""
    Show-Line ("  this mod hides {0} file(s) belonging to {1} lower mod(s):" -f $wins.Count, $wonOver.Count)
    foreach ($g in $wonOver) { Show-Line ("    {0,5}  ->  {1}  [priority {2}]" -f $g.Count, $g.Name, $g.Group[0].Prio) }
}

Write-Host ""
Show-Line "  Note: this is the FILE half only. Plugin record conflicts - the usual" 'DarkGray'
Show-Line "  cause of a black face or a wrong outfit - are invisible here." 'DarkGray'
Write-Host ""

if ($Out) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("MO2 file conflicts for '$Mod'")
    $lines.Add((Get-Date -Format 'yyyy-MM-dd HH:mm'))
    $lines.Add(("priority {0} of {1}; {2} file(s) in scope" -f $prio[$Mod], $enabled.Count, $rels.Count))
    $lines.Add("")
    $lines.Add("OVERWRITTEN")
    foreach ($e in @($lostBy.Values | Sort-Object Rel)) { $lines.Add(("  {0}   <-  {1}" -f $e.Rel, $e.Other)) }
    if ($ShowWins) {
        $lines.Add("")
        $lines.Add("HIDES")
        foreach ($e in @($wins | Sort-Object Rel)) { $lines.Add(("  {0}   ->  {1}" -f $e.Rel, $e.Other)) }
    }
    $outDir = Split-Path $Out -Parent
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    [IO.File]::WriteAllLines($Out, $lines, (New-Object Text.UTF8Encoding $false))
    Show-Line ("  report written: {0}" -f $Out) 'Green'
    Write-Host ""
}
