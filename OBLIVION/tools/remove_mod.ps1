#Requires -Version 5.1
<#
  Retire a mod folder from the MO2 instance.

    X:\MODDING\OBLIVION\tools\remove_mod.ps1 -Name "RAO 1.0"
    X:\MODDING\OBLIVION\tools\remove_mod.ps1 -Name "RAO 1.0","Some Other Mod"
    X:\MODDING\OBLIVION\tools\remove_mod.ps1 -Name "RAO 1.0" -DisableOnly

  Moves the folder to _DELETE_ME and drops its line from modlist.txt.
  Nothing is deleted; modlist.txt is backed up first and every other line is
  preserved verbatim, including MO2's separators and '*' unmanaged entries.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string[]]$Name,
    [switch]$DisableOnly
)

$ErrorActionPreference = 'Stop'

$Instance = 'X:\MODDING\OBLIVION\OBLIVION_REMASTERED'
$ModsDir  = Join-Path $Instance 'mods'
$Profile  = Join-Path $Instance 'profiles\Default'
$Modlist  = Join-Path $Profile 'modlist.txt'
$Quar     = 'X:\MODDING\OBLIVION\_DELETE_ME\removed-mods'
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8NoBom = New-Object Text.UTF8Encoding $false

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. Close it and re-run."
}
if (-not (Test-Path -LiteralPath $ModsDir)) { throw "not found: $ModsDir" }

Write-Host "=== remove mod ==="
Write-Host ""

# --- move the folders -------------------------------------------------------
$moved = @()
foreach ($n in $Name) {
    $src = Join-Path $ModsDir $n

    # never let a name resolve to the mods root itself
    if ([string]::IsNullOrWhiteSpace($n) -or $n -match '^\.+$' -or $n -match '[\\/]') {
        Write-Host ("  REFUSED unsafe name: '{0}'" -f $n); continue }
    if ((Split-Path $src -Parent).TrimEnd('\') -ne $ModsDir.TrimEnd('\')) {
        Write-Host ("  REFUSED resolves outside mods dir: '{0}'" -f $n); continue }

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host ("  not present: {0}" -f $n); continue }

    if ($DisableOnly) {
        Write-Host ("  keeping folder, will disable: {0}" -f $n)
        $moved += $n
        continue
    }

    $n_files = @(Get-ChildItem -LiteralPath $src -Recurse -File).Count
    New-Item -ItemType Directory -Force -Path $Quar | Out-Null
    $dst = Join-Path $Quar ("{0}-{1}" -f $n, $Stamp)
    Move-Item -LiteralPath $src -Destination $dst
    Write-Host ("  moved   {0}  ({1} files) -> {2}" -f $n, $n_files, $dst)
    $moved += $n
}

if (-not $moved.Count) { Write-Host ""; Write-Host "nothing to do."; return }

# --- rewrite modlist.txt ----------------------------------------------------
if (Test-Path -LiteralPath $Modlist) {
    Copy-Item -LiteralPath $Modlist -Destination "$Modlist.bak-$Stamp" -Force
    Write-Host ""
    Write-Host ("backed up modlist.txt -> {0}.bak-{1}" -f (Split-Path $Modlist -Leaf), $Stamp)

    $raw   = @(Get-Content -LiteralPath $Modlist)
    $out   = @()
    $hit   = 0
    foreach ($l in $raw) {
        if ($l -match '^([+\-*])(.+)$' -and ($moved -contains $Matches[2])) {
            $hit++
            if ($DisableOnly) { $out += ('-' + $Matches[2]); Write-Host ("  disabled  {0}" -f $Matches[2]) }
            else              { Write-Host ("  delisted  {0}" -f $Matches[2]) }
            continue
        }
        $out += $l
    }
    [IO.File]::WriteAllLines($Modlist, $out, $Utf8NoBom)
    Write-Host ("modlist.txt: {0} line(s) changed, {1} of {2} lines kept verbatim" -f `
                $hit, $out.Count, $raw.Count)
} else {
    Write-Host "no modlist.txt found - nothing to delist"
}

Write-Host ""
Write-Host "Done. Run:  X:\MODDING\OBLIVION\tools\nexus2.ps1 -Mode verify"
