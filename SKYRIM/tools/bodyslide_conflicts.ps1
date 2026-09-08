#Requires -Version 5.1
<#
  bodyslide_conflicts.ps1 - find out, before you press Batch Build, exactly
  which slider sets collide and therefore how many "Choose Output Set" dialogs
  BodySlide is going to throw at you.

      bodyslide_conflicts.ps1                 summary + report file
      bodyslide_conflicts.ps1 -Full           list every conflict, not just a sample

  WHY

  BodySlide raises one dialog per group of slider sets that write the SAME
  output mesh. With a large wardrobe that is hundreds of dialogs, and clicking
  through them is both unbearable and error-prone. But the collisions are
  entirely determined by files on disk: every .osp declares OutputPath and
  OutputFile, so the whole set of conflicts can be computed up front.

  What comes out of this is the shape of the problem - are the collisions a
  handful of body sets, or one mod duplicating another wholesale? The second
  case is fixed by disabling one mod, not by clicking.

  It only reads. Nothing is modified.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [switch]$Full,
    [string]$Out
)

$ErrorActionPreference = 'Stop'

$Instance = Join-Path $Root 'SKYRIM_SE'
$ModsDir  = Join-Path $Instance 'mods'
$MlPath   = Join-Path $Instance 'profiles\Default\modlist.txt'
if (-not $Out) { $Out = Join-Path $Root 'logs\bodyslide_conflicts.txt' }

foreach ($p in @($ModsDir, $MlPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" }
}
$outDir = Split-Path $Out -Parent
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# ---- which mods are switched on -------------------------------------------
# modlist.txt is written most-recently-applied first, so the LAST line is the
# lowest priority. Priority does not affect whether two sets collide, only
# which file survives, so order is kept purely to make the report readable.
$enabled = @(Get-Content -LiteralPath $MlPath |
             Where-Object { $_ -match '^\+(.+)$' } |
             ForEach-Object { $Matches[1].TrimEnd() })

Write-Host ""
Write-Host ("=== scanning {0} enabled mod(s) for slider sets ===" -f $enabled.Count) -ForegroundColor Cyan

# ---- collect every slider set ----------------------------------------------
$sets = New-Object System.Collections.Generic.List[object]
$modsWithSets = 0
$badFiles = New-Object System.Collections.Generic.List[string]

foreach ($mod in $enabled) {
    $ssDir = Join-Path (Join-Path $ModsDir $mod) 'CalienteTools\BodySlide\SliderSets'
    if (-not (Test-Path -LiteralPath $ssDir)) { continue }
    $osps = @(Get-ChildItem -LiteralPath $ssDir -Filter *.osp -File -ErrorAction SilentlyContinue)
    if (-not $osps.Count) { continue }
    $modsWithSets++

    foreach ($osp in $osps) {
        try { $xml = [xml](Get-Content -LiteralPath $osp.FullName -Raw) }
        catch { $badFiles.Add(("{0}  <-  {1}" -f $osp.Name, $mod)); continue }

        foreach ($ss in @($xml.SelectNodes('//SliderSet'))) {
            $name = [string]$ss.name
            # InnerText, NOT the property accessor. These elements carry
            # attributes (OutputFile has GenWeights), so PowerShell's dotted
            # access returns an XmlElement and [string] on it yields the literal
            # text "System.Xml.XmlElement". Every set then looks like it writes
            # the same file and the collision count is nonsense - which is
            # exactly what the first run of this script reported.
            $opNode = $ss.SelectSingleNode('OutputPath')
            $ofNode = $ss.SelectSingleNode('OutputFile')
            $op = if ($opNode) { $opNode.InnerText.Trim() } else { '' }
            $of = if ($ofNode) { $ofNode.InnerText.Trim() } else { '' }
            if (-not $of) { continue }
            # Normalise so 'meshes\Armor\X' and 'meshes\armor\x' are one target.
            $target = ($op.Trim('\', '/') + '\' + $of.Trim()).ToLowerInvariant() -replace '/', '\'
            $sets.Add([pscustomobject]@{
                Mod    = $mod
                File   = $osp.Name
                Name   = $name
                Target = $target
            })
        }
    }
}

Write-Host ("  {0} slider set(s) across {1} mod(s)" -f $sets.Count, $modsWithSets)
if ($badFiles.Count) {
    Write-Host ("  {0} .osp file(s) would not parse:" -f $badFiles.Count) -ForegroundColor Yellow
    foreach ($b in $badFiles) { Write-Host ("      {0}" -f $b) -ForegroundColor Yellow }
}

# ---- group by output target -------------------------------------------------
$groups    = @($sets | Group-Object Target | Where-Object { $_.Count -gt 1 })
$conflicts = @($groups | Sort-Object Count -Descending)

Write-Host ""
Write-Host ("=== {0} colliding output(s) - that is how many dialogs you would get ===" -f $conflicts.Count) -ForegroundColor Cyan

# ---- which mod pairs are responsible ---------------------------------------
# This is the number that decides the fix. If two mods account for nearly all
# of the collisions, one of them is a duplicate wardrobe and the answer is to
# switch it off, not to click.
$pairCount = @{}
foreach ($g in $conflicts) {
    $mods = @($g.Group | Select-Object -ExpandProperty Mod | Sort-Object -Unique)
    $key  = ($mods -join '  vs  ')
    if ($pairCount.ContainsKey($key)) { $pairCount[$key]++ } else { $pairCount[$key] = 1 }
}
$pairs = @($pairCount.GetEnumerator() | Sort-Object Value -Descending)

Write-Host ""
Write-Host "  collisions by mod combination:" -ForegroundColor Cyan
foreach ($p in $pairs) {
    Write-Host ("    {0,5}  {1}" -f $p.Value, $p.Key)
}

# ---- write the report -------------------------------------------------------
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("BodySlide slider set collisions")
$lines.Add((Get-Date -Format 'yyyy-MM-dd HH:mm'))
$lines.Add("")
$lines.Add(("{0} slider sets across {1} enabled mods" -f $sets.Count, $modsWithSets))
$lines.Add(("{0} outputs are written by more than one set" -f $conflicts.Count))
$lines.Add("")
$lines.Add("COLLISIONS BY MOD COMBINATION")
foreach ($p in $pairs) { $lines.Add(("{0,5}  {1}" -f $p.Value, $p.Key)) }
$lines.Add("")
$lines.Add("DETAIL")
$show = if ($Full) { $conflicts } else { @($conflicts | Select-Object -First 40) }
foreach ($g in $show) {
    $lines.Add(("  {0}" -f $g.Name))
    foreach ($s in ($g.Group | Sort-Object Mod)) {
        $lines.Add(("      [{0}]  {1}" -f $s.Mod, $s.Name))
    }
}
if (-not $Full -and $conflicts.Count -gt 40) {
    $lines.Add(("  ... {0} more. Re-run with -Full for all of them." -f ($conflicts.Count - 40)))
}

[IO.File]::WriteAllLines($Out, $lines, (New-Object Text.UTF8Encoding $false))

Write-Host ""
Write-Host ("  report written: {0}" -f $Out) -ForegroundColor Green
Write-Host ""
