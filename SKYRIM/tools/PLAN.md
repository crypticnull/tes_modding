# Skyrim SE 1.6.1170 - running plan

The long-horizon list. Everything intended, everything deferred, everything
half-finished. Items keep their id when they move between sections, so
"P-2" means the same thing next week.

Companion files:
  WORKING_CONFIG.md   how the working stack is configured, and the traps
  DECISIONS.md        what was switched off or rejected, and why
  PLAN.md             this - what is still to do

---

## The premise

A Skyrim SE install used as a **DLSS 5 neural rendering test bed**, driven by
scripts rather than by clicking. Two consequences that shape everything below:

- Any change to Community Shaders, the upscaler, or the SKSE plugin set gets
  checked against the neural pipeline before launch. `nr_check.ps1` is that
  check, and it has caught a real regression once.
- Anything done more than twice becomes a script in `tools\`.

---

## PILLARS - what this modlist is for   (stated 2026-09-08)

Written down because this is heading for hundreds of mods, and every future
"should we take this" should be answerable from here rather than re-argued.
Deliberately FIVE, kept general. New wants get folded into an existing pillar,
not appended as a sixth - if something genuinely does not fit, that is the
signal to re-cut these, not to grow the list.

**1. NEXT-GEN VISUALS.** The reason the install exists. Anchored on DLSS 5
   neural rendering via dlss5-bridge - anything that fights it loses, always
   (see the CS hard-block list). But NOT only textures. Equal weight to the
   dynamic layer: lighting, weather, water, wetness, rain, puddles, magic
   effects. The test is "does it look next gen" - volumetric, physically
   behaving light, motion that sells the world as real. A static 4K rock is
   worth less than rain that behaves, or than light that falls off correctly.

**2. CHARACTERS.** Pretty, best in class. Skin, face, eyes, brows, overlays,
   body. Done as of 2026-09-08 apart from head topology, which was declined
   on quality grounds (S-6).

**3. WARDROBE AND GEAR.** Best in class variety in clothing and in weapons.
   Skimpiest wins where a choice exists. Adult content belongs here and is a
   first-class part of the pillar rather than a side effect - held to the same
   visual quality bar as everything else, so a badly made adult mod loses to a
   good vanilla one. NOTE: Gate To Sovngarde is NOT a source for this - its 7
   adult-flagged mods are all gore. That ecosystem is LoversLab, reachable
   with ips_get.ps1, and mining it is its own pass.

**4. IMMERSION AND ROLEPLAY.** A world that behaves like a place and changes
   over time - seasons, NPCs reacting to what you do, encounters. A character
   with a past. Quests that do not start themselves and membership that is
   earned. Content variety lives here too: quests, followers, player homes.
   THE TIEBREAKER: fun, explicitly NOT difficult. This is what kills most
   "hardcore" mods. Combat should feel better, not punish more. Survival
   mechanics earn their place by being interesting, never by adding chores.

**5. SYSTEMS, PROGRESSION AND ACCESS.** Magic already deep - Apocalypse, Odin,
   Triumvirate, Summermyst - and vampirism on Sacrosanct. The want is MORE to
   work on: skill trees for vampirism and for magic schools like pyromancy and
   cryomancy. Custom Skills Framework (41780) is the enabler; the trees are
   off-collection. Combat feel sits here, judged by pillar 4's tiebreaker. And
   ALL of it has to be reachable on a CONTROLLER without fighting the UI - a
   system that can only be driven from a keyboard menu is a worse pick than a
   slightly weaker one that cannot.

**AXES TO JUDGE A CANDIDATE ON**

  does it serve a pillar          if not, it does not go in, however popular
  does it fight DLSS 5 or CS      hard no
  is it still maintained          a stale base other people are still patching
                                  is a defect - see S-6 (High Poly Head) and
                                  V-3 (ELFX). Endorsements measure history,
                                  not health.
  does it edit NPC records        weigh against Bijin, Seranaholic, Nordic Faces
  does it add a plugin            then it is gated behind the DynDOLOD run
  does it need a framework        check F-1 first
  is there an installed rival     one overhaul per domain, always. See R-5.

## DECIDED 2026-09-08 - answered directly, do not re-litigate

  SEASONS            YES. Cost accepted knowingly. Stage 4 is now priced in
                     HOURS. Six tree/flora mods need seasons patches - open.
  ADULT SPINE        OStim Standalone (98163). NOT SexLab, NOT Toys&Love.
                     Kills Conditional Expressions (45148) and FK's Diverse
                     Racial Skeletons (38563) from Y-2.
  RACES/STONES/SHOUTS  The GTS picks: Aetherius (26686), Mundus (33411),
                     Stormcrown (90659). Imperious, Andromeda and Thunderchild
                     are out.
  LIGHTING           Lux + Lux CS + Lux Orbis, not ELFX. See V-3.
  HIGH POLY HEAD     Declined. See S-6.
  UI                 STILL OPEN - reviewing galleries.

## BUILD ORDER - how every constraint resolves into one sequence

The rule underneath all of it: ANYTHING THAT CHANGES A PLUGIN OR A WORLD STATIC
MESH MUST BE IN PLACE BEFORE THE GENERATION CHAIN RUNS, because both invalidate
LOD. Anything that touches neither is unconstrained.

**FREE LANE - no dependencies, any time, in parallel with everything.**
  U-1 UI overhaul, the character pass (done), wardrobe and adult content,
  housekeeping, tooling, and the off-collection hunts (magic VFX, skill trees,
  LoversLab). None of it is a plugin or a world static. Actors are not in LOD
  and neither is anything worn on one - which is why pillar 3 can grow forever
  without ever touching the chain.

**BLOCK 1 - framework layer (F-1).**
  Why first: block 2 declares it as a hard requirement, and Skyrim silently
  deactivates any plugin whose masters it cannot resolve. Install the plumbing
  after the gameplay mods and that failure gets chased repeatedly instead of
  avoided once.

**BLOCK 2 - gameplay, roleplay, systems.**
  R-2, R-3, R-4, F-2, F-3, F-4, M-1. Depends on block 1. Every item adds a
  plugin, so all of it lands inside the pre-generation window.
  Two need care: AI Overhaul (21654) edits NPC records and collides with Bijin,
  Seranaholic and the facegen layering - its own decision, not part of a batch.
  Alternate Perspective REPLACES Alternate Start rather than adding to it.

**BLOCK 3 - world, meshes and the visual layer.**
  P-1..P-5, C-1, C-2, V-2, V-3, W-1..W-3, U-2, R-1. Static mesh changes
  invalidate LOD exactly like plugins. Two items must be PRESENT AT GENERATION
  TIME rather than merely installed: Seasons needs terrain LOD built per
  season, and A Clear Map ships DynDOLOD rules that only apply if it is there
  when the chain runs.
  REMOVALS HAPPEN FIRST, INSIDE THIS BLOCK: Simplicity of Snow, and possibly
  MajesticMountains_Moss.esp. Double-pass snow and moss shaders do not work
  with PBR textures.

**BLOCK 4 - the generation chain. Order is not negotiable.**

    BodySlide -> PGPatcher -> Grass cache -> xLODGen terrain -> TexGen
      -> DynDOLOD -> Occlusion

  PGPatcher refuses to run while DynDOLOD output is active, and any PGPatcher
  run forces TexGen and DynDOLOD to be redone. Grass cache only needs redoing
  if plugins changed; it survives texture-only changes.
  THE SEASONS MULTIPLIER: four seasons plus the default means terrain LOD
  generated FIVE times, spawning concurrent LODGen processes each wanting
  several GB of RAM. A ninety-minute unattended job becomes most of an evening
  and a much larger output, on top of the 30 GB already needed free on X:.

**BLOCK 5 - verify, then play.**
  A step, not an afterthought: three separate failures this month looked like
  successful installs - a plugin with an unresolved master, a mod id pointing
  at the wrong mod, and a wrong-body skin, all reporting ok.
  check_masters.ps1, nr_check.ps1, bodyslide_coverage.ps1, confirm overlays in
  RaceMenu -> Face Paint, confirm the stranded Whiterun billboard is gone, then
  H-7 fresh character.

**THE MISTAKE THIS ORDERING EXISTS TO PREVENT:** installing anything from block
2 or 3 AFTER the chain has run. It costs the entire generation again, and with
seasons that is not ninety minutes. The tree LOD is already stale for exactly
this reason.

## NOW - characters

Deliberately descoped from the graphics package below. None of this touches
LOD, so it is independent of the whole PGPatcher/TexGen/DynDOLOD chain and can
be iterated on freely.

**S-0  DONE 2026-09-08.** Nordic Faces (40658) installed `-Bottom`, FaceGen +
       FaceTint. Verified: 92 of 6237 files shadowed, all of them Bijin or
       Seranaholic reclaiming their own NPCs. Exactly the intended layering.
**S-1  DONE 2026-09-08.** BnP - Female Skin, **CBBE file 405623**. The primary
       MAIN file is the UNP build and `-Main` picked it first; caught and
       replaced. Always check the body in the filename.
**S-2/S-3  DONE 2026-09-08.** SkFO (20183), Community Overlays 1 (22487) and 2
       (26224), Warrior's Paints Vol 3 (80438), RX'Overlays (166670).
**S-4  DONE 2026-09-08.** `racemenu_overlays.ps1`. Face 3->10, Body 6->15,
       Hands 3->5, Feet 3->5, `bPlayerOnly` 1->0. NOT YET VERIFIED IN GAME -
       the co-save read on 09-08 showed every overlay slot still empty.
**S-5  DONE 2026-09-08.** ODF (155120). Ships configs for community-overlays-1,
       community-overlays-2 and skin-feature-overlays; Warrior's Paints and
       RX'Overlays have none and stay player-only.
**S-8  DONE 2026-09-08.** Freckles. See S-8 below.
**S-6  High Poly Head** - the only character item left. See S-6.

**B-1  Panties of Skyrim black face**
`pantiesofskyrim.esp` at load order 124 wins Ysolda's NPC record over Bijin
Wives (73) and Bijin - UCMT (94), assigning a panty outfit. It ships no
FaceGen, so geometry and tint desync - the black face. Affects every NPC it
force-dresses that an appearance mod also covers, so roughly the 24 Bijin NPCs.

    install_mod.ps1 -Mod 47574 -Apply -Fomod "Slots=Slot52; NPC=Without NPC; ESL=ESL Flag"

Alternative: move the plugin above the Bijin ones, which keeps panties on
non-Bijin NPCs, but LOOT re-sorts it away unless a rule is added.

---

## PACKAGE - graphics, to run in ONE sitting

Everything from here to the end of the city-meshes section is one job, not
several. Roughly 16 GB of downloads and about ninety minutes of generation,
most of it unattended. The reason to keep it together is P-6: the chain has to
run once, after every mesh and plugin change is in, or it runs twice.

Parked deliberately until the character work is settled.

### PBR and landscape

**P-1  Landscape pack decision**
Vanaheimr 6.0 PBR at 2K is the recommendation: zero hard requirements, roads
included, Majestic-Mountains-aware variant, a triaged bug tracker. Vyrthland
(190416) is probably better looking and is rejected only for now - see
DECISIONS.md. Revisit ~Oct 2026.

**P-2  Remove Simplicity of Snow**  *(blocks P-6)*
Double-pass snow shaders do not work with PBR textures.

**P-3  Install Better Dynamic Snow 3**  *(replaces P-2, prereq for most packs)*

**P-4  Remove MajesticMountains_Moss.esp** - only if a Majestic Mountains PBR
conversion is used. Same double-pass problem as the snow.

**P-5  PBR ground materials** - decide alongside P-1 rather than after.

**P-6  Run the chain, in this exact order**

    BodySlide  ->  PGPatcher  ->  TexGen  ->  DynDOLOD

PGPatcher errors out if DynDOLOD output is active, and every PGPatcher run
forces TexGen and DynDOLOD to be regenerated. `--autostart` makes PGPatcher
headless after one GUI configuration; TexGen and DynDOLOD cannot be automated -
xEdit does not expose their GUI settings to the command line. Grass cache
survives texture-only changes.

**P-8  Use ULTRA tree LOD when regenerating** - 3D tree LOD in object LOD
instead of billboards. sheson names this as the permanent fix for billboards
failing to unload in active cells, because it sidesteps the engine limitation
rather than working around it. Decide this before the P-6 run, not after.

**P-9  Tree LOD is currently STALE.** DynDOLOD output was generated
2026-09-07 00:01 UTC; roughly 45 plugins went in from 22:27 that evening
onward, and LOOT re-sorted. Symptom already seen in game: a flat, low-res
billboard sitting in a loaded cell with no collision, near a Nordic ruin west
of Whiterun. sheson's diagnosis of exactly this is *"the load order of plugins
that add new tree references is not the same as it was when tree LOD was
generated"* - the engine matches LOD to references by form id, the ids moved,
so the billboard never unloads. Expect more of them.

Regeneration is already required by P-6, so **do not regenerate twice** - fold
it into the PBR phase unless the artefacts become intolerable first.

**P-7  Shattered Royal Armor** - installed with the Vanilla Skyrim option. Its
PBR variant is a one-mod reinstall once the PBR phase lands.

---


### Water

Currently **nothing** - vanilla water with only Skyland's colour tweak on top.
This belongs in the package rather than the character pass, because water
meshes and records feed water LOD, and DynDOLOD generates that.

**W-1  Water Effects - Community Shaders (112762)** - by doodlum, the
Community Shaders author. Adds **caustics** - the light patterns on the bottom,
scaling and fading with depth - and a **water-specific parallax**. 7,003
endorsements. Requires only Community Shaders, which is already there. The
caustics half works on its own; the parallax half needs a water mod supplying
**displacement maps**, which is what W-2 is for. This one is close to free and
should go in regardless.

**W-2  A displacement-map water mod**, one of:

  *Simplicity of Sea (56520)* - explicitly ships ENB **and Community Shaders**
  displacement textures, so it is the pairing W-1's parallax is written for.

  *Water for ENB (37061)* - the other displacement source W-1 names. ENB in the
  title but it is the textures that matter, and CS's own page points at it.

  *Realistic Water Two (2182)* - the long-standing classic and by far the most
  mature. Changes meshes and records rather than shader inputs; whether it
  supplies displacement maps for W-1's parallax is unconfirmed.

**W-3  A Water Made For CS in mind (172959)** - the interesting one and the
riskiest. PBR water built specifically for Community Shaders: reworked water
types, reflection tuning, Fresnel balancing, new sounds with an MCM. It
**requires PGPatcher** and recommends PBR landscape and dungeon textures -
which is exactly what the rest of this package installs, so the dependencies
line up for free. Updated Aug 2026. But **100 endorsements** against W-1's
7,003, so it is unproven at this load order's scale. Must load last in the
plugin order, before DynDOLOD.

Sequencing: W-1 any time. W-2 and W-3 before the P-6 regeneration.

### Community Shaders audit

**G-1  Enumerate what CS 1.8.4 offers against what is installed.**
Every candidate gets checked against the DLSS 5 pipeline before it goes in -
that is a standing requirement, not a formality.

Installed as separate feature mods: Skylighting, Screen Space GI, Terrain
Blending, Terrain Variation, Wetness Effects, Subsurface Scattering, Hair
Specular, Upscaling. Core in 1.8.4: True PBR, Dynamic Cubemaps, Light Limit
Fix, Extended Materials.

Not present, worth evaluating: Cloud Shadows (139185), Screen Space Shadows
(93209), sun rays and volumetric sky, grass collision, particle lights, and the
screen-effect group (depth of field, bloom, HDR, eye adaptation). Water caustics
and parallax are resolved - see W-1.

The rule for judging them: **anything that stops CS creating a DLSS feature, or
takes the resolve away from it, kills neural rendering. Anything that only
changes how the scene is shaded does not.** Shading features are safe; anything
touching the upscaler contract is not.

**G-2  Solar Lens Flare Redux (84049)** - needs two files by id. Raised days
ago and dropped off; this is the note that stops that happening again.

**G-3  Cubemap Patches never installed.** The 109194 FOMOD's `Cubemap Patches`
group sits behind a step-visibility condition the resolver did not satisfy, so
seven cubemap patches were skipped. Worth having - Dynamic Cubemaps is core.

**G-4  Frame generation stays off.** Interpolated frames cannot receive the
neural pass and it reads as strobing. `nr_check.ps1` warns if it changes.

---

## PHASE - movement and animation

**M-1  True Directional Movement 2.3.1 (51614) + MCM Helper (53000)**
       *(MCM Helper is also in F-1, the framework layer. Install it there.
       Confirmed 2026-09-08: TDM and SmoothCam are NOT a conflict - TDM ships
       SmoothCam integration.)*
Install MCM Helper first. Turn headtracking off before first launch.

**M-2  Animation stack phase two** - OAR, Pandora, Goetia, Assorted Behavior
Fixes. Deprioritised, not rejected: the actual complaint (casting arm dropping
while moving) was XPMSE with no skeleton behaviour patch and is fixed. The rest
buys procedural leaning, 360 mounted archery and better casting animations.

---

## Body and wardrobe - residual

The wardrobe pass is done: 4028 slider sets, 385 removed by rule, zero dialogs,
BD's Replacer winning the vanilla wardrobe. What is left is small.

**B-2  Fashions Of The Banditry - 26 uncovered.** Its own 3BA download covers
only 23 of the 49; no conversion exists for the rest. Outfit Studio or nothing.

**B-3  Residual coverage** - TAWOBA Remastered 59 (author's spare bikini and
tasset variants plus `femalebody`, `testy`, `unused1`), BD's Standalone 41
(Daedric and Dwarven race variants), BD's AIO 39 (not yet examined).

**B-4  Teach the coverage classifier BD's AIO's shapes** - the 39 above are
probably ground models and first-person meshes it has not learned yet, which is
what every other mod's first pass turned out to be.

**B-5  TAWoBA strap fit** - the ORefit blacklist test was queued before the
squeeze bodyslides won the ranking. Probably moot now; look before acting.


---

### City and world meshes

**Must land BEFORE the P-6 regeneration.** These add or replace static meshes,
and every static mesh change invalidates LOD the same way a plugin change does.
Installed after the chain runs, they buy another hour of TexGen and DynDOLOD.

**C-1  Major Cities Mesh Overhaul (49259)** - the broad answer to "is there a
version of this for the other cities". Covers Whiterun, Riften, Solitude,
Windhelm, farmhouses and Skaal Village: UV errors, clipping, vertex problems,
some textures. Explicitly recommended alongside SMIM rather than against it.

**C-2  Whiterun 3D stone walls (139069)** - real geometry for the wall panels
instead of flat normal-mapped faces. This is the mod Vanilla PBR AIO ships an
optional patch for (file 750564), so taking one means taking the other.
**Must overwrite C-1**: it forwards changes from Major Cities Mesh Overhaul and
Skyrim Objects SMIMed, and its author says to let it win over both. Uses
USSEP meshes as its base. Adds ~300k triangles.

**C-3  DROPPED.** Whiterun City Walls - Collision Redone (163348) is built for
the VANILLA wall meshes, documents nothing about 3D wall replacements, and warns
it "will allow you to jump over Whiterun's walls in certain places". Vanilla
collision over 3D geometry is untested at best. Revisit only if collision
actually feels wrong after C-2.

Alternatives seen and not chosen: Whiterun Has Walls (101603) and Whiterun Has
Walls Redone (119229) add walls where vanilla has none, which is a different
goal from replacing the existing ones with 3D versions.

---

## PHASE - skin, face and overlays   (S-1..S-5 SHIPPED 2026-09-08)

**S-1 through S-5 are DONE.** See the NOW section at the top for what actually
installed and which file ids were used. What follows is the research that led
to those picks, kept only so the reasoning survives - it is NOT a to-do list.
Live items in here are S-6 (declined), S-7 (open) and S-8 (solved).

**Independent of the LOD chain.** Actors are not in LOD, so none of this needs
a regeneration and it can be done whenever. That is the reason to separate it
from C-* above rather than lumping it in.

State BEFORE 2026-09-08, for context: CBBE base textures, Bijin NPCs / Wives /
Warmaidens with `Bijin - Use CBBE Meshes and Textures`, Seranaholic, RaceMenu,
KS Hairdos. No dedicated skin replacer, no high poly head, no overlays at all.

**S-1  Female skin replacer.** The current field, most-recommended first:
BnP - Female Skin (65274), Diamond Skin (45718), Noble Elegance CBBE 3BA
(106378), The Pure (20583), Simply Skin (98131). All are CBBE/3BA-compatible
diffuse/normal/specular sets. Pick one - they are mutually exclusive.

**S-2  Skin Feature Overlays SE (20183)** - freckles, scars, birthmarks, stretch
marks, moles, for face and body. This is the specific answer to the freckles
question and it is the standard for that job.

**S-3  Tattoos and body paint.** Community Overlays 1 (22487) and 2 (26224) are
the community sets; Warrior's Paints Vol. 3 (80438) continues them. RX'Overlays
(166670) is 3BA-specific. Overlay Collection (120581) aggregates.

**S-4  Overlay slots have to be raised.** RaceMenu allocates a fixed number of
overlay slots in its ini. Installing overlay packs without raising the counts
means most of them silently never appear. Do this before judging S-2 or S-3.

**S-5  NPC overlay distribution** - Overlay Distribution Framework (155120) or
Distributed Bodypaints and Overlays (55386), if the freckles and tattoos should
appear on NPCs and not only the player.

**S-6  DECIDED 2026-09-08: SKIPPING High Poly Head. Do not re-open without
a new reason.**

Why, in one line: a third party is still actively patching HPH's UVs four years
after the base mod last shipped - High Poly Head UV Stretch Fix (NECK SEAM
FIXED), 141690, updated July 2026, 581 endorsements. HPH's UVs do not match
vanilla, so textures stretch over the head and a seam opens at the neck, worst
at low weight. BnP's face textures are authored against vanilla UVs, so that
distortion lands on exactly the work finished this session.

Full working stack would have been: HPH 1.4 (off-Nexus, Google Drive link
inside another mod's requirements) + Expressive Facegen Morphs + the UV/neck
seam fix + possibly Alternate HPH (which alters the mesh AGAIN: removed
vertices, fixed split edges, fixed broken morphs) + the vampire headpart fix +
re-running Improved Eye Model for its HPH patches. Six mods on an unmaintained
base, for a smoother jaw and nose silhouette at close range.

There is no good substitute and none was invented. The vanilla head is what it
is; remaining close-up wins are the skin, eye mesh and brows (all done) and the
lighting/PBR work in the graphics package.

The reference material below is kept only so this is not researched a third
time.

**S-6 background, investigated 2026-09-08. An earlier warning here was WRONG.**

High Poly Head does NOT replace NPC head meshes. It adds an alternate Face Part
in RaceMenu's Head tab, selectable per character. Installing it cannot cause
mass black faces, because it edits nothing. The claim that it would was a bad
inference from the Panties incident and is retracted.

What the options actually are:

  **Nordic Faces (40658) - the recommendation.** Lore-friendly FaceGen and
  textures for the player and ALL vanilla NPCs, and it is **plugin-less** -
  meshes, textures and FaceGen only, no ESP or ESM. That is the whole reason
  to prefer it: with no plugin there is no NPC record to lose, so the black
  face failure mode does not exist. The author documents the intended layering
  as Nordic Faces first, then Pandorable's, Bijin and similar on top,
  overwriting it. That is exactly this load order already.

  **Install it at LOW priority.** It also ships hands, feet and body models,
  which must not beat CBBE 3BA, and its FaceGen must lose to Bijin for the 24
  NPCs Bijin covers. `install_mod.ps1 -Bottom`.

  **High Poly Expressive NPCs (41107)** - applies high poly heads to all vanilla
  NPCs with regenerated FaceGen. Stronger result, but it requires High Poly Head
  itself, which is hosted on VectorPlexus rather than Nexus, so `nexus_get`
  cannot fetch it - manual download and `install_mod.ps1 -Archive`. Its own
  author recommends Nordic Faces instead for setups running several NPC mods,
  which describes this one.

  **High Poly Head (VectorPlexus), v1.4 - CONFIRMED 2026-09-08.**
  https://vectorplexis.com/files/file/283-high-poly-head/
  KouLeifoh pulled it from Nexus years ago, which is why searching Nexus turns
  up only thin-looking spin-offs and patch packs. This is the popular one.

  It is a denser version of the VANILLA head mesh, not a restyle. It adds an
  entry to RaceMenu's Face Part slider and ships morphs for the extended
  sliders plus matching high-poly brows, beards and scars. Player only in
  practice - NPCs need FaceGen regenerated in the CK, which is not happening
  here. Requires RaceMenu, which is installed.

  Switching Face Part rebuilds the head on new topology. Slider VALUES carry
  across; freeform sculpting does not. Save first.

  VAMPIRE CAVEAT, and it is not what it sounds like. Turning vampire swaps the
  player to the vampire variant race, whose head part list points at the
  vanilla head, so the Face Part selection reverts. Plain vanilla vampirism, no
  race mod involved. HPH's own installer has a vampire head fix option - take
  it. ONLY if Expressive Facegen Morphs is also installed, skip HPH's fix and
  use Vampire Headpart fix (140535) instead; those two fixes collide.

  CHECKED 2026-09-08: **Sacrosanct contains zero RACE records** - 1279 records
  parsed, 335 MGEF / 247 SPEL / 71 PERK / 15 QUST / 3 NPC_ and no race edits at
  all. Enai does vampirism through spells and perks. And `plugin_who.ps1 -Name
  RaceVampire -Type RACE` returns USSEP as the only editor across the load
  order. Nothing competes with HPH's vampire fix.

  If Expressive Facial Animation goes in alongside it, **re-run Improved Eye
  Model (59099)** - its FOMOD carries `Vector High Poly Head Expressive Facial
  Animation Female/Male` patches, and only the RaceMenu patch was taken on
  2026-09-08 because neither mod existed yet.

  DELIVERY - READ THIS, THE OBVIOUS ROUTE IS DANGEROUS.

  **DO NOT USE vectorplexis.com OR vectorplexus.com.** Confirmed 2026-09-08:
  vectorplexis.com immediately redirects to a malware page (get.privacy-keeper
  -site style) with a fake "security check" that drops an unsigned executable -
  a ClickFix fake-CAPTCHA. Matt hit it and deleted the file without running it.
  vectorplexus.com is dead and throws a certificate error.

  The claim that vectorplexis.com was the good domain came from a Wabbajack
  issue dated JULY 2022. Four years old, never re-verified. A fetch of the URL
  returned plausible mod-page content, which was treated as confirmation - a
  clone or a compromised site looks identical from a fetcher. Do not repeat
  that reasoning.

  SAFE ROUTE: Alternate High Poly Head - 148541
  https://www.nexusmods.com/skyrimspecialedition/mods/148541
  Actively maintained, v2.5, updated March 2026. Its requirements section
  carries an OFFICIAL Google Drive alternate download link for High Poly Head
  1.4 SE, published by the author. Take the dependency from there.

  Then `install_downloaded.ps1 -Match 'High*Poly*Head' -Plan -FomodDefaults`,
  and turn the printed plan into real `-Fomod` answers.

  `ips_get.ps1` still works and is still worth having - LoversLab is live and
  legitimate. Just never aim it at the VectorPlex* hosts.

  **Alternate High Poly Head (148541)** is on Nexus but still needs the
  original as a dependency, so it saves nothing.

  **Expressive Facegen Morphs (35785)** - soft requirement of both of the above,
  and additive. Safe.

**S-8  Freckles - SOLVED 2026-09-08.** The character's face read far more
freckled and blotchy than the body. Ruled out by evidence, in order:

  - **Skin diffuse: clean.** Decoded the installed `femalehead.dds` and the
    three human alternatives in BnP's Extra Options (405689). Mean per-pixel
    difference 3.5, 3.5 and 4.2 out of 255 - the same texture. Extra Options is
    race skins (Dremora, altmer, bosmer, dunmer, orc, vampire, elder,
    Akvaviri, Bijin adaption, clean), not freckle levels.
  - **Overlays: none applied.** Parsed the SKEE block of the SKSE co-save.
    Every `OVST` overlay chunk 4 or 9 bytes, string table 185 entries of XPMSE
    node and RaceMenu morph names, zero `.dds` paths. ODF, SkFO and the
    Community packs were all innocent.
  - **Source: the complexion detail map**, `femaleheaddetail_frekles.dds`.
    Native range 29-70 so it looks flat raw; stretched, it is a dense freckle
    field over cheeks, nose bridge and forehead matching the screenshot. The
    complexion head part is chosen at character creation and lives in the .ess,
    and RaceMenu on this install exposes no complexion control - so the texture
    is the only lever.

Fix: `freckle_strength.ps1 -Level 0|25|50|100 -Apply`. Variants live in
`_incoming\freckles`, each the same map blended toward neutral grey 63,63,63,
the value BnP's own `blankdetailmap.dds` uses, so the blend is a true strength
dial. 32-bit uncompressed on purpose - the map's whole range is 41 levels and
DXT5 produced compression noise about the size of the signal. Running at 0.

**S-7  PBR skin - open question.** True PBR can cover skin, and PBR Hub (139889)
and My PBR Conversion Hub (175588) collect conversions. Whether a PBR skin set
is mature enough to beat a good conventional one plus Community Shaders'
Subsurface Scattering is genuinely unknown to me - it needs looking at, not
asserting. Worth checking before committing to S-1, since the two choices
interact.

---

## PHASE - interface and map   (added 2026-09-08)

Two jobs with OPPOSITE relationships to the graphics package. Read that before
sequencing either.

**U-1  UI overhaul - fully independent, do it whenever.** These ship SWF,
textures and DLLs, not plugins, so nothing here invalidates LOD or touches the
PGPatcher/TexGen/DynDOLOD chain. Goal stated 2026-09-08: minimal, sharp, clean,
modern.

  Untarnished UI - 75188      https://www.nexusmods.com/skyrimspecialedition/mods/75188
    Flat and modern. Strips drop shadows, fake gloss, radial blur. Futura Book
    BT. Elden Ring-influenced layout. 7325 endorsements, the most established by
    a distance. Last updated July 2023. Needs Dear Diary Dark Mode underneath.

  Norden UI - 166086          https://www.nexusmods.com/skyrimspecialedition/mods/166086
    Clean modern, muted monochrome, Nordic texture. v1.2.6 June 2026, 1984
    endorsements, ~100 companion patches.

  Oathvein UI - 160916        https://www.nexusmods.com/skyrimspecialedition/mods/160916
    Same idea, grim-dark. v1.2.3 June 2026, 1808 endorsements.

  Vel'dun UI - 176230         https://www.nexusmods.com/skyrimspecialedition/mods/176230
    Morrowind/Dunmer themed. Aug 2026. Only one doing 32:9. Not minimal.

  Norden, Oathvein and Vel'dun are ALL by Nithog - one framework, three skins.
  Identical dependencies and patch coverage, so the choice is purely the look.

  New dependencies for the Nithog family, none of which are installed:
    SkyHUD - 463                        https://www.nexusmods.com/skyrimspecialedition/mods/463
    Widescreen Scale Removed 1.6.1130+  https://www.nexusmods.com/skyrimspecialedition/mods/136793
    TrueHUD - 62775 (soft)              https://www.nexusmods.com/skyrimspecialedition/mods/62775
    MCM Helper (Vel'dun lists it hard)
  Untarnished instead needs Dear Diary Dark Mode.

  The trade: Untarnished is the most literally minimal and sharp but three years
  stale; Norden is the most modern and maintained but drags in SkyHUD and
  Widescreen Scale Removed.

**U-2  World map - MUST GO IN BEFORE THE DYNDOLOD RUN.**

  A Clear Map of Skyrim and Other Worlds - 56367
    https://www.nexusmods.com/skyrimspecialedition/mods/56367
    v4.0, 8111 endorsements. Adds the missing maps for Blackreach, Forgotten
    Vale, Soul Cairn, Skuldafn and Sovngarde. Removes map fog, fixes map
    lighting, full 360 rotation and 90 pitch instead of the locked vanilla
    angle, roads with paths distinguished from roads, and fixes terrain/water
    z-fighting on the map.

    THE SEQUENCING POINT: it ships optional custom DynDOLOD rules that build
    high quality Map LOD as a fake object LOD level 32 - map-only detail at no
    runtime cost. DynDOLOD is already being regenerated for the graphics
    package and for the stranded tree billboard. Install this BEFORE that run
    and the map is generated in the same pass. Install it after and the whole
    generation happens twice.

    Soft requirement: Unique Map Weather Framework, for custom map weathers.

  A Quality World Map - 5804  https://www.nexusmods.com/skyrimspecialedition/mods/5804
    The classic paper/vivid reskin with roads. Coexists with the above. Run it
    for the aesthetic, not the function.

  SKIP the Water for ENB patch (74342) - this install is Community Shaders,
  not ENB.

## REFERENCE - Gate To Sovngarde   (added 2026-09-08)

https://www.nexusmods.com/games/skyrimspecialedition/collections/qdurkx
Wiki: https://gatetosovngarde.wiki.gg/

jayserpa's curated collection, ~1900 mods. Tags: all-in-one, animation, bug
fixes, environment, gameplay, lore-friendly, visual.

**MINE IT, DO NOT INSTALL IT.** Two reasons, and only the second is obvious.

  It is a complete list installed as a whole through Vortex collections into
  its own instance. Not a parts bin. Merging it into a 131-mod build gives
  something worse than either list alone.

  It would also bury the point of this install. GTS ships CS Upscaling
  (FSR 3.1 by default, DLSS suggested for RTX). This build instead runs
  dlss5-bridge in synth mode, which is why SkyrimUpscaler.dll is on the CS
  hard-block list. Two upscalers, one of them the entire reason the install
  exists.

**Why it is still worth reading.** GTS uses **Community Shaders exclusively,
not ENB** - same architecture as this build, so its choices actually transfer,
unlike the ENB-based lists. It is the closest thing to a reference
implementation of a large CS list, and the wiki documents the reasoning rather
than just naming mods. Read it for the categories this build has not touched:
gameplay, immersion, animation, bug fixes, UI.

**Possible tool, not built.** `collection_diff.ps1` - pull the collection's mod
list from the Nexus v2 GraphQL API with the existing key, map installed mods to
Nexus ids via each mod folder's meta.ini `modid=`, and write ONE report of what
GTS has that this build does not, grouped by category and sorted by
endorsements. Would need a category filter to be useful; a raw 1900-vs-131 diff
is not reviewable. Build it only if the shortlist is actually wanted.

## PHASE - roleplay, reactivity, living world   (from GTS, 2026-09-08)

Mined from Gate To Sovngarde via collection_diff.ps1 - 1553 mods, 1519 not
installed here, full report at logs\gts_full.txt. These are the picks, not the
list. Grouped by what was actually asked for: a world that changes, NPCs that
react, immersion, and a character with a past.

**R-0  THE GATE.** Everything below adds plugins, and plugins invalidate tree
LOD. Seasons needs LOD generated PER SEASON. A Clear Map (U-2) wants its
DynDOLOD rules present at generation time. So the graphics package is now a
gate: seasons, the map and this gameplay set are all decided BEFORE it runs, or
the ~90 minute chain runs three times.

ACCEPTED by Matt 2026-09-08: R-1 through R-4 are wanted, R-5 exclusions agreed.
These are decisions now, not proposals. Sequencing still gated by R-0.

**R-1  Seasons - CONFIRMED 2026-09-08. Matt took the cost knowingly.**
  The generation multiplier and the six-mod patch hunt were both put to him
  explicitly and he chose yes. This is now a fixed requirement of the chain,
  not an option, and STAGE 4 IS PRICED IN HOURS NOT NINETY MINUTES.
  OPEN TASK: find seasons patches for S3DTrees NextGenerationForests, Nature
  of the Wild Lands, Blubbo aspens, Folkvangr, Alpine Forest of Whiterun
  Valley and Bent Pines. Any without one stays summer year-round - and if most
  lack patches that is worth raising before the chain runs, not after.

**R-1  Seasons - the living world.**
  Seasons of Skyrim SKSE - 62861          the framework
  Turn of the Seasons - 63623             flora swaps
  Shrubs of Snow - 63463
  Seasonal Wildlife Distribution - 63700  animals change too
  Seasonal Alchemy - 63969                ingredients follow the calendar
  RASS Seasons patch - 93600

  REAL COST: every tree and flora mod needs a seasons patch or it stays summer
  forever. Installed and affected: S3DTrees, Nature of the Wild Lands, Blubbo's
  aspens, Folkvangr, Alpine Forest, Bent Pines. Six mods needing coverage.
  Simplicity of Snow is already slated for removal in the graphics package.

**R-2  NPCs reacting.**
  Skyrim Reputation - 22374               the core system
    + Fixed and Patched - 42538, + Improved - 52416   (GTS runs both; the base
      needing two community fixes is worth knowing before committing)
  NPCs React To Necromancy - 70428
  NPCs React To Invisibility - 91480
  NPCs React To Frenzy - 107492
  To Your Face - 24720                    they turn and look at you
  Guard Dialogue Overhaul - 22075
  Bandit Lines Expansion - 63733 / Civil War - 77566 / Forsworn-Thalmor - 80188
  Sleeping Expanded - 59250
  Relationship Dialogue Overhaul Lite - 42068

  AI Overhaul SSE - 21654 is the heavyweight, 36142 endorsements, real
  schedules and behaviour. IT EDITS NPC RECORDS, so it lands on Bijin,
  Seranaholic and the facegen layering set up on 09-08. Patches and deliberate
  load order required. Treat as its own decision, not part of a batch.

**R-3  Backstory and roleplay.**
  Why I Came to Skyrim - Origin Stories - 167166   literally the ask
  Alternate Perspective - Alternate Start - 50307  jayserpa's. REPLACES
    Alternate Start - Live Another Life, which is installed. A swap, not an add
    + Voiced Addon - 96865, New Beginnings extension - 57818
  The Choice is Yours - 3850              quests stop auto-starting on rumour
  At Your Own Pace - 52704
  Timing is Everything - 25464            content gated by level
  Thieves Guild Requirements - 33256 / Improved College Entry - 22184
  Mundus - Standing Stone Overhaul - 33411
  Aetherius - A Race Overhaul - 26686

**R-4  Immersion.**
  Immersive Interactions - 47670 (+ Integration Patch 76862)
  Immersive Equipment Displays - 62001
  Simple Dual Sheath - 50049
  Dynamic Things Alternative - 60741
  Dirt and Blood - 38886
  Dynamic Activation Key - 96273
  Audio Overhaul for Skyrim SE - 12466
  Immersive World Encounters - 18330 / Extended Encounters - 44810
  Missives - 17576
  Trade and Barter - 23081 / Simply Knock - 14098 / Go to bed - 4224

**R-5  DO NOT INSTALL - the alternative is already here.**
  Adamant - 30191        perk overhaul, mutually exclusive with Ordinator
  Scion - 41639          vampire overhaul, excludes Sacrosanct
  Manbeast - 44746       werewolf overhaul, excludes Growl
  Serana Dialogue Edit - 16222   overlaps Serana Dialogue Add-On
  Azurite Weathers and Seasons - 42731   collides with the current weather set

  NOT a conflict, correcting an earlier assumption: True Directional Movement
  (51614) and SmoothCam run together fine - TDM ships SmoothCam integration.

## PHASE - framework layer   (found 2026-09-08, do this FIRST)

**SHIPPED 2026-09-08. F-1 tiers 1-3 plus the Y-1 engine fixes went in as one
46-mod block. check_masters is clean at 226 plugins: no missing master, none
inactive, none out of order. Eleven were FOMODs and were answered explicitly -
every DLL picker got SSE/AE v1.6.1170 by name rather than the first option,
which is listed newest-first and would have installed a 1.7.x DLL. AnimObject
Swapper has no 1170 entry so it took the 1.6.629+ bucket. OCF took Full
(Recommended) with Mod Dependant deliberately empty - Campsite, Skyrim's Got
Talent and White Phial are not installed and those patches carry them as
masters. The CC patch took Merged, correct because the Data folder carries all
74 creations. Navigator took All-in-one + ESP-FE.**

**HELD BACK from that block, each for a stated reason:** Auto Parallax (79473,
belongs with the PBR package), Flat World Map Framework (29932, decide with
U-2), Dynamic Key Action Framework (87706, overlaps the installed Dynamic
Activation Key), Precision Locational Damage (78744, needs Precision first).

**F-1  The plumbing is missing.** Scanning GTS by endorsement turned up that
this build lacks most of the standard framework layer - not gameplay mods, the
things other mods list as HARD requirements. Nearly everything in R-1..R-4
depends on some subset. Install before any of them, or repeat the silent
missing-master deactivation over and over.

  TIER 1 - the plumbing other mods declare as hard requirements
  powerofthree's Tweaks - 51073            95816
  Fuz Ro D-oh - Silent Voice - 15109       93828
  MCM Helper - 53000                       87797
  powerofthree's Papyrus Extender - 22854  87638
  Mfg Fix - 11669                          74112
  Bug Fixes SSE - 33261                    57783
  Animation Motion Revolution - 50258      54258
  Open Animation Replacer - 92109          44816
  Animation Queue Fix - 82395              41390
  More Informative Console - 19250         42356
  Better Jumping SE - 18967                69901
  Footprints - 3808                        84831

  TIER 2 - ENABLERS. Researched 2026-09-08. These are not optional extras;
  each one is the thing a later mod is built on top of.
  Base Object Swapper - 60805              36472  THE BIG MISS. Swaps world
    objects by rule. Dynamic Things Alternative in R-4 is literally named
    "Base Object Swapper", and the 3D flora and mountain flower mods use it.
  Papyrus Tweaks NG - 77779                31058  script engine performance
    and stability, which starts mattering at hundreds of mods
  Crash Logger SSE - 59818                 30337  would have named Improved
    Alternate Conversation Camera in one launch instead of a crash hunt
  Sound Record Distributor - 77815         25175
  Behavior Data Injector - 78146           18982  + Universal Support - 78159
  FormList Manipulator (FLM) - 74037       18404
  AnimObject Swapper - 75167               11890
  Object Categorization Framework - 81469   9538  item categorisation, needed
    by inventory and UI mods
  Navigator - Navmesh Fixes - 52641         9507
  Container Distribution Framework - 120152 4332
  Crafting Recipe Distributor - 52276       4032
  Console Commands Extender - 74390         4406
  MCM Recorder - 61719                     10178
  Description Framework - 105799            7490

  TIER 3 - DIRECTLY SERVING A PILLAR
  Dynamic Activation Key - 96273           17390  input remapping. PILLAR 5
    controller clause. Has an MCM (96408) and an addons collection (96430).
  Dynamic Key Action Framework - 87706             same domain, check overlap
  Dynamic Magic Modification Framework - 127918    the layer under Apocalypse
    and Odin. PILLAR 5 magic depth.
  Spell Extender - 85968                           same
  Perk Adjuster - 127999                           progression, pairs with CSF
  Precision - Unofficial Locational Damage - 78744 extends Precision in F-4
  Flat World Map Framework - 29932          9843  CHECK AGAINST U-2 before
    installing either - both touch the world map

  Enhanced Lights and FX - 2424 (139462) is the most endorsed thing in the
  whole report but is an INTERIOR LIGHTING OVERHAUL. Against Community Shaders
  and the DLSS 5 presentation contract that is a real decision, not a freebie.
  Deferred, deliberately.

**F-2  Custom Skills Framework - 41780** (19131). The answer to "skill trees
for vampirism, pyromancy, cryomancy". It is the framework that lets mods add
real trees with their own menu. GTS uses it for Skills of the Wild (37693) and
Prelude to Purgatory - a Lich tree (53143). The magic-school trees Matt wants
are CSF-based but are NOT in GTS - separate hunt required. OPEN QUESTION: how
CSF menus behave on a controller. Verify, do not assume.

**F-3  Controller accessibility.** Auto Input Switch - 54309 (14799) flips the
UI between keyboard and gamepad automatically. Base layer for pillar 5's
accessibility clause.
Also seen: Favorite Misc Items (42750), Persistent Favorites (118174),
Hotkey Reminder (115853).

**F-4  Combat - direction, not yet decided.** Judged against pillar 4's
tiebreaker, fun and explicitly not difficult:
  Precision - Accurate Melee Collisions - 72347   38831   melee hits what it
    looks like it hits. Biggest feel change, no difficulty change.
  Blade and Blunt - A Combat Overhaul - 34549      9301   GTS's pick,
    deliberately light-touch
  Stagger Effect Fix - 110508 / Dynamic Block Hit - 100570 / Parrying RPG - 81356
  Precision Creatures - 74887 / Animated Armoury Precision patch - 6710

**F-5  New exclusion.** Mysticism - A Magic Overhaul (27839, 29458) is GTS's
magic overhaul and is mutually exclusive with Odin. Odin, Apocalypse and
Triumvirate are installed. Do not take Mysticism. Add to the R-5 list.

**F-7  THE ENAI FORK - one per domain, and it is a real choice.**

Eight Enai mods are already installed: Ordinator, Apocalypse, Summermyst,
Wintersun, Sacrosanct, Growl, Odin, Triumvirate. Three domains remain where he
has an entry, and Gate To Sovngarde picked someone else in ALL THREE. Mutually
exclusive, one overhaul per domain.

    domain            Enai                       GTS chose
    races             Imperious - 1315           Aetherius - 26686   (11184)
    standing stones   Andromeda - 14910          Mundus - 33411       (9716)
    shouts            Thunderchild               Stormcrown - 90659   (5725)

  DECIDED 2026-09-08: THE GTS PICKS. Aetherius (26686) for races, Mundus
  (33411) for standing stones, Stormcrown (90659) for shouts.
  Imperious, Andromeda and Thunderchild are therefore EXCLUDED - add them to
  the R-5 exclusion list mentally, they lose to installed rivals now.
  The Enai argument was that his mods interlock with the eight already here;
  the GTS argument, which won, is that they are more modern and were tested
  together in a 1900-mod list. Thunderchild's id never needed confirming.
  Thunderchild's own mod id is not confirmed - 68421 is the Russian
  translation, not the base. Look it up before installing.

**F-8  Non-competing gameplay systems - take on merit, nothing to displace.**

  Realistic AI Detection (RAID) - 2345     24171  makes stealth detection make
    SENSE rather than making it harder. Pillar 4 tiebreaker exactly.
  Undeath - Classical Lichdom - 40802       6243  become a lich. THE CLOSEST
    THING IN THE ENTIRE REPORT TO THE SKILL-TREE WANT: GTS pairs it with
    Prelude to Purgatory - 53143, a Custom Skills Framework lich tree. A real
    progression system with its own tree, already proven working together.
  SkyParkour v3 - 132292                   12564  procedural parkour and
    climbing framework
  Smart NPC Potions - 40102                10658  enemies use their tools
  NPCs Take Cover - 111890                  6819  smarter anti-cheese AI
  Sorcerer - Staff and Scroll Overhaul - 95196   3808
  Gourmet - A Cooking Overhaul - 96876      6312
  Penitus Oculatus - 21061                 12828
  YASTM - Yet Another Soul Trap Manager - 56144   3238
  Fort Takeovers Framework - 25143          4795

  HONEST GAP: there is NO Sacrosanct vampire skill tree anywhere in this
  research. Undeath's lich tree is the nearest equivalent. A CSF-based
  vampirism tree, if one exists at all, is off-collection and needs its own
  hunt alongside the pyromancy and cryomancy trees.

**F-6  Still to mine, at Matt's request:** player homes (10 in the report),
quests and adventures (108), followers and companions (50). Deferred, not
forgotten.

## PHASE - everything else that must precede the chain   (X, 2026-09-08)

Researched because the generation chain must not run twice. This is the sweep
for categories NOT already covered by P, C, V, W, U-2 or R-1.

**X-0  A CORRECTION FIRST, and it makes the free lane much bigger.**

  "Any plugin gates behind the run" was TOO BROAD and it has been repeated
  several times in this file. Sheson's actual mechanism: tree LOD unloads by
  matching FORM IDS, and it breaks when the load order OF PLUGINS THAT ADD
  TREE REFERENCES changes. An armour mod's ESP adds no world references.

  THE REAL RULE: world references and static meshes gate behind the chain.
  Item and actor mods do not.

  FREE LANE, confirmed - can go in at any time, including after the chain:
    weapons, armour, clothing, jewellery, book covers, instruments
    creatures and mounts, followers - actors, never in LOD
    audio, UI, animation behaviour, skin/face/overlays
    INTERIOR-ONLY overhauls - interiors have no LOD at all. The whole JK's
      series in the GTS report is interiors: JK's The Bannered Mare (33845,
      23339), Palace of the Kings (48902), High Hrothgar (62219), Septimus
      (66915), Bards College (71054), Castle Dour (74309).
  This matters for PILLAR 3 directly: the wardrobe and adult content can keep
  growing forever without re-running anything.

**X-1  NEW WORLDSPACES - the biggest uncatalogued category, and the most
expensive to get wrong.** DynDOLOD generates LOD PER WORLDSPACE. Add a new
land after the chain and it does not get partial LOD, it gets none.

  Beyond Skyrim - Bruma SE - 10917         67195  14th most endorsed mod in
    the whole 1519 report and nothing in this plan mentioned it
  The Forgotten City - 1179                47435
  VIGILANT SE - 11849                      35084  (+ translation 11894)
  Wyrmstooth - 45565                       26137
  Project AHO - 15996                      20730
  Undeath Remastered - 6180                19685  pairs with F-8's lichdom
  Beyond Skyrim - Wares of Tamriel - 31519  9281
  SIRENROOT - Deluge of Deceit - 70917      7296
  Siege at Icemoth - 109541                 2588

  THESE INTERLOCK WITH U-2. A Clear Map ships optional support for Bruma,
  Wyrmstooth, Vominheim, Midwood Isle and Falskaar, so the land-mod decision
  has to be made WITH the map, not after it.

**X-2  City and settlement overhauls.** Enormous static counts. All of these
stack against C-1 Major Cities Mesh Overhaul - one per city, check before
taking both.

  Cities of the North - Dawnstar 28952 (13068) / Morthal 34168 (11652) /
    Falkreath 56731 (11161)
  The Great City Of Winterhold - 17127     10943
  The Great City of Solitude - 22243        9341
  The Great Village of Mixwater Mill - 36350  9160 / Old Hroldan - 33189 9007
    / Kynesgrove - 42639 7694
  Capital Whiterun Expansion - 37982        8921
  Capital Windhelm Expansion - 42990        8183
  Fortified Whiterun - 40094                7770
  The Great Cities - Resources - 104373     4998
  Orc Strongholds - Largashbur 89354 / Narzulbur 88809 / Dushnikh Yal 92485

**X-3  Flora, grass and 3D plants.** Feeds BOTH object LOD and the grass cache
step. Note two dependencies inside this group.

  DrJacopo's - 3D Landscapes and Grass Library - 80687   7235
  DrJacopo's - 3D Pine Grass - 42032                    13671
  DrJacopo's - 3D Clover Plant - 68793                   9985
  DrJacopo's - 3D Pine Shrubs - 94791                    5466
  DrJacopo's - 3D Solstheim Grass - 90945                3966
  DrJacopo's - 3D Vanilla Tundra Grass - 141074           848
  Mari's flora - 45952                                  11379
  Fabled Forests - 94462                                 5803
  Cathedral - 3D Rocky Shores - 33474                    4710
  Edmond's Unique Flowers and Plants - 29154             3972
  No Grassias - universal grass fix - 35639              7335
  Grass Sampler Fix - 91285                              5075
  Mountain Flowers - Base Object Swapper - 60756         5050  REQUIRES Base
    Object Swapper from F-1 tier 2
  Happy Little Trees Add-On - DynDOLOD 3 - 56907         7032  explicitly a
    DynDOLOD addon
  Skyland Happy Little Trees Bark - 82491                3267

**X-4  World statics in Models and Textures.** The half of that 87-mod
category that is NOT items. TexGen bakes LOD textures from these.

  Skyrim 3D Rocks - 17732                  21192
  Dwemer Pipework Reworked - 46507         13873
  Unique Border Gates SE - 4819            10232
  Animated Ships - 110260                  11062
  Daedric Shrines - All in One - 78772     12578
  Solitude and Temple Frescoes - 29695      4299
  Nordic Ruins of Skyrim - 20382            7569
  Whiterun Watchtower Doesn't Start Broken - 49305  7229

**X-5  Exterior structures - the Environs and Lawbringer series.** Small
individually, all LOD-relevant.
  Lawbringer - 29882 (7175), Environs - Master Plugin - 91160, and the Environs
  set: Ruined Tundra Farmhouse 72981, Whiterun Watchtower 76261, Abandoned
  Abodes 82410, Riften Warehouse 88024, Greenwood Shack 73732, Hroggar's House
  83457, Kolskeggr 78477.

**X-6  Dungeons and player homes - SPLIT, check each.** New dungeons are mostly
interior cells (free lane) but their ENTRANCES are exterior statics (gated).
Player homes the same. Hammet's Dungeon Pack 12186 (9720), Dungeons - Revisited
51798 (8402), Hidden Hideouts of Skyrim 2625, Riverside Shack 20982.

## PHASE - the dynamic visual layer   (V, added 2026-09-08)

Pillar 1 is not only textures. These are the moving parts of the world, mined
from GTS by endorsement. Several belong INSIDE the graphics package run, not
after it.

**V-1  Water - see W-1/W-2/W-3 in the graphics package, do not duplicate.**
  The water decision already lives in the PACKAGE section and is more complete
  than this list was. GTS independently picking Simplicity of Sea (56520) is
  corroboration for the W-2 option already written there, nothing new. W-3
  (A Water Made For CS in mind, 172959) is still the more interesting and
  riskier candidate and GTS does not carry it.

  NEW from the GTS scan, and genuinely additive rather than duplicate:
  Skyrim Landscape and Water Fixes - 26138   28268   near-universal bug fix
  FYX - Water Mesh Optimization - 97713       4558
  Depths of Skyrim - underwater overhaul - 26913   14300
  Loki's Wade In Water - 42854 / Wade In Water Redone - 71418

**V-2  Rain, wetness, atmosphere.**
  R.A.S.S. Rain Ash And Snow Shaders - 22780   13755   rain streaks, wetness,
    frost, ash as screen and character effects. PARTIALLY OVERLAPS the
    installed CS - Wetness Effects. A decision, not a stack. There is also a
    RASS Seasons of Skyrim patch (93600) if R-1 goes ahead.
  Soaking Wet - Character Wetness Effect - 68025   9454
  Volumetric Mists - 29273                        12063
  ETHEREAL CLOUDS - 2393                          31151
  Rainbows Remade - 88161                          7737
  Rain Extinguishes Fires - 80419                  3361

  Azurite Weathers and Seasons - 42731 is in R-5, DO NOT TAKE - collides with
  the current weather set.

**V-3  Lighting - DECIDED 2026-09-08: Lux, not ELFX. CONFIRMED by Matt.**

  Matt asked for Enhanced Lights and FX and was right that it does not fight
  the renderer - ELFX changes light PLACEMENT and interior lighting data, and
  Community Shaders' Skylighting and SSGI work on top of whatever sources
  exist. Better sources underneath means those have MORE to work with. The
  earlier deferral here was over-cautious.

  His skybox worry was also right, and it is one specific module: ELFX ships
  ELFX - Weathers.esp, and the author's own note is that it may conflict with
  alternate weather systems and is not recommended alongside them. Answer
  would have been "install ELFX, skip Weathers".

  EXCEPT ELFX is version 3.06, last updated OCTOBER 2017. Nine years. Same
  staleness defect as High Poly Head.

  TAKE INSTEAD:
    Lux - 43158                interiors
    Lux CS - 153919            v2.6.0, updated Aug 2026, 6475 endorsements.
      Community Shaders NATIVE: HDR tonemapping tuned for CS, plus INVERSE
      SQUARE LIGHTING across the Lux plugins.
    Lux Orbis - 56095          exteriors
    Lux Via - 63588            roads. Check against installed Northern Roads.
    Requires ISL Helper SKSE, optionally Light Placer (127557) and Inverse
    Square Lighting - Community Shaders.

  WHY ISL IS THE POINT. Bethesda lights have a flat radius and stop. Inverse
  square falloff is how light behaves in reality and how every offline
  renderer does it. That single change does more for "volumetric and
  ray-traced looking" than any texture in the graphics package, and it hands
  Skylighting and SSGI better data. It is the highest-leverage item in pillar 1.

  Lux ships NO weather module, so the skybox question disappears rather than
  being managed.

  Also available: Smoking Torches and Candles - 8607 (23220).
  ELFX (2424) and ELFX Shadows (63790) are GTS's choice and remain defensible,
  just older. Not taken.

**V-4  Magic VFX - CORRECTED 2026-09-08. The gap was smaller than claimed.**

  The earlier entry said "GTS barely touches spell visuals". That was WRONG,
  and wrong because the keyword hunt behind it did not include 'combustion' or
  'electrocuted'. A conclusion drawn from a search that did not cover the term.

    Frozen Electrocuted Combustion - 3532   24907  fire, frost and shock
      death and impact effects. The single biggest spell-visual mod available.
    Dust Effects by HHaleyy - 2407          21132  impact particles
    Core Impact Framework (CIF) - 146873     7273
    Elemental Mastery Magic - 139953         3130

  There IS still an off-collection hunt for spell projectile and particle
  overhauls, alongside the skill-tree hunt in F-2. It is just smaller.

## PHASE - top 250 sweep   (Y, 2026-09-08)

Method: the 250 highest-endorsed mods in the GTS report, minus every mod id
already referenced anywhere in this file. 114 were already covered; 136 were
not. What follows is the worthwhile remainder. Nearly all of it is FREE LANE
under the X-0 rule - actors, items, animation behaviour and engine fixes carry
no world references.

**Y-1  ENGINE AND BUG FIXES - an entire tier that is missing.** Free lane.

  Face Discoloration Fix - 42441           38184  THE standing engine-level
    fix for the black-face class of problem that ate the evening of 09-08.
    Should have been installed before any NPC appearance work.
  Scrambled Bugs - 43532                   35125
  Unofficial Creation Club Content Patches - 18975  30036  THIS BUILD RUNS AE
  Actor Limit Fix - 32349                  29936
  Assorted mesh fixes - 32117              23756
  Auto Parallax - 79473                    19161  matters for the PBR work
  Equip Enchantment Fix - 42839            17598
  Recursion Monitor - 76867                16361
  NPC AI Process Position Fix NG - 69326   14458
  Dual Casting Fix - 92454                 13610  magic pillar
  First Person Animation Teleport Bug Fix - 92795  10954
  OnMagicEffectApply Replacer - 67968      10748
  Sprint Sneak Movement Speed Fix - 86631  10742
  Vanilla Scripting Enhancements - 68139   10580
  Inertia - Floating Gear Fix - 148746      9849
  Hunters Not Bandits - 1547               15030

**Y-2  ANIMATION - 25 mods, entirely untouched, all free lane.**

  Expressive Facial Animation Female - 19181  69396  and Male - 19532  46493
    ONLY ever discussed as a High Poly Head dependency. It is not one. Worth
    taking on merit, and it serves pillar 2.
  Conditional Expressions - 45148  DROPPED 2026-09-08 - INCOMPATIBLE with
    OStim Standalone, which was chosen as the adult spine. An extended version
    is said to work; verify before considering it again. FK's Diverse Racial
    Skeletons (38563) is out for the same reason.
  Paired Animation Improvements - 99621    32006
  EVG Conditional Idles - 34006            29291
  Payload Interpreter - 65089              27990  framework
  EVG Animation Variance - 38534           20912
  Animated Armoury DAR - 35978             20181  new weapon TYPES with
    animations. Pillar 3.
  Gesture Animation Remix OAR - 64420      18438
  EVG Animated Traversal - 63232           16630
  Goetia Animations - Magic Spell Casting - 70204  16070  (M-2 named Goetia)
  NPC Animation Remix OAR - 63471          15666
  Vanargand Sneak Archery - 56788          15150
  Comprehensive First Person Animation Overhaul - 87169  13650
  Jump Behavior Overhaul - 36889           13167
  Take a Seat - 54193                      13095
  Weapon Styles for IED - 85085            12375
  Dynamic Animation Casting NG - 73293     11173
  Eating Animations and Sounds - 42602     11430

**Y-3  SYSTEMS that complete the magic stack.** Simon Magus, designed to sit
alongside Ordinator - the two schools the current stack does not cover.
  Apothecary - An Alchemy Overhaul - 52130    12865
  Thaumaturgy - An Enchanting Overhaul - 57138  10718
  Also: Honed Metal - NPC crafting services - 61015 11650, Encounter Zones
  Unlocked - 19608 13367, Headhunter Bounties Redone - 51847 17416,
  Survival Mode Improved - 78244 11255, Skyrim's Got Talent - 50357 11937.

**Y-4  FOLLOWERS - actors, free lane, pillar 4 content.**
  INIGO - 1461                             70162
  Lucien - 20035                           31066
  Song of the Green (Auri) - 11278         20283
  Remiel - 51874                           11082

**Y-5  QUEST EXPANSIONS - pillar 4, mostly free lane.**
  Paarthurnax - Quest Expansion - 51711    20196
  College of Winterhold - QE - 66666       15510
  Skyrim Extended Cut - Saints and Seducers - 72772  15092
  House of Horrors - QE - 57285            12945
  Konahrik's Accoutrements - 22206         11438
  Caught Red Handed - QE - 65708           10663
  The Only Cure - QE - 57683                9571
  The Whispering Door - QE - 76606          9230
  Innocence Lost - QE - 80974               9198
  Obscure's College of Winterhold - 20514  16483  (overhaul, adds statics -
    gated, not free lane)

**Y-6  UI - pairs with the U-1 decision.**
  moreHUD SE - 12688                       48157
  Inventory Interface Information Injector - 85702  23097
  Constructible Object Custom Keyword System - 81409  16845
  Immersive Icons (B.O.O.B.I.E.S.) - 89241  14794  and its supplement 89823
  Skyrim Souls RE - Unpaused Menus - 27859  12008
  CoMAP - Common Marker Addon Project - 56123  11513
  ConsolePlusPlus - 79975                  10379

**Y-7  PILLAR 2 and 3 - free lane, add whenever.**
  Beards - 1067                            45998
  Vanilla hair remake - 63979              21271
  KS Hairdos Lite - 1932                   13617
  Improved closefaced helmets - 824        33349
  Book Covers Skyrim - 901                 65457
  aMidianBorn Book of Silence - 35382      35611
  Gemling Queen Jewelry - 4294             26791
  Left Hand Rings Modified - 3240          26715
  HDT-SMP for Cloaks and Capes - 55030     10462
  Armor Variants Expansion - 34100         10971
  Nirn Necessities - SMP Accessories - 112481  10112
  ElSopa Quivers Redone - 65921            13443
  JS Unique Utopia Daggers - 65394         10455
  Skeleton Replacer HD - 52845             10273

**Y-8  NEEDS A DECISION, not a default.**
  RS Children Overhaul - 2650              86791  4th highest in the report.
    Replaces every child NPC. Needs its Patch Compendium - 13409 (23233).
    Touches NPC records, so weigh it like AI Overhaul.
  Campfire - Complete Camping System - 667  78320  survival and camping, and
    the base for the Skills of the Wild CSF trees. Judge against the pillar 4
    tiebreaker: interesting system or chore?
  Interesting NPCs (3DNPC) - 29194         44275  huge content add. Adds
    locations as well as NPCs, so PARTIALLY GATED - check before the chain.
  Alternate Conversation Camera - 21220    24803  NOTE: the IMPROVED version
    (68210) is permanently retired for crashing. This is the original.

    CORRECTION 2026-09-08: do not install 21220 without checking SmoothCam
    first. SmoothCam already ships a full dialogue camera and ours was simply
    switched off, dialogueMode was 0 in overwrite\SKSE\Plugins\SmoothCam.json.
    It has two modes, Oblivion which narrows FOV by 30 for a tight portrait
    shot, and Face To Face which is an over the shoulder two shot with a 30
    unit side offset and an optional force to thirdperson. It also ships
    SmoothCam_FocusBones_Default.txt targeting NPC Head and NPCEyeBone, so the
    framing is built for faces. All of it is live in the MCM under SmoothCam,
    Dialogue, Dialogue Mode, so it costs nothing to try. Only install 21220 if
    that is not enough, and set dialogueMode back to 0 first so two mods are
    not both hooking the dialogue camera.

## PHASE - adult content   (A, 2026-09-08)   PILLAR 3

**A-0  THE FINDING: the two major frameworks are on NEXUS, not LoversLab.**

  OStim Standalone - Nexus 98163      the modern animation framework. Third
    generation, now fully INDEPENDENT of OSA. Actively developed at
    github.com/VersuchDrei/OStimNG. Supports 1.6.x; 1.7.x still in progress,
    which does not affect this build at 1.6.1170.
  Toys and Love - Nexus 63512         v2.62. Describes itself as THREE
    FRAMEWORKS IN ONE: bondage, love scenes, and arousal. This is the direct
    answer to the bondage/BDSM question raised earlier in the session, and it
    is a Nexus mod.
  SexLab                              the LoversLab one. Older architecture,
    but by far the largest content ecosystem - the animation packs, Devious
    Devices and most third-party adult content are built against it rather
    than OStim.

  DECIDED 2026-09-08: OSTIM STANDALONE (98163). Chosen for animation quality
  and active maintenance over SexLab's larger content library. SexLab and
  Toys&Love are therefore not the spine - Toys&Love may still be worth a look
  later for its bondage half IF it coexists with OStim, which is UNVERIFIED.
  CONSEQUENCE, already actioned in Y-2: Conditional Expressions (45148) and
  FK's Diverse Racial Skeletons (38563) are OUT. OStim lists both as
  incompatible.

**A-1  CONFLICT CREATED THE SAME DAY, and it is between two of these lists.**
  OStim Standalone lists as INCOMPATIBLE:
    Conditional Expressions - Subtle Face Animations - 45148  <- RECOMMENDED
      IN Y-2 for pillar 2 on 2026-09-08. An extended version works; the plain
      one does not.
    FK's Diverse Racial Skeletons - 38563
    Racial Body Morphs Redux
    OSex, OSA by CEO, OAlign, OSearch, OSound
  If OStim is the pick, Y-2 needs amending.

**A-2  GATING.** Under X-0 this is all FREE LANE - actors and items, no world
  references - EXCEPT any adult mod that adds locations or worldspaces, which
  gates like anything else. Check per mod.

**A-3  HONEST LIMIT ON LOVERSLAB.** It cannot be enumerated the way GTS was:
  no API, content behind an account, and guessing a mod list from recall and
  handing over unverified ids is EXACTLY the failure mode that produced the
  vectorplexis malware incident on this same day. Do not do it.

  The working method instead:
    1. He browses LoversLab signed in and picks file pages.
    2. ips_get.ps1 downloads them with his session cookie:
       ips_get.ps1 -Url '<file page url>' -CookieFromClipboard -List
    3. Send the file page URLs back here for requirement, version and conflict
       checking against the installed load order. That part IS doable well.

  BODY NOTE: this build runs CBBE 3BA, which most current LoversLab content
  targets alongside BHUNP. Well positioned; no body swap needed.

**A-4  QUALITY BAR.** Pillar 3 says adult content is held to the same visual
  quality bar as everything else - a badly made adult mod loses to a good
  vanilla one. The "is it still maintained" axis matters more here than
  anywhere else in the plan, because that ecosystem has a very long tail of
  abandoned work.

## PHASE - top 1000 sweep   (Z, 2026-09-08)

Same method as Y, widened to the 1000 highest-endorsed. 278 were already
referenced, 722 were not. 348 of those sit below 3000 endorsements and are
long tail, not listed. The worthwhile remainder:

**Z-1  POSSIBLY RELEVANT TO A LIVE PROBLEM.**
  LOD Unloading Bug Fix - 61251             8281  Given the stranded flat
    billboard outside Whiterun, this name is worth checking BEFORE assuming
    the P-6 regeneration is the only fix. May not be the same bug - it is the
    first thing in 1519 mods that describes the symptom.
  Skyrim Cell load Freeze fix NG - 160704   7465
  SCROTE - script optimization - 97155      8202
  WIDeadBodyCleanupScript Crash Fix - 62413 8183
  Death Idle Fix - 152344                   7273

**Z-2  FOR A RENDERING TEST BED.**
  Photo Mode - 91701                        8693  free camera, DOF, framing.
    More useful here than the endorsement count suggests.
  Target Focus - 67996                      3191

**Z-3  SYSTEMS worth having.**
  Security Overhaul SKSE - Lock Variations - 58224  31794, plus Regional
    Locks - 62781 (18993) and Lock Add-ons - 59529 (18699). A three-part
    system, unusually high endorsements for something this quiet.
  Open World Loot - 49681                   6438
  Artificer - An Artifact Overhaul - 99619  5181
  Take a Peek - stealth mechanic - 66908    6650
  Lost Grimoire - 4455                      8297  spells
  Praedy's Staves AIO - 65481               4345
  Enhanced Reanimation - 43500              8608
  Sanguine Symphony - 148388                6775  combat
  NOTE: Pilgrim - A Religion Overhaul - 54099 (6971) overlaps WINTERSUN, which
  is installed. One per domain - do not take both without checking.

**Z-4  PILLAR 2 - free lane.**
  Koralina's Freckles and Moles 4k 2k - 62508  6126  directly relevant after
    the 09-08 freckle work
  Authentic Eyes - 36063                    5193
  Valkyr HDT-SMP Hairstyles - 63181         4625  and 02 - 64259 (4739)
  Weathered Nordic Bodypaints - 19594       7272
  Horns Are Forever - 1139                  6100

**Z-5  PILLAR 3 - free lane.**
  Face Masks of Skyrim - 1953               7623
  Pierced Ears - Earrings - 13571           5363
  Gold and Silver Reading Glasses - 120188  6119
  Wizard Hats - 2385                        4804
  Master Thief Armor 3BA-BHUNP - 141700     8604
  Gryphonknight Regalia SMP and PBR - 107437  8498
  Chevalier's Armor Set HDT-SMP - 132629    6814
  Reforging - To the Masses - 49030         4670

**Z-6  ANIMATION and BEHAVIOUR - free lane.**
  Nemesis Creature Behaviour Compatibility - 45966  14971
  EVG CLAMBER - Slope Animations - 114753   8774
  Pristine Vanilla Movement - 66635         8784
  Relaxed Sneak Animations - 37260          7978
  Open Animation Replacer - Math Plugin - 92607  4357

**Z-7  WORLD - gated, adds statics.**
  Farmhouse Chimneys SE - 8766              7057
  Simple Snow Improvements (BOS) - 78702    4016  REQUIRES Base Object Swapper
  Cathedral Snow - 18033                    4725
  Better Blended Mushrooms - 67725          3104
  Better Butterflies - 79332                3002
  TMD The Rift Leaves - 111461              3264
  GKB Waves - 19077                         5801
  Skyking Signs - 112902                    7787

## Housekeeping

**H-1** `SkyrimSE.exe.manifest` - dead file, verify then remove.
**H-2** `PreferExternalManifest` registry value - **verify only, do not write.**
        Steam files and the registry are off limits.
**H-3** SSE Display Tweaks still logging at debug level.
**H-4** `cleanup.ps1` written but never run.
**H-5** `DP_Extender.dll` fails to load every launch - diagnose or retire.
**H-6** Stale `meshes\armor\84_storm\head` in BodySlide Output from an earlier
        build. One file; sweep it with the next cleanup.
**H-8** `profiles\Default` holds roughly 250 timestamped `.bak` files written
by these scripts over 2026-09-06/07/08. Keep the newest few per file, drop the
rest.

**H-7** **Fresh character** once the stack settles. The current save carries
        orphaned scripts from everything removed during the crash hunt, and
        TAWoBA 9547's items are gone from it entirely.

---

## Tooling

Done: `bodyslide_pick.ps1` (replaced the prune), FOMOD support in
`install_mod.ps1`, `mo2_conflicts.ps1` (file conflicts without the MO2 UI),
`plugin_who.ps1` (record conflicts without xEdit), `install_mod.ps1 -KeepTop`
(stops new installs demoting BodySlide Output).

**T-1  A single `status.ps1`** - `nr_check` + `bodyslide_pick` dry run +
`bodyslide_coverage`, one command, one compact output, run before every launch.

**T-3  `plugin_who.ps1` does not scan the game's own masters.** It reads
plugins under `mods\` only, never `STOCK GAME\Data`. Found 2026-09-08: a
vampire-race query returned nine races edited by USSEP and omitted
`NordRaceVampire` and `BretonRaceVampire` entirely, because nothing in `mods\`
touches those two. A record whose only editor is a vanilla master currently
reads as "does not exist", which is the wrong answer to a conflict question.

**T-4  install_mod.ps1 could not find a Data root for behaviour-only mods.**
Found 2026-09-08 on First Person Animation Teleport Bug Fix (92795), whose
archive is nothing but `Nemesis_Engine\`. The descent heuristic looks for a
plugin, a BSA or a known Data subfolder, saw none, walked past the real root
and failed. `nemesis_engine`, `pandora_engine` and `fnis behavior` are now in
$DataDirs. Same shape will hit any behaviour patch that ships no plugin.

**T-2  Device bridge writes land one operation late.** Every commit is done
twice and verified by reading the file back. Three separate fixes silently
failed to reach disk before this was understood, including `skip_game=0`, which
meant an entire day of play on the wrong setting.

---

## Standing rules

**Off-Nexus downloads.** A mod host outside Nexus is only used when the link
comes from an ACTIVE, reputable page - a Nexus mod's requirements section, a
GitHub release. Never from a search result, never from recall, never from a
migration note more than a year old. Domains lapse and get bought. A fetch
that returns sensible-looking content is NOT verification: a clone and a
compromised site both read as normal. Added 2026-09-08 after vectorplexis.com
served a ClickFix fake-CAPTCHA malware page.

- **Skimpiest wins.** Encoded in `bodyslide_pick.ps1`'s `$ModPriority`. A
  milder replacer only ever wins an item nothing skimpier covers.
- **PGPatcher order is not negotiable** - see P-6.
- **Check every Community Shaders change against neural rendering** - `nr_check.ps1`.
- **Steam files and the registry are off limits.** No exceptions.
- **Verify every device write** by reading it back.
- **`BodySlide Output` stays at highest priority** - now automatic.
- **Static mesh changes invalidate LOD too**, not just plugin changes. Anything
  that adds or replaces world meshes - city overhauls, 3D wall replacements,
  tree mods - goes in BEFORE the TexGen/DynDOLOD run, never after. Skin, face
  and overlay mods do not, because actors are not in LOD.
- **Adding or removing ANY plugin invalidates tree LOD.** The engine unloads
  LOD by matching form ids; change the load order and billboards strand in
  loaded cells. Batch plugin changes, then regenerate once - never regenerate
  in the middle of an install run.

## FINDING - stale DynDOLOD is carrying a ghost mod   (2026-09-08)

  Reported in game as a bridge near Honningbrew Meadery that shows as a big
  wooden structure and then reverts to the vanilla stone bridge on a return
  visit. It is not two mods fighting, it is one mod that is half present.

  DynDOLOD.esp holds 45 REFR records in the Tamriel worldspace with editor ids
  shaped like northernroadsesp&03D4E7_Tamriel_DynDOLOD_REFERENCE. Those are LOD
  stand ins DynDOLOD generated from Northern Roads. But Northern Roads is
  DISABLED, line 247 of modlist.txt reads -Northern Roads, and Northern
  Roads.esp appears in neither plugins.txt nor loadorder.txt. So the LOD draws
  the wooden bridge at distance and the full model up close is vanilla stone.
  Northern Roads.esp is not even a master of DynDOLOD.esp, the references are
  orphaned outright.

  Why it was disabled is not recoverable. git log -S'Northern Roads' on
  modlist.txt returns only a9b49a0, the first commit, so it was already off
  before the repo existed.

  CORRECTION, same evening, an hour later. That paragraph is wrong and it is
  wrong in the way section 7 keeps warning about, a negative result from one
  search treated as absence. The reason WAS recorded, just not in the file I
  searched. DECISIONS.md has had an entry since the day it happened:

    Northern Roads (Nexus 77530) - disabled 2026-09-06. Not broken. Disabled
    because of a terrain seam at Whiterun's front gate, the dirt sat below the
    gate floor, producing a stone ledge you had to jump.

  It also says This one may come back, that several PBR landscape packs pair
  with Northern Roads or Blended Roads, that Vanaheimr includes Blended Roads
  so it does not need Northern Roads back, and that the trigger to revisit is
  the landscape choice changing. It is still in mods\ deliberately, because it
  is not dead. So this is the revisit condition, not a new idea.

  Matt also remembered Northern Roads as the mod that forced a bisect. It was
  not. The bisect was Jump Behavior Overhaul 36889, dropped 2026-09-08 after
  crashing every launch with a ucrtbase 0xc0000409 fastfail, and issues.md
  carries the five launch search. Two different mods, and Northern Roads never
  crashed anything.

  What is genuinely new since 09-06 is that ZERO of its patches were ever
  installed, and the Whiterun gate seam is exactly the class of defect its
  Patches Compendium exists to fix. Northern Roads - Fixes and Optimization is
  in there, so is a Landscape and Water Fixes patch and a Ryn's Whiterun City
  Limits patch. The 09-06 call was made against unpatched Northern Roads, which
  is not the same mod.

  Same root cause as the floating trees and the LOD tree standing in the
  Riverwood to Whiterun road. DynDOLOD Output is dated 2026-09-06 20:02 and
  five world mods landed after it, Alpine Forest of Whiterun Valley and
  Immersive Fallen Trees on 09-08 00:59, then Seasons of Skyrim SKSE and Turn
  of the Seasons on 09-08 20:57, then Terrain Helper at 21:07. Seasons in
  particular has a hard requirement on a DynDOLOD run made with seasons on,
  and ours predates it by two days.

  Matt wants the wooden bridges, so the exit is to re-enable Northern Roads
  rather than to regenerate it away. Order matters and the chain is long:
  Northern Roads 77530 v1.3.1 is already on disk at 593.8 MB, but ZERO of its
  patches are installed. Pull the one fits all Grass Patch from Miscellaneous
  on its file page first, because Folkvangr plus Grass Cache plus No Grass In
  Objects is exactly the setup that grows grass through roads. Then the Patch
  Collection and the Patches Compendium, checked against Alpine Forest of
  Whiterun Valley which edits the same valley. Then regenerate the grass cache,
  because the current cache was built without Northern Roads. Only then TexGen,
  DynDOLOD with seasons, and Occlusion.

  Bonus, and it lands on the Terrain Helper gap. Northern Roads v1.3 dropped
  road meshes entirely and paints every road as texture, which its author
  states is compatible with terrain parallax. It also declares itself
  compatible with Seasons of Skyrim. So it feeds the exact hole found the same
  night, Terrain Helper is installed but NOTHING declares TerrainHelper.esp as
  a master, so the terrain shader has no height data to read and the ground
  renders flat.
