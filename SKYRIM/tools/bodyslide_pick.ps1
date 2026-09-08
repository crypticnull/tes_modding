#Requires -Version 5.1
<#
  bodyslide_pick.ps1 - decide, once and in writing, which slider set wins every
  output mesh, so Batch Build never asks.

      bodyslide_pick.ps1              dry run - shows every decision and every
                                      group it could not decide
      bodyslide_pick.ps1 -Apply       do it (backs up every file it touches)
      bodyslide_pick.ps1 -Restore     put the originals back

  THIS REPLACES bodyslide_prune.ps1

  The old script had a two-tier model: a flat list of winner mods and a flat
  list of loser mods, and it refused to act unless exactly one winner was in
  the collision. That was enough when the only fight was CBBE vs 3BA. It is not
  enough now. 648 collisions, and most of them are a mod fighting ITSELF -
  TAWOBA Remastered ships a plain and a [3BA] set for the same mesh, Cosplay
  Pack ships four physics variants, KS Hairdos ships one per body type. The old
  script deliberately skipped all of those, which is why they were never
  resolved.

  So there are two rule sets here, applied in this order:

    1. MOD PRIORITY. Across different mods, the highest-ranked mod wins the
       output and every lower-ranked mod's set for that output is removed.
       Rank is position in $ModPriority - lower number wins.

    2. VARIANT PREFERENCE. Among the sets that survive rule 1 and come from
       the SAME mod, the first pattern in that mod's Prefer list that matches
       any candidate picks the winner. Everything else in the group goes.

  Anything still ambiguous after both is left alone and reported, with the
  candidate names, so a rule can be added rather than guessed at. Nothing is
  ever removed if it would leave an output with no set at all.

  WHY EDIT THE .osp AND NOT JUST HIDE FILES

  Because the files are mixed. CBBE Vanilla.osp covers vanilla CLOTHING that
  Remodeled Armor does not replace, and TAWOBA Remastered's file holds both the
  CBBE and the 3BA build of every outfit. Hiding either file would leave real
  outfits unbuilt. This works at the SliderSet node, not the file.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [switch]$Apply,
    [switch]$Restore,
    [string]$Out
)

$ErrorActionPreference = 'Stop'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$Instance = Join-Path $Root 'SKYRIM_SE'
$ModsDir  = Join-Path $Instance 'mods'
$MlPath   = Join-Path $Instance 'profiles\Default\modlist.txt'
if (-not $Out) { $Out = Join-Path $Root 'logs\bodyslide_pick.txt' }

# ---------------------------------------------------------------------------
# RULE 1 - mod priority. Lower number wins. A mod not listed here ranks below
# every listed mod, and two unlisted mods in one collision stay ambiguous.
# ---------------------------------------------------------------------------
$ModPriority = @(
    # THE RULE, stated once so it does not have to be re-derived:
    #
    #   SKIMPIEST WINS. Always. A milder replacer only ever wins an item that
    #   nothing skimpier covers. That is why this is an ordered list and not a
    #   set of per-mod judgements - coverage gaps fall through to the next
    #   entry automatically.
    #
    # Entries match a mod folder by exact name first, then by unique substring,
    # so a folder named slightly differently at install time still ranks.

    'CBBE 3BA (3BBB)'                                     # the body always wins its own meshes

    'Random Tawoba Realistic and Squeeze Bodyslides'      # squeeze fit over stock TAWOBA
    'TAWOBA REMASTERED 6.1 CBBE SE'

    # --- VANILLA WARDROBE, SKIMPIEST FIRST -----------------------------------
    # The winning slider set is what gets built to the mesh path the game
    # loads, so this ordering IS what the armour looks like.
    # The 1.42 update is a separate mod folder and must outrank the AIO it
    # patches. Named exactly, because exact match is tested before the prefix
    # rule below - otherwise both folders resolve to the same rank and a
    # collision between them has no winner.
    "BD's Armor and clothes replacer CBBE 3BA - V1.42 Update file"
    "BD's Armor and Clothes Replacer"                     # skimpy AND broad - clothes as well as armour
    'Skimped - Vanilla'                                   # skimpy, but no farm/merchant clothes
    'Somewhere in Between - 3BA Armor ReplacerNPM'        # mid
    'SMR Vanilla Outfits 3BA'                             # mild
    'CBBE 3BA Vanilla Outfits Redone - Default'           # faithful
    'Remodeled Armor SE - CBBE 3BA'                       # faithful
    'Common Clothes and Armors 3BA Bodyslide 1.0'

    # --- standalone sets, listed so a stray overlap resolves rather than asking
    "BD's Armor and Clothes 3BA Standalone (Vanilla)"     # NOT the replacer above - adds items only
    'Cosplay Basics - (CBBE 3BA)'
    'Cosplay Pack - hdt SMP (CBBE 3BA)'
    'Modular Mage - CBBE 3BA'
)

# Mods that must lose to EVERYTHING, including mods not named above. Without
# this tier an unlisted mod ranked below plain CBBE, so CBBE 2.0.3 - the one
# thing that should never win - beat 186 sets from a 3BA replacer purely
# because it appeared in a list and the replacer did not.
$ModLast = @(
    "Caliente's Beautiful Bodies Enhancer CBBE - v2.0.3"
)

# ---------------------------------------------------------------------------
# RULE 2 - variant preference inside one mod. Patterns are regex, matched
# against the SliderSet name, most-preferred first.
# ---------------------------------------------------------------------------
$VariantRules = @(
    # Patterns are regex against the SliderSet NAME, most-preferred first, and
    # they narrow progressively: one that matches several shrinks the pool and
    # the next decides inside it. Fallback='first' means the leftover variants
    # in that mod are cosmetic and any of them will do - it is a deliberate
    # statement about that mod, not a global "stop asking me".

    @{ Mod = 'TAWOBA REMASTERED 6.1 CBBE SE'
       Prefer = @('\[3BA\]'); Fallback = 'first' }        # 3BA build, never the plain CBBE one.
                                                          # Fallback covers sets whose names differ
                                                          # only by a trailing space.

    @{ Mod = 'Random Tawoba Realistic and Squeeze Bodyslides'
       # The plain squeeze. 'alt' appears as both 'alt1 squeeze kp84' and
       # 'squeeze kp84 alt 4', so \balt\b does NOT work - there is no word
       # boundary inside 'alt1'. 'realistic' and 'lower physics' are separate
       # shape variants and are excluded the same way.
       Prefer = @('^(?!.*\balt(\d|\s|$))(?!.*realistic)(?!.*lower physics).*squeeze',
                  '^(?!.*\balt(\d|\s|$)).*squeeze')
       Fallback = 'first' }

    @{ Mod = 'T.E.W.O.B.A. - The Expanded World of Bikini Armors By PUMPKIN'
       Prefer = @('- 3BBB -') }                           # 3BBB, not the CBBE build

    @{ Mod = 'Tera Armors Collection 3BA Realistic BodySlide'
       # NOT \bHH$ - there is no word boundary inside 'SHH', which is a second
       # high-heel variant. No heel mod is installed, so neither is wanted.
       Prefer = @('^(?!.*HH$)') }

    @{ Mod = 'CBBE 3BA Vanilla Outfits Redone - Default'
       Prefer = @('Glowmapped', '\(Physics\)$', '\(Im Physics\)$')
       Fallback = 'first' }

    # The replacer ships two axes of variant: '- Realistic' (a less exaggerated
    # cut) and flat versus heeled boots. Skimpiest wins, so non-Realistic; no
    # high-heel mod is installed, so flat. Both folders get the same rule -
    # VariantRules keys on the exact folder name, and the AIO and its update
    # are separate mods.
    @{ Mod = "BD's Armor and clothes replacer CBBE 3BA - AIO"
       Prefer = @('^(?!.*Realistic)', 'flat boots', '\bflat\b'); Fallback = 'first' }

    @{ Mod = "BD's Armor and clothes replacer CBBE 3BA - V1.42 Update file"
       Prefer = @('^(?!.*Realistic)', 'flat boots', '\bflat\b'); Fallback = 'first' }

    @{ Mod = "BD's Armor and Clothes 3BA Standalone (Vanilla)"
       Prefer = @('flat boots', '\bflat\b', '^(?!.*\blow\b)')
       Fallback = 'first' }                               # remaining splits are hair colour and
                                                          # cut variants - cosmetic, any will do

    @{ Mod = 'Remodeled Armor SE - CBBE 3BA'
       # 'Hands Redone' needs a hand-mesh mod that is not installed. '- Toggled'
       # is the toggleable variant of the same piece.
       Prefer = @('^(?!.*Hands Redone)', '^(?!.* - Toggled$)') }

    @{ Mod = 'DX Armors and Clothing 3BA Bodyslide Emporium Modular'
       Prefer = @('^(?!.*No Physics).*\(Physics\)$', '^(?!.*No Physics).*\(Im Physics\)$',
                  '^(?!.*No Physics)')
       Fallback = 'first' }                               # hood sizes and wigs are cosmetic

    @{ Mod = 'Modular Mage - CBBE 3BA'
       Prefer = @('SMP$', 'xavbio', '^(?!.*\(Realistic\))')
       Fallback = 'first' }

    @{ Mod = 'TIWOBA Dawnguard bikini set'
       Prefer = @('^(?!.*no physics).*\bhdt\b', '^(?!.*no physics)') }

    @{ Mod = 'Imperial Bikini armor 3BA HDT-SMP - Tawoba addon'
       # \balt with no trailing boundary: 'alt2' has none, same trap as 'alt1'.
       # Fallback covers one pair of identically-named sets in separate files.
       Prefer = @('^(?!.*\balt).*\bhdt\b', '^(?!.*\balt)', '\bhdt\b'); Fallback = 'first' }

    @{ Mod = 'Stormcloaks Bikini armor 3BA HDT-SMP -Tawoba addon'
       Prefer = @('^(?!.*\balt).*\bhdt\b', '^(?!.*\balt)', '\bhdt\b'); Fallback = 'first' }

    @{ Mod = 'Somewhere in Between - 3BA Armor ReplacerNPM'
       # Almost all of these are boot heel height, spelled four different ways:
       # 'flat boots', 'boots flat', '(low)/(high)', and '(light low)/(light
       # high)'. No high-heel support is installed, so flat and low win. The
       # leftovers - '(Gold)', 'boots 2', 'alt' - are cosmetic.
       Prefer = @('flat boots', '\bflat\b', '\blow\b', '^(?!.*\bhigh\b)', '^(?!.*\balt\b)')
       Fallback = 'first' }

    @{ Mod = 'Skimped - Vanilla'
       Prefer = @('^(?!.*\(Realistic\))'); Fallback = 'first' }

    @{ Mod = 'Wonderland Lingerie SE'
       Prefer = @('\b3BA\b') }

    @{ Mod = 'Shattered Royal Armor'
       Prefer = @('^(?!.*No Physics)(?!.*Transparent)(?!.*\bFlat\b)') }

    @{ Mod = 'Cosplay Pack - hdt SMP (CBBE 3BA)'
       Prefer = @('\[String SMP\]', '\[SMP\]', '\[String\]'); Fallback = 'first' }

    @{ Mod = 'Cosplay Basics - (CBBE 3BA)'
       Prefer = @('\[String SMP\]', '\[SMP\]', '\[String\]'); Fallback = 'first' }

    @{ Mod = 'KS Hairdos SMP'
       Prefer = @('\(CBBE\)') }                           # the CBBE collision body, not BHUNP/UBE/TBD

    @{ Mod = 'Towels'
       # Ships CBBE 3BA, BHUNP and HIMBO builds of every piece side by side.
       # HIMBO is the male body and lands on different meshes, but BHUNP
       # collides with 3BA head-on. 'Towel Head' has no body variant at all,
       # so it never reaches this rule.
       Prefer = @('CBBE 3BA') }
)

foreach ($p in @($ModsDir, $MlPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" }
}
$outDir = Split-Path $Out -Parent
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

if (Get-Process -Name 'BodySlide*' -ErrorAction SilentlyContinue) {
    throw "BodySlide is running. It reads these files at startup and caches them. Close it and re-run."
}

# ---- restore ---------------------------------------------------------------
if ($Restore) {
    $failed = 0
    $enabledR = @(Get-Content -LiteralPath $MlPath |
                  Where-Object { $_ -match '^\+(.+)$' } |
                  ForEach-Object { $Matches[1].TrimEnd() })
    $restored = 0
    foreach ($mod in $enabledR) {
        $ssDir = Join-Path (Join-Path $ModsDir $mod) 'CalienteTools\BodySlide\SliderSets'
        if (-not (Test-Path -LiteralPath $ssDir)) { continue }
        # ONLY timestamped backups this script wrote. The glob '*.osp.bak-*' also
        # matched a '.bak-bom' file left by the XML-declaration fix; the strip
        # regex did not remove that suffix, so the destination came out equal to
        # the source and Copy-Item threw - aborting the whole restore partway,
        # with no indication of how far it got. Restoring it would also have put
        # the malformed XML back.
        $baks = @(Get-ChildItem -LiteralPath $ssDir -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match '\.osp\.bak-\d{8}-\d{6}$' })
        if (-not $baks.Count) { continue }
        # Newest backup per original, so repeated runs cannot walk backwards
        # through a chain of half-pruned copies.
        foreach ($g in @($baks | Group-Object { ($_.Name -replace '\.bak-\d{8}-\d{6}$','') })) {
            $newest = @($g.Group | Sort-Object Name -Descending)[0]
            $dest   = Join-Path $ssDir $g.Name
            if ($dest -eq $newest.FullName) { continue }
            try {
                Copy-Item -LiteralPath $newest.FullName -Destination $dest -Force
                Write-Host ("  restored {0}  <-  {1}" -f $g.Name, $newest.Name) -ForegroundColor Green
                $restored++
            } catch {
                # One bad file must not abandon the other two hundred.
                Write-Host ("  FAILED  {0}  ({1})" -f $g.Name, $_.Exception.Message) -ForegroundColor Red
                $failed++
            }
        }
    }
    Write-Host ""
    Write-Host ("{0} file(s) restored." -f $restored) -ForegroundColor Green
    if ($failed) { Write-Host ("{0} file(s) FAILED - re-run after fixing them." -f $failed) -ForegroundColor Red }
    Write-Host ""
    return
}

# ---- collect ----------------------------------------------------------------
$enabled = @(Get-Content -LiteralPath $MlPath |
             Where-Object { $_ -match '^\+(.+)$' } |
             ForEach-Object { $Matches[1].TrimEnd() })

# Three tiers: named order, then anything unnamed, then the demoted list.
$UNRANKED = 10000

function Resolve-Rank {
    # Exact name wins. Failing that, a unique PREFIX match - so a mod folder
    # that came out of the installer with a suffix ("... - CBBE 3BA (3BBB)")
    # still ranks instead of silently dropping to unranked, which is the
    # mistake that let plain CBBE beat three 3BA replacers.
    #
    # Prefix, not substring: 'CBBE 3BA (3BBB)' appears in the MIDDLE of several
    # other mods' folder names, so a free substring match made half the list
    # ambiguous against the body mod.
    param([string]$ModName)
    for ($i = 0; $i -lt $ModPriority.Count; $i++) { if ($ModPriority[$i] -eq $ModName) { return $i } }
    for ($i = 0; $i -lt $ModLast.Count; $i++)     { if ($ModLast[$i]     -eq $ModName) { return 20000 + $i } }
    $hits = @()
    for ($i = 0; $i -lt $ModPriority.Count; $i++) { if ($ModName.StartsWith($ModPriority[$i], 'OrdinalIgnoreCase')) { $hits += @{ R = $i; N = $ModPriority[$i] } } }
    for ($i = 0; $i -lt $ModLast.Count; $i++)     { if ($ModName.StartsWith($ModLast[$i],     'OrdinalIgnoreCase')) { $hits += @{ R = 20000 + $i; N = $ModLast[$i] } } }
    if ($hits.Count -eq 1) { return $hits[0].R }
    if ($hits.Count -gt 1) {
        throw ("'{0}' matches {1} priority entries by prefix ({2}). Add its exact folder name to the list." -f `
               $ModName, $hits.Count, (($hits | ForEach-Object { $_.N }) -join '; '))
    }
    return $UNRANKED
}

$dupRule = @($VariantRules | Group-Object { $_.Mod } | Where-Object { $_.Count -gt 1 })
if ($dupRule.Count) {
    throw ("VariantRules names the same mod more than once: {0}. The later entry silently " +
           "replaces the earlier one, so the run succeeds using rules you did not intend." -f
           (($dupRule | ForEach-Object { $_.Name }) -join '; '))
}
$dupMod = @($ModPriority | Group-Object | Where-Object { $_.Count -gt 1 })
if ($dupMod.Count) {
    throw ("ModPriority lists the same mod more than once: {0}" -f (($dupMod | ForEach-Object { $_.Name }) -join '; '))
}

$prefer   = @{}
$fallback = @{}
foreach ($v in $VariantRules) {
    $prefer[$v.Mod] = @($v.Prefer)
    if ($v.ContainsKey('Fallback')) { $fallback[$v.Mod] = $v.Fallback }
}

$rankCache = @{}
$sets    = New-Object System.Collections.Generic.List[object]
$badFile = New-Object System.Collections.Generic.List[string]

foreach ($mod in $enabled) {
    $ssDir = Join-Path (Join-Path $ModsDir $mod) 'CalienteTools\BodySlide\SliderSets'
    if (-not (Test-Path -LiteralPath $ssDir)) { continue }
    foreach ($osp in @(Get-ChildItem -LiteralPath $ssDir -Filter *.osp -File -ErrorAction SilentlyContinue)) {
        try {
            $xml = [xml](Get-Content -LiteralPath $osp.FullName -Raw)
        } catch {
            # Do not swallow this. BodySlide fails on the same file, so every
            # outfit it declares is silently never built - which is exactly how
            # CT77StalhrimHR.osp went unnoticed for weeks.
            $badFile.Add(("{0}  <-  {1}   ({2})" -f $osp.Name, $mod, $_.Exception.Message))
            continue
        }
        foreach ($ss in @($xml.SelectNodes('//SliderSet'))) {
            # InnerText, NOT the dotted property. These elements carry
            # attributes (OutputFile has GenWeights), so PowerShell's dotted
            # access returns an XmlElement and [string] on it yields the
            # literal text "System.Xml.XmlElement".
            $opNode = $ss.SelectSingleNode('OutputPath')
            $ofNode = $ss.SelectSingleNode('OutputFile')
            $op = if ($opNode) { $opNode.InnerText.Trim() } else { '' }
            $of = if ($ofNode) { $ofNode.InnerText.Trim() } else { '' }
            if (-not $of) { continue }
            # Built on its own line. A bare comma inside a hashtable value is
            # parsed as an element separator, so `Target = ... -replace '/','\'`
            # is a syntax error rather than a string operation.
            $target = ($op.Trim('\', '/') + '\' + $of).ToLowerInvariant() -replace '/', '\'
            $target = $target -replace '\.nif$', ''
            if (-not $rankCache.ContainsKey($mod)) { $rankCache[$mod] = Resolve-Rank $mod }
            $r = $rankCache[$mod]
            $sets.Add([pscustomobject]@{
                Mod    = $mod
                Path   = $osp.FullName
                File   = $osp.Name
                Name   = $ss.GetAttribute('name')
                Target = $target
                Rank   = $r
            })
        }
    }
}

# ---- decide ------------------------------------------------------------------
$drop      = New-Object System.Collections.Generic.List[object]
$unresolved = New-Object System.Collections.Generic.List[object]
$byMod     = 0
$byVariant = 0

foreach ($g in @($sets | Group-Object Target | Where-Object { $_.Count -gt 1 })) {
    $cands   = @($g.Group)
    # Nothing is recorded until the whole group is decided, so a group that
    # turns out to be unresolvable leaves no half-applied removals behind.
    $pending = New-Object System.Collections.Generic.List[object]
    $winner  = $null
    $done    = $false

    $modsHere = @($cands | Select-Object -ExpandProperty Mod -Unique)

    if ($modsHere.Count -eq 1) {
        # A mod colliding with itself - its own variant sets. Rank is irrelevant
        # here, and demanding one wrongly parked every KS Hairdos body-type group.
        $survivors = $cands
    } else {
        # --- rule 1: mod priority ---------------------------------------------
        $best = ($cands | Measure-Object Rank -Minimum).Minimum
        if ($best -eq $UNRANKED -and @($cands | Where-Object { $_.Rank -eq $UNRANKED } |
                                      Select-Object -ExpandProperty Mod -Unique).Count -gt 1) {
            $unresolved.Add([pscustomobject]@{ Target = $g.Name; Why = 'no ranked mod'; Cands = $cands })
            continue
        }
        $survivors = @($cands | Where-Object { $_.Rank -eq $best })
        foreach ($loser in @($cands | Where-Object { $_.Rank -ne $best })) {
            $pending.Add([pscustomobject]@{
                Path = $loser.Path; File = $loser.File; Name = $loser.Name; Mod = $loser.Mod
                Target = $g.Name; Rule = 'mod'; Beaten = $survivors[0].Mod
            })
        }
        if ($survivors.Count -eq 1) { $winner = $survivors[0]; $done = $true }
    }

    # --- rule 2: variant preference inside the surviving mod ------------------
    if (-not $done) {
    $mod = $survivors[0].Mod
    $pats = if ($prefer.ContainsKey($mod)) { $prefer[$mod] } else { @() }

    # Patterns narrow progressively. A pattern that matches several does not
    # fail the group, it shrinks the pool and the next pattern decides within
    # it; a pattern that matches nothing is simply skipped. Only running out of
    # patterns with more than one candidate left is ambiguous.
    $winner = $null
    $pool = $survivors
    foreach ($pat in $pats) {
        $hit = @($pool | Where-Object { $_.Name -match $pat })
        if ($hit.Count -eq 1) { $winner = $hit[0]; break }
        if ($hit.Count -gt 1) { $pool = $hit }
    }
    if (-not $winner -and $fallback[$mod] -eq 'first') { $winner = $pool[0] }
    if (-not $winner) {
        $unresolved.Add([pscustomobject]@{ Target = $g.Name; Why = "no variant rule for '$mod'"; Cands = $survivors })
        continue
    }
    foreach ($loser in @($survivors | Where-Object { $_.Name -ne $winner.Name })) {
        $pending.Add([pscustomobject]@{
            Path = $loser.Path; File = $loser.File; Name = $loser.Name; Mod = $loser.Mod
            Target = $g.Name; Rule = 'variant'; Beaten = $winner.Name
        })
    }
    }

    # --- commit, unless removal by name would take the winner with it --------
    # Sets are removed from a file by NAME, so a loser sharing both file and
    # name with the WINNER cannot be removed without removing the winner too.
    # Duplicates that are all losers are fine - both copies go, which is what
    # was wanted. The earlier version refused the whole group whenever any
    # duplicate existed, which left the Barkeeper collision unresolved even
    # though its duplicates were both losing sets.
    # Test the CANDIDATES, not the pending drops. A twin sharing the winner's
    # name never lands in the drop list - the loser filter compares by name and
    # excludes it - so checking only the drops reported a clean group while
    # quietly leaving two sets on the output.
    $sameName = @($cands | Where-Object { $_.Path -eq $winner.Path -and $_.Name -eq $winner.Name })
    if ($sameName.Count -gt 1) {
        $unresolved.Add([pscustomobject]@{
            Target = $g.Name; Why = 'winner shares a name with another set in the same file'; Cands = $cands })
        continue
    }
    foreach ($d in $pending) {
        $drop.Add($d)
        if ($d.Rule -eq 'mod') { $byMod++ } else { $byVariant++ }
    }
}

# Safety net: never remove the last set writing an output.
$keptPerTarget = @{}
foreach ($s in $sets) {
    if (-not $keptPerTarget.ContainsKey($s.Target)) { $keptPerTarget[$s.Target] = 0 }
    $keptPerTarget[$s.Target]++
}
foreach ($d in $drop) { $keptPerTarget[$d.Target]-- }
$orphans = @($keptPerTarget.GetEnumerator() | Where-Object { $_.Value -lt 1 })
if ($orphans.Count) {
    throw ("BUG: {0} output(s) would end up with no slider set at all, first is '{1}'. Nothing written." -f $orphans.Count, $orphans[0].Key)
}

# ---- report ------------------------------------------------------------------
Write-Host ""
Write-Host ("=== {0} ===" -f $(if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' })) -ForegroundColor Cyan
Write-Host ""
Write-Host ("  {0} slider set(s) across {1} enabled mod(s)" -f $sets.Count, $enabled.Count)
if ($badFile.Count) {
    Write-Host ("  {0} .osp file(s) DID NOT PARSE - BodySlide cannot read these either:" -f $badFile.Count) -ForegroundColor Red
    foreach ($b in $badFile) { Write-Host ("      {0}" -f $b) -ForegroundColor Red }
}
Write-Host ""
Write-Host ("  {0} set(s) removed by mod priority" -f $byMod)
Write-Host ("  {0} set(s) removed by variant preference" -f $byVariant)
Write-Host ("  {0} total" -f $drop.Count) -ForegroundColor Green
Write-Host ""
Write-Host ("  {0} group(s) still ambiguous - that is your remaining dialog count" -f $unresolved.Count) -ForegroundColor $(if ($unresolved.Count) { 'Yellow' } else { 'Green' })

if ($unresolved.Count) {
    Write-Host ""
    Write-Host "  ambiguous groups by reason:" -ForegroundColor Yellow
    foreach ($u in @($unresolved | Group-Object Why | Sort-Object Count -Descending)) {
        Write-Host ("    {0,5}  {1}" -f $u.Count, $u.Name) -ForegroundColor Yellow
    }
}
Write-Host ""
Write-Host "  removals by file:"
foreach ($f in @($drop | Group-Object File | Sort-Object Count -Descending)) {
    Write-Host ("    {0,5}  {1}" -f $f.Count, $f.Name)
}
Write-Host ""

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("BodySlide pick - which slider set wins each output")
$lines.Add((Get-Date -Format 'yyyy-MM-dd HH:mm'))
$lines.Add(("mode: {0}" -f $(if ($Apply) { 'APPLY' } else { 'dry run' })))
$lines.Add("")
if ($badFile.Count) {
    $lines.Add("UNPARSEABLE .osp FILES - BodySlide skips these too, so their outfits never build")
    foreach ($b in $badFile) { $lines.Add("  $b") }
    $lines.Add("")
}
$lines.Add(("{0} removed by mod priority, {1} by variant preference, {2} total" -f $byMod, $byVariant, $drop.Count))
$lines.Add(("{0} group(s) still ambiguous" -f $unresolved.Count))
$lines.Add("")
$lines.Add("STILL AMBIGUOUS - add a rule for these, or answer them in the dialog")
foreach ($u in $unresolved) {
    $lines.Add(("  {0}    [{1}]" -f $u.Target, $u.Why))
    foreach ($c in $u.Cands) { $lines.Add(("      [{0}]  {1}" -f $c.Mod, $c.Name)) }
}
$lines.Add("")
$lines.Add("REMOVED")
foreach ($d in ($drop | Sort-Object Target)) {
    $lines.Add(("  {0}" -f $d.Target))
    $lines.Add(("      drop [{0}]  {1}" -f $d.Mod, $d.Name))
    $lines.Add(("      beaten by ({0})  {1}" -f $d.Rule, $d.Beaten))
}
[IO.File]::WriteAllLines($Out, $lines, (New-Object Text.UTF8Encoding $false))
Write-Host ("  report written: {0}" -f $Out) -ForegroundColor Green
Write-Host ""

if (-not $drop.Count) { Write-Host "Nothing to do."; Write-Host ""; return }
if (-not $Apply) {
    Write-Host "Nothing written. Read the report, then re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ---- write --------------------------------------------------------------------
$removed = 0
foreach ($f in @($drop | Group-Object Path)) {
    $path  = $f.Name
    $names = @($f.Group | Select-Object -ExpandProperty Name)

    Copy-Item -LiteralPath $path -Destination ("{0}.bak-{1}" -f $path, $Stamp) -Force

    $xml = [xml](Get-Content -LiteralPath $path -Raw)
    foreach ($ss in @($xml.SelectNodes('//SliderSet'))) {
        if ($names -contains $ss.GetAttribute('name')) {
            [void]$ss.ParentNode.RemoveChild($ss)
            $removed++
        }
    }
    $xml.Save($path)
    Write-Host ("  {0,-46} {1} removed" -f (Split-Path $path -Leaf), $names.Count) -ForegroundColor Green
}

Write-Host ""
Write-Host ("{0} slider set(s) removed. Backups: *.osp.bak-{1}" -f $removed, $Stamp) -ForegroundColor Green
Write-Host "Undo with -Restore."
Write-Host ""
