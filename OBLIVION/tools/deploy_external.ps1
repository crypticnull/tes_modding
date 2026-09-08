#Requires -Version 5.1
<#
  Some files a mod ships cannot be deployed by MO2 at all, because they live
  outside the game directory its virtual filesystem covers. This handles them.

    X:\MODDING\OBLIVION\tools\deploy_external.ps1            report only
    X:\MODDING\OBLIVION\tools\deploy_external.ps1 -Apply     copy them

  1. Engine.ini            -> Documents\My Games\Oblivion Remastered\Saved\Config\Windows
     Parked by nexus2 under the mod's Root\ tree, which MO2 never deploys.
  2. Character preset .sav -> Documents\My Games\Oblivion Remastered\Saved\SaveGames
  3. Every mod's Root\ tree -> the game folder, mirrored

  On 3: MO2 does not deploy Root\ - that is Root Builder's job and it is not
  installed. So without this step UNBSE's loader, UE4SS.dll and MagicLoader all
  sit in mod folders where nothing loads them, and the game runs unmodded while
  MO2 looks perfectly healthy.

  These tools also locate the game from their OWN position on disk - MagicLoader
  ignores -g doing it - so it is not enough to point a launcher at the mod copy.
  They have to physically sit beside OblivionRemastered.exe. Only their location
  needs to be real: launched through MO2 they still read the virtual Data\ and
  still write output into overwrite, so mods stay the source of truth and the
  game folder holds a mirror. -Undo reverses the whole thing.

  Existing files are backed up, never overwritten blind.
#>

[CmdletBinding()]
param([switch]$Apply, [switch]$Undo)

$ErrorActionPreference = 'Stop'

$Instance = 'X:\MODDING\OBLIVION\OBLIVION_REMASTERED'
$GameDir  = 'C:\Program Files (x86)\Steam\steamapps\common\Oblivion Remastered'
$ModsDir  = Join-Path $Instance 'mods'
$Dloads   = Join-Path $Instance 'downloads'
$GameDocs = "$env:USERPROFILE\Documents\My Games\Oblivion Remastered\Saved"
$ConfigDir = Join-Path $GameDocs 'Config\Windows'
$Saves     = Join-Path $GameDocs 'SaveGames'
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$Work     = Join-Path $env:TEMP ("ext_$Stamp")

$PresetArchives = @('Lilia 1.2 Update - Sliders and sewer save-1283-1-2-1746566729.zip')

function Get-SevenZip {
    foreach ($c in @("$env:ProgramFiles\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
        if (Test-Path -LiteralPath $c) { return $c } }
    $c = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

$Manifest   = 'X:\MODDING\OBLIVION\data\root_deployed.json'
$RootBackup = Join-Path 'X:\MODDING\OBLIVION\backups' "game-root-$Stamp"

$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to write' }

# -Undo reverses step 3 only - it is the only step that writes into the game
# folder, and the only one worth being able to take back wholesale.
if ($Undo) {
    Write-Host "=== undo Root\ deployment ($mode) ==="
    if (-not (Test-Path -LiteralPath $Manifest)) { Write-Host "  no manifest - nothing was ever deployed"; return }
    $man = @(Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json)
    Write-Host ("  manifest lists {0} file(s)" -f $man.Count)
    $del = 0; $res = 0; $gone = 0
    foreach ($r in $man) {
        $d = Join-Path $GameDir $r.rel
        if (-not (Test-Path -LiteralPath $d)) { $gone++; continue }
        if ($r.origin -eq 'overwrote' -and $r.backup -and (Test-Path -LiteralPath $r.backup)) {
            Write-Host ("  restore  {0}" -f $r.rel)
            if ($Apply) { Copy-Item -LiteralPath $r.backup -Destination $d -Force }
            $res++
        } else {
            Write-Host ("  remove   {0}" -f $r.rel)
            if ($Apply) { Remove-Item -LiteralPath $d -Force }
            $del++
        }
    }
    Write-Host ""
    Write-Host ("  {0} to remove, {1} to restore, {2} already gone" -f $del, $res, $gone)
    if ($Apply) {
        Remove-Item -LiteralPath $Manifest -Force -ErrorAction SilentlyContinue
        Write-Host "Undone. The game folder is back to how it was."
    } else { Write-Host "Nothing changed. Re-run with -Apply." }
    return
}

Write-Host "=== external files ($mode) ==="
Write-Host ("game docs: {0}" -f $GameDocs)
if (-not (Test-Path -LiteralPath $GameDocs)) {
    Write-Host "  NOT FOUND - launch the game once so it creates this, then re-run."
    return
}
Write-Host ""

# ---- 1. Engine.ini --------------------------------------------------------
Write-Host "--- 1. Engine.ini ---"
$found = @(Get-ChildItem -LiteralPath $ModsDir -Recurse -File -Filter 'Engine.ini' -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match '(?i)\\Root\\' })
if (-not $found.Count) {
    Write-Host "  none staged by any mod"
} else {
    if ($found.Count -gt 1) {
        Write-Host ("  {0} mods ship an Engine.ini - only ONE may be active:" -f $found.Count)
        $found | ForEach-Object { Write-Host ("    {0}" -f $_.FullName.Substring($ModsDir.Length).TrimStart('\')) }
        Write-Host "  Refusing to guess. Disable all but one, then re-run."
    } else {
        $src = $found[0]
        Write-Host ("  from: {0}" -f $src.FullName.Substring($ModsDir.Length).TrimStart('\'))
        Write-Host ("  size: {0:N0} bytes" -f $src.Length)
        $dst = Join-Path $ConfigDir 'Engine.ini'
        if (Test-Path -LiteralPath $dst) {
            $cur = (Get-Item -LiteralPath $dst).Length
            Write-Host ("  existing Engine.ini is {0:N0} bytes - it will be backed up" -f $cur)
        } else {
            Write-Host "  no existing Engine.ini"
        }
        if ($Apply) {
            New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
            if (Test-Path -LiteralPath $dst) { Copy-Item -LiteralPath $dst -Destination "$dst.bak-$Stamp" -Force }
            Copy-Item -LiteralPath $src.FullName -Destination $dst -Force
            # UE rewrites this file on exit and can undo the tweaks; the usual
            # community fix is to mark it read-only.
            (Get-Item -LiteralPath $dst).IsReadOnly = $true
            Write-Host "  copied, and set read-only so the game cannot overwrite it"
        }
    }
}
Write-Host ""

# ---- 2. character preset saves -------------------------------------------
Write-Host "--- 2. character preset saves ---"
if (-not (Test-Path -LiteralPath $Saves)) {
    Write-Host "  SaveGames folder does not exist yet - launch the game once."
} else {
    Write-Host ("  {0} save(s) already present" -f @(Get-ChildItem -LiteralPath $Saves -File -Filter '*.sav' -EA SilentlyContinue).Count)
    $sz = Get-SevenZip
    if (-not $sz) { Write-Host "  7-Zip required, skipping" }
    else {
        New-Item -ItemType Directory -Force -Path $Work | Out-Null
        foreach ($a in $PresetArchives) {
            $path = Join-Path $Dloads $a
            if (-not (Test-Path -LiteralPath $path)) { Write-Host ("  not downloaded: {0}" -f $a); continue }
            $ex = Join-Path $Work ([IO.Path]::GetFileNameWithoutExtension($a))
            & $sz x "-o$ex" -y -bso0 -bsp0 -- "$path" | Out-Null
            $savs = @(Get-ChildItem -LiteralPath $ex -Recurse -File -Filter '*.sav' -EA SilentlyContinue)
            Write-Host ("  {0}: {1} save(s)" -f $a, $savs.Count)
            foreach ($s in $savs) {
                # already there, byte for byte? then this has run before - don't duplicate
                $dupe = @(Get-ChildItem -LiteralPath $Saves -File -Filter '*.sav' -EA SilentlyContinue |
                          Where-Object { $_.Length -eq $s.Length } |
                          Where-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm MD5).Hash -eq
                                         (Get-FileHash -LiteralPath $s.FullName  -Algorithm MD5).Hash })
                if ($dupe.Count) {
                    Write-Host ("    already present: {0}" -f $dupe[0].Name)
                    continue
                }
                $dst = Join-Path $Saves $s.Name
                if (Test-Path -LiteralPath $dst) {
                    $dst = Join-Path $Saves ("{0} ({1}){2}" -f [IO.Path]::GetFileNameWithoutExtension($s.Name), $Stamp, $s.Extension)
                }
                Write-Host ("    -> {0}" -f (Split-Path $dst -Leaf))
                if ($Apply) { Copy-Item -LiteralPath $s.FullName -Destination $dst -Force }
            }
        }
        if ($Apply) { Remove-Item -LiteralPath $Work -Recurse -Force -EA SilentlyContinue }
    }
}
Write-Host ""

# ---- 3. Root\ payloads into the game folder -------------------------------
#
#  MO2 does not deploy a mod's Root\ folder. That is Root Builder's job, and
#  Root Builder is not installed (the OBR wiki warns it needs OBR-specific
#  exclusions first or it caches gigabytes and hangs MO2 on launch). So every
#  file under Root\ is inert: it sits in the mod folder where nothing loads it.
#
#  That is not a corner case here. UNBSE ships its entire payload that way -
#  UNBSELoader.exe, UE4SS.dll, UE4SS-settings.ini - so with Root\ undeployed
#  there is no script extender installed at all, however healthy MO2 looks.
#  MagicLoader is the same story.
#
#  Root\ is defined as "relative to the game directory", so deploying it is a
#  straight mirror. Every file written is recorded in a manifest, and -Undo
#  reverses it exactly: files we created are deleted, files we overwrote are
#  restored from the backup taken at the time.
#
Write-Host "--- 3. Root\ payloads ---"
$mlFile  = Join-Path $Instance 'profiles\Default\modlist.txt'
$enabled = @()
foreach ($l in (Get-Content -LiteralPath $mlFile)) { if ($l -match '^\+(.+)$') { $enabled += $Matches[1].TrimEnd() } }

# modlist.txt is highest-priority-first, so the first mod to claim a relative
# path is the one that wins - same rule MO2 applies to the virtual tree.
$claim  = [ordered]@{}
$byMod  = @{}
foreach ($m in $enabled) {
    $rd = Join-Path (Join-Path $ModsDir $m) 'Root'
    if (-not (Test-Path -LiteralPath $rd)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $rd -Recurse -File -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($rd.Length).TrimStart('\')
        # Engine.ini belongs in Documents, which step 1 handles. A copy in the
        # game tree is inert and only invites confusion about which one is live.
        if ($rel -match '(?i)^OblivionRemastered\\Saved\\Config\\') { continue }
        if ($claim.Contains($rel)) { continue }
        $claim[$rel] = @{ src = $f.FullName; mod = $m }
        if (-not $byMod.ContainsKey($m)) { $byMod[$m] = 0 }
        $byMod[$m]++
    }
}

if (-not $claim.Count) {
    Write-Host "  no enabled mod ships a Root\ folder"
} else {
    Write-Host ("  {0} file(s) from {1} mod(s):" -f $claim.Count, $byMod.Count)
    foreach ($m in ($byMod.Keys | Sort-Object)) { Write-Host ("    {0}  ({1} files)" -f $m, $byMod[$m]) }

    $new = @(); $chg = @(); $same = 0
    foreach ($rel in $claim.Keys) {
        $s = Get-Item -LiteralPath $claim[$rel].src
        $d = Join-Path $GameDir $rel
        if (-not (Test-Path -LiteralPath $d)) { $new += $rel; continue }
        $e = Get-Item -LiteralPath $d
        if ($e.Length -ne $s.Length -or $e.LastWriteTimeUtc -ne $s.LastWriteTimeUtc) { $chg += $rel } else { $same++ }
    }
    Write-Host ("  {0} new, {1} differing, {2} already current" -f $new.Count, $chg.Count, $same)
    foreach ($r in @($new + $chg)) { Write-Host ("    {0}   [{1}]" -f $r, $claim[$r].mod) }

    if ($Apply -and ($new.Count -or $chg.Count)) {
        $man = @()
        if (Test-Path -LiteralPath $Manifest) { $man = @(Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json) }
        $known = @{}; foreach ($r in $man) { $known[$r.rel] = $true }

        foreach ($rel in @($new + $chg)) {
            $d = Join-Path $GameDir $rel
            $origin = 'created'; $bk = $null
            if (Test-Path -LiteralPath $d) {
                if ($known[$rel]) {
                    # ours from a previous run - just refresh it, keep the original record
                    $origin = 'created'
                } else {
                    # a genuine game file. Keep a copy so -Undo can put it back.
                    $origin = 'overwrote'
                    $bk = Join-Path $RootBackup $rel
                    New-Item -ItemType Directory -Force -Path (Split-Path $bk -Parent) | Out-Null
                    Copy-Item -LiteralPath $d -Destination $bk -Force
                }
            }
            New-Item -ItemType Directory -Force -Path (Split-Path $d -Parent) | Out-Null
            Copy-Item -LiteralPath $claim[$rel].src -Destination $d -Force
            if (-not $known[$rel]) {
                $man += [pscustomobject]@{ rel = $rel; mod = $claim[$rel].mod; origin = $origin; backup = $bk }
                $known[$rel] = $true
            }
        }
        # Record every file we are responsible for, not only the ones this run
        # happened to copy. Otherwise -Undo silently leaves behind everything an
        # earlier run deployed, which is most of them on any re-run.
        foreach ($rel in $claim.Keys) {
            if ($known[$rel]) { continue }
            $man += [pscustomobject]@{ rel = $rel; mod = $claim[$rel].mod; origin = 'created'; backup = $null }
            $known[$rel] = $true
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $Manifest -Parent) | Out-Null
        # NB: -AsArray is PowerShell 7 only. On 5.1 a one-element array collapses
        # to a bare object, so the reader wraps its result in @() to compensate.
        ($man | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $Manifest -Encoding UTF8
        Write-Host ("  copied. manifest: {0} entr(ies)" -f $man.Count)
        if (Test-Path -LiteralPath $RootBackup) { Write-Host ("  overwritten originals backed up -> {0}" -f $RootBackup) }
    }
    Write-Host "  note: this is a MIRROR. Change the mod, re-run this. Never edit the copy."
    Write-Host "  to reverse it entirely:  deploy_external.ps1 -Undo -Apply"
}
Write-Host ""

if (-not $Apply) { Write-Host "Nothing changed. Re-run with -Apply." }
else { Write-Host "Done." }
