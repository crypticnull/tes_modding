#Requires -Version 5.1
<#
  run_build.ps1 - install the chosen build in one go.

    X:\MODDING\SKYRIM\tools\run_build.ps1            list what it will do
    X:\MODDING\SKYRIM\tools\run_build.ps1 -Apply     do it

  The CBBE + 3BA lane, picked from the chooser. Four SKSE dependencies go in
  first because FSMP is a DLL plugin and will not load without Address Library,
  and none of the MCMs exist without SkyUI.

  ORDER IS NOT ARBITRARY. install_mod.ps1 puts each new mod at the TOP of
  modlist.txt, which is highest priority, so the LAST thing installed wins file
  conflicts. That is why the body goes in before the skin textures: Reverie has
  to end up above CBBE for its textures to override the body's stock ones.
  Shuffle this list and you can silently get the wrong skin.

  It stops in the middle on purpose. MO2 has to see the new plugins once before
  their active flags will stick - a plugin MO2 is meeting for the first time is
  forced off no matter what plugins.txt says. That is the whole reason Alternate
  Start installed cleanly and then did nothing.

  NOT INCLUDED, because they need a human:
    WACCF (18994)  a FOMOD - install it through MO2's own installer
    KS Hairdos - HDT SMP (31300)  also a FOMOD. DECIDED: body 3BA, WIGS ON.
                   Wigs are equippable hair items, and they are the only route
                   to putting physics hair on NPCs later. Turning them on costs
                   nothing now and cannot be retrofitted without reinstalling.
    BodySlide      run it after LOOT and batch build, or 3BA has no physics
                   bone weights and every outfit keeps vanilla proportions

  A WARNING ABOUT HAIR. KS Hairdos SSE (6817) is the STATIC pack - 1058 styles
  and not one of them moves. The physics version is 31300, a separate standalone
  mod that does not need 6817 at all. Installing 6817 and expecting movement is
  the single most common mistake in this category.
#>

[CmdletBinding()]
param(
    [string]$Root = 'X:\MODDING\SKYRIM',
    [switch]$Apply,
    [switch]$SkipInstall     # jump straight to the activate + verify half
)

$ErrorActionPreference = 'Stop'
$Tools   = Join-Path $Root 'tools'
$ModsDir = Join-Path $Root 'SKYRIM_SE\mods'

# ordered: dependencies, body, tools, physics, skin, outfits, gameplay
$PLAN = @(
    @{ id = 32444; n = 'Address Library for SKSE Plugins'; why = 'FSMP will not load without it' }
    @{ id = 12604; n = 'SkyUI';                            why = 'no MCM exists without it' }
    @{ id = 13048; n = 'PapyrusUtil SE';                   why = "FSMP's MCM" }
    @{ id = 16495; n = 'JContainers SE';                   why = "FSMP's MCM" }
    @{ id =   198; n = 'CBBE';                             why = 'the body' }
    @{ id = 30174; n = 'CBBE 3BA';                         why = 'physics-ready variant' }
    @{ id = 56875; n = 'CBBE 3BA Settings Loader';         why = 'the 3BA MCM' }
    @{ id =   201; n = 'BodySlide and Outfit Studio';      why = 'builds meshes to your preset' }
    @{ id =  1988; n = 'XPMSSE skeleton';                  why = 'everything physical hangs off it' }
    @{ id = 57339; n = 'Faster HDT-SMP';                   why = 'cloth and body simulation' }
    @{ id = 64314; n = 'Reverie - Skin';                   why = 'after the body, so it wins the textures' }
    @{ id = 22168; n = 'Remodeled Armor SE - CBBE 3BA';    why = 'skimpy vanilla replacer' }
    @{ id =  9547; n = 'TAWoBA - CBBE SE';                 why = 'bikini armour' }
    @{ id =  3928; n = 'Sacrosanct';                       why = 'vampires' }
    @{ id = 16788; n = 'Immersive Weapons';                why = '230 new weapons' }
    @{ id =  3334; n = 'Unique Uniques SE';                why = 'remodels the named uniques' }
    @{ id =  1137; n = 'Ordinator';                        why = 'perks' }
    @{ id =  1090; n = 'Apocalypse';                       why = 'new spells' }
    @{ id = 46000; n = 'Odin';                             why = 'reworks vanilla spells' }
    @{ id = 39170; n = 'Triumvirate - Mage Archetypes';    why = 'druid, shadow mage, cleric' }
    @{ id =  6285; n = 'Summermyst';                       why = 'enchantments' }
    @{ id = 31245; n = 'Growl';                            why = 'werebeasts' }
    @{ id = 22506; n = 'Wintersun';                        why = 'religion' }
    @{ id = 93608; n = 'Modular SMP Hairstyles';           why = 'physics hair, built for FSMP, no FOMOD' }
)

$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN - pass -Apply to install' }
Write-Host ""
Write-Host "=== Skyrim build run ($mode) ===" -ForegroundColor Cyan
Write-Host ("  {0} mod(s), CBBE + 3BA lane" -f $PLAN.Count)
Write-Host ""

foreach ($t in @('install_mod.ps1','enable_plugins.ps1','check_masters.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Tools $t))) { throw "missing tool: $t" }
}
if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    throw "Mod Organizer is running. Close it - it rewrites modlist.txt on exit."
}

if (-not $Apply) {
    foreach ($p in $PLAN) { Write-Host ("  {0,6}  {1,-34} {2}" -f $p.id, $p.n, $p.why) }
    Write-Host ""
    Write-Host "Then: pause for MO2, enable_plugins, check_masters." -ForegroundColor Yellow
    Write-Host "Re-run with -Apply." -ForegroundColor Yellow
    Write-Host ""
    return
}

# ------------------------------------------------------------------ install --
$ok = @(); $bad = @()
if (-not $SkipInstall) {
    $i = 0
    foreach ($p in $PLAN) {
        $i++
        Write-Host ""
        Write-Host ("[{0}/{1}] {2}  ({3})" -f $i, $PLAN.Count, $p.n, $p.id) -ForegroundColor Cyan
        try {
            # one failure must not abandon the other twenty-one
            & (Join-Path $Tools 'install_mod.ps1') -Mod $p.id -Apply
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
            $ok += $p
        } catch {
            Write-Host ("  FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
            $bad += [pscustomobject]@{ id = $p.id; n = $p.n; err = $_.Exception.Message }
        }
    }

    # Do NOT trust the exit code. install_mod reports a FOMOD and returns
    # cleanly, so a skipped mod looks identical to an installed one from here.
    # Ask the filesystem what actually landed instead: every installed mod has
    # a meta.ini carrying its Nexus id.
    $landed = @{}
    foreach ($d in @(Get-ChildItem -LiteralPath $ModsDir -Directory -ErrorAction SilentlyContinue)) {
        $mi = Join-Path $d.FullName 'meta.ini'
        if (-not (Test-Path -LiteralPath $mi)) { continue }
        foreach ($l in (Get-Content -LiteralPath $mi)) {
            if ($l -match '^\s*modid\s*=\s*(\d+)') { $landed[[int]$Matches[1]] = $d.Name }
        }
    }
    $absent = @($PLAN | Where-Object { -not $landed.ContainsKey($_.id) })

    Write-Host ""
    Write-Host "--- install summary ---" -ForegroundColor Cyan
    Write-Host ("  on disk    {0} of {1}" -f ($PLAN.Count - $absent.Count), $PLAN.Count) -ForegroundColor Green
    if ($absent.Count) {
        Write-Host ""
        Write-Host ("  NOT INSTALLED - {0} mod(s), almost certainly FOMODs:" -f $absent.Count) -ForegroundColor Yellow
        foreach ($a in $absent) { Write-Host ("      {0,6}  {1}" -f $a.id, $a.n) -ForegroundColor Yellow }
        Write-Host ""
        Write-Host "  Their archives ARE downloaded. Install each through MO2's own"
        Write-Host "  installer, in the order listed above - priority is install order,"
        Write-Host "  and the skin has to go on after the body to win the textures."
    }
    if ($bad.Count) {
        Write-Host ("  failed     {0}" -f $bad.Count) -ForegroundColor Red
        foreach ($b in $bad) { Write-Host ("      {0,6}  {1,-34} {2}" -f $b.id, $b.n, $b.err) -ForegroundColor Red }
        Write-Host ""
        Write-Host "  A 403 here means Nexus adult content is still switched off on the" -ForegroundColor Yellow
        Write-Host "  account: nexusmods.com > Account > Site Preferences > Content Blocking." -ForegroundColor Yellow
        Write-Host "  A FOMOD is not a failure - it is reported and skipped by design."
    }
}

# -------------------------------------------------------------------- pause --
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Yellow
Write-Host " STOP HERE AND OPEN MO2, THEN CLOSE IT AGAIN." -ForegroundColor Yellow
Write-Host ""
Write-Host " MO2 forces any plugin it is seeing for the first time to OFF, whatever"
Write-Host " plugins.txt says. It has to meet them once before the active flags"
Write-Host " will stick. Nothing below works until it has."
Write-Host "=====================================================================" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter once MO2 has been opened and closed"

if (Get-Process -Name 'ModOrganizer' -ErrorAction SilentlyContinue) {
    Write-Host "MO2 is still running - close it, then re-run with -SkipInstall." -ForegroundColor Red
    return
}

# ---------------------------------------------------------- activate + check --
Write-Host ""
Write-Host "--- activating plugins ---" -ForegroundColor Cyan
& (Join-Path $Tools 'enable_plugins.ps1') -Apply

Write-Host ""
Write-Host "--- verifying ---" -ForegroundColor Cyan
& (Join-Path $Tools 'check_masters.ps1')

Write-Host ""
Write-Host "=== what is left, and none of it is optional ===" -ForegroundColor Green
Write-Host ""
Write-Host "  1. Open MO2 and Sort with LOOT."
Write-Host "  2. Re-run  X:\MODDING\SKYRIM\tools\check_masters.ps1  until it is clean."
Write-Host "     'loads out of order' means LOOT has not been run yet."
Write-Host "  3. Install these two through MO2's own installer - both are FOMODs:"
Write-Host "       WACCF (18994)"
Write-Host "       KS Hairdos - HDT SMP (31300)  -> body 3BA, WIGS ON"
Write-Host "  4. Run BodySlide from MO2's executable dropdown, pick a preset, tick"
Write-Host "     'Build Morphs', and Batch Build everything."
Write-Host ""
Write-Host "  Step 4 is the one people skip. Without it 3BA has no physics bone"
Write-Host "  weights, so nothing moves, and every outfit keeps vanilla proportions"
Write-Host "  regardless of the body you just installed."
Write-Host ""
