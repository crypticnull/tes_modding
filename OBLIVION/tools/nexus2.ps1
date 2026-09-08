#Requires -Version 5.1
<#
  nexus2.ps1 - Nexus -> Mod Organizer 2 installer for Oblivion Remastered (Steam).

  Rewritten after an adversarial review of v1. Behavioural rules:
    * Never destroys load order. modlist.txt is backed up and only ever has
      NEW names inserted; existing lines are preserved verbatim.
    * Never auto-disables a mod. Conflicts are reported, never acted on.
    * Never replaces a working mod folder with a failed build. Every mod is
      staged to temp, verified non-empty, then swapped in.
    * Refuses FOMOD shapes it cannot install correctly rather than half-installing.
    * Verifies every download by size and MD5 before trusting it.

  MODES
    setkey    store your Nexus personal API key
    resolve   read mod ids/urls (or -ModsFile) -> writes an editable picks file
    install   download + lay out + set priority
    verify    post-install sanity checks for this game's silent failure modes

  ORDER RULE: position in the list is priority. Later in the list wins.
#>

[CmdletBinding()]
param(
    [ValidateSet('setkey','resolve','install','verify')]
    [string]$Mode = 'resolve',
    [string[]]$Mods,
    [string]$ModsFile,
    [string]$ApiKey,
    [switch]$Force,
    [int]$Limit = 0
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$GameDomain = 'oblivionremastered'
$Platform   = 'Steam'                       # this install is Steam, not Game Pass
$Instance   = 'X:\MODDING\OBLIVION\OBLIVION_REMASTERED'
$ModsDir    = Join-Path $Instance 'mods'
$Dloads     = Join-Path $Instance 'downloads'
$ProfileDir = Join-Path $Instance 'profiles\Default'
$Quar       = 'X:\MODDING\OBLIVION\_DELETE_ME\replaced-mods'
$KeyFile    = 'X:\MODDING\OBLIVION\data\.nexus_api_key'
$PicksFile  = 'X:\MODDING\OBLIVION\data\nexus_picks.txt'
$StateFile  = 'X:\MODDING\OBLIVION\data\nexus_state.json'
$ChoiceDir  = 'X:\MODDING\OBLIVION\choices'
$Stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$Log        = "X:\MODDING\OBLIVION\logs\nexus_${Mode}_$Stamp.txt"
$UserAgent  = 'ObrMO2Installer/2.0 (PowerShell)'
$Utf8NoBom  = New-Object Text.UTF8Encoding $false

$script:RateLimited = $false

# ============================================================================
# helpers
# ============================================================================

function Write-Utf8 { param([string]$Path,[string[]]$Lines)
    [IO.File]::WriteAllLines($Path, $Lines, $Utf8NoBom) }

function Get-ApiKey {
    if (-not (Test-Path -LiteralPath $KeyFile)) { throw "No API key. Run: X:\MODDING\OBLIVION\tools\nexus2.ps1 -Mode setkey" }
    (Get-Content -LiteralPath $KeyFile -Raw).Trim()
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
        # NOTE: switch rebinds $_ to its input, so capture the error first.
        $err  = $_
        $msg  = $err.Exception.Message
        $code = $null
        if ($err.Exception.Response) { $code = [int]$err.Exception.Response.StatusCode }
        Start-Sleep -Milliseconds 300
        if ($code -eq 401) { throw "API key rejected (401). Re-run -Mode setkey." }
        if ($code -eq 403) { throw "403 - adult content disabled on your account, or mod hidden." }
        if ($code -eq 404) { throw "404 - mod or file does not exist." }
        if ($code -eq 429) { $script:RateLimited = $true; throw "RATE LIMIT (429)." }
        if ($code) { throw "HTTP $code - $msg" }
        throw "request failed: $msg"
    }
}

function ConvertTo-ModId {
    param([string]$s)
    if ($s -match '/mods/(\d+)')  { return [int]$Matches[1] }
    if ($s -match '^\s*(\d+)\s*$'){ return [int]$Matches[1] }
    return $null
}

# C1 / M7 - a mod folder name must never be able to resolve to the mods root
function Assert-SafeModName {
    param([string]$n)
    if ($null -eq $n) { throw "null mod name" }
    $n = ($n -replace '[\\/:*?"<>|]', ' ' -replace '\s+', ' ').Trim()
    $n = $n.TrimEnd('.', ' ')
    if ([string]::IsNullOrWhiteSpace($n)) { throw "mod name sanitises to empty" }
    if ($n -match '^\.+$')                { throw "dot-only mod name" }
    if ($n -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') { throw "reserved device name '$n'" }
    if ($n.Length -gt 90) { $n = $n.Substring(0, 90).TrimEnd('.', ' ') }
    return $n
}

function Assert-UnderModsDir {
    param([string]$Path)
    $parent = (Split-Path $Path -Parent).TrimEnd('\')
    if ($parent -ne $ModsDir.TrimEnd('\')) { throw "refusing to touch path outside mods dir: $Path" }
}

# --- C6 / H1 / H11 : layout rules ------------------------------------------
# Needles are anchored to a path boundary so 'Metadata/' can never match 'Data/'.
function Get-Destination {
    param([string]$Rel, [string]$Kind = 'none')

    $r = $Rel -replace '\\', '/'

    # This is a Steam install: Game Pass payloads are dead weight, not errors.
    if ($r -match '(?i)(^|/)Binaries/WinGDK/') { return $null }

    # The MagicLoader TOOL lives next to OblivionRemastered.exe, i.e. the game
    # root. Data\MagicLoader\ is where mod JSONs go - a different thing that
    # happens to share the folder name. Route the whole tool payload to Root.
    if ($Kind -eq 'mltool') {
        if ($r -match '(?i)^MagicLoader/') { return "Root/$r" }
        return "Root/MagicLoader/$r"
    }

    # H11: extender payload routing is per-file, not per-mod. A bundled UE4SS
    # must not drag the mod's Data/Paks/Content trees into Root/.
    if ($Kind -eq 'extender' -and $r -notmatch '(?i)(^|/)(Data|Paks|Content|Movies|GameSettings)/') {
        return "Root/OblivionRemastered/Binaries/Win64/$r"
    }

    # ordered: longest / most specific first. ue4ss/Mods/ MUST precede UE4SS/.
    $rules = @(
        @('OblivionRemastered/Content/Dev/ObvData/Data/MagicLoader/', 'Data/MagicLoader/'),
        @('OblivionRemastered/Content/Dev/ObvData/Data/',    'Data/'),
        @('OblivionRemastered/Content/Paks/',                'Paks/'),
        @('OblivionRemastered/Content/Movies/',              'Movies/'),
        @('OblivionRemastered/Binaries/Win64/ue4ss/Mods/',   'UE4SS/'),
        @('OblivionRemastered/Binaries/Win64/OBSE/Plugins/', 'OBSE/Plugins/'),
        @('OblivionRemastered/Binaries/Win64/OBSE/',         'OBSE/'),
        @('OblivionRemastered/Binaries/Win64/GameSettings/', 'GameSettings/'),
        @('ue4ss/Mods/',      'UE4SS/'),
        @('OBSE/Plugins/',    'OBSE/Plugins/'),
        # TesSyncMapInjector consumer inis live in Data\SyncMap\ and must be
        # named exactly like their esp. Missing these = invisible items.
        @('SyncMap/',         'Data/SyncMap/'),
        @('Data/MagicLoader/','Data/MagicLoader/'),
        @('MagicLoader/',     'Data/MagicLoader/'),
        @('Data/',            'Data/'),
        @('Paks/',            'Paks/'),
        @('UE4SS/',           'UE4SS/'),
        @('OBSE/',            'OBSE/'),
        @('Movies/',          'Movies/'),
        @('GameSettings/',    'GameSettings/')
    )
    foreach ($pair in $rules) {
        $needle = $pair[0]; $out = $pair[1]
        $i = $r.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase)
        if ($i -ge 0 -and ($i -eq 0 -or $r[$i - 1] -eq '/')) {
            return $out + $r.Substring($i + $needle.Length)
        }
    }

    $leaf = Split-Path $r -Leaf
    # UE4SS activation marker must survive the .txt drop rule
    if ($leaf -ieq 'enabled.txt') { return $null }   # MO2 owns activation via mods.json

    # Engine.ini lives in the user's Documents config folder, outside anything
    # MO2 can deploy. Park it under Root (not deployed) so it stays versioned
    # with the mod; deploy_external.ps1 copies it to the real location.
    if ($leaf -ieq 'Engine.ini') { return 'Root/OblivionRemastered/Saved/Config/Windows/Engine.ini' }

    switch ([IO.Path]::GetExtension($leaf).ToLower()) {
        '.pak'  { return "Paks/~mods/$leaf" }
        '.ucas' { return "Paks/~mods/$leaf" }
        '.utoc' { return "Paks/~mods/$leaf" }
        '.esp'  { return "Data/$leaf" }
        '.esm'  { return "Data/$leaf" }
        '.bsa'  { return "Data/$leaf" }
        '.bk2'  { return "Movies/Modern/$leaf" }
        '.txt'  { return $null }
        '.md'   { return $null }
        '.pdf'  { return $null }
        '.jpg'  { return $null }
        '.jpeg' { return $null }
        '.png'  { return $null }
        '.webp' { return $null }
        '.docx' { return $null }
        '.sav'  { return $null }   # character-preset saves: not installable as a mod
    }
    return 'UNMAPPED'
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

function Expand-Any {
    param([string]$Archive, [string]$Dest)
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    $sz = Get-SevenZip
    if (-not $sz) { throw "7-Zip is required (winget install --id 7zip.7zip -e)" }
    & $sz x "-o$Dest" -y -bso0 -bsp0 -- "$Archive" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7-Zip exit code $LASTEXITCODE" }
}

# --- C4 : FOMOD -------------------------------------------------------------
function Get-FomodInfo {
    param([string]$Root)
    $all = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'ModuleConfig.xml' -ErrorAction SilentlyContinue)
    if (-not $all.Count) { return $null }
    if ($all.Count -gt 1) { return @{ Unsupported = "archive contains $($all.Count) FOMODs" } }
    $cfg = $all[0]

    try { [xml]$x = Get-Content -LiteralPath $cfg.FullName -Raw }
    catch { return @{ Unsupported = "ModuleConfig.xml is not valid XML" } }

    $required = @()
    foreach ($f in @($x.config.requiredInstallFiles.folder)) { if ($f) {
        $required += @{ Source=$f.source; Destination=$f.destination; IsFolder=$true } } }
    foreach ($f in @($x.config.requiredInstallFiles.file))   { if ($f) {
        $required += @{ Source=$f.source; Destination=$f.destination; IsFolder=$false } } }

    # conditionalFileInstalls: extra file sets gated on flags that the chosen
    # plugins set. Parse the patterns; they are evaluated after selection.
    $patterns = @()
    foreach ($pat in @($x.config.conditionalFileInstalls.patterns.pattern)) {
        if (-not $pat) { continue }
        $deps = @(); $op = 'And'; $ok = $true
        if ($pat.dependencies) {
            if ($pat.dependencies.operator) { $op = $pat.dependencies.operator }
            foreach ($fd in @($pat.dependencies.flagDependency)) {
                if ($fd) { $deps += @{ Flag=$fd.flag; Value=$fd.value } }
            }
            # anything other than a flag test is beyond this engine
            foreach ($nodeName in @('fileDependency','gameDependency','fommDependency','dependencies')) {
                if ($pat.dependencies.$nodeName) { $ok = $false }
            }
        }
        $pf = @()
        foreach ($f in @($pat.files.folder)) { if ($f) {
            $pf += @{ Source=$f.source; Destination=$f.destination; IsFolder=$true } } }
        foreach ($f in @($pat.files.file))   { if ($f) {
            $pf += @{ Source=$f.source; Destination=$f.destination; IsFolder=$false } } }
        $patterns += @{ Deps=$deps; Operator=$op; Files=$pf; Supported=$ok }
    }

    # Every group is kept, in document order. One pick per group, so a 7-group
    # FOMOD is answered as "1464.fomod = 1,0,3,1,2,1,1" (0 = take nothing here).
    $groups = @()
    foreach ($s in @($x.config.installSteps.installStep)) {
        if (-not $s) { continue }
        foreach ($g in @($s.optionalFileGroups.group)) {
            if (-not $g) { continue }
            $plugins = @()
            foreach ($p in @($g.plugins.plugin)) {
                if (-not $p) { continue }
                $srcs = @()
                foreach ($f in @($p.files.folder)) { if ($f) {
                    $srcs += @{ Source=$f.source; Destination=$f.destination; IsFolder=$true } } }
                foreach ($f in @($p.files.file))   { if ($f) {
                    $srcs += @{ Source=$f.source; Destination=$f.destination; IsFolder=$false } } }
                $img = $null
                if ($p.image -and $p.image.path) { $img = $p.image.path }
                $flags = @()
                foreach ($fl in @($p.conditionFlags.flag)) {
                    if ($fl) { $flags += @{ Name=$fl.name; Value="$($fl.'#text')" } }
                }
                $plugins += @{ Name=$p.name; Image=$img; Sources=$srcs; Flags=$flags
                               Description=(($p.description -replace '\s+',' ').Trim()) }
            }
            if ($plugins.Count) {
                $groups += @{ Step=$s.name; Name=$g.name; Type=$g.type; Plugins=$plugins }
            }
        }
    }
    if (-not $groups.Count) { return @{ Unsupported = 'no installable options found' } }

    # Steps carrying a <visible> condition are shown or hidden based on earlier
    # answers (typically an MO2-vs-Vortex branch that duplicates every group).
    # This engine has no flag evaluation, so it shows every group - the user must
    # zero out the branch they don't want or both get installed.
    $conditional = [bool](@($x.config.installSteps.installStep | Where-Object { $_.visible }).Count)

    return @{ Root=(Split-Path $cfg.DirectoryName -Parent); Groups=$groups
              Required=$required; Conditional=$conditional; Patterns=$patterns }
}

# --- C5 : FOMOD copy with correct spec semantics ---------------------------
function Copy-FomodSources {
    param($Sources, [string]$FomodRoot, [string]$Dest)
    foreach ($s in $Sources) {
        $from = Join-Path $FomodRoot ($s.Source -replace '/', '\')
        if (-not (Test-Path -LiteralPath $from)) { Write-Host "      missing source: $($s.Source)"; continue }
        if ($s.IsFolder) {
            # spec: copy the CONTENTS of source into destination
            $to = if ($s.Destination) { Join-Path $Dest ($s.Destination -replace '/','\') } else { $Dest }
            New-Item -ItemType Directory -Force -Path $to | Out-Null
            Get-ChildItem -LiteralPath $from -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $to -Recurse -Force }
        } else {
            # spec: destination is a FILE path
            $to = if ($s.Destination) { Join-Path $Dest ($s.Destination -replace '/','\') }
                  else { Join-Path $Dest (Split-Path $s.Source -Leaf) }
            New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent) | Out-Null
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
    }
}

# ============================================================================
# MODE: setkey
# ============================================================================
if ($Mode -eq 'setkey') {
    Write-Host "Personal API key: https://www.nexusmods.com/users/myaccount?tab=api"
    Write-Host ""
    $plain = $ApiKey
    if (-not $plain) {
        # Plain Read-Host, not -AsSecureString: the classic console host silently
        # ignores Ctrl+V at a SecureString prompt, which reads as "nothing pasted".
        Write-Host "Paste the key and press Enter (it will be visible, then cleared)."
        Write-Host "Right-click pastes in this console if Ctrl+V does not."
        $plain = Read-Host -Prompt 'Key'
    }
    $plain = "$plain".Trim().Trim('"',"'")
    if (-not $plain) {
        throw "No key entered. You can also pass it directly:  X:\MODDING\OBLIVION\tools\nexus2.ps1 -Mode setkey -ApiKey `"<key>`""
    }
    if ($plain.Length -lt 20) { throw "That does not look like a Nexus API key (only $($plain.Length) chars)." }
    try { Clear-Host } catch {}
    Write-Host "Key received ($($plain.Length) chars). Screen cleared."
    New-Item -ItemType Directory -Force -Path (Split-Path $KeyFile -Parent) | Out-Null
    [IO.File]::WriteAllText($KeyFile, $plain.Trim(), (New-Object Text.ASCIIEncoding))
    try {
        $acl = Get-Acl -LiteralPath $KeyFile
        $acl.SetAccessRuleProtection($true, $false)
        $acl.Access | ForEach-Object { [void]$acl.RemoveAccessRule($_) }
        $me = ([Security.Principal.WindowsIdentity]::GetCurrent()).User
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($me,'FullControl','Allow')))
        Set-Acl -LiteralPath $KeyFile -AclObject $acl
        Write-Host "Stored, ACL locked to you."
    } catch { Write-Host "Stored (ACL tighten failed: $($_.Exception.Message))" }
    try {
        $v = Invoke-Nexus '/v1/users/validate.json'
        Write-Host ("Validated: {0}   premium={1}" -f $v.name, $v.is_premium)
        if (-not $v.is_premium) { Write-Host "WARNING: not premium - API downloads will be refused." }
    } catch { Write-Host "Validation failed: $($_.Exception.Message)" }
    return
}

New-Item -ItemType Directory -Force -Path (Split-Path $Log -Parent) | Out-Null
Start-Transcript -Path $Log | Out-Null

# ============================================================================
# MODE: verify   (game-specific silent-failure checks)
# ============================================================================
if ($Mode -eq 'verify') {
    Write-Host "=== verify ==="
    $issues = 0

    $allNotes = @()
    foreach ($md in Get-ChildItem -LiteralPath $ModsDir -Directory) {
        $problems = @()
        $notes = @()

        # pak triads must be complete
        $paks = Get-ChildItem -LiteralPath $md.FullName -Recurse -File -Filter '*.pak' -ErrorAction SilentlyContinue
        foreach ($p in $paks) {
            # An IoStore pak is a tiny stub whose payload lives in .ucas/.utoc, so a
            # small pak with no siblings is broken. A large standalone pak is normal.
            if ($p.Length -gt 51200) { continue }
            $stem = [IO.Path]::ChangeExtension($p.FullName, $null).TrimEnd('.')
            foreach ($ext in @('.utoc','.ucas')) {
                if (-not (Test-Path -LiteralPath ($stem + $ext))) {
                    $problems += "IoStore pak stub missing its $ext payload: $($p.Name)"
                }
            }
        }
        # Filename ordering only decides pak conflicts OUTSIDE MO2. MO2 places each
        # pak group in a numbered ~mods subfolder and that folder order wins, so a
        # 'z' prefix is inert here - worth knowing, not worth flagging as a problem.
        foreach ($p in $paks) {
            if ($p.Name -match '^(?i)z+[_\-]') {
                $notes += "'z' prefixed pak (author expected last-wins; inert under MO2's numbered folders): $($p.Name)"
            }
        }
        # paks must be under Paks\ (~mods or LogicMods), never loose
        foreach ($p in $paks) {
            $rel = $p.FullName.Substring($md.FullName.Length).TrimStart('\')
            if ($rel -notmatch '^(?i)Paks\\') { $problems += "pak outside Paks\: $rel" }
            elseif ($rel -notmatch '(?i)^Paks\\(~mods|LogicMods)\\') { $problems += "pak not in ~mods or LogicMods: $rel" }
        }
        # UE4SS mods: <Name>\scripts\main.lua or <Name>\dlls\main.dll, no spaces in <Name>
        $u = Join-Path $md.FullName 'UE4SS'
        if (Test-Path -LiteralPath $u) {
            foreach ($mod in Get-ChildItem -LiteralPath $u -Directory) {
                # 'shared' is UE4SS's own library folder, not a mod
                if ($mod.Name -ieq 'shared') { continue }
                if ($mod.Name -match '\s') { $problems += "UE4SS mod folder has a space (UE4SS will not load it): $($mod.Name)" }
                $hasLua = Test-Path -LiteralPath (Join-Path $mod.FullName 'scripts\main.lua')
                $hasLua2= Test-Path -LiteralPath (Join-Path $mod.FullName 'Scripts\main.lua')
                $hasDll = @(Get-ChildItem -LiteralPath $mod.FullName -Recurse -File -Filter '*.dll' -ErrorAction SilentlyContinue).Count -gt 0
                if (-not ($hasLua -or $hasLua2 -or $hasDll)) {
                    $problems += "UE4SS mod has no scripts\main.lua and no dll: $($mod.Name)"
                }
                if (Test-Path -LiteralPath (Join-Path $mod.FullName 'Mods')) {
                    $problems += "UE4SS mod is double-nested (contains a Mods folder): $($mod.Name)"
                }
            }
        }
        # MagicLoader: the TOOL belongs in Root\MagicLoader\, mod JSONs in Data\MagicLoader\
        foreach ($e in Get-ChildItem -LiteralPath $md.FullName -Recurse -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -in @('MagicLoader.exe','mlcli.exe') }) {
            $rel = $e.FullName.Substring($md.FullName.Length).TrimStart('\')
            if ($rel -notmatch '(?i)^Root\\MagicLoader\\') {
                $problems += "MagicLoader tool must be in Root\MagicLoader\, found: $rel"
            }
        }
        foreach ($j in Get-ChildItem -LiteralPath $md.FullName -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue) {
            $rel = $j.FullName.Substring($md.FullName.Length).TrimStart('\')
            if ($rel -match '(?i)^Data\\' -and $rel -match '(?i)MagicLoader' -and
                $rel -notmatch '(?i)^Data\\MagicLoader\\') {
                $problems += "MagicLoader json not in Data\MagicLoader\: $rel"
            }
        }
        # a .dll or .exe sitting in Data\ is almost always a routing mistake
        foreach ($b in Get-ChildItem -LiteralPath (Join-Path $md.FullName 'Data') -Recurse -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.Extension -in @('.exe','.dll') }) {
            $problems += "executable in Data\: $($b.FullName.Substring($md.FullName.Length).TrimStart('\'))"
            break
        }
        # nothing but meta.ini
        $n = @(Get-ChildItem -LiteralPath $md.FullName -Recurse -File | Where-Object { $_.Name -ne 'meta.ini' }).Count
        if ($n -eq 0) { $problems += "EMPTY - contains only meta.ini" }

        if ($problems.Count) {
            $issues += $problems.Count
            Write-Host ("--- {0}" -f $md.Name)
            $problems | ForEach-Object { Write-Host "    $_" }
        }
        foreach ($n in $notes) { $allNotes += ("{0}: {1}" -f $md.Name, $n) }
    }
    if ($allNotes.Count) {
        Write-Host ""
        Write-Host ("--- notes ({0}, not problems) ---" -f $allNotes.Count)
        $allNotes | ForEach-Object { Write-Host "    $_" }
    }

    # ESPs installed vs enabled in plugins.txt
    $espFiles = @(Get-ChildItem -LiteralPath $ModsDir -Recurse -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Extension -in @('.esp','.esm') } | ForEach-Object { $_.Name } | Sort-Object -Unique)
    $pt = Join-Path $ProfileDir 'plugins.txt'
    $listed = @()
    if (Test-Path -LiteralPath $pt) {
        $listed = @(Get-Content -LiteralPath $pt | Where-Object { $_ -notmatch '^\s*[#*]' -and $_.Trim() })
    }
    $missing = @($espFiles | Where-Object { $listed -notcontains $_ })
    Write-Host ""
    Write-Host ("plugins: {0} esp/esm installed, {1} listed in plugins.txt" -f $espFiles.Count, $listed.Count)
    if ($missing.Count) {
        Write-Host ("  {0} NOT enabled (enable in MO2's right pane):" -f $missing.Count)
        $missing | ForEach-Object { Write-Host "    $_" }
    }

    # --- same Nexus mod installed under two folder names ---
    Write-Host ""
    Write-Host "--- duplicate mods ---"
    $byModId = @{}
    foreach ($md in Get-ChildItem -LiteralPath $ModsDir -Directory) {
        $mi = Join-Path $md.FullName 'meta.ini'
        if (-not (Test-Path -LiteralPath $mi)) { continue }
        $m = (Get-Content -LiteralPath $mi | Where-Object { $_ -match '^modid=(\d+)' })
        if (-not $m) { continue }
        $mid = ($m -replace '^modid=','').Trim()
        if ($mid -eq '0') { continue }
        if (-not $byModId.ContainsKey($mid)) { $byModId[$mid] = @() }
        $byModId[$mid] += $md.Name
    }
    $dupes = @($byModId.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })
    if (-not $dupes.Count) { Write-Host "  none" }
    else {
        foreach ($d in $dupes) {
            $issues++
            Write-Host ("  Nexus mod {0} installed {1} times:" -f $d.Key, $d.Value.Count)
            $d.Value | ForEach-Object { Write-Host "      $_" }
            Write-Host "      ^ keep one, disable or delete the rest"
        }
    }

    # --- same pak filename shipped by two different mods ---
    # ~mods subfolder names are only load order, so the BASENAME is the identity.
    Write-Host ""
    Write-Host "--- duplicate pak files ---"
    $pakOwners = @{}
    foreach ($md in Get-ChildItem -LiteralPath $ModsDir -Directory) {
        foreach ($p in Get-ChildItem -LiteralPath $md.FullName -Recurse -File -Filter '*.pak' -ErrorAction SilentlyContinue) {
            if (-not $pakOwners.ContainsKey($p.Name)) { $pakOwners[$p.Name] = @() }
            if ($pakOwners[$p.Name] -notcontains $md.Name) { $pakOwners[$p.Name] += $md.Name }
        }
    }
    $pakDupes = @($pakOwners.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })
    if (-not $pakDupes.Count) { Write-Host "  none" }
    else {
        foreach ($d in $pakDupes) {
            $issues++
            Write-Host ("  {0}  shipped by: {1}" -f $d.Key, ($d.Value -join ', '))
        }
    }

    # TesSyncMapInjector index-drift hazard
    $ghost = @($listed | Where-Object { $_ -eq 'AltarESPLocal.esp' })
    if ($ghost.Count) {
        Write-Host ""
        Write-Host "WARNING: AltarESPLocal.esp is listed in plugins.txt but ships with no file."
        Write-Host "  This shifts every plugin index and is a known cause of invisible items"
        Write-Host "  and CTDs for TesSyncMapInjector-dependent mods."
    }

    Write-Host ""
    Write-Host ("=== {0} issue(s) ===" -f $issues)
    Stop-Transcript | Out-Null
    return
}

# ============================================================================
# MODE: resolve
# ============================================================================
if ($Mode -eq 'resolve') {

    if ($ModsFile) {
        if (-not (Test-Path -LiteralPath $ModsFile)) { Stop-Transcript|Out-Null; throw "not found: $ModsFile" }
        $Mods = @()
        foreach ($line in Get-Content -LiteralPath $ModsFile) {
            $id = ConvertTo-ModId $line
            if ($id) { $Mods += "$id" }
        }
    }
    if (-not $Mods) { Stop-Transcript|Out-Null; throw "Pass -Mods or -ModsFile." }

    # dedupe, first occurrence wins its position
    $seenId = @{}; $ordered = @()
    foreach ($m in $Mods) {
        $id = ConvertTo-ModId $m
        if (-not $id) { continue }
        if ($seenId.ContainsKey("$id")) { Write-Host "  duplicate skipped: $id"; continue }
        $seenId["$id"] = $true; $ordered += $id
    }
    Write-Host ("=== resolve: {0} unique mod(s) ===" -f $ordered.Count)

    $v = Invoke-Nexus '/v1/users/validate.json'
    Write-Host ("account {0}  premium={1}" -f $v.name, $v.is_premium)
    Write-Host ""

    # load state
    $state = @{}
    if (Test-Path -LiteralPath $StateFile) {
        (Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $state[$_.Name] = $_.Value }
    }
    # H4: fold the user's edited picks back into state before regenerating
    $fomodKeep = @()
    $headKeep  = @()
    if (Test-Path -LiteralPath $PicksFile) {
        Copy-Item -LiteralPath $PicksFile -Destination "$PicksFile.bak-$Stamp" -Force
        # FOMOD blocks are always appended at the end of the file, so keep
        # everything from the first FOMOD header onward, verbatim.
        $inFomod = $false
        foreach ($line in Get-Content -LiteralPath $PicksFile) {
            if (-not $inFomod -and $line -match '^#\s*FOMOD\b') { $inFomod = $true }
            if ($inFomod) { $fomodKeep += $line; continue }
            # H12: keep the existing blocks too. -Mods is an APPEND, and
            # regenerating the file from only the ids on the command line throws
            # away every other mod's answered pick. -Mode install then treats
            # them all as unanswered and skips them.
            if ($line -notmatch '^\s*\d+\.fomod\s*=') { $headKeep += $line }
            # must accept the comma form ("221 = 1,2") or multi-file picks are lost
            if ($line -match '^\s*(\d+)\s*=\s*(-?[\d]+(?:\s*,\s*\d+)*)\s*$' -and $state[$Matches[1]]) {
                $state[$Matches[1]].pick = ($Matches[2] -replace '\s','')
            }
        }
        # a .fomod answer outside a block (hand-added) must survive too
        foreach ($line in Get-Content -LiteralPath $PicksFile) {
            if ($line -match '^\s*\d+\.fomod\s*=' -and $fomodKeep -notcontains $line) { $fomodKeep += $line }
        }
    }

    # Order semantics:
    #   -ModsFile  the file IS the load order, so renumber 1..N from it
    #   -Mods      an ad-hoc addition, so append after the current maximum
    $order = 0
    if (-not $ModsFile -and $state.Count) {
        $mx = @($state.Values | ForEach-Object { [int]$_.order }) | Measure-Object -Maximum
        if ($mx.Maximum) { $order = [int]$mx.Maximum }
        Write-Host ("appending after existing position {0}" -f $order)
    } elseif ($ModsFile) {
        Write-Host "list file is the load order - renumbering from 1"
    }
    Write-Host ""

    $out = @('# Nexus picks. Edit the "<modid> = <n>" lines, then: X:\MODDING\OBLIVION\tools\nexus2.ps1 -Mode install',
             '#   n = 0   skip this mod',
             '#   later in this file = higher priority (wins conflicts)',
             "# generated $Stamp", '')
    $hdrCount = $out.Count      # H12: where the generated blocks start

    foreach ($id in $ordered) {
        $order++
        Write-Host ("--- {0} (pos {1}) ---" -f $id, $order)
        try {
            $info  = Invoke-Nexus "/v1/games/$GameDomain/mods/$id.json"
            $files = Invoke-Nexus "/v1/games/$GameDomain/mods/$id/files.json"
        } catch {
            Write-Host ("    FAIL {0}" -f $_.Exception.Message)
            $out += "# mod $id : COULD NOT RESOLVE - $($_.Exception.Message)"
            $out += "$id = 0"; $out += ''
            if ($script:RateLimited) { Write-Host "Rate limited - stopping."; break }
            continue
        }

        try { $name = Assert-SafeModName $info.name }
        catch {
            Write-Host ("    FAIL unusable mod name: {0}" -f $_.Exception.Message)
            $out += "# mod $id : unusable name"; $out += "$id = 0"; $out += ''
            continue
        }
        # H8: disambiguate colliding sanitised names
        $clash = @($state.Keys | Where-Object { $_ -ne "$id" -and $state[$_].name -eq $name })
        if ($clash.Count) { $name = "$name ($id)" }

        Write-Host ("    {0}   v{1}  adult={2}" -f $name, $info.version, $info.contains_adult_content)

        $rank = { param($c) if (-not $c) { return 3 }
                  switch ($c) { 'MAIN'{0} 'OPTIONAL'{1} 'MISCELLANEOUS'{2} 'OLD_VERSION'{4} default{3} } }
        $fl = @($files.files) | Sort-Object @{Expression={ & $rank $_.category_name }},
                                            @{Expression={ $_.uploaded_timestamp }; Descending=$true}

        $out += ('# ' + ('=' * 74))
        $out += "# mod $id  -  $name    (v$($info.version))"
        if ($info.contains_adult_content) { $out += '#   [adult content]' }
        $mainCount = @($fl | Where-Object { $_.category_name -eq 'MAIN' }).Count
        if ($mainCount -gt 1) { $out += "#   >>> $mainCount MAIN files - deliberate choice required" }

        $n = 0; $fileMap = @{}; $detail = @()
        foreach ($f in $fl) {
            $n++; $fileMap["$n"] = $f.file_id
            $mb = [math]::Round($f.size_kb / 1024, 1)
            $out += ("#   [{0,2}] {1,-50} v{2,-10} {3,7} MB  {4}" -f $n,$f.name,$f.version,$mb,$f.category_name)
            $d = (($f.description -replace '<[^>]+>','' -replace '&nbsp;',' ' -replace '\s+',' ').Trim())
            if ($d) { if ($d.Length -gt 130) { $d = $d.Substring(0,130)+'...' }; $out += "#        $d" }
            $detail += @{ index=$n; fileId=$f.file_id; name=$f.name; version=$f.version
                          category=$f.category_name; sizeMb=$mb; description=$d }
        }
        if ($n -eq 0) { $out += '#   (no files)' }

        $prev = if ($state["$id"]) { $state["$id"].pick } else { $null }
        $default = if ($null -ne $prev -and "$prev" -ne '') { "$prev" } elseif ($n -ge 1) { '1' } else { '0' }
        $out += "$id = $default"; $out += ''
        $firstPick = [int](("$default" -split ',')[0])

        $state["$id"] = @{
            modId=$id; name=$name; version=$info.version; order=$order
            adult=[bool]$info.contains_adult_content
            pictureUrl=$info.picture_url
            summary=(($info.summary -replace '<[^>]+>','' -replace '\s+',' ').Trim())
            mainCount=$mainCount; detail=$detail; files=$fileMap
            pick=$default; pickFileId=$fileMap["$firstPick"]
        }
    }

    # H12: in append mode the existing file is the base; only the newly resolved
    # blocks are added to it. -ModsFile still regenerates wholesale, because
    # there the list file genuinely is the whole load order.
    if (-not $ModsFile -and $headKeep.Count) {
        $newBlocks = @()
        if ($out.Count -gt $hdrCount) { $newBlocks = $out[$hdrCount..($out.Count - 1)] }
        $out = @($headKeep) + $newBlocks
        Write-Host ("keeping {0} existing pick line(s), appending {1} new block line(s)" -f `
                    @($headKeep | Where-Object { $_ -match '^\s*\d+\s*=' }).Count, $newBlocks.Count)
    }

    if ($fomodKeep.Count) { $out += ''; $out += $fomodKeep }   # H10: never lose FOMOD answers

    # A picks file with fewer answers than state has mods means something ate
    # them. Refuse to write rather than hand -Mode install a file that will make
    # it skip mods silently.
    $answered = @($out | Where-Object { $_ -match '^\s*\d+\s*=' }).Count
    if ($answered -lt $state.Count) {
        Write-Host ""
        Write-Host ("REFUSING TO WRITE: {0} pick line(s) for {1} mod(s) in state." -f $answered, $state.Count)
        Write-Host ("The previous file is intact, and backed up as {0}.bak-{1}" -f $PicksFile, $Stamp)
        Stop-Transcript | Out-Null
        throw "picks file would lose answers - nothing written"
    }

    Write-Utf8 -Path $PicksFile -Lines $out
    Write-Utf8 -Path $StateFile -Lines @(($state | ConvertTo-Json -Depth 8))
    Write-Host ""
    Write-Host "picks -> $PicksFile"
    Stop-Transcript | Out-Null
    return
}

# ============================================================================
# MODE: install
# ============================================================================
Write-Host "=== install ==="

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    Stop-Transcript|Out-Null; throw "Mod Organizer is running. Close it." }
foreach ($p in @($ModsDir,$Dloads,$ProfileDir)) {
    if (-not (Test-Path -LiteralPath $p)) { Stop-Transcript|Out-Null; throw "missing: $p" } }
if (-not (Get-SevenZip)) { Stop-Transcript|Out-Null; throw "7-Zip required: winget install --id 7zip.7zip -e" }
if (-not (Test-Path -LiteralPath $PicksFile)) { Stop-Transcript|Out-Null; throw "run -Mode resolve first" }

$lp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled
if ($lp -ne 1) { Write-Host "WARNING: Win32 long paths disabled - deep mod trees may fail to copy." }

$free = (Get-PSDrive -Name ($Instance.Substring(0,1))).Free
Write-Host ("free space on {0}: {1} GB" -f $Instance.Substring(0,1), [math]::Round($free/1GB,1))
Write-Host ""

# full profile backup before anything
$bk = "X:\MODDING\OBLIVION\backups\profile-$Stamp"
New-Item -ItemType Directory -Force -Path $bk | Out-Null
Copy-Item -LiteralPath $ProfileDir -Destination $bk -Recurse -Force
Write-Host "profile backed up -> $bk"
Write-Host ""

$state = @{}
(Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json).PSObject.Properties |
    ForEach-Object { $state[$_.Name] = $_.Value }

$picks = @{}; $fomodPicks = @{}
# A pick may be a single index, or a comma list to install several files as one
# mod (e.g. "221 = 1,2"). Files are merged in the order given, so later wins.
$badLines = @()
foreach ($line in Get-Content -LiteralPath $PicksFile) {
    if ($line -match '^\s*#' -or -not $line.Trim()) { continue }
    # NOTE: no end anchor - a trailing "# comment" must not defeat this.
    if     ($line -match '^\s*(\d+)\s*=\s*(-?[\d]+(?:\s*,\s*\d+)*)') {
        $picks[$Matches[1]] = @($Matches[2] -split '\s*,\s*' | ForEach-Object { [int]$_ })
    }
    # trailing "# comment" must not defeat this - the generated lines carry one
    # one value per FOMOD group, comma separated; trailing "# comment" allowed
    # one value per FOMOD group, comma separated. Within a group, "1+2" takes
    # several options (for SelectAny / SelectAtLeastOne groups).
    elseif ($line -match '^\s*(\d+)\.fomod\s*=\s*(-?[\d+]+(?:\s*,\s*[\d+]+)*)') {
        $fomodPicks[$Matches[1]] = ($Matches[2] -replace '\s','')
    }
    elseif ($line -match '^\s*\d+\s*=' -or $line -match '^\s*\d+\.fomod\s*=') {
        # looks like an answer but did not parse - never skip one silently
        $badLines += $line
    }
}
if ($badLines.Count) {
    Write-Host ("WARNING: {0} answer line(s) could not be parsed and were IGNORED:" -f $badLines.Count)
    $badLines | ForEach-Object { Write-Host "    $_" }
    Write-Host ""
}

# a state entry with no pick line at all is also a silent skip - catch it
$noAnswer = @($state.Keys | Where-Object { -not $picks.ContainsKey($_) })
if ($noAnswer.Count) {
    Write-Host ("WARNING: {0} mod(s) in state have no pick line and will be skipped:" -f $noAnswer.Count)
    $noAnswer | Sort-Object { [int]$_ } | ForEach-Object {
        Write-Host ("    {0}  {1}" -f $_, $state[$_].name) }
    Write-Host ""
}

$Work = Join-Path $Instance ('_work_' + $Stamp)
New-Item -ItemType Directory -Force -Path $Work | Out-Null

$byOrder = $picks.Keys | Sort-Object { if ($state[$_] -and $state[$_].order) { [int]$state[$_].order } else { 99999 } }
if ($Limit -gt 0) { $byOrder = @($byOrder | Select-Object -First $Limit; Write-Host "LIMIT: first $Limit only") }

$results = @(); $needsChoice = @()

foreach ($id in $byOrder) {
  $meta = $state[$id]
  if (-not $meta) {
      Write-Host "--- $id ---"; Write-Host "    FAIL no state entry - re-run resolve for this id"
      $results += [pscustomobject]@{ Mod="(id $id)"; Status='no state'; Files=0; Unmapped=0 }; continue }
  $name = $meta.name
  $pickList = @($picks[$id])

  Write-Host ("--- {0}  {1} ---" -f $id, $name)
  if (-not $pickList.Count -or $pickList[0] -le 0) {
      Write-Host "    skipped"
      $results += [pscustomobject]@{ Mod=$name; Status='skipped'; Files=0; Unmapped=0 }; Write-Host ""; continue }

  try {
    $fileIds = @()
    foreach ($p in $pickList) {
        $f = $meta.files."$p"
        if (-not $f) { throw "pick $p is not in the file list" }
        $fileIds += $f
    }
    # H5: a new upload shifts indices - refuse rather than install the wrong file.
    # Only meaningful when the pick is UNCHANGED since resolve; if the user edited
    # it, the stored pickFileId belongs to the old index and proves nothing.
    $userEdited = ("$($pickList -join ',')" -ne "$($meta.pick)")
    if (-not $userEdited -and $pickList.Count -eq 1 -and $meta.pickFileId -and
        "$($fileIds[0])" -ne "$($meta.pickFileId)") {
        throw "file list changed since resolve (pick $($pickList[0]) now = file $($fileIds[0]), was $($meta.pickFileId)). Re-run resolve." }
    if ($userEdited) { Write-Host ("    pick edited since resolve: {0} -> {1}" -f $meta.pick, ($pickList -join ',')) }
    if ($pickList.Count -gt 1) {
        Write-Host ("    merging {0} files: picks {1}" -f $pickList.Count, ($pickList -join ', ')) }

    $dest = Join-Path $ModsDir (Assert-SafeModName $name)
    Assert-UnderModsDir $dest

    # M1: already installed from this exact combination?
    $sig = ($fileIds -join '+')
    $stampFile = Join-Path $dest '.nexus_installed'
    if ((Test-Path -LiteralPath $stampFile) -and -not $Force) {
        if ((Get-Content -LiteralPath $stampFile -Raw).Trim() -eq $sig) {
            Write-Host "    up to date (files $sig)"
            $results += [pscustomobject]@{ Mod=$name; Status='up to date'; Files=0; Unmapped=0 }
            Write-Host ""; continue }
    }

    # download + extract each picked file; merge in list order (later wins)
    $baseDirs = @(); $archNames = @(); $fiLast = $null; $skipMod = $false
    $fileSeq = 0
    foreach ($fileId in $fileIds) {
      $fileSeq++
      $fi = Invoke-Nexus "/v1/games/$GameDomain/mods/$id/files/$fileId.json"
      $fiLast = $fi
      $target = Join-Path $Dloads $fi.file_name
      $archNames += $fi.file_name

      # H3: verified download via .part
      $want = if ($fi.size_in_bytes) { [int64]$fi.size_in_bytes } else { [int64]$fi.size_kb * 1024 }
      $have = (Test-Path -LiteralPath $target) -and
              ($want -le 0 -or [math]::Abs((Get-Item -LiteralPath $target).Length - $want) -lt 4096)
      if ($have -and -not $Force) {
          Write-Host ("    have    {0}" -f $fi.file_name)
      } else {
          if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
          $dl = Invoke-Nexus "/v1/games/$GameDomain/mods/$id/files/$fileId/download_link.json"
          $uri = @($dl)[0].URI
          $part = "$target.part"
          Write-Host ("    getting {0}  ({1} MB)" -f $fi.file_name, [math]::Round($want/1MB,1))
          $wc = New-Object Net.WebClient
          try { $wc.Headers.Add('User-Agent',$UserAgent); $wc.DownloadFile($uri,$part) }
          finally { $wc.Dispose() }
          $got = (Get-Item -LiteralPath $part).Length
          if ($want -gt 0 -and [math]::Abs($got-$want) -ge 4096) {
              Remove-Item -LiteralPath $part -Force; throw "size mismatch: $got vs $want" }
          if ($fi.md5) {
              $h = (Get-FileHash -LiteralPath $part -Algorithm MD5).Hash
              if ($h -ne $fi.md5.ToUpper()) { Remove-Item -LiteralPath $part -Force; throw "md5 mismatch" } }
          Move-Item -LiteralPath $part -Destination $target -Force
      }

      $ex = Join-Path $Work ("m{0}_{1}" -f $id, $fileSeq)
      Expand-Any -Archive $target -Dest $ex
      $baseDirs += $ex
    }

    # ---- FOMOD (only meaningful for a single-file pick) ----
    $ex = $baseDirs[0]
    $srcRoot = $ex
    $fomod = if ($pickList.Count -eq 1) { Get-FomodInfo -Root $ex } else { $null }
    if ($fomod -and $fomod.Unsupported) { throw "FOMOD unsupported: $($fomod.Unsupported)" }
    if ($fomod) {
        $gCount = $fomod.Groups.Count
        $raw = if ($fomodPicks.ContainsKey($id)) { "$($fomodPicks[$id])" } else { '' }
        # each entry is a group: "2" one option, "1+3" several, "0" none
        $sel = @()
        if ($raw -ne '') { $sel = @($raw -split ',') }

        if ($sel.Count -eq 1 -and $sel[0] -eq '-1') { throw "FOMOD marked skip (-1)" }

        # undecided when unanswered, all zeros, or the wrong number of answers
        $answered = ($sel.Count -eq $gCount) -and (@($sel | Where-Object { $_ -ne '0' }).Count -gt 0)
        if (-not $answered) {
            if ($sel.Count -and $sel.Count -ne $gCount) {
                Write-Host ("    FOMOD: needs {0} value(s), one per group - got {1}" -f $gCount, $sel.Count)
            } else {
                Write-Host ("    FOMOD: {0} group(s) - choice needed" -f $gCount)
            }
            if ($fomod.Conditional) {
                Write-Host "    NOTE: this FOMOD hides groups based on earlier answers (e.g. an"
                Write-Host "          MO2-vs-Vortex branch). Set the groups you do not want to 0,"
                Write-Host "          or both branches get installed."
            }
            $cdir = Join-Path $ChoiceDir $id
            New-Item -ItemType Directory -Force -Path $cdir | Out-Null
            $gi = 0; $man = @()
            foreach ($g in $fomod.Groups) {
                $gi++; $pi = 0; $plist = @()
                foreach ($p in $g.Plugins) {
                    $pi++; $imgOut = $null
                    if ($p.Image) {
                        $src = Join-Path $fomod.Root ($p.Image -replace '/','\')
                        if (Test-Path -LiteralPath $src) {
                            $imgOut = "g{0:d2}_p{1:d2}{2}" -f $gi, $pi, [IO.Path]::GetExtension($src)
                            Copy-Item -LiteralPath $src -Destination (Join-Path $cdir $imgOut) -Force } }
                    $plist += [pscustomobject]@{ index=$pi; name=$p.Name
                                                description=$p.Description; image=$imgOut }
                }
                $man += [pscustomobject]@{ group=$gi; name=$g.Name; type=$g.Type
                                           step=$g.Step; plugins=$plist }
            }
            Write-Utf8 -Path (Join-Path $cdir 'choices.json') -Lines @(([pscustomobject]@{
                modId=$id; modName=$name; kind='fomod'; groupCount=$gCount; groups=$man
            } | ConvertTo-Json -Depth 8))
            $needsChoice += [pscustomobject]@{ Id=$id; Name=$name; Groups=$fomod.Groups }
            $results += [pscustomobject]@{ Mod=$name; Status='awaiting FOMOD choice'; Files=0; Unmapped=0 }
            Write-Host ""; continue
        }

        $chosen = @(); $flags = @{}
        for ($gi = 0; $gi -lt $gCount; $gi++) {
            $entry = "$($sel[$gi])"
            if ($entry -eq '0') { continue }                     # take nothing from this group
            foreach ($one in ($entry -split '\+')) {
                $pick2 = [int]$one
                if ($pick2 -eq 0) { continue }
                $p = $fomod.Groups[$gi].Plugins[$pick2 - 1]
                if (-not $p) { throw "FOMOD group $($gi+1) has no option $pick2" }
                Write-Host ("    FOMOD [{0}] {1} -> {2}" -f ($gi+1), $fomod.Groups[$gi].Name, $p.Name)
                $chosen += $p.Sources
                foreach ($f in @($p.Flags)) { if ($f) { $flags[$f.Name] = $f.Value } }
            }
        }

        # conditionalFileInstalls: add file sets whose flag tests now pass
        foreach ($pat in @($fomod.Patterns)) {
            if (-not $pat) { continue }
            if (-not $pat.Supported) {
                Write-Host "    NOTE: a conditional pattern uses a dependency type this engine cannot"
                Write-Host "          evaluate (file/game version). Its files were NOT installed."
                continue
            }
            $results2 = @()
            foreach ($d in @($pat.Deps)) {
                $have = if ($flags.ContainsKey($d.Flag)) { $flags[$d.Flag] } else { '' }
                $results2 += ($have -eq $d.Value)
            }
            $pass = if (-not $results2.Count) { $true }
                    elseif ($pat.Operator -eq 'Or') { @($results2 | Where-Object { $_ }).Count -gt 0 }
                    else { @($results2 | Where-Object { -not $_ }).Count -eq 0 }
            if ($pass -and $pat.Files.Count) {
                Write-Host ("    FOMOD conditional set matched ({0} source(s))" -f $pat.Files.Count)
                $chosen += $pat.Files
            }
        }
        $srcRoot = Join-Path $Work "m$id`_sel"
        New-Item -ItemType Directory -Force -Path $srcRoot | Out-Null
        Copy-FomodSources -Sources (@($fomod.Required) + $chosen) -FomodRoot $fomod.Root -Dest $srcRoot
    }

    if ($fomod) { $baseDirs[0] = $srcRoot }   # FOMOD selection replaces the raw extract

    $structural = @('OblivionRemastered','Engine','ue4ss','Data','Paks','UE4SS','OBSE','Movies',
                    'GameSettings','Root','~mods','LogicMods','Content','Binaries','MagicLoader',
                    'Scripts','scripts','dlls','Mods','Meshes','Textures','Sound','SyncMap')

    # ---- C3: stage, verify, THEN swap ----
    $staging = Join-Path $Work "stage_$id"
    New-Item -ItemType Directory -Force -Path $staging | Out-Null

    $placed=0; $dropped=0; $unmapped=@(); $collisions=@(); $writtenTo=@{}
    $bn = 0
    foreach ($bd in $baseDirs) {
        $bn++
        # H2: unwrap at most ONE non-structural wrapper folder, per archive
        $base = $bd
        $wrapName = $null
        $kids = @(Get-ChildItem -LiteralPath $base -Force | Where-Object { $_.Name -ne 'fomod' })
        if ($kids.Count -eq 1 -and $kids[0].PSIsContainer -and ($structural -notcontains $kids[0].Name)) {
            $base = $kids[0].FullName
            $wrapName = $kids[0].Name
            Write-Host ("    unwrapped: {0}" -f $wrapName)
        }

        # ---- UE4SS script / C++ mod shape ----------------------------------
        # These ship as <ModName>\Scripts\main.lua or <ModName>\dlls\*.dll with
        # no ue4ss\Mods\ prefix. UE4SS keys on that <ModName> folder, so it must
        # survive: stripping it produces a mod that loads nothing, silently.
        $u4Root = $null; $u4Name = $null
        $mk = @(Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ieq 'main.lua' -and $_.Directory.Name -ieq 'Scripts' }) |
              Select-Object -First 1
        if (-not $mk) {
            $mk = @(Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.dll' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Directory.Name -ieq 'dlls' }) | Select-Object -First 1
        }
        if ($mk) {
            $modDir = $mk.Directory.Parent
            $probe  = ($modDir.FullName.Substring($base.Length).TrimStart('\')) -replace '\\','/'
            # leave it alone if the archive already carries a proper ue4ss\Mods\ path
            if ($probe -notmatch '(?i)ue4ss/Mods') {
                if ($modDir.FullName.TrimEnd('\') -eq $base.TrimEnd('\')) {
                    # <root>\Scripts\main.lua - the wrapper we stripped WAS the name
                    $u4Root = $base
                    $u4Name = if ($wrapName) { $wrapName } else { ($name -replace '[^A-Za-z0-9_\-]','') }
                } else {
                    $u4Root = $modDir.FullName
                    $u4Name = $modDir.Name
                }
                if ($u4Name -match '\s') {
                    $u4Name = $u4Name -replace '\s',''
                    Write-Host "    note: stripped spaces from UE4SS mod folder name"
                }
                Write-Host ("    UE4SS mod -> UE4SS\{0}\" -f $u4Name)
            }
        }

        # classify the payload once per archive
        $kind = 'none'
        # H11: only a ROOT-level UE4SS.dll marks a script-extender payload
        if ((Get-ChildItem -LiteralPath $base -File -Filter 'UE4SS.dll' -ErrorAction SilentlyContinue) -or
            (Test-Path -LiteralPath (Join-Path $base 'ue4ss\UE4SS.dll'))) { $kind = 'extender' }
        # the MagicLoader tool ships its own host executables
        elseif (@(Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -in @('MagicLoader.exe','mlcli.exe') }).Count) { $kind = 'mltool' }
        if ($kind -eq 'extender') { Write-Host "    script-extender payload -> Root" }
        if ($kind -eq 'mltool')   { Write-Host "    MagicLoader tool -> Root (game root, not Data)" }

        foreach ($f in Get-ChildItem -LiteralPath $base -Recurse -File) {
            $rel = $f.FullName.Substring($base.Length).TrimStart('\')
            if ($rel -like 'fomod\*') { $dropped++; continue }
            if ($u4Root -and $f.FullName.StartsWith($u4Root, [StringComparison]::OrdinalIgnoreCase)) {
                $sub = ($f.FullName.Substring($u4Root.Length).TrimStart('\')) -replace '\\','/'
                $d = "UE4SS/$u4Name/$sub"
            } else {
                $d = Get-Destination -Rel $rel -Kind $kind
            }
            if ($null -eq $d)      { $dropped++; continue }
            if ($d -eq 'UNMAPPED') { $unmapped += $rel; continue }
            if ($writtenTo.ContainsKey($d)) {
                # within one archive a collision is a packaging problem; across a
                # merge it is the intended "later file wins" behaviour
                if ($writtenTo[$d] -eq $bn) { $collisions += "$d  <- $rel" }
                else { Write-Host ("    merge override: {0}" -f $d) }
            }
            $writtenTo[$d] = $bn
            $o = Join-Path $staging ($d -replace '/','\')
            $od = Split-Path $o -Parent
            if (-not (Test-Path -LiteralPath $od)) { New-Item -ItemType Directory -Force -Path $od | Out-Null }
            Copy-Item -LiteralPath $f.FullName -Destination $o -Force
            $placed++
        }
    }

    if ($placed -eq 0) {
        if ($unmapped.Count -eq 0 -and $dropped -gt 0) {
            Write-Host ("    nothing installable - {0} file(s) were docs/saves/GamePass only" -f $dropped)
            $results += [pscustomobject]@{ Mod=$name; Status='nothing installable'; Files=0; Unmapped=0 }
        } else {
            Write-Host ("    FAIL nothing mapped ({0} unmapped) - existing folder left untouched" -f $unmapped.Count)
            $unmapped | Select-Object -First 10 | ForEach-Object { Write-Host "      $_" }
            $results += [pscustomobject]@{ Mod=$name; Status='no files mapped'; Files=0; Unmapped=$unmapped.Count }
        }
        Write-Host ""; continue
    }

    if (Test-Path -LiteralPath $dest) {
        New-Item -ItemType Directory -Force -Path $Quar | Out-Null
        Move-Item -LiteralPath $dest -Destination (Join-Path $Quar ("{0}-{1}-{2}" -f $name,$Stamp,$id))
        Write-Host "    previous copy -> _DELETE_ME"
    }
    Move-Item -LiteralPath $staging -Destination $dest

    $ini = @("[General]","gameName=$GameDomain","modid=$id","version=$($fiLast.version)",
             "newestVersion=","category=`"0`"","repository=Nexus",
             "installationFile=$($archNames[0])")
    if ($archNames.Count -gt 1) { $ini += "notes=merged files: $($archNames -join ' + ')" }
    Write-Utf8 -Path (Join-Path $dest 'meta.ini') -Lines $ini
    [IO.File]::WriteAllText((Join-Path $dest '.nexus_installed'), $sig, (New-Object Text.ASCIIEncoding))

    Write-Host ("    placed {0}, dropped {1}" -f $placed, $dropped)
    foreach ($t in (Get-ChildItem -LiteralPath $dest -Directory | Sort-Object Name)) {
        Write-Host ("      {0,-14} {1}" -f $t.Name, @(Get-ChildItem -LiteralPath $t.FullName -Recurse -File).Count) }
    if ($unmapped.Count)   { Write-Host ("    UNMAPPED {0}:" -f $unmapped.Count)
                             $unmapped | Select-Object -First 10 | ForEach-Object { Write-Host "      $_" } }
    if ($collisions.Count) { Write-Host ("    COLLISIONS {0} (review by hand):" -f $collisions.Count)
                             $collisions | Select-Object -First 10 | ForEach-Object { Write-Host "      $_" } }

    $results += [pscustomobject]@{ Mod=$name; Status='installed'; Files=$placed; Unmapped=$unmapped.Count }
  }
  catch {
    Write-Host ("    FAIL {0}" -f $_.Exception.Message)
    $results += [pscustomobject]@{ Mod=$name; Status='error'; Files=0; Unmapped=0 }
    if ($script:RateLimited) { Write-Host ""; Write-Host "Rate limited - stopping so the rest can resume later."; break }
  }
  Write-Host ""
}

# ---- H10: append FOMOD blocks only for ids not already asked ---------------
if ($needsChoice.Count) {
    $asked = @{}
    foreach ($line in Get-Content -LiteralPath $PicksFile) {
        if ($line -match '^\s*(\d+)\.fomod\s*=') { $asked[$Matches[1]] = $true } }
    $add = @()
    foreach ($nc in $needsChoice) {
        if ($asked.ContainsKey($nc.Id)) { continue }
        $add += ''; $add += ('# ' + ('=' * 74))
        $add += "# FOMOD  mod $($nc.Id)  -  $($nc.Name)"
        $add += "#   images + descriptions: $ChoiceDir\$($nc.Id)\"
        $add += "#   one value per group, in order. 0 = take nothing from that group."
        $gi = 0
        foreach ($g in $nc.Groups) {
            $gi++
            $add += ("#   group {0}: {1}   [{2}]" -f $gi, $g.Name, $g.Type)
            $pi = 0
            foreach ($p in $g.Plugins) { $pi++
                $add += ("#      [{0,2}] {1}" -f $pi, $p.Name)
                if ($p.Description) { $add += "#           $($p.Description)" } }
        }
        $zeros = (@('0') * $nc.Groups.Count) -join ','
        $add += "$($nc.Id).fomod = $zeros    # one per group, -1 = skip this mod"
    }
    if ($add.Count) { Add-Content -LiteralPath $PicksFile -Value $add -Encoding UTF8 }
    Write-Host ("{0} FOMOD choice(s) pending - see {1}" -f $needsChoice.Count, $PicksFile)
    Write-Host ""
}

# ---- conflicts: REPORT ONLY, never disable --------------------------------
Write-Host "=== conflicts (report only - nothing is disabled) ==="
# Scan EVERY mod folder, not just this run's - a pre-existing mod can still be
# shadowed by one we just installed.
$orderOf = @{}
foreach ($k in $state.Keys) { if ($state[$k].name) { $orderOf[$state[$k].name] = [int]$state[$k].order } }

$fileOwners=@{}; $modFiles=@{}
foreach ($md in Get-ChildItem -LiteralPath $ModsDir -Directory) {
    $mdir = $md.FullName
    $ord  = if ($orderOf.ContainsKey($md.Name)) { $orderOf[$md.Name] } else { 0 }  # unmanaged = lowest
    $rels=@()
    foreach ($f in Get-ChildItem -LiteralPath $mdir -Recurse -File) {
        $rel = $f.FullName.Substring($mdir.Length).TrimStart('\')
        if ($rel -in @('meta.ini','.nexus_installed')) { continue }
        $rels += $rel
        if (-not $fileOwners.ContainsKey($rel)) { $fileOwners[$rel] = @() }
        $fileOwners[$rel] += @{ Mod=$md.Name; Order=$ord }
    }
    $modFiles[$md.Name] = $rels
}
$contested = @($fileOwners.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })
if (-not $contested.Count) { Write-Host "  none" }
else {
    $pairs=@{}
    foreach ($c in $contested) {
        $sorted = @($c.Value | Sort-Object { [int]$_.Order })      # H7: scriptblock, not -Property
        $winner = $sorted[-1]
        foreach ($loser in $sorted[0..($sorted.Count-2)]) {
            if ($loser.Mod -eq $winner.Mod) { continue }           # H8
            $k = "{0}`t{1}" -f $loser.Mod, $winner.Mod             # H6: tab key, split with -split
            if (-not $pairs.ContainsKey($k)) { $pairs[$k]=0 }
            $pairs[$k]++ }
    }
    foreach ($k in $pairs.Keys | Sort-Object) {
        $p = $k -split "`t"
        $total = @($modFiles[$p[0]]).Count
        $pct = if ($total) { [math]::Round(100*$pairs[$k]/$total) } else { 0 }
        Write-Host ("  {0}  loses {1}/{2} files ({3}%) to  {4}" -f $p[0],$pairs[$k],$total,$pct,$p[1])
        if ($total -gt 0 -and $pairs[$k] -eq $total) {
            Write-Host "      ^ FULLY SHADOWED - consider disabling it yourself in MO2" }
    }
}
Write-Host ""

# ---- C2: modlist.txt - backup, preserve verbatim, insert new only ---------
# A FOMOD awaiting a choice is a deliberate pause, not a failure - it must not
# block the mods that DID install from being written into the load order.
$benign = @('installed','skipped','up to date','awaiting FOMOD choice')
$failed = @($results | Where-Object { $_.Status -notin $benign }).Count
$modlistPath = Join-Path $ProfileDir 'modlist.txt'

if ($results.Count -and $failed -gt [math]::Floor($results.Count / 4)) {
    Write-Host ("NOT touching modlist.txt: {0} of {1} mods failed. Fix and re-run." -f $failed, $results.Count)
} else {
    if (Test-Path -LiteralPath $modlistPath) {
        Copy-Item -LiteralPath $modlistPath -Destination "$modlistPath.bak-$Stamp" -Force }
    $raw = @(); if (Test-Path -LiteralPath $modlistPath) { $raw = @(Get-Content -LiteralPath $modlistPath) }
    $seen = @{}
    foreach ($l in $raw) { if ($l -match '^([+\-*])(.+)$') { $seen[$Matches[2]] = $true } }

    $installedNow = @($results | Where-Object { $_.Status -in @('installed','up to date') } | ForEach-Object { $_.Mod })
    $newOnes = @()
    foreach ($id in $byOrder) {
        $meta = $state[$id]; if (-not $meta) { continue }
        if ($installedNow -notcontains $meta.name) { continue }
        if ($seen.ContainsKey($meta.name)) { continue }     # already listed: leave its state alone
        $newOnes += $meta.name }
    [array]::Reverse($newOnes)                              # last in list = top = wins

    $lines=@(); $body=$raw
    if ($raw.Count -and $raw[0] -like '#*') { $lines += $raw[0]; $body = @($raw | Select-Object -Skip 1) }
    else { $lines += '# This file was automatically generated by Mod Organizer.' }
    foreach ($n in $newOnes) { $lines += "+$n" }
    foreach ($l in $body) { if ($l.Trim()) { $lines += $l } }
    Write-Utf8 -Path $modlistPath -Lines $lines
    Write-Host ("modlist.txt: +{0} new at top, {1} existing lines preserved verbatim" -f $newOnes.Count, $body.Count)
}
Write-Host ""

$espCount = @(Get-ChildItem -LiteralPath $ModsDir -Recurse -File -ErrorAction SilentlyContinue |
              Where-Object { $_.Extension -in @('.esp','.esm') }).Count
Write-Host "=== summary ==="
$results | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "$espCount plugin file(s) on disk. This script does NOT write plugins.txt -"
Write-Host "enable them in MO2's right pane, then sort with LOOT."
Write-Host ""
Write-Host "Next:  X:\MODDING\OBLIVION\tools\nexus2.ps1 -Mode verify"
Write-Host "Log: $Log"

Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
Stop-Transcript | Out-Null
