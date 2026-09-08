<#
.SYNOPSIS
    Assert the load-order constraints from NEXT.md section 3, in one command.

.DESCRIPTION
    check_masters.ps1 proves every plugin's masters are present, active and
    ordered. It cannot prove a constraint that is about which mod WINS a
    conflict, because both orders are master-legal. NEXT.md section 3 is
    entirely that second kind, so it had gone unverified through several LOOT
    sorts while being wrong.

    Run this after any sort. Exit code 1 if a constraint is violated.

.TRAPS
    - A missing plugin is reported, not skipped silently. A rule that quietly
      matches nothing is worse than no rule.
    - Compares positions in loadorder.txt, which is the full order. plugins.txt
      holds only the managed subset and its indices are not the load order.

.EXAMPLE
    & 'X:\MODDING\SKYRIM\tools\check_order.ps1'
#>
[CmdletBinding()]
param(
    [string] $Root = 'X:\MODDING\SKYRIM',
    [string] $ProfileName = 'Default'
)

$ErrorActionPreference = 'Stop'

# earlier plugin  ->  must load before  ->  each of these
$rules = @(
    @{ Before = 'AI Overhaul.esp'
       After  = @('Bijin NPCs.esp','Bijin Wives.esp','Bijin Warmaidens.esp','Bijin - UCMT.esp')
       Why    = 'Bijin must win the NPC appearance records (NEXT.md s3)' },

    @{ Before = 'AI Overhaul.esp'
       After  = @('AI Overhaul - USSEP Patch.esp','AI Overhaul - Fishing Addon.esp')
       Why    = 'patches load after their parent' },

    @{ Before = 'The Book of Origins.esp'
       After  = @('The Book of Origins - Alternate Start.esp')
       Why    = 'addon loads after its parent' }
)

$lo = [IO.File]::ReadAllLines((Join-Path $Root ("SKYRIM_SE\profiles\{0}\loadorder.txt" -f $ProfileName))) |
        Where-Object { $_ -and -not $_.StartsWith('#') }

$pos = @{}
for ($i = 0; $i -lt $lo.Count; $i++) { $pos[$lo[$i].Trim().ToLowerInvariant()] = $i + 1 }
function Get-Pos { param([string]$n) $k = $n.ToLowerInvariant(); if ($pos.ContainsKey($k)) { $pos[$k] } else { $null } }

Write-Host ""
Write-Host ("check_order  profile {0}  {1} plugins in loadorder.txt" -f $ProfileName, $lo.Count)

$fail = 0
$missing = 0
foreach ($r in $rules) {
    $bp = Get-Pos $r.Before
    Write-Host ""
    if ($null -eq $bp) {
        Write-Host ("  MISSING  " + $r.Before) -ForegroundColor Red
        $missing++
        continue
    }
    Write-Host ("  {0}  (position {1})  -  {2}" -f $r.Before, $bp, $r.Why)
    foreach ($a in $r.After) {
        $ap = Get-Pos $a
        if ($null -eq $ap) {
            Write-Host ("      MISSING  " + $a) -ForegroundColor Red
            $missing++
        } elseif ($bp -lt $ap) {
            Write-Host ("      ok    {0,4}  {1}" -f $ap, $a) -ForegroundColor Green
        } else {
            Write-Host ("      FAIL  {0,4}  {1}   <-- loads BEFORE {2}" -f $ap, $a, $r.Before) -ForegroundColor Red
            $fail++
        }
    }
}

Write-Host ""
Write-Host "SUMMARY"
Write-Host ("  violations  " + $fail)
Write-Host ("  missing     " + $missing)
Write-Host ""
if ($fail -gt 0) {
    Write-Host "  Load order is WRONG. If a LOOT sort just ran, the userlist rule is not" -ForegroundColor Red
    Write-Host "  being applied - check tools\deploy_loot_rules.ps1 landed the file." -ForegroundColor Red
    exit 1
} else {
    Write-Host "  All ordering constraints hold." -ForegroundColor Green
}
