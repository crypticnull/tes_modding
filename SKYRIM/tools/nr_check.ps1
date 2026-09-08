#Requires -Version 5.1
<#
  nr_check.ps1 - is anything in the load order about to break DLSS 5 neural
  rendering? Run it before launching after ANY change to Community Shaders,
  the upscaler, or the SKSE plugin set.

      nr_check.ps1            check everything, print a verdict

  WHY THIS EXISTS

  Two separate incidents cost most of a day, and neither was where we looked:

    1. Dynamic Wetness shipped a DLL that Community Shaders hard-blocks. CS
       responded by disabling ALL of its hooks and features - not just the
       conflicting one. No CS means no Upscaling, no DLSS feature is ever
       created, and the bridge has no contract to attach the neural pass to.
       The symptom was "neural rendering is off", nowhere near the cause.

    2. dlss5-bridge.cfg had skip_game=1, which means "skip the game's own DLSS
       evaluate while the bridge is delivering". Community Shaders' DLSS was
       therefore never resolving the image - the bridge's private D3D12 mirror
       was, running on textures copied across two devices several frames
       behind. Its history never converged, giving a uniform shimmer that got
       worse with distance. Present even with the neural add-on removed, which
       is what made it look like a mod problem.

  THE ACTUAL RULE

  The neural pass rides on the game's own DLSS. Anything that stops CS from
  creating a DLSS feature, or that takes the resolve away from it, kills NR.
  Anything that merely changes how the scene is shaded - PBR, Skylighting,
  SSGI, terrain features - does not touch the upscaler contract and is not
  in this category, whatever it looks like on screen.

  Reads only. Nothing is modified.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM'
)

$ErrorActionPreference = 'Stop'

$Instance = Join-Path $Root 'SKYRIM_SE'
$Stock    = Join-Path $Root 'STOCK GAME'
$ModsDir  = Join-Path $Instance 'mods'
$MlPath   = Join-Path $Instance 'profiles\Default\modlist.txt'
$Cfg      = Join-Path $Stock 'dlss5-bridge.cfg'
$RsLog    = Join-Path $Stock 'ReShade.log'

# Community Shaders refuses to run alongside these and disables EVERYTHING
# when it sees one. Taken from its XSEPlugin.cpp block list.
$Blocked = @(
    'SkyrimUpscaler.dll',
    'TAASharpen.dll',
    'NVIDIA_Reflex.dll',
    'SSEReShadeHelper.dll',
    'EVLaS.dll',
    'AELAS.dll',
    'ShaderTools.dll',
    'MARA.dll',
    'DynamicWetness.dll'
)

$problems = New-Object System.Collections.Generic.List[string]
$notes    = New-Object System.Collections.Generic.List[string]

function Say([string]$text, [string]$colour = 'Gray') { Write-Host $text -ForegroundColor $colour }

Write-Host ""
Say "=== bridge config ===" 'Cyan'

if (-not (Test-Path -LiteralPath $Cfg)) {
    $problems.Add("dlss5-bridge.cfg not found at $Cfg")
} else {
    $want = [ordered]@{
        'skip_game'   = '0'
        'reset_every' = '0'
        'source'      = 'auto'
        'synth'       = '0'
    }
    $why = @{
        'skip_game'   = 'anything else hands the temporal resolve to the bridge mirror - distance shimmer'
        'reset_every' = 'non-zero applies the NGX Reset flag and wipes DLSS history'
        'source'      = 'mirror/synth pin a route instead of letting the game win'
        'synth'       = 'the substitute contract looks visibly worse than real DLSS'
    }
    $text = Get-Content -LiteralPath $Cfg -Raw
    foreach ($k in $want.Keys) {
        $m = [regex]::Match($text, ('(?m)^\s*' + [regex]::Escape($k) + '\s*=\s*(\S+)\s*$'))
        if (-not $m.Success) {
            $notes.Add("$k not set in dlss5-bridge.cfg - the add-on default applies")
            continue
        }
        $got = $m.Groups[1].Value
        if ($got -eq $want[$k]) {
            Say ("  {0,-12} = {1,-6} ok" -f $k, $got) 'Green'
        } else {
            Say ("  {0,-12} = {1,-6} EXPECTED {2}" -f $k, $got, $want[$k]) 'Red'
            $problems.Add("$k=$got - " + $why[$k])
        }
    }
}

Write-Host ""
Say "=== community shaders upscaling ===" 'Cyan'

# CS writes its live settings into overwrite, not into the mod folder.
$csCandidates = @(
    (Join-Path $Instance 'overwrite\SKSE\Plugins\CommunityShaders\SettingsUser.json'),
    (Join-Path $Stock 'Data\SKSE\Plugins\CommunityShaders\SettingsUser.json')
)
$csPath = @($csCandidates | Where-Object { Test-Path -LiteralPath $_ })[0]

if (-not $csPath) {
    $notes.Add('CommunityShaders SettingsUser.json not found - CS has not written settings yet')
} else {
    $cs = Get-Content -LiteralPath $csPath -Raw | ConvertFrom-Json
    $up = $cs.'Upscaling'
    if (-not $up) {
        $notes.Add('no Upscaling block in SettingsUser.json - the Upscaling feature may not be installed')
    } else {
        $method = $up.upscaleMethod
        $names  = @{ 0 = 'None'; 1 = 'TAA'; 2 = 'FSR'; 3 = 'DLSS' }
        $mName  = if ($names.ContainsKey([int]$method)) { $names[[int]$method] } else { "unknown($method)" }
        if ($mName -eq 'DLSS') {
            Say ("  upscaleMethod         = {0}   ok" -f $mName) 'Green'
        } else {
            Say ("  upscaleMethod         = {0}   EXPECTED DLSS" -f $mName) 'Red'
            $problems.Add("upscaleMethod is $mName - no DLSS feature is created, so there is nothing for the neural pass to attach to")
        }

        if ([int]$up.frameGenerationMode -eq 0) {
            Say  ("  frameGenerationMode   = 0    ok") 'Green'
        } else {
            Say  ("  frameGenerationMode   = {0}    check" -f $up.frameGenerationMode) 'Yellow'
            $notes.Add('frame generation is on - interpolated frames cannot receive the neural pass, which reads as strobing')
        }

        if (-not $up.sharpnessEnabledDLSS) {
            Say  ("  sharpnessEnabledDLSS  = False ok") 'Green'
        } else {
            Say  ("  sharpnessEnabledDLSS  = True  check") 'Yellow'
            $problems.Add('RCAS sharpening runs AFTER DLSS. Community Shaders removed it once over flicker complaints, and it amplifies exactly the residual noise the neural pass then sharpens again')
        }
        Say ("  qualityMode           = {0}" -f $up.qualityMode)
    }
}

Write-Host ""
Say "=== blocked SKSE plugins ===" 'Cyan'

$enabled = @(Get-Content -LiteralPath $MlPath |
             Where-Object { $_ -match '^\+(.+)$' } |
             ForEach-Object { $Matches[1].TrimEnd() })

$hits = 0
foreach ($mod in $enabled) {
    $pl = Join-Path (Join-Path $ModsDir $mod) 'SKSE\Plugins'
    if (-not (Test-Path -LiteralPath $pl)) { continue }
    foreach ($dll in @(Get-ChildItem -LiteralPath $pl -Filter *.dll -File -ErrorAction SilentlyContinue)) {
        if ($Blocked -contains $dll.Name) {
            Say ("  {0}  <-  {1}" -f $dll.Name, $mod) 'Red'
            $problems.Add("$($dll.Name) in '$mod' is on Community Shaders' block list. CS disables ALL hooks and features when it sees one, which takes DLSS and the neural pass down with it")
            $hits++
        }
    }
}
if (-not $hits) { Say "  none present  ok" 'Green' }

Write-Host ""
Say "=== reshade add-ons in STOCK GAME ===" 'Cyan'
$addons = @(Get-ChildItem -LiteralPath $Stock -Filter *.addon64 -File -ErrorAction SilentlyContinue)
if (-not $addons.Count) {
    $problems.Add('no .addon64 files in STOCK GAME - the bridge and the neural add-on are both missing')
    Say "  none - neural rendering cannot run" 'Red'
} else {
    foreach ($a in $addons) { Say ("  {0}" -f $a.Name) 'Green' }
    if (-not ($addons.Name -contains 'dlss5-bridge.addon64')) {
        $problems.Add('dlss5-bridge.addon64 is missing - Skyrim is D3D11 and the neural pass has nowhere to run without the bridge')
    }
    if (-not ($addons.Name -contains 'renodx-dlss5.addon64')) {
        $problems.Add('renodx-dlss5.addon64 is missing - nothing injects the neural feature')
    }
}

Write-Host ""
Say "=== last run ===" 'Cyan'
if (-not (Test-Path -LiteralPath $RsLog)) {
    $notes.Add('no ReShade.log yet')
} else {
    $log = Get-Content -LiteralPath $RsLog
    $created = @($log | Select-String -SimpleMatch 'feature 18 created')
    $counts  = @($log | Select-String -Pattern 'evaluation succeeded \(count=(\d+)' -AllMatches |
                 ForEach-Object { [int]$_.Matches[0].Groups[1].Value })
    if (-not $created.Count) {
        Say "  the neural feature was never created in the last run" 'Yellow'
        $notes.Add('no feature 18 creation in the last run - either the save was never loaded, or CS never created a DLSS feature')
    } else {
        $peak = if ($counts.Count) { ($counts | Measure-Object -Maximum).Maximum } else { 0 }
        Say ("  neural feature created, highest logged evaluation count {0}" -f $peak) 'Green'
        $notes.Add('the count= line is logged at milestones only - the add-on overlay shows the live number, and that is the one to trust')
    }
}

Write-Host ""
if ($problems.Count) {
    Say ("=== {0} problem(s) ===" -f $problems.Count) 'Red'
    foreach ($p in $problems) { Say ("  - {0}" -f $p) 'Red' }
} else {
    Say "=== nothing found that would break neural rendering ===" 'Green'
}
if ($notes.Count) {
    Write-Host ""
    Say "notes:" 'DarkGray'
    foreach ($n in $notes) { Say ("  - {0}" -f $n) 'DarkGray' }
}
Write-Host ""
