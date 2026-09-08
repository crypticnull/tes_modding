# Skyrim SE 1.6.1170 — DLSS 5 test bed, known-good configuration

Captured 2026-09-06, the first configuration where Community Shaders, DLSS
upscaling and DLSS 5 neural rendering all run together at 4K.

## The chain, in order

    Skyrim renders 2560x1440
      -> Community Shaders does its lighting work (D3D11)
      -> DLSS reconstructs to 3840x2160
      -> RenoDX injects NGX feature 18 (DLSSNR) immediately after the DLSS output
      -> UI composited downstream, untouched by the neural pass
      -> presented into a borderless window filling the 4K panel

Confirmed in the logs by:

    [bridge] feature ready: render 2560x1440 -> output 3840x2160
    inline feature 18 evaluation succeeded (NR input 3840x2160, guides 2560x1440, output 3840x2160)

## Settings that matter

### `STOCK GAME\dlss5-bridge.cfg`

| key | value | why |
|---|---|---|
| `skip_game` | `0` | **The one that actually matters.** The default `1` means *skip the game's own DLSS evaluate while the bridge is delivering*, so Community Shaders' DLSS never resolves the image - the bridge's private D3D12 mirror does, running on textures copied across two devices three or four frames behind. Its history never converges, and the result is a uniform shimmer that gets worse with distance, because sub-pixel detail is what fails to resolve. It is present with the bridge alone, with RenoDX removed and with NR intensity at zero, which is exactly what makes it look like a mod problem and cost an evening. `0` leaves the temporal resolve with the game. |
| `reset_every` | `0` | Leave it alone. It does **not** rebuild the contract periodically - it applies the NGX **Reset** flag, which wipes DLSS's accumulated temporal history. Upstream documents it as diagnostic only. Any non-zero value throws away the frames DLSS needs to converge, and looks like the image restarting before it can settle. |
| `source` | `auto` | The game's own DLSS wins, with the substitute as fallback. `synth` pins the substitute and is only for a game with no DLSS of its own. |
| `synth` / `synth_after` | `0` / `0` | Off. Only for a game with no DLSS at all; the substitute is built from ReShade depth plus optical flow and looks visibly worse. |

Upstream documentation for every key is at https://github.com/NIGos/dlss5-bridge - read it before changing one. Two of the values above were previously set from inference rather than from those docs, and both were wrong.

### `SKYRIM_SE\profiles\Default\SkyrimPrefs.ini`

    bBorderless=1
    bFull Screen=0
    iSize W=3840
    iSize H=2160

Borderless, not exclusive fullscreen. In exclusive fullscreen the game clamps
its display mode to the resolution Windows reports, which under 200% scaling is
1920x1080 — you get correct proportions at a quarter of the pixels.

### `mods\SSE Display Tweaks\SKSE\Plugins\SSEDisplayTweaks.ini`

    Resolution=3840x2160        # overrides whatever the game picks
    BorderlessUpscale=true      # window sized to the screen, render stays 4K
    DisableBufferResizing=true  # documented remedy for post-process breaking under upscaling
    LogLevel=debug              # logs window + swapchain geometry; drop to `message` when stable
    FramerateLimit=60           # capped 2026-09-07: CPU-bound at ~78 fps, averaging 77 C
                                # and 89 W. The frame rate IS the CPU work rate here.

`[HAVOK] Enabled=true`, `DynamicMaxTimeScaling=true`, `MaximumFramerate=240` —
leave it on even at a 60 cap. Required above 60 fps or physics runs fast (objects drift, carts and ladders
misbehave, ragdolls launch). Engine Fixes does **not** cover this.

### Windows

- Display at **120 Hz** (panel does 120, was sitting at 60 — the frame interval
  in the bridge log was pinned at 17.49 ms until this was changed).
- Desktop scaling stays at 200%. The game does not need it changed.

## Traps found, so they aren't rediscovered

| symptom | cause |
|---|---|
| Game image spills past the monitor edges | Borderless window built in 200%-scaled logical space and composited 2x. Not fixed by the `~ HIGHDPIAWARE` compat flag (already set on both exes), nor by an external manifest with `PreferExternalManifest=1`. Fixed by letting Display Tweaks own the geometry. |
| Correct proportions but soft / clearly not 4K | Exclusive fullscreen clamping to the DPI-virtualised 1920x1080. Check `Requesting mode:` in `SSEDisplayTweaks.log`. |
| Neural rendering visibly off, overlay says `NO NR FEATURE MATCHED (STANDBY/FAILED)` | Binding lost on a render-target rebuild and latched. `reset_every=0` is the cause. The in-game "Reset NR feature and clear failure latch" button does not recover it. |
| Neural rendering *silently* stops a second or two in | Same cause seen from the log instead. `ReShade.log` prints `inline feature 18 evaluation succeeded (count=1...)`, then `count=60`, then never again, while `dlss5-bridge.log` keeps counting thousands of delivered frames. Frames delivered is only the bridge mirroring; the `count=` line is the sole proof the neural pass is still running. Check `reset_every` in `dlss5-bridge.cfg` first. |
| No neural rendering at all, and no `NGX feature create intercepted: feature=1` line anywhere in `ReShade.log` | There is no DLSS contract to attach to. Either the save was never loaded (Community Shaders does not create its DLSS feature until the world finishes loading, roughly 30 s after attach - the main menu has no upscaling running and F6 has nothing to toggle), or Community Shaders shut itself off. See the next row. |
| Community Shaders pops `Incompatible DLL ... will disable all hooks and features` at startup | CS refuses to run alongside another mod that hooks the same rendering, and it disables **everything**, not just the conflicting part. No CS means no Upscaling, no DLSS, so the bridge never sees a contract and neural rendering is dead too. `Dynamic Wetness` (`DynamicWetness.dll`) is one of these - it predates CS and duplicates the built-in `Wetness Effects` feature. Remove it rather than trying to make it coexist. |
| `nvngx_dlss.dll` appears as an NGX layer then unloads ~200 ms later | Community Shaders' Upscaling feature loading and dropping the DLSS runtime before it engages. Resolves once upscaling is actually selected and the render resolution is settled. |
| Community Shaders refuses to load any features | Hard dependency on SSE Engine Fixes. The AIO archive is split: `data\` installs as a mod, `d3dx9_42.dll` must go into `STOCK GAME` beside `SkyrimSE.exe` — it is the proxy loader and `install_mod.ps1` will silently drop it. |
| Logs appear empty at `Documents\My Games\...` | Documents is redirected to OneDrive. Real path: `%USERPROFILE%\OneDrive\Documents\My Games\Skyrim Special Edition\SKSE\`. |
| Instant crash at the main menu, exception `0x80000003` (STATUS_BREAKPOINT, not an access violation), same address every time | Two SKSE plugins driving the camera on the same frames. SmoothCam yields the dialogue camera only to a plugin that registers through its messaging interface under the exact consumer name `Alternate Conversation Camera`; Improved Alternate Conversation Camera's own changelog says its SmoothCam support is disabled until fixed, so it never registers and the handoff never happens. Its `bSmoothCam = 1` ini switch does not change that. The fix reported by other users - **SmoothCam `dialogueMode` set to 0 (Disabled)** in `overwrite\SKSE\Plugins\SmoothCam.json` - was tested here and did **not** help: it still crashed instantly with SmoothCam fully out of the dialogue camera. So the two are incompatible on 1.6.1170 beyond what that switch controls. IACC is removed to `_retired\` permanently; SmoothCam is back on `dialogueMode` 1. Do not reinstall it. |
| SmoothCam's MCM offers `Oblivion` and `Face To Face` dialogue modes that do nothing | Those two modes are compiled out of every public build - `thirdperson_dialogue.cpp` registers them only under `#ifdef DEVELOPER`, which `CMakeLists.txt` never defines. The Papyrus side is not gated, so the MCM still lists them. Selecting either sets the active mode to null and silently disables SmoothCam's dialogue handling. Leave it on `Skyrim` or `Disabled`. |
| Papyrus cannot frame a camera at all | `Game.SetCameraTarget()` only changes which actor the third-person camera orbits - there is no script API to position, aim, or compose a shot. That is why every dialogue-camera mod for SE/AE ships an SKSE DLL, and why a DLL-free one does not exist. |

## Diagnosing, fastest first

    # is it 4K, and is the neural pass running
    Get-Content "X:\MODDING\SKYRIM\STOCK GAME\dlss5-bridge.log" |
        Select-String "back buffer|feature ready" | Select-Object -Last 4

    Get-Content "X:\MODDING\SKYRIM\STOCK GAME\ReShade.log" |
        Select-String "feature 18 evaluation succeeded" | Select-Object -Last 5

    # what geometry did Display Tweaks actually apply
    Select-String -Path "$env:USERPROFILE\OneDrive\Documents\My Games\Skyrim Special Edition\SKSE\SSEDisplayTweaks.log" `
        -Pattern "Requesting mode|Window created|Resolution override"

In game, ReShade overlay (**Home**) → DLSS 5 Neural Rendering panel. Its status
line is more authoritative than any log: it says whether NR is bound, and
`Successful NR frames` climbing is the proof it is live. **F6** toggles NR.

## Grass cache

Two mods, and they are not interchangeable:

- **Grass Cache Helper NG** (101095) is the runtime helper. It sets
  `bAllowCreateGrass` / `bAllowLoadGrass` / `bGenerateGrassDataFiles`, manages
  worldspace NoGrass flags, and makes the game *use* a cache. It does not
  generate one.
- **No Grass In Objects** (42161, file 797980 "NGIO - NG") is the generator.

Generation: `PrecacheGrass.txt` in `STOCK GAME\` (confirmed as the trigger
string inside `GrassCacheHelperNG.dll`), `Use-grass-cache = true` and
`DynDOLOD-Grass-Mode = 1` in `GrassControl.ini`, then launch. Output is `.cgid`
files in `overwrite\Grass\`. Afterwards: delete the trigger file, set
`Only-load-from-cache = true`, and package the cache as its own mod.

The helper's log distinguishes `Generating precache` from `Using precache`, and
says which it chose - that line is how you tell whether the trigger was seen.
Seeing `Generating precache` with no `.cgid` output means the helper is armed and
the generator is missing.

## Snapshot / restore

    tools\working_config.ps1 -Save -Label "cs + dlss5 + 4k"
    tools\working_config.ps1 -Check      # what drifted since the last snapshot
    tools\working_config.ps1 -List
    tools\working_config.ps1 -Restore    # newest real snapshot, never an undo copy

Eleven files across five programs, in `backups\known_good\<timestamp>`. Restore
writes the current state to a `-before-restore` folder first, and refuses to run
while MO2 or Skyrim is open, since both rewrite these files on exit.

Each entry carries a list of candidate paths, first existing wins. That matters
because MO2 redirects a write aimed at the game's Data folder into `overwrite\`,
so a file a program's own log says it wrote to `STOCK GAME\Data` is often not
there - Community Shaders' `SettingsUser.json` is exactly that case, and the
first version of this script recorded it as missing.


---

# 2026-09-06/07 — the full stack, working

Everything below is live and snapshotted (`working_config.ps1 -List` shows the
restore points).

    Skyrim renders 2560x1440
      -> Community Shaders lighting (Skylighting, Screen Space GI, Wetness
         Effects, Terrain Blending, Terrain Variation, plus the base features)
      -> DLSS reconstructs to 3840x2160
      -> RenoDX injects NGX feature 18 (DLSSNR) after the DLSS output
      -> presented into a borderless window filling the 4K panel

Plus: grass cache (~13k .cgid, no runtime grass generation), DynDOLOD object and
tree LOD with occlusion, 120 Hz, Havok clamped for high frame rates.

## Additional traps found

| symptom | cause |
|---|---|
| Any xEdit-family tool (xEdit, TexGen, DynDOLOD) operating on the wrong game | They resolve the game through `HKLM\SOFTWARE\WOW6432Node\Bethesda Softworks\Skyrim Special Edition` → `installed path`, which pointed at the Steam copy. Set to `X:\MODDING\SKYRIM\STOCK GAME\`. xEdit ALSO has its own Steam app-ID detection and ignored the registry — only an explicit `-D:` stopped it. |
| `-D:` argument silently ignored or mangled | It **must end in a trailing backslash**. The path contains a space so it must be quoted, and a lone backslash before the closing quote escapes the quote — so it is doubled: `"-D:X:\MODDING\SKYRIM\STOCK GAME\Data\\"`. |
| Arguments in MO2's `ModOrganizer.ini` not surviving | MO2 stores them escaped: every `\` doubled, every `"` written `\"`. The Explorer++ entry is a working reference sample. Both xEdit entries now carry the `-D:` permanently. |
| DynDOLOD: "Deleted large references found" | 7 plugins needed xEdit QuickAutoClean: Update, Dawnguard, HearthFires, ccvsvsse004-beafarmer, ccbgssse005-goldbrand, ccbgssse016-umbra, cctwbsse001-puzzledungeon. `tools\clean_masters.ps1 -Apply` does all of them unattended. The startup scan is global, so its list is complete — it does not find more later. |
| A mod created while MO2 is open comes back disabled | MO2 rewrites `modlist.txt` from memory on exit and registers unknown folders with `-`. Always close MO2 before scripts touch `modlist.txt`, `plugins.txt` or `ModOrganizer.ini`. |
| DynDOLOD warnings that look alarming but are not | 94 × "Reference attached to wrong cell" (Nature of the Wild Lands, Alpine Forest), 18 × "Duplicate reference ignored for LOD", 8 × "File not found Meshes\architecture\nise\…" (TAWoBA ships broken STAT records), 13 × "Property not found … in scripts" (vanilla Creation Club). None block generation. Only `<Error:` lines matter. |

## Order of operations for LOD

1. Grass cache (NGIO) — must exist before anything else references it
2. TexGen → install output as a mod, keep enabled forever
3. Clean masters (`clean_masters.ps1`)
4. DynDOLOD → install output as a mod, keep enabled forever
5. LOOT sort: DynDOLOD.esm with the masters, DynDOLOD.esp and Occlusion.esp last

## Open items

- `reset_every=600` in `dlss5-bridge.cfg` is what keeps the neural pass bound
  with CS running. If a periodic hitch is noticeable, raise it.
- The NR pass measured ~20% darker output than input (`brightness out/in 0.81`).
  Never A/B tested with F6. Could be the tone-map codec or a double sRGB.
- To undo from the failed DPI investigation: delete
  `STOCK GAME\SkyrimSE.exe.manifest` and set
  `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\SideBySide\PreferExternalManifest`
  back to 0. Neither is doing anything.
- `SSEDisplayTweaks.ini` still has `LogLevel=debug`; drop to `message`.
- Grass LOD was never generated — TexGen greys the Grass billboard option and the
  reason was not established. `DynDOLOD-Grass-Mode` is set to `0` so grass fades
  normally instead of cutting off. Cosmetic only.
- `cleanup.ps1` has never been run; `_retired\` and `_incoming\` are accumulating.

## Next, by payoff

1. **xLODGen terrain LOD.** DynDOLOD did objects and trees; terrain LOD meshes
   are still vanilla. Biggest remaining distant-view gain. Same offline-run
   shape as DynDOLOD, and the registry / `-D:` / cleaning problems that made
   tonight painful are now all solved.
2. **PBR texture packs.** True PBR is loaded and doing nothing, because nothing
   in the load order ships PBR texture sets. A pack activates a feature already
   running. See the picker for candidates.
3. **More CS features** — subsurface scattering for skin, hair specular, water.
4. **Frame generation**, only if GPU-limited. Currently off because its D3D11→
   D3D12 proxy collides with the bridge's own private D3D12 session.

## Queued, in order (as of 2026-09-07 ~00:30)

1. **Casting arm-drop fix** - `Auto Skeleton Patch - Universal Behaviour Runtime`
   (Nexus 176724). XPMSE ships a skeleton with animation-driven nodes the
   behaviour graph does not know about, and nothing here has ever run a
   behaviour patcher. The author lists the exact symptom: "hand not moving
   while casting in motion". SKSE plugin, needs only Address Library, no
   Pandora, no Nemesis. Confirm 1.6.1170 on its posts tab first - it is
   confirmed broken on 1.7.104. Do NOT also tick XPMSE in a behaviour
   patcher later; it is one or the other.
2. **MCM Helper** (53000) - missing, and `Better Third Person Selection`
   has been running without its MCM this whole time because of it.
3. **True Directional Movement 2.3.1** (51614) - walk toward the camera.
   Integrates with SmoothCam through a published API, unlike the camera mod
   that crashed. Turn headtracking OFF first thing: with no behaviour patch
   it sets IsNPC=true on the player, which breaks bow aim and blocking.
   Take 2.3.1, not 2.3.0 - 2.3.0 has a broken gamepad-detection check.
4. **Solar Lens Flare Redux** (84049) - sun flares. Vanilla-weather patch,
   no ENB needed. Edits weather records, so watch `SunDaytimeNorth_MM_default.esp`.
5. **Animation stack proper** - Open Animation Replacer 3.2.1 + Animation
   Queue Fix, A-Pose Bug Fix, Pandora Behaviour Engine Plus, then Goetia
   Animations (OAR-only, drop-in) and Assorted Behavior Fixes (needs a
   Pandora re-run). DAR is dead on 1.6.1170 - OAR reads DAR-format mods.
   Pandora goes outside the mods tree, added as an MO2 executable, output
   into an empty `PandoraOutput` mod at the bottom, and "Create files in
   mod instead of overwrite" stays OFF. Ignore the guide's instruction to
   purge meshes from Overwrite - that is for FNIS migrants.
6. **Wardrobe** - author sampler published as an artifact; he picks authors,
   then a full chooser. OBody NG (77016) needs `UIExtensions` (missing) and
   the 3BA/SMP collision fix (125724). OBody does NOT replace batch-building:
   build everything to the Zeroed Sliders preset with Build Morphs ticked.

Also still open: `DP_Extender.dll` (Better Crafted Potions) fails to load
every launch, built against an older SKSE ABI. And the save has orphaned
scripts from tonight's removals - worth a fresh character before sinking
real hours in.

## BodySlide: the 300-dialog problem

Batch Build raises one "Choose Output Set" dialog per group of slider sets
that write the SAME output mesh. `Remodeled Armor SE - CBBE 3BA` replaces
vanilla and DLC armours; CBBE ships plain-CBBE sets for those same meshes.
Result on this install: **308 collisions, 281 of them that one pairing.**

    tools\bodyslide_conflicts.ps1          read-only, counts and groups them
    tools\bodyslide_prune.ps1              dry run
    tools\bodyslide_prune.ps1 -Apply       removes the redundant CBBE sets
    tools\bodyslide_prune.ps1 -Restore     undo

Hiding CBBE's `.osp` files wholesale is wrong - `CBBE Vanilla.osp` also
covers vanilla CLOTHING that Remodeled Armor does not replace, and those
would be left unbuilt. The prune works at the SliderSet node level and only
removes a set when exactly one 3BA mod writes the identical output, so
nothing loses its only provider. 329 sets removed across 8 files, leaving
about 21 real dialogs.

Two traps in writing these scripts, both hit here:

- `[string]$ss.OutputFile` returns `System.Xml.XmlElement`, because the
  element carries attributes. Use `SelectSingleNode('OutputFile').InnerText`.
  The first run reported 106 collisions instead of 308 because every set in a
  folder looked like it wrote the same file.
- A bare comma inside a hashtable value is an element separator, so
  `Target = ... -replace '/', '\'` is a parse error. Build the string on its
  own line first.

Batch Build itself: preset `- Zeroed Sliders -`, tick **Build Morphs**, Batch
Build, leave everything checked. Afterwards move anything in Overwrite into
the `BodySlide Output` mod and keep that mod below CBBE and CBBE 3BA.

## TAWoBA: why it moved to Remastered

The original `The Amazing World of Bikini Armor - CBBE SE` (Nexus 9547) ships
**prebuilt meshes with no BodySlide slider sets at all** - no CalienteTools
folder. Confirmed by `bodyslide_coverage.ps1`: 1102 meshes, 1102 uncovered.
So it never morphs to an OBody preset. Each piece has a body baked inside it
at the author's shape, which is why the armour looks different from the body
underneath rather than the mod being "overwritten" by anything.

`ReSqueeze` (Nexus 131355) does target 9547 - it dropped the uncovered count
1102 -> 1029 - but covers only ~7%. The full CBBE conversion (Nexus 40015)
would cover the rest at the cost of CBBE rather than 3BA bone weighting,
which on bikini armour trades physics for shape matching. Not worth it.

**TAWOBA Remastered 6.1 (SunJeong) ships CBBE 3BAv2 BodySlide natively**, plus
SMP skirt cloth physics on the 3BAv2 bodies specifically. Free, no Patreon.
NOT on Nexus - the author forbids re-upload there, so `nexus_get` cannot fetch
it. Site: https://sunkeumjeong.wixsite.com/mysite (mods index at /mods).

    install_mod.ps1 -Archive "...\TAWOBA REMASTERED 6.1 CBBE SE.7z" -Apply

It is a different plugin from 9547, so it is a swap, not an addition - items
from the old mod vanish from any save. 9547 and ReSqueeze were retired to
`_retired\` on 2026-09-07. The author specifies a **two-stage build for 3BA**
and a slider group named `TAWOBA Remastered` - read her instructions before
batch building, the normal single pass is not what she describes.

## BodySlide: superseding the prune (2026-09-07)

`bodyslide_prune.ps1` is retired. Its model was a flat winner list and a flat
loser list, acting only when exactly one winner was in a collision - enough for
CBBE vs 3BA, useless once the wardrobe pass landed. Final state: 5691 slider
sets across 118 mods, **2218 removed, one dialog left**.

`bodyslide_pick.ps1` decides every collision with two ordered rule sets, both
editable at the top of the file.

**Rule 1 - mod priority, three tiers.** `$ModPriority` in order, then anything
unnamed, then `$ModLast` which loses to everything including unnamed mods.

    CBBE 3BA (3BBB)                     the body always wins its own meshes
    Random Tawoba Squeeze / TAWOBA Remastered
    Skimped - Vanilla                   VANILLA WARDROBE, SKIMPIEST FIRST
    Somewhere in Between
    SMR Vanilla Outfits 3BA
    CBBE 3BA Vanilla Outfits Redone
    Remodeled Armor SE - CBBE 3BA
    Common Clothes and Armors 3BA
    ... standalone sets ...
    $ModLast: Caliente's CBBE 2.0.3     loses everything, always

This list is not bookkeeping. **The winning slider set is what gets built to
the mesh path the game loads**, so this ordering is literally what the vanilla
armour looks like.

**Rule 2 - variant preference** inside one mod: ordered regex against the set
name, narrowing progressively rather than failing when a pattern matches
several. `Fallback = 'first'` marks mods whose leftover variants are cosmetic.
A group whose candidates all come from one mod skips rule 1 entirely.

Standing preferences encoded: `[3BA]` over plain CBBE, `3BBB` over CBBE on
TEWOBA, `SSE` over `HH`/`SHH` (no heel mod installed), flat and low boots over
heeled, `hdt` over `no physics`, `(Physics)` over `(Im Physics)` over `(No
Physics)`, `SMP` over static, non-`alt` over `alt`, non-`Realistic` over
`Realistic`.

### Four traps, all found the hard way

- **A repeated `Mod` key in `$VariantRules` silently overrides the earlier
  entry.** The run reports success while using rules you did not intend - half
  the boots kept the heeled variant and the other half kept flat. The script
  now throws on duplicate Mod keys in either table.
- **Unlisted mods must not rank below a named loser.** The first version gave
  unranked mods `[int]::MaxValue`, so plain CBBE 2.0.3 - named only to lose -
  beat 214 sets from three 3BA replacers that simply were not in the list. Hence
  the three-tier rank.
- **`\b` does not exist between a letter and a digit.** `\balt\b` misses `alt1`
  and `alt2`; `\bHH$` misses `SHH`. Three separate rules were wrong this way.
- **Two sets with the same name in the same file cannot be addressed
  individually** - removal matches by name, so dropping one drops both. The
  script detects that and leaves the whole group alone. That is the one
  remaining Barkeeper dialog; answer it with `Skimped - Vanilla - Barkeeper`.

Restore only considers backups matching `*.osp.bak-<8 digits>-<6 digits>`. The
original glob `*.osp.bak-*` also matched the `.bak-bom` file left by the XML
fix below, produced a destination equal to its source, and the terminating
Copy-Item error abandoned the rest of the restore silently - and restoring it
would have put the malformed XML back.

### Batch Build

Sort (LOOT) first. Launch BodySlide through MO2, preset `- Zeroed Sliders -`,
tick **Build Morphs**, Batch Build, leave everything checked. OBody applies the
shape at runtime, so the built mesh is the zeroed base plus morph data -
building to a preset here fights it. Afterwards move anything in Overwrite into
the `BodySlide Output` mod and keep that mod below CBBE and CBBE 3BA.

## FOMOD installs are scripted now (2026-09-07)

`install_mod.ps1` gained `-Fomod`, `-FomodDefaults` and `-FomodPlan`. It models
install steps, all five group types, file and folder destinations, priority
ordering, `conditionFlags` and `conditionalFileInstalls`. It does NOT model
`fileDependency`/`gameDependency` - those evaluate true rather than being
guessed, so a step gated on "is mod X installed" still shows.

    -Fomod "DLL=v1.6.1170; Light Set Texture=Dawn 3"

`;` between groups, `|` between options in one group - not `,` or `+`, because
option names contain both ("ESL + 3BA Bodyslide"). Names match exact, then
prefix, then substring; ambiguous or unknown is an error, never a guess. `*`
takes every option, `-` takes none.

`-FomodDefaults` takes the first option in any unnamed SelectExactlyOne or
SelectAtLeastOne group. **It is wrong for runtime-version groups** - the newest
DLL is usually listed first, so KID would get the 1.7.99 build on a 1.6.1170
install. Name those explicitly.

`install_fomod.ps1` retired to `_retired\` - it did the same job with
positional picks (`-Picks "1,2,0"`), which is order-dependent and unreadable at
forty groups. `fomod_export.ps1` stays; different job (a JSON catalogue of
every FOMOD's options and screenshots).

Trap, and an expensive one: the detection line was `$fomod = @(Get-ChildItem
...)`. PowerShell variable names are **case-insensitive**, so `$fomod` IS the
`-Fomod` parameter, and because that parameter is declared `[string]` the
DirectoryInfo array was coerced to a string. `$fomod.Count` returned 1,
`$fomod[0]` returned the first CHARACTER of the path, `.FullName` on a char is
null, and the error surfaced as "Cannot bind argument to parameter 'Path'" from
a `Split-Path` several lines away. Renamed to `$fomodDirs`. Any new parameter
must be checked against every assigned variable in the file, case-insensitively.

Also fixed: one `.osp` in Remodeled Armor (`CT77StalhrimHR.osp`) had a stray
space before its XML declaration, so BodySlide silently never built the four
Stalhrim gauntlet and bracer sets. `bodyslide_pick.ps1` now reports unparseable
`.osp` files instead of skipping them quietly.
