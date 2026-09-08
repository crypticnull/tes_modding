#Requires -Version 5.1
<#
  fomod_export.ps1 - pull every FOMOD's option tree and images into one JSON.

    X:\MODDING\SKYRIM\tools\fomod_export.ps1
    X:\MODDING\SKYRIM\tools\fomod_export.ps1 -Mods 198,30174

  Writes X:\MODDING\SKYRIM\data\fomods.json

  WHY THIS EXISTS

  A FOMOD wizard is a renderer for fomod\ModuleConfig.xml plus the images that
  XML points at. Everything needed to show you the same choices is in the
  archive - it just needs getting out. The archives themselves are far too big
  to move anywhere (CBBE is 497 MB, Reverie 726 MB), so this opens each one in
  place, takes only the fomod folder and the referenced images, shrinks the
  images, and writes a single small file.

  Images are downscaled to 460px wide and re-encoded as JPEG quality 68. A
  FOMOD's option images are screenshots meant to be looked at, not studied, and
  full-size they would run to tens of megabytes across seven mods.

  Nothing is installed and nothing is changed. Read-only apart from the JSON.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [int[]]$Mods  = @(198, 30174, 57339, 64314, 22168, 18994, 31300, 1988),
    [switch]$Fresh,   # discard what is already in fomods.json instead of merging
    [int]$MaxWidth = 460,
    [int]$Quality  = 68
)

$ErrorActionPreference = 'Stop'
$Dloads = Join-Path $Root 'SKYRIM_SE\downloads'
$OutDir = Join-Path $Root 'data'
$OutFile = Join-Path $OutDir 'fomods.json'
$Work   = Join-Path $env:TEMP ("fomodx-" + (Get-Date -Format 'HHmmss'))

Add-Type -AssemblyName System.Drawing

function Get-NodeText {
    param($Node)
    # "" + $node stringifies an XmlElement to its type name, which is how
    # "System.Xml.XmlElement" ended up in the output instead of the description.
    if ($null -eq $Node) { return '' }
    if ($Node -is [string]) { return $Node }
    try { return ("" + $Node.InnerText) } catch { return '' }
}

function Get-SevenZip {
    foreach ($c in @("$env:ProgramFiles\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe",
                     "$env:ProgramFiles\NanaZip\NanaZipC.exe")) {
        if (Test-Path -LiteralPath $c) { return $c } }
    $c = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}
$SZ = Get-SevenZip; if (-not $SZ) { throw "7-Zip not found" }

# JPEG encoder, so the images come out small instead of as huge PNGs
$jpg = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep  = New-Object Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality, [int64]$Quality)

function ConvertTo-DataUri {
    param([string]$Path)
    try {
        $img = [Drawing.Image]::FromFile($Path)
    } catch { return $null }
    try {
        $w = $img.Width; $h = $img.Height
        if ($w -gt $MaxWidth) { $h = [int]($h * ($MaxWidth / $w)); $w = $MaxWidth }
        $bmp = New-Object Drawing.Bitmap $w, $h
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($img, 0, 0, $w, $h)
        $g.Dispose()
        $ms = New-Object IO.MemoryStream
        $bmp.Save($ms, $jpg, $ep)
        $bmp.Dispose()
        return "data:image/jpeg;base64," + [Convert]::ToBase64String($ms.ToArray())
    } catch { return $null }
    finally { $img.Dispose() }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$all = New-Object System.Collections.Generic.List[object]

Write-Host ""
Write-Host "=== FOMOD export ===" -ForegroundColor Cyan

foreach ($id in $Mods) {
    # the downloader puts the mod id in the filename, either -123- or " 123 "
    $arc = @(Get-ChildItem -LiteralPath $Dloads -File |
             Where-Object { $_.Extension.ToLower() -in @('.7z','.zip','.rar') -and
                            $_.Name -match ("[-\s]" + $id + "[-\s]") } |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if (-not $arc) { Write-Host ("  {0,6}  no archive in downloads - skipped" -f $id) -ForegroundColor Yellow; continue }

    $tmp = Join-Path $Work "$id"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    # 1. FIND the fomod folder before extracting anything.
    #
    # Wildcard extraction was the wrong tool. "fomod\*" matches only at the
    # archive root, and 7-Zip's -r did not rescue it for Remodeled Armor, whose
    # config sits one level down at
    #   Remodeled Armor SE - CBBE 3BA\fomod\ModuleConfig.xml
    # so the archive kept reporting itself as "not a FOMOD".
    #
    # Listing first costs a second and removes the guessing: read the real path
    # out of the table of contents, then extract that exact folder. It also
    # covers XP32, whose folder is "Fomod" with a capital F.
    $names = @(& $SZ l -ba -slt -- $arc.FullName 2>$null |
               Where-Object { $_ -match '^Path = ' } |
               ForEach-Object { $_.Substring(7) })
    $mcRel = @($names | Where-Object { $_ -match '(?i)(^|[\\/])fomod[\\/]ModuleConfig\.xml$' } |
               Sort-Object Length | Select-Object -First 1)
    if (-not $mcRel.Count) {
        Write-Host ("  {0,6}  {1}  -> not a FOMOD" -f $id, $arc.Name) -ForegroundColor Yellow
        continue
    }
    $fomodDir = Split-Path $mcRel[0] -Parent          # "...\fomod" or "Fomod"
    $prefix   = Split-Path $fomodDir  -Parent          # the wrapper folder, or ''

    & $SZ x "-o$tmp" -y -bso0 -bsp0 -- $arc.FullName ($fomodDir + '\*') | Out-Null
    $mc = @(Get-ChildItem -LiteralPath $tmp -Recurse -File -Filter 'ModuleConfig.xml' -ErrorAction SilentlyContinue)
    if (-not $mc.Count) {
        Write-Host ("  {0,6}  {1}  -> extract of '{2}' produced nothing" -f $id, $arc.Name, $fomodDir) -ForegroundColor Red
        continue
    }

    # image paths in the XML are relative to the folder ABOVE fomod\
    $base = if ($prefix) { Join-Path $tmp $prefix } else { $tmp }

    [xml]$cfg = Get-Content -LiteralPath $mc[0].FullName -Raw
    # Get-NodeText, not "" + node. moduleName usually stringifies fine, but when
    # the author gives it attributes - <moduleName position="Left" colour="..."> -
    # the adapter hands back an XmlElement and you get the literal text
    # "System.Xml.XmlElement" as the mod's name. Blended Roads does exactly that.
    $modName = (Get-NodeText $cfg.config.moduleName).Trim()

    # 2. collect image paths, then fetch any that live outside fomod\
    $imgPaths = New-Object System.Collections.Generic.List[string]
    foreach ($n in $cfg.SelectNodes('//image')) {
        $p = "" + $n.path
        if ($p) { $imgPaths.Add($p) }
    }
    $outside = @($imgPaths | Where-Object { $_ -notmatch '^(?i)fomod[\\/]' } | Select-Object -Unique)
    if ($outside.Count) {
        $pats  = @($outside | ForEach-Object { if ($prefix) { Join-Path $prefix $_ } else { $_ } })
        $args2 = @("x", "-o$tmp", "-y", "-bso0", "-bsp0", "--", $arc.FullName) + $pats
        & $SZ @args2 | Out-Null
    }

    function Resolve-Img {
        param([string]$p)
        if (-not $p) { return $null }
        $f = Join-Path $base $p
        if (Test-Path -LiteralPath $f) { return ConvertTo-DataUri $f }
        # some archives differ in case or leading folder; find it by name
        $leaf = Split-Path $p -Leaf
        $hit = @(Get-ChildItem -LiteralPath $tmp -Recurse -File -Filter $leaf -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($hit.Count) { return ConvertTo-DataUri $hit[0].FullName }
        return $null
    }

    $groups = New-Object System.Collections.Generic.List[object]
    foreach ($stepNode in @($cfg.config.installSteps.installStep)) {
        if (-not $stepNode) { continue }
        foreach ($g in @($stepNode.optionalFileGroups.group)) {
            if (-not $g) { continue }
            $plugs = New-Object System.Collections.Generic.List[object]
            foreach ($pl in @($g.plugins.plugin)) {
                if (-not $pl) { continue }
                $plugs.Add([pscustomobject]@{
                    name = "" + $pl.name
                    desc = ((Get-NodeText $pl.description) -replace '\s+',' ').Trim()
                    type = "" + $pl.typeDescriptor.type.name
                    img  = Resolve-Img ("" + $pl.image.path)
                })
            }
            $groups.Add([pscustomobject]@{
                step = "" + $stepNode.name; name = "" + $g.name
                type = "" + $g.type; plugins = $plugs })
        }
    }

    $all.Add([pscustomobject]@{
        id       = $id
        name     = if ($modName) { $modName } else { $arc.BaseName }
        archive  = $arc.Name
        cond     = ($null -ne $cfg.config.conditionalFileInstalls)
        required = ($null -ne $cfg.config.requiredInstallFiles)
        groups   = $groups
    })

    $nImg  = @($groups | ForEach-Object { $_.plugins } | Where-Object { $_.img }).Count
    $nWant = @($groups | ForEach-Object { $_.plugins }).Count
    # "0 images" is ambiguous on its own - a FOMOD with no screenshots at all
    # looks identical to one whose screenshots failed to extract. Say which.
    $imgTxt = if ($imgPaths.Count -eq 0) { "no images in the config" }
              elseif ($nImg -eq 0)       { "{0} image(s) declared, NONE resolved" -f $imgPaths.Count }
              else                       { "{0}/{1} option(s) with an image" -f $nImg, $nWant }
    Write-Host ("  {0,6}  {1,-42} {2} group(s), {3}{4}" -f `
        $id, $modName, $groups.Count, $imgTxt,
        $(if ($cfg.config.conditionalFileInstalls) { "  [conditional]" } else { "" })) -ForegroundColor Green
}

# ---------------------------------------------------------------- merge ----
# Merge, do not clobber. Running this for two mods must not throw away the
# other six.
#
# Every step below is named and wrapped. The previous version failed with a
# bare "Argument types do not match" and no line number, which is useless -
# the collections here come from two different worlds (freshly built
# PSCustomObjects with List[object] members, and whatever ConvertFrom-Json
# hands back on this host) and they do not compare or enumerate alike. So:
# no casts, string keys throughout, plain arrays, and each stage says what it
# was doing if it dies.
# NOT @($all). The array subexpression operator throws
#   "Argument types do not match"
# when its operand is a System.Collections.Generic.List[object] - and only that
# type. @() on a List[string], a List[psobject] or an ArrayList is fine, which
# is why nothing else here ever tripped it and why the error named no line.
# .ToArray() is the plain way to say the same thing.
$step = 'start'
$final = $all.ToArray()
try {
    if (-not $Fresh -and (Test-Path -LiteralPath $OutFile)) {

        $step = 'reading the existing fomods.json'
        $prevRaw = (Get-Content -LiteralPath $OutFile -Raw | ConvertFrom-Json)

        # PS 5.1 hands a JSON array to the pipeline as ONE Object[], PS 7
        # unrolls it. Flatten one level either way rather than depending on it.
        $step = 'flattening the existing entries'
        $flat = New-Object System.Collections.ArrayList
        foreach ($x in @($prevRaw)) {
            if ($null -eq $x) { continue }
            if ($x -is [object[]]) { foreach ($y in $x) { if ($y) { [void]$flat.Add($y) } } }
            else { [void]$flat.Add($x) }
        }

        # keyed on the STRING form of the id. Int32 from this run and Int64
        # from the JSON are different types and comparing them is exactly the
        # sort of thing that produced the last error.
        $step = 'indexing what was just exported'
        $done = @{}
        foreach ($a in $all) { $done[[string]$a.id] = $true }

        $step = 'selecting the entries to carry over'
        $keep = @()
        foreach ($x in $flat) {
            $k = [string]$x.id
            if ($k -and -not $done.ContainsKey($k)) { $keep += ,$x }
        }

        $step = 'combining'
        $final = $all.ToArray() + $keep
        Write-Host ("  carried over {0} existing entr(ies)" -f $keep.Count)
    }

    # Sort on a plain property, not a scriptblock key. Ordering here is a
    # nicety; it is not worth failing the whole export over.
    $step = 'sorting'
    $final = @($final | Sort-Object -Property id)
}
catch {
    Write-Host ""
    Write-Host ("  merge failed while {0}: {1}" -f $step, $_.Exception.Message) -ForegroundColor Red
    Write-Host "  falling back to writing ONLY what was just exported." -ForegroundColor Yellow
    Write-Host ("  the previous file is untouched at {0}" -f $OutFile) -ForegroundColor Yellow
    Write-Host "  re-run with no -Mods to rebuild every entry from scratch." -ForegroundColor Yellow
    $final = $all.ToArray()
}

# ---------------------------------------------------------------- write ----
# Temp file then move. A crash midway through serialising used to be able to
# leave fomods.json truncated, and a truncated wizard looks like a working
# wizard that has lost half your mods.
$step = 'serialising'
$tmpOut = "$OutFile.tmp"
($final | ConvertTo-Json -Depth 8 -Compress) | Set-Content -LiteralPath $tmpOut -Encoding UTF8
$check = @(Get-Content -LiteralPath $tmpOut -Raw | ConvertFrom-Json)
if (-not $check.Count) { throw "the file just written does not read back as JSON - left at $tmpOut" }
Move-Item -LiteralPath $tmpOut -Destination $OutFile -Force

Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue

$mb = [math]::Round((Get-Item -LiteralPath $OutFile).Length / 1MB, 2)
Write-Host ""
Write-Host ("wrote {0}  ({1} MB, {2} mod(s))" -f $OutFile, $mb, $final.Count) -ForegroundColor Green
Write-Host ""
