#Requires -Version 5.1
<#
  bisect_mods.ps1 - find which mod causes a reproducible crash, by halving.

    X:\MODDING\OBLIVION\tools\bisect_mods.ps1 -Start      begin: all managed mods are suspects
    X:\MODDING\OBLIVION\tools\bisect_mods.ps1 -Crash      last run crashed   -> narrow
    X:\MODDING\OBLIVION\tools\bisect_mods.ps1 -Clean      last run was fine  -> narrow
    X:\MODDING\OBLIVION\tools\bisect_mods.ps1 -Status     where we are
    X:\MODDING\OBLIVION\tools\bisect_mods.ps1 -Abort      restore every mod, delete state

  HOW TO USE

    1. -Start.  It disables half your mods and tells you which half is OFF.
    2. Launch, reproduce the crash the same way every time.
    3. -Crash or -Clean. It halves again.
    4. Repeat. 106 mods needs at most 7 runs.

  It edits ONLY the +/- flags in modlist.txt, never the order, and backs the
  file up every time. MO2 deactivates a disabled mod's plugins and paks for you,
  so this covers ESP records and pak assets in one pass.

  WHY MODS AND NOT PLUGINS
  Disabling a plugin by hand risks orphaning another plugin that lists it as a
  master, which crashes for a different reason and poisons the result. Disabling
  the whole mod lets MO2 handle dependent deactivation. Run check_masters.ps1
  after each step if you want that confirmed rather than assumed.

  NOTE: run the crash test on the plain 'Oblivion Remastered' executable if the
  fault reproduces there. Loads are faster and it removes the script mods as a
  variable entirely. Do not save while testing with mods disabled.
#>

[CmdletBinding()]
param(
    [string]$Instance = 'X:\MODDING\OBLIVION\OBLIVION_REMASTERED',
    [string]$StateFile = 'X:\MODDING\OBLIVION\data\bisect_state.json',
    [switch]$Start, [switch]$Crash, [switch]$Clean, [switch]$Status, [switch]$Abort
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$ModlistP  = Join-Path $Instance 'profiles\Default\modlist.txt'
$Utf8NoBom = New-Object Text.UTF8Encoding $false

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. It rewrites modlist.txt on exit and would undo this. Close it and re-run."
}
if (-not (Test-Path -LiteralPath $ModlistP)) { throw "not found: $ModlistP" }

# ---- modlist.txt is order-significant; only the leading +/- may change -----
$lines = @(Get-Content -LiteralPath $ModlistP)
$names = @()
foreach ($l in $lines) { if ($l -match '^[+\-](.+)$') { $names += $Matches[1].TrimEnd() } }

function Save-State { param($S)
    New-Item -ItemType Directory -Force -Path (Split-Path $StateFile -Parent) | Out-Null
    ($S | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $StateFile -Encoding UTF8
}
function Load-State {
    if (-not (Test-Path -LiteralPath $StateFile)) { throw "no bisect in progress - run with -Start" }
    return (Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json)
}
function Write-Modlist { param([string[]]$Off)
    $offSet = @{}; foreach ($o in $Off) { $offSet[$o] = $true }
    Copy-Item -LiteralPath $ModlistP -Destination "$ModlistP.bisect-$Stamp" -Force
    $out = @()
    foreach ($l in $lines) {
        if ($l -match '^([+\-])(.+)$') {
            $n = $Matches[2].TrimEnd()
            $out += $(if ($offSet[$n]) { "-$n" } else { "+$n" })
        } else { $out += $l }
    }
    [IO.File]::WriteAllLines($ModlistP, $out, $Utf8NoBom)
}
function Show { param($S)
    $n = $S.candidates.Count
    $rounds = [Math]::Ceiling([Math]::Log([Math]::Max($n,1), 2))
    Write-Host ""
    Write-Host ("suspects remaining : {0}" -f $n)
    Write-Host ("runs still needed  : at most {0}" -f $rounds)
    if ($n -le 1) { return }
    Write-Host ("currently DISABLED : {0} mod(s)" -f $S.currentOff.Count)
    foreach ($m in $S.currentOff) { Write-Host ("    - {0}" -f $m) }
}

# ---- abort ----------------------------------------------------------------
if ($Abort) {
    Write-Modlist @()
    Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
    Write-Host "All mods re-enabled. Bisect state cleared."
    Write-Host "Open MO2 and re-sort with LOOT before playing properly again."
    return
}

# ---- status ---------------------------------------------------------------
if ($Status) { $s = Load-State; Write-Host "=== bisect status ==="; Show $s; return }

# ---- start ----------------------------------------------------------------
if ($Start) {
    $state = [pscustomobject]@{ candidates = $names; currentOff = @(); round = 0; history = @() }
    $half  = [Math]::Floor($state.candidates.Count / 2)
    $state.currentOff = @($state.candidates[0..($half - 1)])
    $state.round = 1
    Write-Modlist $state.currentOff
    Save-State $state
    Write-Host "=== bisect started ==="
    Write-Host ("{0} mods, testing with the first {1} disabled" -f $names.Count, $state.currentOff.Count)
    Show $state
    Write-Host ""
    Write-Host "Launch, reproduce, then run this again with -Crash or -Clean."
    return
}

# ---- narrow ---------------------------------------------------------------
if (-not ($Crash -or $Clean)) { throw "Pass -Start, -Crash, -Clean, -Status or -Abort." }

$s = Load-State
$off = @($s.currentOff)
$on  = @($s.candidates | Where-Object { $off -notcontains $_ })

if ($Crash) {
    # it still crashed with those OFF, so the cause is among the ones left ON
    $s.candidates = $on
    $verdict = "crashed with {0} disabled -> culprit is among the {1} still enabled" -f $off.Count, $on.Count
} else {
    # disabling that half fixed it, so the cause is among the ones we turned OFF
    $s.candidates = $off
    $verdict = "clean with {0} disabled -> culprit is among those {0}" -f $off.Count
}
$s.history += ("round {0}: {1}" -f $s.round, $verdict)
Write-Host "=== bisect ==="
Write-Host ("  {0}" -f $verdict)

if ($s.candidates.Count -le 1) {
    $found = if ($s.candidates.Count) { $s.candidates[0] } else { '(none - the fault is not in any managed mod)' }
    Write-Host ""
    Write-Host ("CULPRIT: {0}" -f $found) -ForegroundColor Green
    Write-Host ""
    foreach ($h in $s.history) { Write-Host ("  {0}" -f $h) }
    Write-Host ""
    Write-Host "Re-enable everything else with:  bisect_mods.ps1 -Abort"
    Write-Host "then disable just that one mod in MO2 and re-sort with LOOT."
    Save-State $s
    return
}

# everything not still a suspect stays ON - only suspects get halved, so each
# run changes as little as possible
$half = [Math]::Floor($s.candidates.Count / 2)
if ($half -lt 1) { $half = 1 }
$s.currentOff = @($s.candidates[0..($half - 1)])
$s.round = $s.round + 1
Write-Modlist $s.currentOff
Save-State $s
Show $s
Write-Host ""
Write-Host "Launch, reproduce, then -Crash or -Clean again."
