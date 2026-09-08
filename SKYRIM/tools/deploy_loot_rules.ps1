<#
.SYNOPSIS
    Deploy the tracked LOOT user rules into LOOT's own data directory, and
    report whether the two copies agree.

.DESCRIPTION
    LOOT keeps its user rules at
      %LOCALAPPDATA%\LOOT\games\<game>\userlist.yaml
    which is outside X:\MODDING and therefore outside the archive. The master
    copy is tools\loot-userlist.yaml, which IS tracked. This copies one to the
    other so the rules survive a machine rebuild.

.TRAPS
    - MO2's Sort does NOT use the standalone LOOT.exe. It runs the bundled
      MO2\...\loot\lootcli.exe inside the usvfs virtual file system, which is
      the only way anything sees the mods as a populated Data folder. Both read
      the same %LOCALAPPDATA%\LOOT data directory, so a rule written here
      applies to both.
    - Do NOT "just run LOOT.exe" to test a rule. LOOTDebugLog.txt shows the
      standalone app builds its game handle against
      C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition -
      the Steam install, which CLAUDE.md section 2 puts off limits, and which
      is not this build. Sort from inside MO2 instead.
    - Dry run by default. Pass -Apply to actually write.

.EXAMPLE
    & 'X:\MODDING\SKYRIM\tools\deploy_loot_rules.ps1'
    & 'X:\MODDING\SKYRIM\tools\deploy_loot_rules.ps1' -Apply
#>
[CmdletBinding()]
param(
    [string] $Root = 'X:\MODDING\SKYRIM',
    [string] $Game = 'Skyrim Special Edition',
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

$src = Join-Path $Root 'tools\loot-userlist.yaml'
$dstDir = Join-Path $env:LOCALAPPDATA ("LOOT\games\{0}" -f $Game)
$dst = Join-Path $dstDir 'userlist.yaml'

if (-not (Test-Path -LiteralPath $src)) { throw "Master copy not found: $src" }
if (-not (Test-Path -LiteralPath $dstDir)) { throw "LOOT data dir not found: $dstDir" }

Write-Host ""
Write-Host "deploy_loot_rules  $(if ($Apply) { '(APPLY)' } else { '(dry run)' })"
Write-Host "  from  $src"
Write-Host "  to    $dst"
Write-Host ""

$srcText = [IO.File]::ReadAllText($src)
$dstText = if (Test-Path -LiteralPath $dst) { [IO.File]::ReadAllText($dst) } else { $null }

if ($null -eq $dstText) {
    Write-Host "  target does not exist yet" -ForegroundColor Yellow
} elseif ($srcText -eq $dstText) {
    Write-Host "  identical - nothing to do" -ForegroundColor Green
} else {
    Write-Host "  DIFFERS from the master copy" -ForegroundColor Yellow
}

# the rules actually declared, so the summary is readable without opening YAML
Write-Host ""
Write-Host "  rules in the master copy:"
$current = $null
foreach ($line in [IO.File]::ReadAllLines($src)) {
    if ($line -match "^\s*-\s+name:\s*'(.+)'\s*$") { $current = $Matches[1] }
    elseif ($line -match "^\s*-\s+'(.+)'\s*$" -and $current) {
        Write-Host ("    {0}  loads AFTER  {1}" -f $current, $Matches[1])
    }
}

if ($Apply) {
    if ($dstText -ne $null -and $srcText -ne $dstText) {
        $bak = $dst + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
        Copy-Item -LiteralPath $dst -Destination $bak -Force
        Write-Host ""
        Write-Host "  backed up existing to $bak"
    }
    # LOOT reads UTF-8. PS 5.1 Set-Content -Encoding UTF8 would add a BOM.
    [IO.File]::WriteAllText($dst, $srcText, (New-Object Text.UTF8Encoding $false))
    $ok = ([IO.File]::ReadAllText($dst) -eq $srcText)
    Write-Host ""
    Write-Host ("  written, read-back matches: " + $ok) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    Write-Host "  now Sort in MO2 (not standalone LOOT) for the rules to take effect."
} else {
    Write-Host ""
    Write-Host "  dry run. Re-run with -Apply to write."
}
