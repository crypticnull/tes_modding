#Requires -Version 5.1
<#
  bodyslide_coverage.ps1 - which installed outfits will NOT follow your OBody
  body shape, because nothing provides a BodySlide slider set for them.

      bodyslide_coverage.ps1              summary + report file
      bodyslide_coverage.ps1 -All         scan every mesh, not just armor/clothes
      bodyslide_coverage.ps1 -Detail      list the uncovered meshes per mod

  WHY THIS MATTERS

  OBody applies your chosen preset as a live morph. A morph needs a .tri file,
  and a .tri only exists if BodySlide built the mesh from a slider set. An
  outfit that ships prebuilt meshes with no .osp anywhere is frozen at whatever
  body its author used - it still works, it just keeps its own shape while
  everything else follows you. The Amazing World of Bikini Armor is exactly
  this case: meshes and textures, no CalienteTools folder at all.

  HOW COVERAGE IS DECIDED

  Every .osp declares OutputPath plus OutputFile, and OutputFile is a BASE name
  with no extension - "farmerrobef" produces farmerrobef_0.nif and _1.nif. So a
  mesh is covered when some slider set, in ANY enabled mod, targets its folder
  and base name. Coverage is deliberately checked across the whole load order,
  not per mod: Remodeled Armor supplies the sets that build vanilla armour, and
  a per-mod test would wrongly call every vanilla path uncovered.

  A sibling .tri is reported separately. A mesh with no slider set but a .tri
  next to it was either built earlier or shipped with morphs, so it may still
  respond - that column is a hint, not a verdict.

  STATIC MESHES ARE NOT GAPS

  Several kinds of mesh legitimately have no slider set and never will - ground
  models, first-person arms, hair and wigs, rigid head and neck gear, weapons
  and jewellery that happen to live under meshes\armor\, and male meshes. They
  are counted in their own column. On this load order that is the difference
  between "1119 uncovered" and about 130 that are actually worth looking at.

  The two original cases, kept for the detail:

    - ground models, the item lying on the floor or in the inventory. Named
      with a _gnd or _g suffix, sometimes malformed by the author as _gndnif
      or _gnd.nif. On TAWOBA Remastered these alone were 613 of 814 apparent
      gaps.
    - rigid head and neck gear - helms, masks, circlets, gorgets, collars,
      headdresses, hoods, crowns. They do not deform with the body.

  Both are counted in their own column rather than as missing coverage, so
  the NO SET number means "body-fitted mesh that nothing builds", which is
  the only number worth acting on. -ShowStatic lists them if you want to
  audit the classification.

  Reads only. Nothing is modified.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [switch]$All,
    [switch]$Detail,
    [switch]$ShowStatic,
    [string]$Out
)

$ErrorActionPreference = 'Stop'

$Instance = Join-Path $Root 'SKYRIM_SE'
$ModsDir  = Join-Path $Instance 'mods'
$MlPath   = Join-Path $Instance 'profiles\Default\modlist.txt'
if (-not $Out) { $Out = Join-Path $Root 'logs\bodyslide_coverage.txt' }

foreach ($p in @($ModsDir, $MlPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" }
}
$outDir = Split-Path $Out -Parent
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$enabled = @(Get-Content -LiteralPath $MlPath |
             Where-Object { $_ -match '^\+(.+)$' } |
             ForEach-Object { $Matches[1].TrimEnd() })

Write-Host ""
Write-Host ("=== {0} enabled mod(s) ===" -f $enabled.Count) -ForegroundColor Cyan

# ---- pass 1: every output a slider set claims, anywhere in the load order ----
$covered = New-Object 'System.Collections.Generic.HashSet[string]'
$setCount = 0

foreach ($mod in $enabled) {
    $ssDir = Join-Path (Join-Path $ModsDir $mod) 'CalienteTools\BodySlide\SliderSets'
    if (-not (Test-Path -LiteralPath $ssDir)) { continue }
    foreach ($osp in @(Get-ChildItem -LiteralPath $ssDir -Filter *.osp -File -ErrorAction SilentlyContinue)) {
        try { $xml = [xml](Get-Content -LiteralPath $osp.FullName -Raw) } catch { continue }
        foreach ($ss in @($xml.SelectNodes('//SliderSet'))) {
            $opNode = $ss.SelectSingleNode('OutputPath')
            $ofNode = $ss.SelectSingleNode('OutputFile')
            $op = if ($opNode) { $opNode.InnerText.Trim() } else { '' }
            $of = if ($ofNode) { $ofNode.InnerText.Trim() } else { '' }
            if (-not $of) { continue }
            # Build on its own line: a bare comma inside a hashtable value or an
            # argument list is parsed as a separator, not part of the expression.
            $key = ($op.Trim('\', '/') + '\' + $of).ToLowerInvariant() -replace '/', '\'
            $key = $key -replace '\.nif$', ''
            [void]$covered.Add($key)
            $setCount++
        }
    }
}

Write-Host ("  {0} slider set output(s) claimed" -f $setCount)

# ---- pass 2: every outfit mesh on disk --------------------------------------
$rows = New-Object System.Collections.Generic.List[object]
$uncoveredDetail = New-Object System.Collections.Generic.List[string]

foreach ($mod in $enabled) {
    $meshRoot = Join-Path (Join-Path $ModsDir $mod) 'meshes'
    if (-not (Test-Path -LiteralPath $meshRoot)) { continue }

    $nifs = @(Get-ChildItem -LiteralPath $meshRoot -Recurse -File -Filter *.nif -ErrorAction SilentlyContinue)
    if (-not $All) {
        $nifs = @($nifs | Where-Object { $_.FullName -match '\\(armor|clothes)\\' })
    }
    if (-not $nifs.Count) { continue }

    $seen = @{}
    $total = 0; $cov = 0; $unc = 0; $uncWithTri = 0; $stat = 0
    $uncList    = New-Object System.Collections.Generic.List[string]
    $statList   = New-Object System.Collections.Generic.List[string]

    foreach ($n in $nifs) {
        # femalebody_0.nif and femalebody_1.nif are one built output, not two.
        $base = $n.BaseName -replace '_[01]$', ''
        $dir  = $n.DirectoryName
        $rel  = $dir.Substring($meshRoot.Length).Trim('\')
        $key  = ('meshes\' + $rel + '\' + $base).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $total++

        if ($covered.Contains($key)) { $cov++; continue }

        # Not a gap. Deliberately still narrow: boots, gauntlets and tassets DO
        # deform and must stay countable. Every pattern here was derived from
        # the real load order, not guessed:
        #
        #   ground models  a 'gnd' or 'go' FOLDER (all the TIWOBA sets), a
        #                  _gnd/_go suffix, a bare gnd/go suffix, and the
        #                  author-malformed '_gnd.nif' inside the name.
        #   first person   1stperson* arms - not body-fitted.
        #   hair and wigs  KS Hairdos lives under 'kswigshdt', so 'hair' alone
        #                  misses 230 meshes. Match 'wig' too.
        #   rigid head     circ/gorg/head/face/hat and friends - matching the
        #                  full words ('circlet', 'gorget') missed 'circ1' and
        #                  'gorg2', which is most of TAWOBA's headgear.
        #   weapons and    swords, shields, rings and amulets live under
        #   jewellery      meshes\armor\ and are not body meshes at all.
        #   male           a male mesh whose female twin sits beside it.
        $dirLower = $rel.ToLowerInvariant()
        $segs     = @($dirLower -split '\\')
        $isStatic =
            ($segs -contains 'gnd' -or $segs -contains 'go') -or
            ($base -match '(_gnd|_go|_g|_gndnif)$') -or
            ($base -match '_gnd\.nif$') -or
            ($base.Length -ge 5 -and $base -match '(gnd|go)$') -or
            ($base -match '^1stperson') -or
            ($dirLower -match '(hair|wig)' -or $base -match '(hair|wig)') -or
            ($base -match '(helm|mask|circ|gorg|head|face|visor|hood|crown|horn|hat|tiara|diadem|earring)') -or
            ($base -match '^(neck|coll)') -or
            ($base -match '(ring|amulet|necklace|sword|dagger|axe|shield|hammer|mace|staff|halo|scimitar|arrow|quiver|torch|pickaxe|club|spear|katana|glaive)')
        if (-not $isStatic -and $base -match 'm$') {
            # male twin test: same folder, same name with a trailing f
            $femaleTwin = Join-Path $dir (($base -replace 'm$','f') + '.nif')
            if (Test-Path -LiteralPath $femaleTwin) { $isStatic = $true }
        }
        if ($isStatic) {
            $stat++
            $statList.Add(("      {0}" -f $key))
            continue
        }

        $unc++
        $hasTri = Test-Path -LiteralPath (Join-Path $dir ($base + '.tri'))
        if ($hasTri) { $uncWithTri++ }
        $uncList.Add(("      {0}{1}" -f $key, $(if ($hasTri) { '   (has .tri)' } else { '' })))
    }

    if (-not $total) { continue }
    $rows.Add([pscustomobject]@{
        Mod        = $mod
        Total      = $total
        Covered    = $cov
        Uncovered  = $unc
        WithTri    = $uncWithTri
        Static     = $stat
    })
    if ($unc -gt 0) {
        $uncoveredDetail.Add(("  [{0}]  {1} body mesh(es) with no slider set, of {2}" -f $mod, $unc, $total))
        foreach ($u in $uncList) { $uncoveredDetail.Add($u) }
        $uncoveredDetail.Add("")
    }
    if ($ShowStatic -and $stat -gt 0) {
        $uncoveredDetail.Add(("  [{0}]  {1} static mesh(es) - ground models and rigid gear" -f $mod, $stat))
        foreach ($t in $statList) { $uncoveredDetail.Add($t) }
        $uncoveredDetail.Add("")
    }
}

$bad = @($rows | Where-Object { $_.Uncovered -gt 0 } | Sort-Object Uncovered -Descending)

Write-Host ""
Write-Host ("=== {0} mod(s) contain BODY meshes nothing builds ===" -f $bad.Count) -ForegroundColor Cyan
Write-Host ""
Write-Host ("  {0,-52} {1,7} {2,7} {3,8} {4,7}" -f 'mod', 'meshes', 'no set', 'has .tri', 'static')
foreach ($r in $bad) {
    Write-Host ("  {0,-52} {1,7} {2,7} {3,8} {4,7}" -f `
        $(if ($r.Mod.Length -gt 52) { $r.Mod.Substring(0,49) + '...' } else { $r.Mod }), `
        $r.Total, $r.Uncovered, $r.WithTri, $r.Static)
}
$statOnly = @($rows | Where-Object { $_.Uncovered -eq 0 -and $_.Static -gt 0 })
if ($statOnly.Count) {
    Write-Host ""
    Write-Host ("  {0} mod(s) have only static meshes uncovered - ground models and rigid gear, not gaps:" -f $statOnly.Count) -ForegroundColor DarkGray
    foreach ($r in ($statOnly | Sort-Object Static -Descending)) {
        Write-Host ("      {0,-52} {1,5} static" -f $r.Mod, $r.Static) -ForegroundColor DarkGray
    }
}
Write-Host ""
Write-Host ("  fully covered: {0} mod(s)" -f @($rows | Where-Object { $_.Uncovered -eq 0 }).Count)
Write-Host ""

# ---- report -----------------------------------------------------------------
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("BodySlide coverage - outfits that will not follow an OBody preset")
$lines.Add((Get-Date -Format 'yyyy-MM-dd HH:mm'))
$lines.Add(("scope: {0}" -f $(if ($All) { 'every mesh' } else { 'meshes under \armor\ or \clothes\ only' })))
$lines.Add("")
$lines.Add(("{0} slider set outputs claimed across {1} enabled mods" -f $setCount, $enabled.Count))
$lines.Add("")
$lines.Add(("{0,-60} {1,7} {2,7} {3,8} {4,7}" -f 'MOD', 'MESHES', 'NO SET', 'HAS TRI', 'STATIC'))
foreach ($r in ($rows | Sort-Object Uncovered -Descending)) {
    $lines.Add(("{0,-60} {1,7} {2,7} {3,8} {4,7}" -f $r.Mod, $r.Total, $r.Uncovered, $r.WithTri, $r.Static))
}
if ($Detail) {
    $lines.Add("")
    $lines.Add("UNCOVERED MESHES")
    foreach ($d in $uncoveredDetail) { $lines.Add($d) }
}
[IO.File]::WriteAllLines($Out, $lines, (New-Object Text.UTF8Encoding $false))

Write-Host ("  report written: {0}" -f $Out) -ForegroundColor Green
Write-Host ""
