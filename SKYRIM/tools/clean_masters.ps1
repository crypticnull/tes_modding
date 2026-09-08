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

  THE TWO THINGS THAT MADE THIS HARD

  1. -D: REQUIRES A TRAILING BACKSLASH. Documented, easily missed, and without it
     xEdit silently falls back to whatever it finds for itself.
  2. xEdit has its own Steam detection and has been observed cleaning the Steam
     copy of the game even when the registry points elsewhere. So this does not
     trust -D: - it hashes the target file in BOTH locations before and after and
     tells you which one actually changed. If it cleaned the wrong copy, the
     result is still usable: the files are byte-identical, so -Collect copies
     whatever got cleaned into the mod folder.
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

Write-Host ""
Write-Host ("=== QuickAutoClean: {0} plugin(s) ===" -f $Plugins.Count) -ForegroundColor Cyan
Write-Host ("  exe   {0}" -f $qac.FullName)
Write-Host ("  stock {0}" -f $StockData)
Write-Host ("  steam {0}" -f $(if (Test-Path -LiteralPath $SteamData) { $SteamData } else { '(absent)' }))
foreach ($p in $Plugins) { Write-Host ("    - {0}" -f $p) }

if (-not $Apply) {
    Write-Host ""
    Write-Host "DRY RUN. Re-run with -Apply to actually clean." -ForegroundColor Yellow
    return
}
if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. Close it first."
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($p in $Plugins) {
    Write-Host ""
    Write-Host ("--- {0}" -f $p) -ForegroundColor Cyan

    $b1 = Snap $StockData $p
    $b2 = Snap $SteamData $p
    if (-not $b1 -and -not $b2) {
        Write-Host "    not present in either Data folder - skipped" -ForegroundColor Yellow
        $results.Add([pscustomobject]@{ Plugin=$p; Where='(missing)'; Before=0; After=0 }); continue
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
        $results.Add([pscustomobject]@{ Plugin=$p; Where='TIMEOUT'; Before=0; After=0 }); continue
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
    $results.Add([pscustomobject]@{ Plugin=$p; Where=$w; Before=$bef; After=$aft })
}

Write-Host ""
Write-Host "=== summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

# whichever copy got cleaned, put it where MO2 will use it
$steamOnly = @($results | Where-Object { $_.Where -eq 'Steam' })
if ($steamOnly.Count) {
    Write-Host ""
    Write-Host ("xEdit wrote to the Steam copy for {0} plugin(s). Collecting into the mod." -f $steamOnly.Count) -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $ModDir -Force | Out-Null
    foreach ($r in $steamOnly) {
        Copy-Item (Join-Path $SteamData $r.Plugin) (Join-Path $ModDir $r.Plugin) -Force
        Write-Host ("    collected {0}" -f $r.Plugin)
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ModDir 'meta.ini'))) {
        "[General]`ngameName=Skyrim Special Edition`nmodid=0`nversion=1.0`ncomments=xEdit QuickAutoClean output" |
            Set-Content -LiteralPath (Join-Path $ModDir 'meta.ini') -Encoding UTF8
    }
    Write-Host ""
    Write-Host "Make sure 'Cleaned Masters' is ENABLED (+) in modlist.txt before running DynDOLOD." -ForegroundColor Cyan
}
Write-Host ""
