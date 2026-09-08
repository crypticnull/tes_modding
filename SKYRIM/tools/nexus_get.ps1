#Requires -Version 5.1
<#
  nexus_get.ps1 - fetch one file from Nexus, for the Skyrim build.

    nexus_get.ps1 -Mod 169962                     list the files, download nothing
    nexus_get.ps1 -Mod 169962 -Main               get the primary/newest MAIN file
    nexus_get.ps1 -Mod 169962 -File 812345         get that exact file id
    nexus_get.ps1 -Mod 169962 -Main -Extract      ...and unpack it beside the archive

  -Mod takes an id or a full Nexus URL.

  WHY THIS EXISTS AND NOT nexus2.ps1

  nexus2.ps1 is an installer, not a downloader. It is hard-wired to
  GameDomain 'oblivionremastered' and everything after the download - the
  Data/Paks/UE4SS/OBSE channel sorting, the FOMOD handling, the mod folder
  naming, the collection ordering - is Oblivion Remastered's file layout.
  Pointing it at Skyrim would not install anything correctly.

  Skyrim's MO2 install path is a solved problem: MO2 installs Skyrim archives
  itself, properly, because Skyrim is a first-class MO2 game. So all that is
  needed here is the download half, which this is. It reuses the same verified
  pattern nexus2 uses: .part file, size check, md5 check, atomic rename.

  Reads the API key from this game's own data\ folder, falling back to the
  Oblivion one only if that is missing. API downloads need a premium Nexus
  account; without one the download_link call returns 403 and the free route
  is the browser.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Mod,
    [int]$File,
    [switch]$Main,
    [switch]$Extract,
    [switch]$Force,
    [switch]$IncludeOld,
    [string]$Game    = 'skyrimspecialedition',
    [string]$Dest    = 'X:\MODDING\SKYRIM\_incoming',
    [string]$KeyFile = ''
)

$ErrorActionPreference = 'Stop'
$UserAgent = 'SkyrimDLSS5Setup/1.0 (PowerShell)'

# PS 5.1 still defaults to SSL3/TLS1.0 on some boxes; the API is TLS 1.2 only.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ------------------------------------------------------------------ helpers --
# This root owns its own key so it does not reach into the Oblivion install.
# The Oblivion path stays as a fallback only so an existing setup keeps working;
# once the local copy exists it is the one used.
$script:KeyCandidates = @(
    'X:\MODDING\SKYRIM\data\.nexus_api_key',
    'X:\MODDING\data\.nexus_api_key'
)
if ($KeyFile) { $script:KeyCandidates = @($KeyFile) }

function Get-ApiKey {
    foreach ($c in $script:KeyCandidates) {
        if (Test-Path -LiteralPath $c) { return (Get-Content -LiteralPath $c -Raw).Trim() }
    }
    throw ("no API key found. Looked in:`n  " + ($script:KeyCandidates -join "`n  "))
}

function Invoke-Nexus {
    param([string]$Path)
    $uri = "https://api.nexusmods.com$Path"
    try {
        $r = Invoke-RestMethod -Uri $uri -Method Get -Headers @{
            apikey = (Get-ApiKey); 'User-Agent' = $UserAgent; Accept = 'application/json' }
        Start-Sleep -Milliseconds 300
        return $r
    } catch {
        $err = $_
        $code = $null
        if ($err.Exception.Response) { $code = [int]$err.Exception.Response.StatusCode }
        Start-Sleep -Milliseconds 300
        if ($code -eq 401) { throw "API key rejected (401)." }
        if ($code -eq 403) { throw "403 - premium required for API downloads, or the mod is hidden/adult-blocked." }
        if ($code -eq 404) { throw "404 - no such mod or file in game '$Game'." }
        if ($code -eq 429) { throw "429 - rate limited. Wait a few minutes." }
        if ($code)         { throw "HTTP $code - $($err.Exception.Message)" }
        throw "request failed: $($err.Exception.Message)"
    }
}

function Get-SevenZip {
    foreach ($c in @("$env:ProgramFiles\7-Zip\7z.exe",
                     "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
                     "$env:ProgramFiles\NanaZip\NanaZipC.exe")) {
        if (Test-Path -LiteralPath $c) { return $c } }
    $c = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

# ---------------------------------------------------------------- mod id -----
$id = $null
if ($Mod -match '/mods/(\d+)')   { $id = [int]$Matches[1] }
elseif ($Mod -match '^\s*(\d+)\s*$') { $id = [int]$Matches[1] }
if (-not $id) { throw "could not read a mod id out of '$Mod'" }

New-Item -ItemType Directory -Force -Path $Dest | Out-Null

$info = Invoke-Nexus "/v1/games/$Game/mods/$id.json"
Write-Host ""
Write-Host ("=== {0}  (mod {1}, {2}) ===" -f $info.name, $id, $Game) -ForegroundColor Cyan
Write-Host ("    by {0}   version {1}" -f $info.uploaded_by, $info.version)
if ($info.status -and $info.status -ne 'published') {
    Write-Host ("    STATUS: {0}" -f $info.status) -ForegroundColor Yellow
}
Write-Host ""

$fl = Invoke-Nexus "/v1/games/$Game/mods/$id/files.json"

# OLD_VERSION and ARCHIVED are hidden by default - they are superseded uploads
# and grabbing one by accident is how you end up version-mismatched. But for a
# version-locked tool they are the whole point: SKSE's current build targets
# whatever runtime is newest, so a downgraded game needs an older SKSE, which
# only lives under OLD_VERSION. -IncludeOld shows them.
$hidden = 0
if ($IncludeOld) {
    $files = @($fl.files | Where-Object { $_.category_name })
} else {
    $files  = @($fl.files | Where-Object { $_.category_name -and $_.category_name -notin @('OLD_VERSION','ARCHIVED') })
    $hidden = @($fl.files | Where-Object { $_.category_name -in @('OLD_VERSION','ARCHIVED') }).Count
}
if (-not $files.Count) { throw "no files listed for mod $id (try -IncludeOld)" }

# ------------------------------------------------------------------- list ----
if (-not $Main -and -not $File) {
    Write-Host ("{0,-10} {1,-12} {2,-12} {3,-10} {4}" -f 'FILE ID', 'CATEGORY', 'VERSION', 'SIZE', 'NAME')
    foreach ($f in ($files | Sort-Object category_name, name)) {
        $mb = if ($f.size_in_bytes) { [math]::Round([int64]$f.size_in_bytes / 1MB, 1) } else { [math]::Round([int64]$f.size_kb / 1024, 1) }
        $star = if ($f.is_primary) { '*' } else { ' ' }
        Write-Host ("{0,-10} {1,-12} {2,-12} {3,7} MB {4}{5}" -f $f.file_id, $f.category_name, $f.version, $mb, $star, $f.name)
    }
    Write-Host ""
    Write-Host "* = the mod's primary file.  Re-run with -File <id>, or -Main for the primary."
    if ($hidden) {
        Write-Host ("{0} older/archived file(s) hidden - pass -IncludeOld to see them." -f $hidden) -ForegroundColor Yellow
    }
    Write-Host ""
    return
}

# ---------------------------------------------------------------- choose -----
$pick = $null
if ($File) {
    # Search EVERY file, not the filtered set. Naming a file id is an explicit
    # choice, and the usual reason to name one is that it is an old build -
    # which is exactly what the default filter hides. Making -File obey the
    # filter meant you could read an id off the -IncludeOld listing and then
    # be told it does not exist.
    $pick = $fl.files | Where-Object { [int]$_.file_id -eq $File } | Select-Object -First 1
    if (-not $pick) { throw "file id $File does not exist on mod $id. List them with: -IncludeOld" }
    if ($pick.category_name -in @('OLD_VERSION','ARCHIVED')) {
        Write-Host ("    note: this is an {0} file - deliberate here, but check the version." -f $pick.category_name) -ForegroundColor Yellow
    }
} else {
    $pick = $files | Where-Object { $_.is_primary } | Select-Object -First 1
    if (-not $pick) {
        $pick = $files | Where-Object { $_.category_name -eq 'MAIN' } |
                Sort-Object { [int64]$_.uploaded_timestamp } -Descending | Select-Object -First 1
    }
    if (-not $pick) { throw "no primary or MAIN file on mod $id - pick one by id from the list." }
}

$want = if ($pick.size_in_bytes) { [int64]$pick.size_in_bytes } else { [int64]$pick.size_kb * 1024 }
$target = Join-Path $Dest $pick.file_name

Write-Host ("--- {0} ---" -f $pick.name)
Write-Host ("    file id  {0}   category {1}   version {2}" -f $pick.file_id, $pick.category_name, $pick.version)
Write-Host ("    {0}   ({1} MB)" -f $pick.file_name, [math]::Round($want / 1MB, 1))
Write-Host ""

# --------------------------------------------------------------- download ----
$have = (Test-Path -LiteralPath $target) -and
        ($want -le 0 -or [math]::Abs((Get-Item -LiteralPath $target).Length - $want) -lt 4096)

if ($have -and -not $Force) {
    Write-Host "    already downloaded and the right size - skipping (use -Force to refetch)"
} else {
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
    $dl  = Invoke-Nexus "/v1/games/$Game/mods/$id/files/$($pick.file_id)/download_link.json"
    $uri = @($dl)[0].URI
    $part = "$target.part"

    Write-Host "    downloading..."
    $wc = New-Object Net.WebClient
    try { $wc.Headers.Add('User-Agent', $UserAgent); $wc.DownloadFile($uri, $part) }
    finally { $wc.Dispose() }

    # Verify before the file gets its real name. A truncated archive that is
    # named correctly is worse than no archive - it fails later, somewhere else.
    $got = (Get-Item -LiteralPath $part).Length
    if ($want -gt 0 -and [math]::Abs($got - $want) -ge 4096) {
        Remove-Item -LiteralPath $part -Force
        throw "size mismatch: got $got bytes, expected $want"
    }
    if ($pick.md5) {
        $h = (Get-FileHash -LiteralPath $part -Algorithm MD5).Hash
        if ($h -ne $pick.md5.ToUpper()) {
            Remove-Item -LiteralPath $part -Force
            throw "md5 mismatch - the download is corrupt"
        }
        Write-Host "    md5 ok"
    }
    Move-Item -LiteralPath $part -Destination $target -Force
    Write-Host ("    saved   {0}" -f $target) -ForegroundColor Green
}

# ---------------------------------------------------------------- extract ----
if ($Extract) {
    $safe = ($pick.file_name -replace '\.(zip|7z|rar)$','') -replace '[^\w\.\- ]','_'
    $ex = Join-Path $Dest ("{0}_{1}" -f $id, $safe)
    $sz = Get-SevenZip
    if (-not $sz) { throw "7-Zip not found (winget install --id 7zip.7zip -e)" }
    New-Item -ItemType Directory -Force -Path $ex | Out-Null
    & $sz x "-o$ex" -y -bso0 -bsp0 -- "$target" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7-Zip exit code $LASTEXITCODE" }
    Write-Host ("    extracted to {0}" -f $ex) -ForegroundColor Green
    foreach ($f in (Get-ChildItem -LiteralPath $ex | Select-Object -First 20)) {
        Write-Host ("       {0}" -f $f.Name)
    }
}
Write-Host ""
