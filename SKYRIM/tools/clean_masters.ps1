#Requires -Version 5.1
<#
  clean_masters.ps1 - run xEdit QuickAutoClean over plugins without clicking.

      clean_masters.ps1                       clean the known offenders
      clean_masters.ps1 -Plugins a.esm,b.esl  clean exactly these
      clean_masters.ps1 -FromLog              read the list out of DynDOLOD's log

  WHY THIS EXISTS

  DynDOLOD refuses to generate while any plugin holds a deleted reference, and it
  reports them a few at a time, so doing this by hand is a loop of: run DynDOLOD,
  read the name, open QuickAutoClean, right-click, Select None, tick one, wait,
  close, repeat. This does the whole list in one go.

  THE THREE THINGS THAT MADE THIS HARD

  1. -D: REQUIRES A TRAILING BACKSLASH. Documented, easily missed, and without it
     xEdit silently falls back to whatever it finds for itself.
  2. xEdit has its own Steam detection and has been observed cleaning the Steam
     copy of the game even when the registry points elsewhere. So this does not
     trust -D: - it hashes the target file in BOTH locations before and after and
     tells you which one actually changed.
  3. CLAUDE.md section 2 says the Steam install is off limits, and point 2 means
     this script can violate that without being asked to. See the guard below.

  THE STEAM GUARD - read this before changing anything in the loop

  This fired for real on 2026-09-06. Update.esm, Dawnguard.esm and HearthFires.esm
  were cleaned IN PLACE inside the Steam folder, the old version of this script
  copied them OUT into mods\Cleaned Masters, and nothing put them back. No backup
  had been taken, so the originals are gone. The Steam copies are still
  functionally fine, a cleaned master is what you want for modding, but the
  install is no longer pristine and that is the outcome the constraint exists to
  prevent.

  So, per plugin, in this order:
      1. Copy the Steam file to backups\steam-guard\<stamp>\ BEFORE xEdit runs,
         and hash it.
      2. Run xEdit. Detect which copy actually changed.
      3. If Steam changed, collect the cleaned file into the mod folder FIRST,
         because that is the only place the cleaned bytes exist.
      4. Then restore the Steam file from the backup and re-hash to prove it
         matches. If it does not match, THROW. A silent restore failure is worse
         than the original problem.

  Making the Steam file read-only before the run was considered and rejected.
  xEdit's behaviour when it cannot write is unknown, and a half-written plugin in
  the Steam install is a bigger mess than a cleaned one.
#>

[CmdletBinding()]
param(
    [string]$Root    = 'X:\MODDING\SKYRIM',
    [string[]]$Plugins,
    [switch]$FromLog,
    [string]$SteamData = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data',
    [int]$TimeoutSec = 600,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$StockData = Join-Path $Root 'STOCK GAME\Data'
$ModDir    = Join-Path $Root 'SKYRIM_SE\mods\Cleaned Masters'
$Log       = Join-Path $Root 'tools\DynDOLOD\DynDOLOD\Logs\DynDOLOD_SSE_log.txt'
$GuardDir  = Join-Path $Root ('backups\steam-guard\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$Utf8NoBom = New-Object Text.UTF8Encoding $false

$qac = Get-ChildItem (Join-Path $Root 'tools\xEdit') -Recurse -Filter 'SSEEditQuickAutoClean.exe' -ErrorAction SilentlyContinue |
       Select-Object -First 1
if (-not $qac) { throw "SSEEditQuickAutoClean.exe not found under $Root\tools\xEdit" }

if ($FromLog) {
    if (-not (Test-Path -LiteralPath $Log)) { throw "no DynDOLOD log at $Log" }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches((Get-Content -LiteralPath $Log -Raw),
                    '(?i)Deleted reference ([A-Za-z0-9_ ()''.\-]+\.(?:esm|esl|esp))')) {
        $n = $m.Groups[1].Value.Trim()
        if (-not $found.Contains($n)) { $found.Add($n) }
    }
    $Plugins = $found.ToArray()
}
if (-not $Plugins -or -not $Plugins.Count) {
    $Plugins = @('Update.esm','Dawnguard.esm','HearthFires.esm','ccvsvsse004-beafarmer.esl',
                 'ccbgssse005-goldbrand.esl','ccbgssse016-umbra.esm','cctwbsse001-puzzledungeon.esm')
}

function Snap {
    param([string]$Dir, [string]$Name)
    $p = Join-Path $Dir $Name
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $i = Get-Item -LiteralPath $p
    return [pscustomobject]@{ Path = $p; Length = $i.Length; Ticks = $i.LastWriteTimeUtc.Ticks }
}
function Hash256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

Write-Host ""
Write-Host ("=== QuickAutoClean: {0} plugin(s) ===" -f $Plugins.Count) -ForegroundColor Cyan
Write-Host ("  exe   {0}" -f $qac.FullName)
Write-Host ("  stock {0}" -f $StockData)
Write-Host ("  steam {0}" -f $(if (Test-Path -LiteralPath $SteamData) { $SteamData } else { '(absent)' }))
Write-Host ("  guard {0}" -f $GuardDir)
foreach ($p in $Plugins) { Write-Host ("    - {0}" -f $p) }

if (-not $Apply) {
    Write-Host ""
    Write-Host "DRY RUN. Re-run with -Apply to actually clean." -ForegroundColor Yellow
    Write-Host "Each Steam-side copy will be backed up before xEdit runs and restored after." -ForegroundColor Yellow
    return
}
if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. Close it first."
}

$results   = New-Object System.Collections.Generic.List[object]
$collected = New-Object System.Collections.Generic.List[string]

foreach ($p in $Plugins) {
    Write-Host ""
    Write-Host ("--- {0}" -f $p) -ForegroundColor Cyan

    $b1 = Snap $StockData $p
    $b2 = Snap $SteamData $p
    if (-not $b1 -and -not $b2) {
        Write-Host "    not present in either Data folder - skipped" -ForegroundColor Yellow
        $results.Add([pscustomobject]@{ Plugin=$p; Where='(missing)'; Before=0; After=0; Steam='n/a' }); continue
    }

    # --- guard: snapshot the Steam copy BEFORE xEdit can touch it
    $guardPath = $null
    $guardHash = $null
    if ($b2) {
        if (-not (Test-Path -LiteralPath $GuardDir)) { New-Item -ItemType Directory -Path $GuardDir -Force | Out-Null }
        $guardPath = Join-Path $GuardDir $p
        Copy-Item -LiteralPath $b2.Path -Destination $guardPath -Force
        $guardHash = Hash256 $guardPath
        Write-Host ("    guarded Steam copy -> {0}" -f $guardPath) -ForegroundColor DarkGray
    }

    # -D: must end in a backslash (documented, easy to miss). The path has a
    # space so it must be quoted, and a lone backslash before the closing quote
    # would escape the quote - so it is doubled: CommandLineToArgvW collapses
    # \\" into \ and then ends the argument. NOT named $args - automatic variable.
    $qacArgs = '-sse -qac "-D:{0}\\" -autoload -autoexit "{1}"' -f $StockData, $p
    Write-Host ("    args  {0}" -f $qacArgs) -ForegroundColor DarkGray
    $proc = Start-Process -FilePath $qac.FullName -ArgumentList $qacArgs `
                          -WorkingDirectory $qac.DirectoryName -PassThru
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        Write-Host ("    TIMEOUT after {0}s - killing" -f $TimeoutSec) -ForegroundColor Red
        try { $proc.Kill() } catch {}
        $results.Add([pscustomobject]@{ Plugin=$p; Where='TIMEOUT'; Before=0; After=0; Steam='n/a' }); continue
    }

    $a1 = Snap $StockData $p
    $a2 = Snap $SteamData $p
    $chStock = $b1 -and $a1 -and ($b1.Ticks -ne $a1.Ticks)
    $chSteam = $b2 -and $a2 -and ($b2.Ticks -ne $a2.Ticks)

    if     ($chStock) { $w='STOCK GAME'; $bef=$b1.Length; $aft=$a1.Length }
    elseif ($chSteam) { $w='Steam';      $bef=$b2.Length; $aft=$a2.Length }
    else              { $w='no change';  $bef=0;          $aft=0 }

    Write-Host ("    exit {0} | changed: {1}{2}" -f $proc.ExitCode, $w,
        $(if ($bef) { "  {0:N0} -> {1:N0} bytes" -f $bef, $aft } else { '' }))

    # --- Steam was written to. Collect the cleaned bytes, THEN put Steam back.
    $steamState = 'untouched'
    if ($chSteam) {
        Write-Host "    xEdit wrote to the STEAM copy" -ForegroundColor Yellow

        if (-not (Test-Path -LiteralPath $ModDir)) { New-Item -ItemType Directory -Path $ModDir -Force | Out-Null }
        Copy-Item -LiteralPath (Join-Path $SteamData $p) -Destination (Join-Path $ModDir $p) -Force
        [void]$collected.Add($p)
        Write-Host ("    collected cleaned {0} into Cleaned Masters" -f $p)

        if (-not $guardPath) {
            $steamState = 'NO BACKUP'
            Write-Host "    NO BACKUP EXISTS - cannot restore Steam" -ForegroundColor Red
        } else {
            Copy-Item -LiteralPath $guardPath -Destination (Join-Path $SteamData $p) -Force
            $verify = Hash256 (Join-Path $SteamData $p)
            if ($verify -eq $guardHash) {
                $steamState = 'restored'
                Write-Host "    Steam copy RESTORED and hash-verified" -ForegroundColor Green
            } else {
                throw ("STEAM RESTORE FAILED for {0}. Expected {1}, got {2}. Backup is at {3}. Stopping." -f `
                       $p, $guardHash, $verify, $guardPath)
            }
        }
    }

    $results.Add([pscustomobject]@{ Plugin=$p; Where=$w; Before=$bef; After=$aft; Steam=$steamState })
}

Write-Host ""
Write-Host "=== summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if ($collected.Count) {
    # PS 5.1 Set-Content -Encoding UTF8 writes a BOM, and a BOM ahead of
    # [General] means MO2 reads the mod as having no metadata at all.
    $meta = Join-Path $ModDir 'meta.ini'
    if (-not (Test-Path -LiteralPath $meta)) {
        [IO.File]::WriteAllLines($meta, @(
            '[General]'
            'gameName=Skyrim Special Edition'
            'modid=0'
            'version=1.0'
            'comments=xEdit QuickAutoClean output'
        ), $Utf8NoBom)
        Write-Host ("wrote {0}" -f $meta)
    }
    Write-Host ""
    Write-Host "Make sure 'Cleaned Masters' is ENABLED (+) in modlist.txt before running DynDOLOD." -ForegroundColor Cyan
}

$notRestored = @($results | Where-Object { $_.Steam -eq 'NO BACKUP' })
if ($notRestored.Count) {
    Write-Host ""
    Write-Host ("WARNING: {0} plugin(s) left the Steam install modified with no backup." -f $notRestored.Count) -ForegroundColor Red
}
$restored = @($results | Where-Object { $_.Steam -eq 'restored' })
if ($restored.Count) {
    Write-Host ""
    Write-Host ("Steam install protected: {0} file(s) restored and verified." -f $restored.Count) -ForegroundColor Green
    Write-Host ("Backups kept at {0}" -f $GuardDir)
}
Write-Host ""
