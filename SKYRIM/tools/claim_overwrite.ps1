#Requires -Version 5.1
<#
  claim_overwrite.ps1 - turn MO2's Overwrite folder into a normal mod.

    X:\MODDING\SKYRIM\tools\claim_overwrite.ps1            report
    X:\MODDING\SKYRIM\tools\claim_overwrite.ps1 -Apply     do it

  This is exactly what right-click Overwrite -> Create Mod does in the MO2
  interface. It moves the loose files into mods\<name>\ and adds a line to
  modlist.txt. Nothing clever.

  WHY BOTHER AT ALL

  Overwrite already works - MO2 loads it above every mod. The problem is that it
  is a shared bin: the next tool you run through MO2 that writes an unowned file
  drops it in there too, mixed in with your BodySlide morphs, and then there is
  no way to tell whose is whose or to turn one off without turning off the other.

  WHAT IT MOVES

  By default ONLY meshes\ - that is all BodySlide writes. Everything else in
  Overwrite stays put, because Overwrite is a shared bin and the other things
  in it belong to other tools:

    CalienteTools   BodySlide's own log. It wants to keep writing there.
    ShaderCache     Community Shaders' compiled shaders. Sweeping this into a
                    mod named 'BodySlide Output' means disabling that mod one
                    day silently throws away the shader cache.
    SKSE            co-save and plugin logs.

  -All restores the old behaviour: move everything except CalienteTools. Use it
  only when you have looked at what is actually in Overwrite first.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [string]$Name = 'BodySlide Output',
    [string[]]$Only = @('meshes'),
    [switch]$All,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$Instance  = Join-Path $Root 'SKYRIM_SE'
$Over      = Join-Path $Instance 'overwrite'
$ModsDir   = Join-Path $Instance 'mods'
$ProfileD  = Join-Path $Instance 'profiles\Default'
$MlPath    = Join-Path $ProfileD 'modlist.txt'
$Dest      = Join-Path $ModsDir $Name
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$Keep      = @('CalienteTools')   # never moved, even with -All
$mode      = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to do it' }

Write-Host ""
Write-Host "=== claim overwrite ($mode) ===" -ForegroundColor Cyan
Write-Host ""

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. It rewrites modlist.txt from memory on exit, so it would undo this. Close it and re-run."
}
if (-not (Test-Path -LiteralPath $Over))   { throw "not found: $Over" }
if (-not (Test-Path -LiteralPath $MlPath)) { throw "not found: $MlPath" }

$top = @(Get-ChildItem -LiteralPath $Over -Force -ErrorAction SilentlyContinue)
if ($All) {
    $move = @($top | Where-Object { $Keep -notcontains $_.Name })
} else {
    # Allowlist, not a blocklist. A blocklist means every tool that later writes
    # something unowned into Overwrite gets swept into this mod without anyone
    # noticing - which is how Community Shaders' ShaderCache would have ended up
    # inside 'BodySlide Output'.
    $move = @($top | Where-Object { $Only -contains $_.Name -and $Keep -notcontains $_.Name })
}
$stay = @($top | Where-Object { $move -notcontains $_ })

if (-not $move.Count) {
    Write-Host ("  Nothing to claim - Overwrite has no {0}." -f ($Only -join ', ')) -ForegroundColor Green
    foreach ($s in $stay) { Write-Host ("      staying: {0}" -f $s.Name) -ForegroundColor DarkGray }
    Write-Host ""
    return
}

$nFiles = 0; $nBytes = 0
foreach ($m in $move) {
    if ($m.PSIsContainer) {
        foreach ($f in @(Get-ChildItem -LiteralPath $m.FullName -Recurse -File -ErrorAction SilentlyContinue)) {
            $nFiles++; $nBytes += $f.Length
        }
    } else { $nFiles++; $nBytes += $m.Length }
}

Write-Host ("  moving  {0} top-level item(s), {1} file(s), {2} MB" -f `
    $move.Count, $nFiles, [math]::Round($nBytes / 1MB, 1))
foreach ($m in $move) { Write-Host ("      {0}" -f $m.Name) }
foreach ($s in $stay) { Write-Host ("      {0}   (left in Overwrite on purpose)" -f $s.Name) -ForegroundColor DarkGray }
Write-Host ""
Write-Host ("  into    {0}" -f $Dest)

if (Test-Path -LiteralPath $Dest) {
    Write-Host ("  NOTE: '{0}' already exists - files will be merged into it." -f $Name) -ForegroundColor Yellow
}

$lines = @(Get-Content -LiteralPath $MlPath)
$already = @($lines | Where-Object { $_ -match '^[+\-](.+)$' -and $Matches[1].TrimEnd() -eq $Name })
Write-Host ("  modlist {0}" -f $(if ($already.Count) { "already lists '$Name' - will not add twice" } else { "will gain '+$Name' at the top" }))

if (-not $Apply) {
    Write-Host ""
    Write-Host "Nothing moved. Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ---- move ------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
foreach ($m in $move) {
    $d = Join-Path $Dest $m.Name
    if (Test-Path -LiteralPath $d) {
        # merge rather than fail: copy the tree in, then drop the source
        Copy-Item -LiteralPath $m.FullName -Destination $Dest -Recurse -Force
        Remove-Item -LiteralPath $m.FullName -Recurse -Force
    } else {
        Move-Item -LiteralPath $m.FullName -Destination $d -Force
    }
}

# every mod MO2 manages has one of these
$meta = Join-Path $Dest 'meta.ini'
if (-not (Test-Path -LiteralPath $meta)) {
    [IO.File]::WriteAllLines($meta, @('[General]','gameName=skyrimspecialedition','modid=0','repository='), $Utf8NoBom)
}

# ---- modlist ---------------------------------------------------------------
# first line is highest priority, and this has to beat the mods it was built
# from or the game keeps reading their original meshes
if (-not $already.Count) {
    Copy-Item -LiteralPath $MlPath -Destination "$MlPath.bak-$Stamp" -Force
    $out = if ($lines.Count -and $lines[0] -match '^\s*#') {
               @($lines[0]) + @("+$Name") + @($lines[1..($lines.Count-1)])
           } else { @("+$Name") + $lines }
    [IO.File]::WriteAllLines($MlPath, $out, $Utf8NoBom)
}

# ---- verify ----------------------------------------------------------------
$landed = @(Get-ChildItem -LiteralPath $Dest -Recurse -File -ErrorAction SilentlyContinue).Count
$left   = @(Get-ChildItem -LiteralPath $Over -Force -ErrorAction SilentlyContinue |
            Where-Object { $move.Name -contains $_.Name })
$ml     = @(Get-Content -LiteralPath $MlPath)
$listed = @($ml | Where-Object { $_ -match '^\+(.+)$' -and $Matches[1].TrimEnd() -eq $Name }).Count

Write-Host ""
Write-Host ("  {0} file(s) now in the mod  (expected {1} plus meta.ini)" -f $landed, $nFiles)
if ($left.Count) { Write-Host ("  WARNING: {0} item(s) that should have moved are still in Overwrite" -f $left.Count) -ForegroundColor Yellow }
if (-not $listed) { throw "modlist.txt does not list '$Name' - something went wrong" }
Write-Host ("  modlist.txt line 1: {0}" -f $ml[0])
Write-Host ""
Write-Host "done. Open MO2 and it will be there as a normal mod at the top." -ForegroundColor Green
Write-Host ""
