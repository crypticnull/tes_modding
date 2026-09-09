#Requires -Version 5.1
<#
  fomod_auto.ps1 - answer a FOMOD from rules instead of by hand, and SHOW the
  reasoning for every choice so it can be reviewed rather than trusted.

    X:\MODDING\SKYRIM\tools\fomod_auto.ps1 -Mods 4682,8607
    X:\MODDING\SKYRIM\tools\fomod_auto.ps1 -Mods 4682 -Apply

  WHY RULES AND NOT -FomodDefaults

  -FomodDefaults takes the first option in each group, and the first option is
  routinely the wrong one. DLL groups list runtimes NEWEST FIRST, so it picks a
  1.7.x build on a 1.6.1170 game. Language groups list Japanese or Russian
  first. And where every group is optional it selects NOTHING and installs an
  empty mod while reporting ok, which happened twice on 9 September.

  So this answers by rule, in priority order, and prints WHY each option won:

    runtime    an option naming this build's runtime beats every other
    language   English, never whatever is listed first
    resolution the largest offered, this machine has 32 GB of VRAM
    installed  for optional groups, only options naming a mod that is
               actually installed here get selected
    default    an option called Default or Vanilla when nothing else applies
    only       a group with one option and no way to decline
    first      last resort, and it is REPORTED so it can be checked

  Anything it cannot answer is left unanswered and named, rather than guessed.

  Reads data\fomods.json, which fomod_export.ps1 writes. Dry run by default.
#>
[CmdletBinding()]
param(
    [string]$Root  = 'X:\MODDING\SKYRIM',
    [int[]]$Mods,
    [string]$Runtime = '1.6.1170',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$json = Join-Path $Root 'data\fomods.json'
if (-not (Test-Path -LiteralPath $json)) { throw "no $json - run fomod_export.ps1 first" }
$all = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json

# what is installed, normalised, so optional groups can be answered by evidence
function Norm($s) { ([string]$s -replace '[^A-Za-z0-9]', '').ToLower() }
$have = New-Object Collections.Generic.HashSet[string]
foreach ($d in (Get-ChildItem (Join-Path $Root 'SKYRIM_SE\mods') -Directory -ErrorAction SilentlyContinue)) {
    [void]$have.Add((Norm $d.Name))
    foreach ($f in (Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue)) {
        if ($f.Extension -match '^\.es[pml]$') { [void]$have.Add((Norm $f.BaseName)) }
    }
}
$haveList = @($have) | Where-Object { $_.Length -ge 7 }

# answer words never match by content, they are decided by group semantics
$ANSWER_WORDS = 'yes','no','none','continue','install','ok','all','both','next','done','readme','thankyou','finish'

function Pick($group) {
    $opts = @($group.plugins | ForEach-Object { [string]$_.name })
    if (-not $opts.Count) { return $null }

    # 1. runtime
    $r = $opts | Where-Object { $_ -match [regex]::Escape($Runtime) } | Select-Object -First 1
    if ($r) { return @{ v=$r; why='runtime' } }

    # 2. language
    $l = $opts | Where-Object { $_ -match '(?i)\bEnglish\b' } | Select-Object -First 1
    if ($l -and @($opts | Where-Object { $_ -match '(?i)english|japanese|russian|chinese|german|french|\u65e5\u672c\u8a9e' }).Count -gt 1) {
        return @{ v=$l; why='language' }
    }

    # 3. resolution, largest first
    foreach ($res in '8k','4k','2k','1k') {
        $m = $opts | Where-Object { $_ -match ('(?i)(^|[^0-9a-z])' + $res + '([^0-9a-z]|$)') } | Select-Object -First 1
        if ($m) { return @{ v=$m; why=('resolution ' + $res.ToUpper()) } }
    }

    # 4. a single option with no way to decline
    if ($opts.Count -eq 1 -and $group.type -in 'SelectExactlyOne','SelectAll','SelectAtLeastOne') {
        return @{ v=$opts[0]; why='only option' }
    }

    # 5. a group NAMED after a mod we do not have takes its None option.
    #    JS Dragon Claws asks about Legacy of the Dragonborn, Helgen Reborn and
    #    Skyrim Sewers, none of which are installed, and every one of those
    #    groups offers None. Taking the first option there installs five patches
    #    for mods that are not present.
    $none = $opts | Where-Object { $_ -match '(?i)^\s*(none|no patch|not installed|skip)\s*$' } | Select-Object -First 1
    if ($none) {
        $gn = Norm $group.name
        $known = $false
        if ($gn.Length -ge 7) {
            foreach ($h in $haveList) { if ($gn -like "*$h*" -or $h -like "*$gn*") { $known = $true; break } }
            if (-not $known -and $have.Contains($gn)) { $known = $true }
        }
        if (-not $known -and $gn.Length -ge 7) { return @{ v=$none; why='subject not installed' } }
        # subject IS installed: prefer the option that names fewest absent mods
        $best = $null; $bestScore = -99
        foreach ($o in $opts) {
            if ($o -match '(?i)^\s*none\s*$') { continue }
            $score = 0
            foreach ($tok in ([regex]::Matches($o, '[A-Z][A-Za-z''\-]{2,}(?:\s+[A-Z][A-Za-z''\-]{2,})*') | ForEach-Object { $_.Value })) {
                $tn = Norm $tok
                if ($tn.Length -lt 7) { continue }
                $found = $false
                foreach ($h in $haveList) { if ($tn -like "*$h*" -or $h -like "*$tn*") { $found = $true; break } }
                if ($found) { $score += 1 } else { $score -= 2 }
            }
            if ($score -gt $bestScore) { $bestScore = $score; $best = $o }
        }
        if ($best) { return @{ v=$best; why='fewest absent mods' } }
    }

    # 6. default / vanilla
    $d = $opts | Where-Object { $_ -match '(?i)^\s*(default|vanilla)\b' } | Select-Object -First 1
    if ($d) { return @{ v=$d; why='default' } }

    return $null
}

function PickMany($group) {
    # optional groups: take only options naming something installed here
    $sel = @()
    foreach ($p in @($group.plugins)) {
        $n = Norm $p.name
        if (-not $n -or $n -in $ANSWER_WORDS) { continue }
        $hit = $false
        foreach ($h in $haveList) { if ($n -like "*$h*" -or $h -like "*$n*") { $hit = $true; break } }
        if (-not $hit -and $have.Contains($n)) { $hit = $true }
        if ($hit) { $sel += [string]$p.name }
    }
    return $sel
}

# Explicit overrides, for cases where name matching cannot win. Kept small and
# each one carries its reason, because a growing override table means the rules
# are wrong rather than that the mods are unusual.
$OVERRIDE = @{
    # "LOTD" is four characters, below the token length floor, so the scorer
    # could not see it was absent. And this build's folder is spelled
    # "Konarik's Accoutrements" without the h, so it never matched the group.
    57038 = @{
        'Legacy of the Dragonborn'  = 'None'
        'Wyrmstooth'                = 'Wyrmstooth'
        "Konahrik's Accoutrements"  = "Konahrik's Accoutrements"
        'Helgen Reborn'             = 'None'
        'Skyrim Sewers'             = 'None'
    }
    # AIO is the whole set; the instrument group is SelectAtLeastOne so it still
    # needs an answer even when AIO makes it redundant.
    47202 = @{ 'BA Bard Songs' = 'AIO|DRUM|FLUTE|LUTE' }
}

$results = @()
foreach ($id in $Mods) {
    $m = $all | Where-Object { [int]$_.id -eq [int]$id } | Select-Object -First 1
    if (-not $m) { Write-Host ("  {0}: not in fomods.json" -f $id) -ForegroundColor Red; continue }

    Write-Host ""
    Write-Host ("=== {0}  {1}" -f $m.id, $m.name) -ForegroundColor Cyan
    $pick = @{}
    $unanswered = @()
    foreach ($g in $m.groups) {
        $gn = [string]$g.name
        if (-not $gn) { continue }
        $chosen = $null; $why = ''
        if ($OVERRIDE.ContainsKey([int]$m.id) -and $OVERRIDE[[int]$m.id].ContainsKey($gn)) {
            $chosen = @($OVERRIDE[[int]$m.id][$gn] -split '\|')
            $why = 'OVERRIDE'
        }
        elseif ($g.type -in 'SelectAny','SelectAtLeastOne') {
            $many = PickMany $g
            if ($many.Count) { $chosen = $many; $why = 'installed here' }
            elseif ($g.type -eq 'SelectAtLeastOne' -or @($g.plugins).Count -eq 1) {
                $p = Pick $g; if ($p) { $chosen = @($p.v); $why = $p.why }
            }
        } else {
            $p = Pick $g
            if ($p) { $chosen = @($p.v); $why = $p.why }
            elseif ($g.type -eq 'SelectExactlyOne') {
                $chosen = @([string]@($g.plugins)[0].name); $why = 'FIRST - check this'
            }
        }
        if ($chosen) {
            if (-not $pick.ContainsKey($gn)) { $pick[$gn] = New-Object Collections.ArrayList }
            foreach ($c in $chosen) { if (-not $pick[$gn].Contains($c)) { [void]$pick[$gn].Add($c) } }
            $col = if ($why -like 'FIRST*') { 'Yellow' } else { 'Gray' }
            $gnShort = $gn.Substring(0, [Math]::Min(34, $gn.Length))
            $chJoin  = ($chosen -join '|')
            $chShort = $chJoin.Substring(0, [Math]::Min(42, $chJoin.Length))
            Write-Host ("    {0,-34} -> {1,-42} [{2}]" -f $gnShort, $chShort, $why) -ForegroundColor $col
        } elseif ($g.type -in 'SelectExactlyOne','SelectAtLeastOne') {
            $unanswered += $gn
        }
    }
    $str = ($pick.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, ($_.Value -join '|') }) -join '; '
    if ($unanswered.Count) { Write-Host ("    UNANSWERED mandatory: {0}" -f ($unanswered -join ', ')) -ForegroundColor Red }
    $results += [pscustomobject]@{ Id=[int]$m.id; Name=$m.name; Choice=$str; Unanswered=$unanswered.Count }
}

if ($Apply) {
    Write-Host ""
    Write-Host "=== applying ===" -ForegroundColor Cyan
    foreach ($r in $results) {
        $choice = $r.Choice
        $done = $false
        for ($pass = 1; $pass -le 15; $pass++) {
            $txt = (& (Join-Path $Root 'tools\install_mod.ps1') -Mod $r.Id -Fomod $choice -Apply *>&1 | Out-String)
            $bad = [regex]::Match($txt, "no option matches '(.+?)'\. Options")
            if ($bad.Success) {
                $drop = $bad.Groups[1].Value
                $choice = ($choice -split ';\s*' | ForEach-Object {
                    $q = $_ -split '=',2; if ($q.Count -lt 2) { return $_ }
                    $o = @($q[1] -split '\|' | Where-Object { $_.Trim() -ne $drop }); if (-not $o.Count) { return $null }
                    "{0}={1}" -f $q[0], ($o -join '|') } | Where-Object { $_ }) -join '; '
                continue
            }
            $f = [regex]::Match($txt, '(\d+) file\(s\), (\d+) plugin\(s\)')
            if ($txt -match 'FOMOD - skipped') { Write-Host ("  SKIPPED  {0,-7} {1}" -f $r.Id, $r.Name) -ForegroundColor Red }
            elseif ($f.Success -and [int]$f.Groups[1].Value -eq 0) { Write-Host ("  EMPTY    {0,-7} {1}" -f $r.Id, $r.Name) -ForegroundColor Red }
            elseif ($f.Success) { Write-Host ("  ok       {0,-7} {1,-44} {2} file(s), {3} plugin(s)" -f $r.Id, $r.Name.Substring(0,[Math]::Min(42,$r.Name.Length)), $f.Groups[1].Value, $f.Groups[2].Value) -ForegroundColor Green }
            else { Write-Host ("  ok       {0,-7} {1}" -f $r.Id, $r.Name) -ForegroundColor Green }
            $done = $true; break
        }
        if (-not $done) { Write-Host ("  GAVE UP  {0,-7} {1}" -f $r.Id, $r.Name) -ForegroundColor Red }
    }
} else {
    Write-Host ""
    Write-Host ("  {0} mod(s) planned, {1} with an unanswered mandatory group. Re-run with -Apply." -f $results.Count, @($results | Where-Object { $_.Unanswered }).Count) -ForegroundColor Yellow
}
