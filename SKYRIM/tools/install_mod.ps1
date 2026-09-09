#Requires -Version 5.1
<#
  install_mod.ps1 - install a downloaded archive as an MO2 mod, no clicking.

    install_mod.ps1 -Archive "...\Alternate Start ....7z"
    install_mod.ps1 -Archive "..." -Apply
    install_mod.ps1 -Mod 272 -File 729409 -Apply       download it first, then install
    install_mod.ps1 -Apply -All                        install every archive in downloads\

    -Name "Alternate Start"      override the mod folder name
    -Bottom                      lowest priority instead of highest
    -NoPlugins                   install but leave the plugins switched off
    -KeepTop "<mod>"             mod to force back to highest priority after
                                 installing (default 'BodySlide Output')
    -NoKeepTop                   do not do that

  WHAT AN MO2 MOD ACTUALLY IS

  A folder under mods\ whose contents are what would otherwise sit in the game's
  Data folder, plus a meta.ini. That is the whole format. So installing is:
  unpack, work out which directory inside the archive IS the Data folder, copy
  it to mods\<name>\, write meta.ini, add a +<name> line to modlist.txt, and
  activate any plugins. This does those five things.

  Skyrim is far simpler here than Oblivion Remastered, which is why this is a
  fraction of the size of nexus2.ps1 - there is one destination, not six
  (Data / Paks / UE4SS / OBSE / Root / GameSettings), and no pak ordering.

  FINDING THE DATA ROOT

  Archives are inconsistent: some have Data at the top, some wrap everything in
  a folder named after the mod, some nest two or three deep. The rule used here
  is to descend while a directory has exactly one child directory and nothing
  the game would recognise, and stop at the first level that DOES contain
  something recognisable - a plugin, a BSA, or a known Data subfolder like
  meshes or scripts. That is the same heuristic MO2's own installer uses.

  FOMOD INSTALLERS

  A fomod\ModuleConfig.xml means the author intends you to make choices. With
  no choices given this still reports the option list and skips, because
  picking silently is how you end up with the wrong body mod or a DLL for the
  wrong runtime. Name the choices and it applies them:

    -Fomod "DLL=v1.6.1170; Light Set Texture=Dawn 3"
        Group=Option, ';' between groups, '|' between several options in one
        group ('|' and not ',' or '+' because option names contain both).
        Group and option match on exact name, then prefix, then substring, and
        an ambiguous or unknown name is an error rather than a guess.
        '*' selects every option in a group, '-' selects none.

    -FomodDefaults
        Take the first option in any SelectExactlyOne or SelectAtLeastOne group
        that -Fomod did not name. Required and Recommended options are always
        taken regardless. SelectAny and SelectAtMostOne stay EMPTY - "any"
        legitimately means none, and picking the first there is a guess.
        Careful: 'first' is wrong for a runtime-version group, where the newest
        DLL is usually listed first. Name those explicitly.

    -FomodPlan
        Print the resolved options and the file list, install nothing.

  PRIORITY

  modlist.txt is read with the FIRST line as HIGHEST priority in MO2's display,
  and later-listed mods lose conflicts. New mods go on top by default, so the
  thing you just installed wins. -Bottom puts it at the other end.
#>

[CmdletBinding()]
param(
    [string]$Root     = 'X:\MODDING\SKYRIM',
    [string]$Archive,
    [string]$Mod,
    [int]$File,
    [string]$Name,
    [switch]$All,
    [switch]$Bottom,
    [switch]$NoPlugins,
    [string]$KeepTop = 'BodySlide Output',
    [switch]$NoKeepTop,
    [string]$Fomod,
    [switch]$FomodDefaults,
    [switch]$FomodPlan,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$Instance  = Join-Path $Root 'SKYRIM_SE'
$ModsDir   = Join-Path $Instance 'mods'
$Dloads    = Join-Path $Instance 'downloads'
$ProfileD  = Join-Path $Instance 'profiles\Default'
$Work      = Join-Path $env:TEMP ("mo2install-$Stamp")
$Utf8NoBom = New-Object Text.UTF8Encoding $false
$mode      = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to install' }

# things that mean "this directory is the Data folder"
$DataDirs = @('meshes','textures','scripts','interface','sound','music','video','seq','grass',
              'lodsettings','dialogueviews','skse','shaders','shadersfx','strings','source','tools',
              'calientetools','netscriptframework','dyndolod','facegendata','actors','effects',
              'skyproc patchers','asset packs','distributedeasy','_conditions',
              # Behaviour-patch mods ship one of these and nothing else - no plugin,
              # no BSA, no meshes\. Without them the descent walks straight past the
              # real Data root and the install dies with "could not find a Data root".
              # Nemesis_Engine is First Person Animation Teleport Bug Fix (92795).
              'nemesis_engine','pandora_engine','fnis behavior')
$DataExt  = @('.esp','.esm','.esl','.bsa')

# Config-only mods. A distributor ini sits LOOSE at the Data root with no
# plugin, no BSA and no subfolder at all, so nothing above recognises it and
# the descent fails. Found 2026-09-08 on AI Overhaul SPIDified (136826).
$DataPats = @('*_DISTR.ini','*_KID.ini','*_SWAP.ini','*_CRD.ini','*_FLM.ini',
              '*_SRD.ini','*_DESC.ini','*_CDF.ini','*_OCF.ini')

function Test-IsDataRoot {
    param([string]$Dir, [string[]]$Dirs, [string[]]$Exts)
    foreach ($c in @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)) {
        if ($c.PSIsContainer) { if ($Dirs -contains $c.Name.ToLower()) { return $true } }
        elseif ($Exts -contains $c.Extension.ToLower()) { return $true }
        else {
            foreach ($pat in $script:DataPats) { if ($c.Name -like $pat) { return $true } }
        }
    }
    return $false
}

# ---------------------------------------------------------------- fomod ------
# A FOMOD is an installer script: fomod\ModuleConfig.xml declares steps, each
# with groups of options, and each option carries the files it contributes.
# Applying one is therefore: pick a plugin per group, collect the files those
# plugins declare, add requiredInstallFiles, then evaluate conditionalFileInstalls
# against the flags the picked plugins set. The result is an ordinary Data tree,
# which is why this hands off to the same code path as any other archive.
#
# What is modelled: installSteps, all five group types, plugin files and folders
# with destination and priority, conditionFlags, conditionalFileInstalls and
# installStep visibility driven by flagDependency.
#
# What is NOT modelled: fileDependency, gameDependency, and the other
# environment probes. Those evaluate as TRUE rather than being guessed at, so a
# step gated on "is mod X installed" is shown and its group still has to be
# answered. -FomodPlan prints the resolved file list so this is checkable
# before anything is written.

function Resolve-FomodPath {
    # FOMOD source paths are archive-relative and their case rarely matches what
    # 7-Zip wrote to disk. Walk the segments, exact match first, then insensitive.
    param([string]$Base, [string]$Rel)
    if (-not $Rel) { return $Base }
    $cur = $Base
    foreach ($seg in @(($Rel -split '[\\/]+') | Where-Object { $_ -ne '' })) {
        $kids = @(Get-ChildItem -LiteralPath $cur -Force -ErrorAction SilentlyContinue)
        $hit  = @($kids | Where-Object { $_.Name -ceq $seg })
        if (-not $hit.Count) { $hit = @($kids | Where-Object { $_.Name -ieq $seg }) }
        if (-not $hit.Count) { return $null }
        $cur = $hit[0].FullName
    }
    return $cur
}

function Test-FomodDeps {
    param($Node, [hashtable]$Flags)
    if (-not $Node) { return $true }
    $op = $Node.GetAttribute('operator')
    if (-not $op) { $op = 'And' }
    $res = New-Object System.Collections.Generic.List[bool]
    foreach ($c in @($Node.ChildNodes)) {
        switch ($c.LocalName) {
            'flagDependency' {
                $f = $c.GetAttribute('flag')
                $have = if ($Flags.ContainsKey($f)) { $Flags[$f] } else { '' }
                $res.Add([bool]($have -eq $c.GetAttribute('value')))
            }
            'dependencies' { $res.Add([bool](Test-FomodDeps $c $Flags)) }
            default        { $res.Add($true) }   # not modelled - do not fail the step over it
        }
    }
    if (-not $res.Count) { return $true }
    if ($op -ieq 'Or') { return ($res -contains $true) }
    return (-not ($res -contains $false))
}

function Get-FomodPluginType {
    param($Plugin)
    $t = $Plugin.SelectSingleNode('typeDescriptor/type')
    if ($t) { return $t.GetAttribute('name') }
    $d = $Plugin.SelectSingleNode('typeDescriptor/dependencyType/defaultType')
    if ($d) { return $d.GetAttribute('name') }
    return 'Optional'
}

function Add-FomodFiles {
    param($FilesNode, [string]$ArcRoot, $Into)
    if (-not $FilesNode) { return }
    foreach ($n in @($FilesNode.ChildNodes)) {
        if ($n.LocalName -notin @('file','folder')) { continue }
        $srcRel = $n.GetAttribute('source')
        $dstRel = $n.GetAttribute('destination')
        # An omitted destination means "same relative path", not "Data root".
        # An explicitly empty one DOES mean the Data root, which is why this
        # tests for the attribute rather than for emptiness.
        if (-not $n.HasAttribute('destination')) { $dstRel = $srcRel }
        $pr = 0
        if ($n.HasAttribute('priority')) { [void][int]::TryParse($n.GetAttribute('priority'), [ref]$pr) }
        $abs = Resolve-FomodPath $ArcRoot $srcRel
        if (-not $abs) {
            Write-Host ("      missing in archive, skipped: {0}" -f $srcRel) -ForegroundColor Yellow
            continue
        }
        $Into.Add([pscustomobject]@{
            Kind = $n.LocalName; Src = $abs; Dst = $dstRel; Priority = $pr; Rel = $srcRel
        })
    }
}

function Invoke-Fomod {
    <#
      Resolves a FOMOD into a flat Data tree and returns its path, or $null when
      the choices given do not answer every group that has to be answered.
    #>
    param(
        [string]$FomodDir,      # the fomod\ folder holding ModuleConfig.xml
        [string]$ArcRoot,       # the folder that fomod\ sits in - all sources are relative to this
        [string]$OutDir,
        [string]$Choices,       # "Group=Option; Group2=Opt A|Opt B"
        [switch]$Defaults,
        [switch]$PlanOnly
    )

    [xml]$mc = Get-Content -LiteralPath (Join-Path $FomodDir 'ModuleConfig.xml') -Raw

    # ---- parse the choice string -------------------------------------------
    # '|' separates several options inside one group because option names very
    # often contain both ',' and '+' ("ESL + 3BA Bodyslide").
    $want = @{}
    $order = New-Object System.Collections.Generic.List[string]
    foreach ($pair in @(($Choices -split ';') | Where-Object { $_.Trim() })) {
        $i = $pair.IndexOf('=')
        if ($i -lt 1) { throw "bad -Fomod entry '$pair' - expected Group=Option" }
        $k = $pair.Substring(0, $i).Trim()
        $v = $pair.Substring($i + 1).Trim()
        $want[$k] = @(($v -split '\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $order.Add($k)
    }
    $used = @{}

    $flags   = @{}
    $picked  = New-Object System.Collections.Generic.List[object]
    $files   = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[object]

    Add-FomodFiles $mc.SelectSingleNode('/config/requiredInstallFiles') $ArcRoot $files

    # Some FOMODs reuse a group name across many steps with DIFFERENT options -
    # JK's Interiors Patch Collection has ten groups called "Miscellaneous
    # Patches", and More to Say has two called "Available Modules". A -Fomod key
    # addresses them all at once, so an option valid in one is missing from
    # another. Throwing there is wrong: it is not a typo, it is a name clash.
    # So collect the duplicated names first, and downgrade the throw for those.
    $dupGroupNames = New-Object System.Collections.Generic.HashSet[string]
    $seenGroupName = New-Object System.Collections.Generic.HashSet[string]
    foreach ($gg in @($mc.SelectNodes('/config/installSteps/installStep/optionalFileGroups/group'))) {
        $gn = $gg.GetAttribute('name')
        if (-not $gn) { continue }
        if (-not $seenGroupName.Add($gn.ToLower())) { [void]$dupGroupNames.Add($gn.ToLower()) }
    }

    foreach ($step in @($mc.SelectNodes('/config/installSteps/installStep'))) {
        $vis = $step.SelectSingleNode('visible/dependencies')
        if (-not $vis) { $vis = $step.SelectSingleNode('visible') }
        if ($vis -and -not (Test-FomodDeps $vis $flags)) { continue }

        foreach ($g in @($step.SelectNodes('optionalFileGroups/group'))) {
            $gname   = $g.GetAttribute('name')
            $gtype   = $g.GetAttribute('type')
            $plugins = @($g.SelectNodes('plugins/plugin'))
            if (-not $plugins.Count) { continue }

            # which key in -Fomod addresses this group: exact, then prefix, then substring
            $key = $null
            foreach ($k in $order) {
                if ($k -ieq $gname) { $key = $k; break }
            }
            if (-not $key) {
                foreach ($k in $order) {
                    if ($gname -and $gname.ToLower().StartsWith($k.ToLower())) { $key = $k; break }
                }
            }
            if (-not $key) {
                foreach ($k in $order) {
                    if ($gname -and $gname.ToLower().Contains($k.ToLower())) { $key = $k; break }
                }
            }

            $chosen = New-Object System.Collections.Generic.List[object]

            if ($key) {
                $used[$key] = $true
                foreach ($opt in $want[$key]) {
                    if ($opt -eq '*') { foreach ($p in $plugins) { $chosen.Add($p) }; continue }
                    if ($opt -in @('-', 'none', 'None')) { continue }
                    $hit = @($plugins | Where-Object { $_.GetAttribute('name') -ieq $opt })
                    if (-not $hit.Count) {
                        $hit = @($plugins | Where-Object { $_.GetAttribute('name').ToLower().StartsWith($opt.ToLower()) })
                    }
                    if (-not $hit.Count) {
                        $hit = @($plugins | Where-Object { $_.GetAttribute('name').ToLower().Contains($opt.ToLower()) })
                    }
                    if (-not $hit.Count) {
                        if ($gname -and $dupGroupNames.Contains($gname.ToLower())) {
                            # this option belongs to a different group of the same
                            # name. Skip it here; it gets selected where it exists.
                            continue
                        }
                        throw ("group '{0}': no option matches '{1}'. Options are: {2}" -f `
                               $gname, $opt, (($plugins | ForEach-Object { $_.GetAttribute('name') }) -join ' / '))
                    }
                    if ($hit.Count -gt 1) {
                        # An EXACT match always wins over several loose ones. Dragon
                        # Priest Retexture has two groups both called Nahkriin, one
                        # offering "Ebony" and one offering "Nahkriin Ebony", so the
                        # string "Ebony" is exact in one and ambiguous in the other.
                        $exact = @($hit | Where-Object { $_.GetAttribute('name') -ieq $opt })
                        if ($exact.Count -eq 1) { $hit = $exact }
                        elseif ($gname -and $dupGroupNames.Contains($gname.ToLower())) {
                            # a repeated group name: this option belongs to a
                            # different instance, so skip rather than stop.
                            continue
                        } else {
                            throw ("group '{0}': '{1}' matches {2} options - be more specific: {3}" -f `
                                   $gname, $opt, $hit.Count, (($hit | ForEach-Object { $_.GetAttribute('name') }) -join ' / '))
                        }
                    }
                    $chosen.Add($hit[0])
                }
            } else {
                # Nothing named this group. Required options always go in.
                # Recommended ones do too. Beyond that, only a group that MUST be
                # answered gets a fallback, and only under -FomodDefaults.
                foreach ($p in $plugins) {
                    $t = Get-FomodPluginType $p
                    if ($t -eq 'Required') { $chosen.Add($p) }
                }
                if (-not $chosen.Count) {
                    foreach ($p in $plugins) {
                        if ((Get-FomodPluginType $p) -eq 'Recommended') { $chosen.Add($p); break }
                    }
                }
                if (-not $chosen.Count -and $gtype -eq 'SelectAll') {
                    foreach ($p in $plugins) { $chosen.Add($p) }
                }
                if (-not $chosen.Count -and $gtype -in @('SelectExactlyOne','SelectAtLeastOne')) {
                    if ($Defaults) {
                        $chosen.Add($plugins[0])
                    } else {
                        $missing.Add([pscustomobject]@{
                            Group = $gname; Type = $gtype
                            Options = @($plugins | ForEach-Object { $_.GetAttribute('name') })
                        })
                    }
                }
                # SelectAny and SelectAtMostOne with nothing named stay empty on
                # purpose: "any" legitimately means none, and picking the first
                # is not a default, it is a guess.
            }

            # enforce the group's own arity so a typo cannot install two bodies
            if ($gtype -eq 'SelectExactlyOne' -and $chosen.Count -gt 1) {
                throw ("group '{0}' is SelectExactlyOne but {1} options were given" -f $gname, $chosen.Count)
            }
            if ($gtype -eq 'SelectAtMostOne' -and $chosen.Count -gt 1) {
                throw ("group '{0}' is SelectAtMostOne but {1} options were given" -f $gname, $chosen.Count)
            }

            foreach ($p in $chosen) {
                $picked.Add([pscustomobject]@{ Group = $gname; Option = $p.GetAttribute('name') })
                Add-FomodFiles $p.SelectSingleNode('files') $ArcRoot $files
                foreach ($f in @($p.SelectNodes('conditionFlags/flag'))) {
                    $flags[$f.GetAttribute('name')] = $f.InnerText
                }
            }
        }
    }

    foreach ($pat in @($mc.SelectNodes('/config/conditionalFileInstalls/patterns/pattern'))) {
        if (Test-FomodDeps $pat.SelectSingleNode('dependencies') $flags) {
            Add-FomodFiles $pat.SelectSingleNode('files') $ArcRoot $files
        }
    }

    foreach ($k in $order) {
        if (-not $used.ContainsKey($k)) {
            Write-Host ("      -Fomod named a group that does not exist: '{0}'" -f $k) -ForegroundColor Yellow
        }
    }

    if ($missing.Count) {
        Write-Host ("  {0} group(s) still need an answer:" -f $missing.Count) -ForegroundColor Yellow
        foreach ($m in $missing) {
            Write-Host ("      {0}  [{1}]" -f $m.Group, $m.Type) -ForegroundColor Yellow
            foreach ($o in $m.Options) { Write-Host ("         - {0}" -f $o) }
        }
        Write-Host "      Name them with -Fomod, or pass -FomodDefaults to take the first option in each."
        return $null
    }

    Write-Host ("  fomod: {0} option(s) selected, {1} file entr(ies)" -f $picked.Count, $files.Count) -ForegroundColor Green
    foreach ($p in $picked) { Write-Host ("      {0,-42} -> {1}" -f $p.Group, $p.Option) }

    if ($PlanOnly) {
        Write-Host "  files that would be installed:"
        foreach ($f in @($files | Sort-Object Priority)) {
            Write-Host ("      [{0,3}] {1,-6} {2}  ->  {3}" -f $f.Priority, $f.Kind, $f.Rel, $(if ($f.Dst) { $f.Dst } else { '<Data root>' }))
        }
        return $null
    }

    # ---- build the tree -----------------------------------------------------
    # Lower priority first, so higher-priority entries overwrite. Sort-Object is
    # stable, which is what preserves declaration order inside one priority.
    if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    foreach ($f in @($files | Sort-Object Priority)) {
        $dest = if ($f.Dst) { Join-Path $OutDir $f.Dst } else { $OutDir }
        if ($f.Kind -eq 'folder') {
            if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
            foreach ($c in @(Get-ChildItem -LiteralPath $f.Src -Force -ErrorAction SilentlyContinue)) {
                Copy-Item -LiteralPath $c.FullName -Destination $dest -Recurse -Force
            }
        } else {
            $dd = Split-Path $dest -Parent
            if ($dd -and -not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Force -Path $dd | Out-Null }
            Copy-Item -LiteralPath $f.Src -Destination $dest -Force
        }
    }
    return $OutDir
}

Write-Host ""
Write-Host "=== install mod ($mode) ===" -ForegroundColor Cyan

foreach ($p in @($ModsDir, $ProfileD)) { if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" } }
if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. It rewrites modlist.txt on exit and would discard this. Close it first."
}

function Get-SevenZip {
    foreach ($c in @("$env:ProgramFiles\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe",
                     "$env:ProgramFiles\NanaZip\NanaZipC.exe")) {
        if (Test-Path -LiteralPath $c) { return $c } }
    $c = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}
$SZ = Get-SevenZip
if (-not $SZ) { throw "7-Zip not found (winget install --id 7zip.7zip -e)" }

# ---------------------------------------------------------------- gather -----
# -Archive is checked FIRST and wins outright.
#
# It used to come second, so passing -Mod and -Archive together silently ignored
# the archive you named. Worse, the -Mod branch below picked "the newest file in
# downloads" on the theory that it was the one just fetched - true only when a
# fetch actually happened. Skip the download because the file is already there,
# and it installs whatever you happened to download most recently instead. That
# put PapyrusUtil inside a mod folder named JContainers SE and reported success.
$archives = @()
if ($Archive) {
    if (-not (Test-Path -LiteralPath $Archive)) { throw "not found: $Archive" }
    $archives = @(Get-Item -LiteralPath $Archive)
} elseif ($Mod) {
    $get = Join-Path $Root 'tools\nexus_get.ps1'
    if (-not (Test-Path -LiteralPath $get)) { throw "not found: $get" }
    # A HASHTABLE, not an array. Splatting an array passes its elements as
    # POSITIONAL arguments, so '-Mod' arrives as the value of the first
    # positional parameter instead of naming it. Only hashtable splatting
    # binds parameters by name.
    # NOT named $args - that is an automatic variable.
    $getArgs = @{ Mod = $Mod; Dest = $Dloads }
    if ($File) { $getArgs['File'] = $File } else { $getArgs['Main'] = $true }

    # Snapshot before and after, so "what did the fetch produce" is answered by
    # observation rather than by assuming something was produced at all.
    function Get-Arcs {
        return @(Get-ChildItem -LiteralPath $Dloads -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Extension.ToLower() -in @('.7z','.zip','.rar') })
    }
    $before = @{}
    foreach ($f in (Get-Arcs)) { $before[$f.FullName] = $f.LastWriteTimeUtc.Ticks }

    Write-Host ""
    & $get @getArgs

    $after = Get-Arcs
    $fresh = @($after | Where-Object {
        (-not $before.ContainsKey($_.FullName)) -or ($before[$_.FullName] -ne $_.LastWriteTimeUtc.Ticks) })

    if ($fresh.Count) {
        $archives = @($fresh | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    } else {
        # Nothing was fetched, so match on the mod id carried in the filename.
        $byId = @($after | Where-Object { $_.Name -match ("[-\s]" + [regex]::Escape($Mod) + "[-\s]") } |
                  Sort-Object LastWriteTime -Descending)
        if (-not $byId.Count) {
            throw "nothing was downloaded and no archive in $Dloads carries mod id $Mod. Pass -Archive with the exact path."
        }
        if ($byId.Count -gt 1) {
            # Refuse rather than guess. Picking by timestamp among several builds
            # of the same mod is how you end up installing 4.2.9 when you asked
            # for 4.2.13.1, and nothing in the output would tell you.
            Write-Host ""
            Write-Host ("  {0} archives in downloads carry mod id {1}:" -f $byId.Count, $Mod) -ForegroundColor Yellow
            foreach ($b in $byId) { Write-Host ("      {0}" -f $b.Name) -ForegroundColor Yellow }
            throw "ambiguous - pass -Archive with the exact path of the one you want."
        }
        $archives = @($byId)
    }
}
elseif ($All) {
    $archives = @(Get-ChildItem -LiteralPath $Dloads -File | Where-Object { $_.Extension -in @('.7z','.zip','.rar') })
} else {
    throw "pass -Archive <path>, -Mod <id>, or -All"
}

# The guard that would have caught the bug above on the first run: if a mod id
# was named, the archive being installed has to be that mod's.
if ($Mod -and $archives.Count -eq 1) {
    if ($archives[0].Name -notmatch ("[-\s]" + [regex]::Escape($Mod) + "[-\s]")) {
        throw ("refusing to install: -Mod $Mod but the chosen archive is '" + $archives[0].Name +
               "', whose name carries no such id. Pass -Archive alone if that is deliberate.")
    }
}

if (-not $archives.Count) { throw "nothing to install" }

# ---- current profile state, read once --------------------------------------
$mlPath = Join-Path $ProfileD 'modlist.txt'
$mlLines = @()
if (Test-Path -LiteralPath $mlPath) { $mlLines = @(Get-Content -LiteralPath $mlPath) }
$existing = @{}
foreach ($l in $mlLines) { if ($l -match '^[+\-](.+)$') { $existing[$Matches[1].TrimEnd()] = $true } }

$results = New-Object System.Collections.Generic.List[object]

foreach ($a in $archives) {
    Write-Host ""
    Write-Host ("--- {0} ---" -f $a.Name)

    # a clean folder name: strip the Nexus id/version/timestamp tail
    $mn = if ($Name -and $archives.Count -eq 1) { $Name }
          else {
              # Nexus uses two filename conventions. Older: "Name-<id>-<ver>-<epoch>".
              # Current: "Name <id> <ver> <ISO stamp> <hash>". Strip either tail.
              ($a.BaseName -replace '\s+\d+\s+[\w.]+\s+\d{4}-\d{2}-\d{2}T\d{2}-\d{2}Z\s+\S+$','' `
                           -replace '-\d+-[\d\-a-zA-Z]+-\d{6,}$','' `
                           -replace '[-_\s]+$','').Trim()
          }
    $mn = ($mn -replace '[<>:"/\\|?*]', '_').Trim()
    if (-not $mn) { $mn = $a.BaseName }

    $ex = Join-Path $Work ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Force -Path $ex | Out-Null
    & $SZ x "-o$ex" -y -bso0 -bsp0 -- $a.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("  7-Zip failed (exit {0}) - skipping" -f $LASTEXITCODE) -ForegroundColor Red
        $results.Add([pscustomobject]@{ Name = $mn; Status = 'unpack failed' }); continue
    }

    # ---- FOMOD? ------------------------------------------------------------
    # $fomodDirs, NOT $fomod. PowerShell variable names are case-insensitive, so
    # a local named $fomod IS the -Fomod parameter. Because that parameter is
    # declared [string], assigning the DirectoryInfo array to it coerced the
    # whole thing to a string - $fomod.Count then returned 1, $fomod[0] returned
    # the first CHARACTER of the path, and .FullName on a char is null. The
    # symptom was "Cannot bind argument to parameter 'Path'" from Split-Path,
    # nowhere near the assignment that caused it.
    $fomodRoot = $null
    $fomodDirs = @(Get-ChildItem -LiteralPath $ex -Recurse -Directory -Filter 'fomod' -ErrorAction SilentlyContinue |
               Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'ModuleConfig.xml') })
    if ($fomodDirs.Count) {
        # Sources inside ModuleConfig.xml are relative to the folder the fomod\
        # directory sits in, which is not necessarily the archive root.
        $arcRoot = Split-Path $fomodDirs[0].FullName -Parent

        if ($Fomod -or $FomodDefaults -or $FomodPlan) {
            Write-Host "  FOMOD installer - applying the choices given." -ForegroundColor Cyan
            $built = $null
            try {
                $built = Invoke-Fomod -FomodDir $fomodDirs[0].FullName -ArcRoot $arcRoot `
                                      -OutDir (Join-Path $ex '__fomod_out') `
                                      -Choices $Fomod -Defaults:$FomodDefaults -PlanOnly:$FomodPlan
            } catch {
                Write-Host ("  {0}" -f $_.Exception.Message) -ForegroundColor Red
            }
            if (-not $built) {
                $results.Add([pscustomobject]@{ Name = $mn; Status = 'FOMOD - skipped' }); continue
            }
            $fomodRoot = $built
        } else {
            Write-Host "  FOMOD installer - this one wants choices, so it is not being guessed at." -ForegroundColor Yellow
            try {
                [xml]$mc = Get-Content -LiteralPath (Join-Path $fomodDirs[0].FullName 'ModuleConfig.xml') -Raw
                $groups = @($mc.config.installSteps.installStep.optionalFileGroups.group)
                foreach ($g in $groups) {
                    if (-not $g) { continue }
                    Write-Host ("      group: {0}  [{1}]" -f $g.name, $g.type)
                    foreach ($p in @($g.plugins.plugin)) { if ($p) { Write-Host ("         - {0}" -f $p.name) } }
                }
            } catch { Write-Host "      (could not parse its option list)" }
            # Single-quoted: PowerShell's escape character is a backtick, NOT a
            # backslash, so \" ended the string early and the remainder of the
            # line was parsed as commands.
            Write-Host '      Pass -Fomod "Group=Option; ..." or -FomodDefaults to install it.' 
            $results.Add([pscustomobject]@{ Name = $mn; Status = 'FOMOD - skipped' }); continue
        }
    }

    # ---- find the Data root ------------------------------------------------
    # A resolved FOMOD is already a Data tree, so the search starts there and
    # stops immediately - there is no wrapper folder left to descend through.
    $src = if ($fomodRoot) { $fomodRoot } else { $ex }

    # A resolved FOMOD is authoritative: its top level IS the Data folder,
    # by construction from the destination paths the author declared. Running
    # the descent on it would wander into the first subfolder of a mod whose
    # whole payload is, say, SKSE\Plugins ini files - which is exactly the
    # shape the heuristic below cannot recognise.
    if (-not $fomodRoot) {
        for ($depth = 0; $depth -lt 6; $depth++) {
            if (Test-IsDataRoot $src $DataDirs $DataExt) { break }
            # a literal "Data" wrapper is the common case
            $dataChild = @(Get-ChildItem -LiteralPath $src -Directory -Force -ErrorAction SilentlyContinue |
                           Where-Object { $_.Name -match '^(?i)data$' })
            if ($dataChild.Count -eq 1) { $src = $dataChild[0].FullName; continue }
            $kids = @(Get-ChildItem -LiteralPath $src -Force -ErrorAction SilentlyContinue)
            $dirs = @($kids | Where-Object { $_.PSIsContainer })
            # descend only through a single wrapper folder with nothing else beside it
            if ($dirs.Count -eq 1 -and $kids.Count -le 3) { $src = $dirs[0].FullName; continue }
            break
        }
    }

    if (-not $fomodRoot -and -not (Test-IsDataRoot $src $DataDirs $DataExt)) {
        Write-Host "  could not find a Data root - no plugin, BSA or known Data folder anywhere." -ForegroundColor Red
        Write-Host  "  top level of the archive:"
        foreach ($c in @(Get-ChildItem -LiteralPath $ex -Force | Select-Object -First 12)) {
            Write-Host ("      {0}{1}" -f $c.Name, $(if ($c.PSIsContainer) { '\' } else { '' }))
        }
        $results.Add([pscustomobject]@{ Name = $mn; Status = 'no Data root' }); continue
    }

    $rel = if ($fomodRoot) { '<fomod build>' } else { $src.Substring($ex.Length).TrimStart('\') }
    $plugins = @(Get-ChildItem -LiteralPath $src -File -Force -ErrorAction SilentlyContinue |
                 Where-Object { $_.Extension.ToLower() -in @('.esp','.esm','.esl') })
    $nFiles = @(Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue).Count

    Write-Host ("  name      {0}" -f $mn)
    Write-Host ("  data root {0}" -f $(if ($rel) { $rel } else { '<archive root>' }))
    Write-Host ("  {0} file(s), {1} plugin(s)" -f $nFiles, $plugins.Count)
    foreach ($p in $plugins) { Write-Host ("      {0}" -f $p.Name) }
    if ($existing.ContainsKey($mn)) { Write-Host "  already in modlist.txt - will be replaced" -ForegroundColor Yellow }

    if ($Apply) {
        $dest = Join-Path $ModsDir $mn
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        # -LiteralPath takes the '*' literally, so copy the children explicitly
        foreach ($c in @(Get-ChildItem -LiteralPath $src -Force)) {
            Copy-Item -LiteralPath $c.FullName -Destination $dest -Recurse -Force
        }

        # meta.ini - what MO2 shows in the Nexus columns and uses for updates
        $modId = ''
        if ($a.BaseName -match '-(\d+)-[\d\-a-zA-Z]+-\d{6,}$') { $modId = $Matches[1] }
        [IO.File]::WriteAllLines((Join-Path $dest 'meta.ini'), @(
            '[General]',
            'gameName=skyrimspecialedition',
            "modid=$modId",
            'repository=Nexus',
            "installationFile=$($a.Name)"
        ), $Utf8NoBom)
    }

    $results.Add([pscustomobject]@{ Name = $mn; Status = 'ok'; Plugins = $plugins.Name })
}

# ---------------------------------------------------------------- profile ----
$ok = @($results | Where-Object { $_.Status -eq 'ok' })
if ($Apply -and $ok.Count) {
    Write-Host ""
    Write-Host "--- profile ---"
    Copy-Item -LiteralPath $mlPath -Destination "$mlPath.bak-$Stamp" -Force -ErrorAction SilentlyContinue

    # drop any existing lines for these mods, then re-add at the chosen end
    $names = @{}; foreach ($r in $ok) { $names[$r.Name] = $true }
    $kept = @($mlLines | Where-Object { -not ($_ -match '^[+\-](.+)$' -and $names.ContainsKey($Matches[1].TrimEnd())) })
    $new  = @($ok | ForEach-Object { "+$($_.Name)" })
    $out  = if ($Bottom) { $kept + $new } else {
        # keep the generated-by header line on top if there is one
        # 1..0 counts DOWN in PowerShell, so a one-line file would come back
        # reversed. Guard the tail explicitly.
        if ($kept.Count -gt 1 -and $kept[0] -match '^\s*#') { @($kept[0]) + $new + @($kept[1..($kept.Count - 1)]) }
        elseif ($kept.Count -eq 1 -and $kept[0] -match '^\s*#') { @($kept[0]) + $new }
        else { $new + $kept }
    }
    # A new mod goes on top, which silently pushes BodySlide Output down - and
    # the moment it sits below a mod it was built from, the game loads that
    # mod's UNBUILT meshes instead of the built ones. That cost two manual
    # fixes in one evening, so it is automatic now. -NoKeepTop opts out,
    # -KeepTop names a different mod.
    if (-not $NoKeepTop -and $KeepTop) {
        $hasKeep = @($out | Where-Object { $_ -match '^[+\-](.+)$' -and $Matches[1].TrimEnd() -eq $KeepTop })
        if ($hasKeep.Count) {
            $hdr  = @($out | Where-Object { $_ -match '^\s*#' })
            $keep = @($out | Where-Object { $_ -match '^[+\-](.+)$' -and $Matches[1].TrimEnd() -eq $KeepTop })
            $rest = @($out | Where-Object { $_ -notmatch '^\s*#' -and
                                            -not ($_ -match '^[+\-](.+)$' -and $Matches[1].TrimEnd() -eq $KeepTop) })
            $out = @($hdr + $keep + $rest)
            Write-Host ("  modlist.txt  '{0}' kept at highest priority" -f $KeepTop) -ForegroundColor DarkGray
        }
    }

    [IO.File]::WriteAllLines($mlPath, $out, $Utf8NoBom)
    Write-Host ("  modlist.txt  +{0} mod(s), {1} priority" -f $ok.Count, $(if ($Bottom) { 'lowest' } else { 'highest' }))

    if (-not $NoPlugins) {
        # Skyrim uses plugins.txt (active set, * prefix) and loadorder.txt (order).
        # They are a pair - writing one without the other leaves MO2 to reconcile
        # them, and it resolves that by dropping what it cannot match.
        foreach ($f in @('plugins.txt','loadorder.txt')) {
            $pp = Join-Path $ProfileD $f
            $cur = @(); if (Test-Path -LiteralPath $pp) { $cur = @(Get-Content -LiteralPath $pp) }
            $have = @{}; foreach ($l in $cur) { $have[($l.TrimStart('*')).Trim().ToLower()] = $true }
            $add = @()
            foreach ($r in $ok) { foreach ($p in @($r.Plugins)) {
                if ($p -and -not $have[$p.ToLower()]) { $add += $(if ($f -eq 'plugins.txt') { "*$p" } else { $p }) }
            } }
            if ($add.Count) {
                Copy-Item -LiteralPath $pp -Destination "$pp.bak-$Stamp" -Force -ErrorAction SilentlyContinue
                [IO.File]::WriteAllLines($pp, ($cur + $add), $Utf8NoBom)
                Write-Host ("  {0,-14} +{1} plugin(s)" -f $f, $add.Count)
            }
        }
    }
}

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue }

# ----------------------------------------------------------------- report ----
Write-Host ""
Write-Host "--- result ---"
foreach ($r in $results) {
    $col = switch ($r.Status) { 'ok' { 'Green' } 'FOMOD - skipped' { 'Yellow' } default { 'Red' } }
    Write-Host ("  {0,-14} {1}" -f $r.Status, $r.Name) -ForegroundColor $col
}
Write-Host ""
if (-not $Apply) { Write-Host "Nothing installed. Re-run with -Apply." -ForegroundColor Yellow }
else {
    Write-Host "Open MO2, hit Sort (LOOT), then launch SKSE." -ForegroundColor Green
    Write-Host "The mods are already ticked and their plugins already active."
}
Write-Host ""
