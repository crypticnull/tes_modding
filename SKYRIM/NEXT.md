> **RETIRED 2026-09-08. Superseded by `X:\MODDING\SKYRIM\CLAUDE.md`.**
>
> The work queue moved into section 10 of that file, which is now the single
> handoff document. Sections 1 and 3 of this file were completed on 09-08 and
> are struck below. Everything else was carried across, plus three items this
> file never had: the `clean_masters.ps1` Steam-install bug, the BOM at its
> line 143, and Immersive Fallen Trees 8767 in the seasons list.
>
> Kept for history. Do not work from it.

# NEXT.md - the work queue, in order

Handed over from the Cowork session on 2026-09-08. This is what that session
would have run next, written out so you can just execute it. Read `CLAUDE.md`
first - the hard constraints in section 2 are not optional, and section 6
explains most of the traps below before you hit them.

Close Mod Organizer before running anything that installs. `install_mod.ps1`
refuses while `ModOrganizer.exe` is running, which is correct, not a bug.

Every command uses complete absolute paths on purpose. Matt is often in a
fresh PowerShell window and a variable set in an earlier block will be empty.

Work top to bottom. Append an INBOX entry after each numbered section that
changes the load order.

---

## 1. ~~BLOCKING BUG - wrong-runtime SKSE plugins~~ DONE 2026-09-08 17:44 CODE

**Closed.** Bug Fixes SSE reinstalled as file 368384, Actor Limit Fix as file
368385, both the "(1.6.629.0 and later)" build. Both 1.7.99 folders disabled.
runtime_check.ps1 now reports 0 wrong-runtime, check_masters clean at 262
plugins, and SKSE boots to the game window with no AddressLibrary popup.
The sweep also turned up To Your Face AE (24720), which fails SKSE's own
version gate and has no 1170-compatible build - disabled, see INBOX.
Verified unattended with the new tools\launch_check.ps1. Original text below.

`ActorLimitFix.dll - AddressLibrary.cpp(102,34): Identifier not found, 523948`
pops on every SKSE launch. Actor Limit Fix (32349) and Bug Fixes SSE (33261)
are installed as their **1.7.99+** builds on a **1.6.1170** game. Both mods
ship four separate MAIN files, one per runtime, and Nexus flags the
newest-runtime build as primary - which is exactly what `install_mod.ps1 -Mod`
takes. Verified on both mod pages 2026-09-08: the correct file is
**"(1.6.629.0 and later)"**, because 1170 sits inside that range.

`check_masters.ps1` reports clean with this bug present. It is not a master
problem and nothing in the existing tooling catches it.

```powershell
# what file ids exist - confirm the 1.6.629 build before installing
& 'X:\MODDING\SKYRIM\tools\nexus_get.ps1' -Mod 33261
& 'X:\MODDING\SKYRIM\tools\nexus_get.ps1' -Mod 32349
```

Then, substituting the two file ids from that listing:

```powershell
& 'X:\MODDING\SKYRIM\tools\install_mod.ps1' -Mod 33261 -File <id> -Name 'Bug Fixes SSE' -Apply
& 'X:\MODDING\SKYRIM\tools\install_mod.ps1' -Mod 32349 -File <id> -Name 'Actor Limit Fix' -Apply
```

Then disable the two wrong folders. UTF-8 **without** BOM - `Set-Content
-Encoding UTF8` on PowerShell 5.1 writes a BOM and MO2 will not read the file:

```powershell
$ml   = 'X:\MODDING\SKYRIM\SKYRIM_SE\profiles\Default\modlist.txt'
$bad  = @('Bug Fixes SSE Anniversary (1.7.99.0 And Later)',
          'Actor Limit Fix Anniversary (1.7.99.0 And Later)')
$out  = foreach ($l in (Get-Content -LiteralPath $ml)) {
    if ($l.StartsWith('+') -and ($bad -contains $l.Substring(1).TrimEnd())) { '-' + $l.Substring(1) } else { $l }
}
[IO.File]::WriteAllLines($ml, $out, (New-Object Text.UTF8Encoding $false))
Select-String -Path $ml -Pattern 'Actor Limit|Bug Fixes' | ForEach-Object { $_.Line }
```

Then sweep for the same defect everywhere else. Anything this prints is
suspect and needs its own file listing checked:

```powershell
Select-String -Path 'X:\MODDING\SKYRIM\SKYRIM_SE\mods\*\meta.ini' -Pattern 'installationFile=.*1\.7\.' |
    ForEach-Object { $_.Path.Split('\')[-2] + '   ' + $_.Line }
```

Known-good and NOT to be touched by that sweep - 1170 is inside their ranges:
Scrambled Bugs (1.6.629.0 and later), Equip Enchantment Fix (1.6.629 and
newer), Immersive Equipment Displays (1.6.629 and newer), Simple Dual Sheath
(1.6.629 and newer), Address Library All in One (1.7.104.0) v13 - the AiO
carries every database and is correct.

Finish with `check_masters.ps1`, then relaunch through SKSE and confirm no
AddressLibrary popup.

**Worth building while you are here:** a `runtime_check.ps1` that walks every
`mods\*\meta.ini`, extracts the runtime range from the installation filename,
and flags anything that does not contain 1.6.1170. This class of bug is
invisible to every existing script and it will happen again.

---

## 2. FINISH THE PENDING INSTALL BLOCK

Blood, sound and the SPID dependency. EBT's two companion mods are already
installed as their **SPID** builds, which is why EBT itself must be the
SPID-compatible install and why PAPER comes with it.

```powershell
$log4 = 'X:\MODDING\SKYRIM\logs\block2d.txt'
if (Test-Path -LiteralPath $log4) { Remove-Item -LiteralPath $log4 -Force }

foreach ($job in @(
    @{ Id = 73849; F = "" },
    @{ Id = 2357;  F = "Main=Enhanced Blood Textures Main; SPID Compatibility=SPID Compatible; Compatibility Patch=-; Blood Size=Default Splatter; Wounds=EBT - Default; Drips=Default; Screen Blood=Default; Resolution and Color=High Res / Default Color; Alt. Blood=-" },
    @{ Id = 12466; F = "Main Files=Required Files; Mods=Enhanced Blood Textures|True Storms|Rumble Additions; Select One=Standard or SPID; Select Any=Crafting|Jumping|Swiming|Weapons; Thank You=Thank You" }
)) {
    try {
        if ($job.F) {
            & 'X:\MODDING\SKYRIM\tools\install_mod.ps1' -Mod $job.Id -Fomod $job.F -Apply *>&1 |
                Tee-Object -FilePath 'X:\MODDING\SKYRIM\logs\block2d.txt' -Append
        } else {
            & 'X:\MODDING\SKYRIM\tools\install_mod.ps1' -Mod $job.Id -Apply *>&1 |
                Tee-Object -FilePath 'X:\MODDING\SKYRIM\logs\block2d.txt' -Append
        }
    } catch {
        ("  FAILED " + $job.Id + " : " + $_.Exception.Message) |
            Tee-Object -FilePath 'X:\MODDING\SKYRIM\logs\block2d.txt' -Append
    }
}
& 'X:\MODDING\SKYRIM\tools\check_masters.ps1'
```

**PAPER (73849) is the open risk.** v2.2.4, last updated July 2023. Its page
states SE 1.5.97 and AE 1.6.353, with community reports of 1.6.6xx+ working.
It does not state 1.6.1170. It is Address Library based and the AiO covers
1170, so it should resolve, but verify rather than assume - this is the same
class of bug as section 1:

```powershell
$hits = @(Get-ChildItem -Path "$env:USERPROFILE\Documents\My Games" -Recurse -Filter 'skse64.log' -ErrorAction SilentlyContinue) +
        @(Get-ChildItem -Path 'X:\MODDING\SKYRIM\SKYRIM_SE\overwrite' -Recurse -Filter 'skse64.log' -ErrorAction SilentlyContinue)
if (-not $hits) { Write-Host "no skse64.log - SKSE has not run yet" -ForegroundColor Yellow }
foreach ($h in $hits) {
    Write-Host ("=== " + $h.FullName + "   " + $h.LastWriteTime) -ForegroundColor Cyan
    Select-String -Path $h.FullName -Pattern 'PAPER|paper|failed|error|could not' | ForEach-Object { $_.Line }
}
```

If PAPER does not load: both EBT companions have **non-SPID** main files
(mod 76767 "Optimised Scripts ... Non-SPID version", mod 56560 "Enhanced Blood
Textures SE - Settings Loader"), and EBT itself reinstalls with
`SPID Compatibility=Standard Install with Long Distance` instead. The Settings
Loader must load AFTER the optimised scripts or it loses the file conflict.

---

## 3. ~~VERIFY THE LOAD ORDER, ONCE~~ DONE 2026-09-08 18:05 CODE

**It was wrong, and "once" was the bug.** AI Overhaul.esp was at 251 of 262,
AFTER all four Bijin plugins - the reverse of what this section requires. Fixed
in loadorder.txt and plugins.txt: AI Overhaul is now 156, Bijin 159/160/162/181.
Book of Origins was already correct.

Made durable rather than hand-sorted. lockedorder.txt was empty, so nothing was
pinned and the next LOOT sort would simply have undone it - which is almost
certainly what happened the first time. tools\loot-userlist.yaml declares the
constraint to LOOT ("Bijin X after AI Overhaul.esp"; LOOT has no "before" key),
and tools\deploy_loot_rules.ps1 installs it to LOOT's data directory.
Re-check after ANY sort with tools\check_order.ps1, which exits 1 on violation.

Do NOT verify by running standalone LOOT.exe. LOOTDebugLog.txt shows it builds
its game handle against the Steam install, which CLAUDE.md section 2 puts off
limits and which is not this build. Sort from inside MO2, which runs the
bundled lootcli.exe under the VFS. Original text below.

Sort with LOOT in MO2, then confirm by eye in the plugin list:

- **`AI Overhaul.esp` must load BEFORE every Bijin plugin.** This is the one
  ordering LOOT can plausibly get wrong and it decides whether the Bijin faces
  survive. AI Overhaul is installed via the SPID + SkyPatcher route (136826 +
  138722), which is what makes a Bijin-specific patch unnecessary - the
  official patch hub explicitly does not support appearance patches.
- `AI Overhaul - Fishing Addon.esp` and `AI Overhaul - USSEP Patch.esp` after
  `AI Overhaul.esp`.
- `The Book of Origins - Alternate Start.esp` after `The Book of Origins.esp`.

`check_masters.ps1` flagged all three as out of order before the last sort.

---

## 4. VERIFICATION TASKS CARRIED OVER

None of these are installs. Each is a question that was raised and never
closed, and several gate larger decisions.

- **Seasons patches for six flora mods.** Seasons is CONFIRMED and cannot be
  added after the chain runs. Every tree and flora mod needs a seasons patch or
  it stays summer forever. Find patches for: S3DTrees NextGenerationForests,
  Nature of the Wild Lands, Blubbo aspens, Folkvangr, Alpine Forest of
  Whiterun Valley, Bent Pines. **If most of them lack one, raise it with Matt
  BEFORE the chain runs, not after** - it may change whether Seasons is worth
  the five terrain generations.
- **Overlays are not confirmed working in game.** `racemenu_overlays.ps1`
  raised the slot counts (Face 3->10, Body 6->15, Hands/Feet 3->5,
  `bPlayerOnly` 1->0) and verified by read-back, but the SKSE co-save showed
  every `OVST` slot empty. Check RaceMenu -> Face Paint in game.
- **Toys and Love (63512) vs OStim Standalone (98163)** - coexistence is
  UNVERIFIED. OStim is the decided spine; Toys&Love was only ever interesting
  for its bondage half. Verify before installing either together.
- **LOD Unloading Bug Fix (61251)** against the stranded Whiterun billboard.
- **Simply Knock (14098)** has no confirmed 1.6.1170 DLL. It was pulled from
  the reactivity block for that reason. Confirm or drop it.
- **`plugin_who.ps1` does not scan `STOCK GAME\Data`** (tooling item T-3), so
  any record whose only editor is a vanilla master reads as "does not exist".
  That produced a wrong answer once already, on vampire races.

---

## 5. HOUSEKEEPING

Cheap, and it keeps later diagnosis honest.

- **H-8** roughly 250 timestamped `.bak` files in
  `X:\MODDING\SKYRIM\SKYRIM_SE\profiles\Default`, written by these scripts on
  2026-09-06/07/08. Keep the newest two or three per file, drop the rest.
- **H-9** the disabled `Towels UBE` mod folder and the BnP **UNP** archive in
  `downloads\` - both are wrong-variant leftovers, both already replaced.
- **H-6** stale `meshes\armor\84_storm\head` in BodySlide Output.
- **H-4** `cleanup.ps1` was written and never run. Read it before running it.
- **H-3** SSE Display Tweaks still logging at debug level.
- **H-5** `DP_Extender.dll` fails to load every launch - diagnose or retire.
  Given section 1, check whether this is the same wrong-runtime class.
- **H-1** `SkyrimSE.exe.manifest`, dead file, verify then remove.
  **H-2 is verify-only** - the registry is off limits, see CLAUDE.md section 2.

---

## 6. DECISIONS THAT NEED MATT, NOT RESEARCH

Do not batch these. Each was deliberately held back.

- **The UI pick.** Untarnished (75188) / Norden (166086) / Oathvein (160916) /
  Vel'dun (176230). He was reviewing galleries and never chose. This gates the
  interface phase and interacts with U-2, the map.
- **A combat moveset overhaul** - MCO or BFCO - and whether to add a behaviour
  engine (Pandora Behaviour Engine Plus) to support it. This is the largest
  remaining free-lane block and it changes how the game feels more than
  anything else left. He asked for Precision and got it; movesets are the
  separate question.
- **Alternate Perspective (50307)** as a REPLACEMENT for Alternate Start -
  Live Another Life, which is installed. A swap, not an addition.
- **RASS (22780) vs the installed CS - Wetness Effects.** They partially
  overlap. A decision, not a stack.
- **True Storms is now your weather set by default.** It went in with no other
  weather mod present. If the graphics package later picks a weather
  aesthetic mod, they need a patch or one of them goes - the author is
  explicit that weather mods overwrite each other.

---

## 7. WHAT IS STILL FREE LANE, AND WHAT IS NOT

Re-read the LOD gate rule in CLAUDE.md section 4 before adding anything.
World references and static meshes gate behind the chain; item and actor mods
do not.

**Held back from earlier blocks on purpose, each for a stated reason:**
- Auto Parallax (79473) - belongs with the PBR package, not the framework layer
- Flat World Map Framework (29932) - decide together with U-2, the map
- Dynamic Key Action Framework (87706) - overlaps the installed Dynamic
  Activation Key
- Precision Locational Damage (78744) - **dead**, hidden by its author on
  22 Aug 2025 as obsolete. Successor 111351 needs *Wounds - Some Improvements*
  plus a separate integration addon and does nothing without both. Dropped.

**Pulled from the reactivity block because they are GATED, not free lane:**
- Missives (17576) - places mission boards in exterior cells
- Immersive World Encounters (18330) - places encounter markers
- Dynamic Things Alternative (60741) - unverified either way, check it

**Still untouched and all free lane:** the LoversLab pass (method is PLAN.md
section A-3 - Matt browses signed in, sends file page URLs, `ips_get.ps1`
fetches them with his exported session cookie; do NOT guess mod ids from
recall, that is exactly what produced the vectorplexis incident), the player
homes / quests / followers mining in F-6, and the magic VFX and skill-tree
hunts in V-4.

---

## 8. THEN, AND ONLY THEN, PART TWO

Everything above is Part One and none of it requires the generation chain.
Part Two is the graphics package plus the chain, and it runs ONCE:

BodySlide -> PGPatcher -> Grass cache -> xLODGen terrain (five times, for
Seasons) -> TexGen -> DynDOLOD -> Occlusion.

Do not start it until section 6 is answered and every gated mod from section 7
is installed. PGPatcher errors out if DynDOLOD output is active, and any
PGPatcher run forces TexGen and DynDOLOD to be redone. The full ordering and
its reasoning are in PLAN.md under BUILD ORDER.
