<#
.SYNOPSIS
    Snapshot Mod Organizer 2 instances into the tes_modding archive.

.DESCRIPTION
    Walks a root folder for MO2 instances, reads each one's ModOrganizer.ini,
    profiles and mods, and writes a dated, immutable snapshot into
    games/<game>/snapshots/YYYY-MM-DD-<profile>/.

    Reads nothing outside -Root. Writes nothing outside -Repo. No modules, no
    network, Windows PowerShell 5.1 and up.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File X:\MODDING\tes_modding\tools\export-mo2.ps1 -Root X:\MODDING
#>
[CmdletBinding()]
param(
    # Folder to search for MO2 instances.
    [string] $Root = 'X:\MODDING',

    # Repo root. Defaults to the parent of this script.
    [string] $Repo,

    # Snapshot only this instance folder. Default is every instance found.
    [string] $Instance,

    # Snapshot only this MO2 profile. Default is every profile in the instance.
    [string] $ProfileName,

    # Free text stored with the snapshot, e.g. "after ENB swap".
    [string] $Note = '',

    # How deep under -Root to look for ModOrganizer.ini.
    [int] $Depth = 3
)

$ErrorActionPreference = 'Stop'

if (-not $Repo) { $Repo = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path (Join-Path $Repo 'PLAN.md'))) {
    throw "No PLAN.md at $Repo. Pass -Repo pointing at the tes_modding checkout."
}
if (-not (Test-Path $Root)) { throw "Root not found: $Root" }

# ---------------------------------------------------------------- helpers ---

function Get-CleanIniValue {
    param([string] $Value)
    if ($null -eq $Value) { return '' }
    $v = $Value.Trim()
    # MO2 wraps many values as @ByteArray(...) and escapes backslashes.
    if ($v -match '^@ByteArray\((.*)\)$') { $v = $Matches[1] }
    if ($v -match '^@Invalid\(\)$') { $v = '' }
    $v = $v -replace '\\\\', '\'
    return $v.Trim('"')
}

function Read-Ini {
    param([string] $Path)
    $result = [ordered]@{}
    $section = 'General'
    $result[$section] = [ordered]@{}
    if (-not (Test-Path $Path)) { return $result }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith(';') -or $t.StartsWith('#')) { continue }
        if ($t -match '^\[(.+)\]$') {
            $section = $Matches[1]
            if (-not $result.Contains($section)) { $result[$section] = [ordered]@{} }
            continue
        }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $key = $t.Substring(0, $i).Trim()
        $val = $t.Substring($i + 1)
        $result[$section][$key] = Get-CleanIniValue $val
    }
    return $result
}

function Get-IniValue {
    param($Ini, [string] $Section, [string] $Key, [string] $Default = '')
    if ($Ini.Contains($Section) -and $Ini[$Section].Contains($Key)) { return $Ini[$Section][$Key] }
    return $Default
}

function Resolve-GameFolder {
    param([string] $GameName)
    $g = ($GameName + '').ToLowerInvariant()
    if ($g -match 'oblivion') { return 'oblivion' }
    if ($g -match 'skyrim')   { return 'skyrim' }
    return 'other'
}

function Copy-IfExists {
    param([string] $From, [string] $ToDir, [string] $As)
    if (Test-Path $From) {
        if (-not $As) { $As = Split-Path -Leaf $From }
        Copy-Item -LiteralPath $From -Destination (Join-Path $ToDir $As) -Force
        return $true
    }
    return $false
}

# ------------------------------------------------------------- discovery ---

Write-Host "Searching $Root for MO2 instances, depth $Depth"

$iniFiles = Get-ChildItem -Path $Root -Filter 'ModOrganizer.ini' -File -Recurse -Depth $Depth -ErrorAction SilentlyContinue
$instances = @()
foreach ($f in $iniFiles) {
    $dir = $f.Directory.FullName
    if ($Instance -and $dir -notlike "*$Instance*") { continue }
    $instances += $dir
}
$instances = @($instances | Sort-Object -Unique)

if ($instances.Count -eq 0) {
    throw "No ModOrganizer.ini found under $Root. Pass -Root at the folder holding your MO2 instances, or raise -Depth."
}

Write-Host ("Found {0} instance(s)" -f $instances.Count)

$stamp = Get-Date                     # local clock on purpose, this is his time
$dateTag = $stamp.ToString('yyyy-MM-dd')
$written = @()

# ------------------------------------------------------------- per instance ---

foreach ($instDir in $instances) {

    $moIni = Read-Ini (Join-Path $instDir 'ModOrganizer.ini')

    $gameName  = Get-IniValue $moIni 'General' 'gameName'
    if (-not $gameName) { $gameName = Get-IniValue $moIni 'General' 'gameEdition' }
    $gamePath  = Get-IniValue $moIni 'General' 'gamePath'
    $selected  = Get-IniValue $moIni 'General' 'selected_profile'
    $baseDir   = Get-IniValue $moIni 'Settings' 'base_directory'
    if (-not $baseDir) { $baseDir = $instDir }
    $moVersion = Get-IniValue $moIni 'General' 'version'

    $gameFolder = Resolve-GameFolder $gameName
    $modsRoot   = Join-Path $baseDir 'mods'
    $profRoot   = Join-Path $baseDir 'profiles'

    Write-Host ""
    Write-Host ("Instance: {0}" -f $instDir)
    Write-Host ("  game    : {0}  -> games/{1}" -f $gameName, $gameFolder)
    Write-Host ("  base    : {0}" -f $baseDir)
    Write-Host ("  profile : {0}" -f $selected)

    if (-not (Test-Path $profRoot)) {
        Write-Warning "  no profiles folder at $profRoot, skipping instance"
        continue
    }

    # ------- installed mods, read once per instance, shared by all profiles ---

    $mods = @()
    if (Test-Path $modsRoot) {
        foreach ($modDir in (Get-ChildItem -Path $modsRoot -Directory -ErrorAction SilentlyContinue)) {
            $meta = Read-Ini (Join-Path $modDir.FullName 'meta.ini')
            $mods += [pscustomobject]@{
                name              = $modDir.Name
                nexus_mod_id      = Get-IniValue $meta 'General' 'modid'
                version           = Get-IniValue $meta 'General' 'version'
                newest_version    = Get-IniValue $meta 'General' 'newestVersion'
                category          = (Get-IniValue $meta 'General' 'category') -replace ',$', ''
                installation_file = Get-IniValue $meta 'General' 'installationFile'
                repository        = Get-IniValue $meta 'General' 'repository'
                game              = Get-IniValue $meta 'General' 'gameName'
                notes             = Get-IniValue $meta 'General' 'comments'
                installed_at      = $modDir.CreationTime.ToString('s')
            }
        }
    } else {
        Write-Warning "  no mods folder at $modsRoot"
    }
    Write-Host ("  mods    : {0} installed" -f $mods.Count)

    # --------------------------------------------------------- per profile ---

    $profiles = Get-ChildItem -Path $profRoot -Directory -ErrorAction SilentlyContinue
    foreach ($prof in $profiles) {

        if ($ProfileName -and $prof.Name -ne $ProfileName) { continue }

        $modlistPath  = Join-Path $prof.FullName 'modlist.txt'
        if (-not (Test-Path $modlistPath)) { continue }

        # ---- modlist.txt is stored highest priority first, which is the
        # ---- reverse of the left pane. Read it backwards so priority 0 is the
        # ---- top of the pane, the entry that loses every conflict.
        $rawModlist = @([System.IO.File]::ReadAllLines($modlistPath) | Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') })
        $entries = @()
        $priority = 0
        for ($i = $rawModlist.Count - 1; $i -ge 0; $i--) {
            $line = $rawModlist[$i].Trim()
            $flag = $line.Substring(0, 1)
            $name = $line.Substring(1)
            $kind = 'mod'
            if ($name -match '_separator$') { $kind = 'separator' }
            $entries += [pscustomobject]@{
                priority  = $priority
                enabled   = ($flag -eq '+')
                kind      = $kind
                name      = $name
                file_line = $i + 1
            }
            $priority++
        }

        # ---- plugins.txt has two formats and they mean opposite things.
        # Skyrim SE writes every plugin with '*' marking the enabled ones.
        # The older Oblivion format lists ONLY the enabled plugins, unprefixed.
        # Reading the old format with the SE rule reports every plugin disabled,
        # which is how the first Oblivion snapshot came out 0 of 55.
        $plugins = @()
        $pluginsPath = Join-Path $prof.FullName 'plugins.txt'
        $pluginFormat = 'none'
        if (Test-Path $pluginsPath) {
            $pluginLines = @([System.IO.File]::ReadAllLines($pluginsPath) |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -ne '' -and -not $_.StartsWith('#') })
            $starred = @($pluginLines | Where-Object { $_.StartsWith('*') }).Count
            $pluginFormat = if ($starred -gt 0) { 'asterisk' } else { 'listed-only' }
            $idx = 0
            foreach ($t in $pluginLines) {
                $on = if ($pluginFormat -eq 'asterisk') { $t.StartsWith('*') } else { $true }
                if ($t.StartsWith('*')) { $t = $t.Substring(1) }
                $plugins += [pscustomobject]@{ index = $idx; enabled = $on; plugin = $t }
                $idx++
            }
        }

        $loadorder = @()
        $loadorderPath = Join-Path $prof.FullName 'loadorder.txt'
        if (Test-Path $loadorderPath) {
            $loadorder = @([System.IO.File]::ReadAllLines($loadorderPath) |
                Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') })
        }

        # ---- snapshot folder, never overwrite an existing one
        $slug = ($prof.Name -replace '[^A-Za-z0-9._-]', '-')
        $outBase = Join-Path (Join-Path (Join-Path $Repo 'games') $gameFolder) 'snapshots'
        $outDir = Join-Path $outBase ("{0}-{1}" -f $dateTag, $slug)
        $suffix = 98   # 'b'
        while (Test-Path $outDir) {
            $outDir = Join-Path $outBase ("{0}-{1}-{2}" -f $dateTag, $slug, [char]$suffix)
            $suffix++
            if ($suffix -gt 122) { throw "Too many snapshots today for $slug" }
        }
        New-Item -ItemType Directory -Path (Join-Path $outDir 'raw') -Force | Out-Null

        # ---- raw files, verbatim, these are the real archive
        $rawDir = Join-Path $outDir 'raw'
        $copied = @()
        foreach ($f in @('modlist.txt','plugins.txt','loadorder.txt','lockedorder.txt','archives.txt','settings.ini')) {
            if (Copy-IfExists (Join-Path $prof.FullName $f) $rawDir) { $copied += $f }
        }
        foreach ($f in (Get-ChildItem -Path $prof.FullName -Filter '*.ini' -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -eq 'settings.ini') { continue }
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $rawDir $f.Name) -Force
            $copied += $f.Name
        }
        if (Copy-IfExists (Join-Path $instDir 'ModOrganizer.ini') $rawDir 'ModOrganizer.ini') { $copied += 'ModOrganizer.ini' }

        # ---- structured snapshot
        $enabledMods    = @($entries | Where-Object { $_.enabled -and $_.kind -eq 'mod' })
        $enabledPlugins = @($plugins | Where-Object { $_.enabled })

        $snapshot = [ordered]@{
            captured_at     = $stamp.ToString('yyyy-MM-dd HH:mm')
            captured_tz     = [System.TimeZoneInfo]::Local.Id
            note            = $Note
            tool_version     = 1
            instance_path   = $instDir
            base_directory  = $baseDir
            game_name       = $gameName
            game_path       = $gamePath
            game_folder     = $gameFolder
            mo2_version     = $moVersion
            profile         = $prof.Name
            is_live_profile = ($prof.Name -eq $selected)
            counts          = [ordered]@{
                mods_installed  = $mods.Count
                mods_in_list    = @($entries | Where-Object { $_.kind -eq 'mod' }).Count
                mods_enabled    = $enabledMods.Count
                separators      = @($entries | Where-Object { $_.kind -eq 'separator' }).Count
                plugins_listed  = $plugins.Count
                plugins_enabled = $enabledPlugins.Count
            }
            plugins_format  = $pluginFormat
            modlist_order_note = 'priority 0 is the top of the MO2 left pane and loses conflicts. The highest priority number is the bottom of the pane and wins. raw/modlist.txt is stored in the reverse of this, highest priority first.'
            modlist         = $entries
            plugins         = $plugins
            loadorder       = $loadorder
            mods_installed  = $mods
            raw_files       = $copied
        }

        # PowerShell 5.1's Set-Content -Encoding UTF8 writes a BOM, which broke
        # every JSON parser that read the first snapshot. Write UTF-8 no BOM.
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $jsonPath = Join-Path $outDir 'snapshot.json'
        [System.IO.File]::WriteAllText($jsonPath, ($snapshot | ConvertTo-Json -Depth 6), $utf8NoBom)

        # ---- human readable summary
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("# Snapshot $dateTag, $($prof.Name)")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("Captured $($stamp.ToString('yyyy-MM-dd HH:mm')) local. Do not edit this folder, take a new snapshot instead.")
        [void]$sb.AppendLine()
        if ($Note) { [void]$sb.AppendLine("Note: $Note"); [void]$sb.AppendLine() }
        [void]$sb.AppendLine("| field | value |")
        [void]$sb.AppendLine("|---|---|")
        [void]$sb.AppendLine("| game | $gameName |")
        [void]$sb.AppendLine("| game path | $gamePath |")
        [void]$sb.AppendLine("| MO2 instance | $instDir |")
        [void]$sb.AppendLine("| MO2 version | $moVersion |")
        [void]$sb.AppendLine("| profile | $($prof.Name) |")
        [void]$sb.AppendLine("| live profile | $($prof.Name -eq $selected) |")
        [void]$sb.AppendLine("| mods installed | $($mods.Count) |")
        [void]$sb.AppendLine("| mods enabled | $($enabledMods.Count) |")
        [void]$sb.AppendLine("| separators | $(@($entries | Where-Object { $_.kind -eq 'separator' }).Count) |")
        [void]$sb.AppendLine("| plugins enabled | $($enabledPlugins.Count) of $($plugins.Count) |")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("## Enabled mods, in MO2 left pane order, top first")
        [void]$sb.AppendLine()
        foreach ($e in ($entries | Sort-Object priority)) {
            if ($e.kind -eq 'separator') {
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("### " + ($e.name -replace '_separator$', ''))
                [void]$sb.AppendLine("")
                continue
            }
            if (-not $e.enabled) { continue }
            $m = $mods | Where-Object { $_.name -eq $e.name } | Select-Object -First 1
            $ver = if ($m -and $m.version) { $m.version } else { '' }
            $nx  = if ($m -and $m.nexus_mod_id -and $m.nexus_mod_id -ne '0') { "nexus $($m.nexus_mod_id)" } else { '' }
            $tail = (@($ver, $nx) | Where-Object { $_ }) -join ', '
            if ($tail) { [void]$sb.AppendLine("- $($e.name)  ($tail)") }
            else       { [void]$sb.AppendLine("- $($e.name)") }
        }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("## Disabled but installed")
        [void]$sb.AppendLine()
        $off = @($entries | Where-Object { -not $_.enabled -and $_.kind -eq 'mod' })
        if ($off.Count -eq 0) { [void]$sb.AppendLine("None.") }
        else { foreach ($e in $off) { [void]$sb.AppendLine("- $($e.name)") } }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("## Plugin load order")
        [void]$sb.AppendLine()
        foreach ($p in $plugins) {
            $mark = if ($p.enabled) { 'x' } else { ' ' }
            [void]$sb.AppendLine("- [$mark] $($p.plugin)")
        }

        [System.IO.File]::WriteAllText((Join-Path $outDir 'SUMMARY.md'), $sb.ToString(), $utf8NoBom)

        Write-Host ("  wrote   : {0}" -f $outDir)
        $written += $outDir
    }
}

Write-Host ""
Write-Host "Done. Snapshots written:"
foreach ($w in $written) { Write-Host "  $w" }
Write-Host ""
Write-Host "Next: update the Current state table in PLAN.md, add a line to the game changelog, then commit."
