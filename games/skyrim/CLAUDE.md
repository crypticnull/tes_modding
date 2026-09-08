# CLAUDE.md - Skyrim SE 1.6.1170, DLSS 5 neural rendering test bed

You are picking up a project that has been running for days across another
session. Everything that session learned is in this file and in `PLAN.md`.
Read both before touching anything. The single most expensive failure mode
here is confidently repeating a mistake that was already made and solved.

---

## 1. WHAT THIS IS

A Skyrim Special Edition 1.6.1170 install at `X:\MODDING\SKYRIM`, built as a
test bed for DLSS 5 / neural rendering, and built BY SCRIPT rather than by
clicking in Mod Organizer. Every install, every conflict check, every config
edit goes through a PowerShell script in `tools\`. The MO2 GUI is a viewer,
not the interface.

`PLAN.md` holds the pillars, the build order, and every open item. It is the
source of truth for WHAT is being built. This file is the source of truth for
HOW to work on it. **`NEXT.md` is the work queue** - the ordered list of what
to do next, with the commands, handed over from the previous session. Start
there once you have read this file. `INBOX.md` is the message channel between
sessions.

### Layout

```
X:\MODDING\SKYRIM\
  SKYRIM_SE\          the MO2 instance
    mods\<name>\      one folder per mod = what would sit in Data\, plus meta.ini
    downloads\        Nexus archives
    profiles\Default\ modlist.txt, plugins.txt, loadorder.txt
  STOCK GAME\         the actual game files MO2 launches against
  MO2\                Mod Organizer itself
  tools\              every script, PLAN.md, WORKING_CONFIG.md, DECISIONS.md
  logs\               script output
  data\               script state (API key, session cookies)
  _incoming\          staging for generated assets before install
  _retired\           dead scripts. The live tools\ folder is already clean.
  backups\
```

State as of 2026-09-08: 228 plugins, `check_masters.ps1` clean. CBBE 3BA body,
Community Shaders, DLSS, RaceMenu, Ordinator/Apocalypse/Odin/Wintersun/
Sacrosanct/Growl. The framework layer (SPID, KID, SkyPatcher, OAR, po3's
suite, MCM Helper, etc.) went in whole on 09-08.

---

## 2. HARD CONSTRAINTS - THESE ARE NOT NEGOTIABLE

**The Steam install and the Windows registry are off limits.** Matt was
explicit and profane about this. Do not modify, move, verify, downgrade or
"fix" anything under
`C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition`, and do
not write to the registry. Reading a directory listing for information is
fine. Anything else is not. The build runs against `STOCK GAME\`, which is a
separate copy and IS yours to change.

**Off-Nexus downloads require an active, reputable source.** A host outside
Nexus is used only when the link comes from a page you can see right now - a
Nexus mod's requirements section, a GitHub release. Never from a search
result, never from recall, never from a forum post or migration note more
than a year old. Domains lapse and get bought.
On 2026-09-08 this session recommended `vectorplexis.com` from a July 2022
Wabbajack issue. It had become a ClickFix fake-CAPTCHA malware page and it
served Matt an unsigned executable. A successful fetch returning
sensible-looking content is NOT verification - a clone and a compromised site
both read as normal. **Never send him to vectorplexis.com or
vectorplexus.com.** The first is malware, the second is dead.

**No credentials, no CAPTCHAs.** Do not enter his Nexus or LoversLab
credentials anywhere, do not attempt to solve or bypass a CAPTCHA, and do not
build a page that collects a login. The agreed pattern for authenticated
sites: he signs in himself, exports his session cookie, and `ips_get.ps1`
uses it.

(He has said explicitly he does not care about the Nexus API key sitting in
plaintext in `data\`. That is settled; do not re-raise it.)

---

## 3. HOW MO2 ACTUALLY WORKS - the model the scripts assume

- A mod is just a folder under `mods\` whose contents are what would otherwise
  be in `Data\`, plus a `meta.ini`. That is the entire format.
- `profiles\Default\modlist.txt`: **first line is HIGHEST priority.** Later
  lines lose file conflicts. `+` prefix = enabled, `-` = disabled.
- `meta.ini` carries `modid=` (the Nexus id) and `installationFile=`.
- MO2 redirects a write to an *existing* virtual file back into the mod that
  owns it. Only genuinely new files land in `Overwrite`. This is why
  `claim_overwrite.ps1` exists and why "nothing to claim" is a normal result.

---

## 4. THE LOD GATE RULE - the most important technical fact in the project

An earlier version of this said "any plugin gates behind the DynDOLOD run."
**That was wrong and it was blocking half the build.**

Sheson's actual mechanism: tree LOD unloads by matching FORM IDS, and it
breaks when the load order OF PLUGINS THAT ADD TREE REFERENCES changes.

**The real rule: world references and static meshes gate behind the chain.
Item and actor mods do not.**

FREE LANE - installable at any time, including after the chain has run:
weapons, armour, clothing, jewellery, books, instruments, creatures, mounts,
followers, audio, dialogue, UI, animation behaviour, skin/face/overlays, and
**interior-only overhauls** (interiors have no LOD at all).

GATED - must be decided before the chain runs: new worldspaces, city and
settlement overhauls, flora and grass, world statics, exterior structures,
dungeon and player-home *entrances*, and anything that places a new reference
in an exterior cell.

When in doubt, ask: does this plugin place a new object in an exterior cell,
or change a static mesh that LOD is baked from? If no, it is free lane.

### The generation chain, strict order

BodySlide -> PGPatcher -> Grass cache -> xLODGen terrain -> TexGen ->
DynDOLOD -> Occlusion.

- PGPatcher errors out if DynDOLOD output is active.
- Any PGPatcher run forces TexGen and DynDOLOD to be redone.
- **Seasons is confirmed and priced in.** It requires terrain LOD generated
  per season, so xLODGen runs five times (four seasons + default) and TexGen
  and DynDOLOD run with Seasons enabled. Stage 4 is hours, not ninety minutes.
  Seasons cannot be added retroactively.
- Because the chain is that expensive, every gated decision - seasons, the
  map mod, the city overhauls, the land mods - is made BEFORE it runs, once.

---

## 5. THE TOOLING

Everything lives in `X:\MODDING\SKYRIM\tools\`. All scripts take
`-Root 'X:\MODDING\SKYRIM'` implicitly and most are dry-run by default with
an `-Apply` switch. **Read a script's header comment before using it** - each
one documents its own traps.

| script | what it does |
|---|---|
| `install_mod.ps1` | the workhorse. Download + install + activate, no clicking. `-Mod <id>` / `-Archive <path>` / `-All`, `-Fomod "Group=Option; ..."`, `-FomodDefaults`, `-FomodPlan`, `-Name`, `-Bottom`, `-NoPlugins`, `-KeepTop` |
| `check_masters.ps1` | every plugin's masters present, active, correctly ordered. **Run after every install block.** |
| `mo2_conflicts.ps1` | file-level conflicts without the MO2 UI |
| `plugin_who.ps1` | which plugins edit a record, without opening xEdit |
| `nr_check.ps1` | neural rendering / DLSS config check |
| `bodyslide_pick.ps1` | picks the right body build per outfit mod, by rule |
| `bodyslide_coverage.ps1` / `bodyslide_conflicts.ps1` | what has no build, what fights |
| `claim_overwrite.ps1` | move Overwrite contents into the owning mod |
| `collection_diff.ps1` | diff a Nexus collection against this install (v2 GraphQL) |
| `fix_modids.ps1` | repair wrong/missing `modid=` in meta.ini. `-Restore` reverts |
| `ips_get.ps1` | cookie-authenticated downloader for LoversLab / IPS sites. `-Enumerate` lists a forum's file pages |
| `racemenu_overlays.ps1` | edits the winning `skee64.ini` overlay slot counts |
| `freckle_strength.ps1` | `-Level 0\|25\|50\|100` on the BnP complexion detail map |
| `working_config.ps1`, `toggle_mods.ps1`, `diag.ps1`, `display.ps1` | config and diagnostics |

`WORKING_CONFIG.md` is the known-good configuration. `DECISIONS.md` and the
decisions log in `PLAN.md` record what was settled and why - **do not
re-litigate anything in them.**

---

## 6. FACTS LEARNED THE HARD WAY

**PowerShell**
- `$ErrorActionPreference = 'Stop'` inside a called script: a `throw` in that
  script is terminating and will abort the CALLER's entire `foreach`. Wrap
  every call in a batch loop in `try/catch` or one bad mod kills the run.
- PowerShell's escape character is a backtick, not a backslash. `\"` ends a
  string early and the rest of the line is parsed as commands.
- Variable names are case-insensitive, so a local `$fomod` IS the `-Fomod`
  parameter. Assigning an array to a `[string]` parameter silently coerces it
  and `[0]` then returns the first CHARACTER.
- `HttpClient.DefaultRequestHeaders.Add` validates and throws on real browser
  cookie strings. Use `TryAddWithoutValidation`.
- Python f-strings cannot contain backslashes, which bites when generating
  PowerShell from Python.

**FOMODs**
- A DLL version group is listed NEWEST FIRST. `-FomodDefaults` takes the first
  option, which on this 1.6.1170 build installs a 1.7.x DLL. **Always name the
  runtime group explicitly.** Substring matching on `1.6.1170` is reliable.
- Option names rarely match what you would guess. `AIO` was actually
  `All-in-one`. The script errors rather than guessing, which is correct -
  read the printed option list and answer it.
- Groups can be hidden behind an earlier answer (BnP's "Body muscle selection"
  only appears after "Boob size"; the CC patch's Creations list disappears
  when Merged is chosen). A "named a group that does not exist" warning after
  a successful install usually means exactly that.
- Selecting a patch for a mod that is not installed produces a plugin with a
  missing master. Pass `-` to select none.

**Runtime-versioned SKSE plugins - TWO traps, not one**
- *In a FOMOD:* the DLL group is listed newest first. Named explicitly, always.
- *At file selection:* many SKSE plugins ship a SEPARATE MAIN FILE per runtime -
  1.7.99+, 1.6.629+, 1.6.318-353, 1.5.97 - and Nexus marks the NEWEST-runtime
  one as primary. `install_mod.ps1 -Mod <id>` takes the primary, which on this
  1.6.1170 build is the WRONG one. **Before installing any SKSE plugin, list
  its files (`nexus_get.ps1 -Mod <id>`) and check whether more than one MAIN
  file exists.** If it does, pass `-File <id>` for the 1.6.629+ build.
- The symptom is not a missing master and `check_masters.ps1` will not see it.
  It is a popup at launch: `AddressLibrary.cpp(...): Identifier not found,
  <number>`, naming the offending DLL.
- A mod FOLDER NAME containing "1.7.99" on this build is the tell. Sweep with:
  `Select-String -Path 'X:\MODDING\SKYRIM\SKYRIM_SE\mods\*\meta.ini' -Pattern 'installationFile=.*1\.7\.'`

**Nexus APIs**
- v1 REST `.../mods/md5_search/{md5}.json` returns EVERY mod page hosting a
  byte-identical file, not one answer. Corroborate against the id in the
  archive filename before trusting it.
- v2 GraphQL at `https://api.nexusmods.com/v2/graphql` with an `apikey` header
  serves `collectionRevision(slug, domainName, viewAdultContent)`.

**Textures**
- `femaleheaddetail_frekles.dds` is BnP's complexion detail map. Native range
  29-70; neutral is exactly RGB(63,63,63), the value of `blankdetailmap.dds`.
- DXT5 across a 41-level range produces compression noise comparable to the
  signal. Write variants of a detail map as 32-bit uncompressed.

**SKSE co-saves**
- Magic `SKSE`, then four uint32 (`formatVersion`, `skseVersion`,
  `runtimeVersion`, `pluginCount`), then per-plugin
  `signature`/`numChunks`/`length`, then chunks of `type`/`version`/`length`.
- RaceMenu's plugin signature reads as `EEKS` (SKEE reversed). Overlays live
  in `OVST` chunks; the string table is `BTTS`.

**The device bridge (only relevant to a remote session, not to Claude Code)**
- Writes land one operation late. Commit twice, then verify by reading back.
- Staging is capped at 7 folders below the connected root. The mods tree is 8,
  so nothing under `mods\<mod>\textures\actors\character\female` can be staged
  directly. A local Claude Code session has neither limitation, which is a
  large part of why the work moved here.

---

## 7. MISTAKES THAT WERE ACTUALLY MADE, AND WHAT THEY COST

These are here so you do not repeat them. Each one shipped a wrong result.

1. **`fix_modids.ps1` v1 corrupted three correct mod ids.** It took the first
   result from `md5_search` as truth. It overwrote SkyUI's 12604 with 181278
   and gave UIExtensions the same id. *Lesson: verifying that a write landed
   is not verifying that the value is right.* The fix was to require
   corroboration from the archive filename and never replace an existing id on
   a single unverified hash match - a wrong id silently matches another mod, a
   blank one is visibly unknown.
2. **BnP installed as the UNP build on a CBBE 3BA body.** The filename said
   `(UNP Player and Replacer)` and it was read past twice. Same class of error
   as Fashions Of The Banditry. *Lesson: read the body variant in the filename
   before installing anything that touches the body.*
3. **Towels installed as the UBE variant.** Found only because
   `check_masters.ps1` caught a dead `Towels UBE patch.esp` - its meshes were
   inside a BSA, so the loose-file coverage scan never saw them. *Lesson: a
   BSA hides a mod from file-level scans.*
4. **vectorplexis.com.** Covered in section 2. The worst one.
5. **A wrong claim about Gate To Sovngarde's spell visuals**, made from a
   keyword hunt that never searched the obvious terms. The data contradicted
   it. *Lesson: a negative result from your own search is not evidence of
   absence; say which terms you searched.*
6. **Recommended Conditional Expressions, then chose OStim, which lists it as
   incompatible.** Caught two messages later. *Lesson: when a spine decision
   lands, re-check the recommendations already made against it.*
7. **Read a stale container mirror of `tools\` and told him twenty superseded
   scripts needed clearing.** They had already been retired. *Lesson: list the
   real directory, not a cached copy.*
8. **Installed the 1.7.99+ builds of Actor Limit Fix (32349) and Bug Fixes SSE
   (33261) on a 1.6.1170 game.** Both ship four main files, one per runtime,
   with the newest-runtime build flagged primary; `-Mod <id>` took the primary.
   It passed `check_masters.ps1` clean and only surfaced as an
   `AddressLibrary.cpp: Identifier not found` popup on the first SKSE launch.
   *Lesson: the FOMOD DLL-version trap has a twin at the file-selection level,
   and the FOMOD guard does not cover it. See the runtime-versioned plugin
   entry in section 6.*
9. **An artifact rewrite would have silently dropped the entire decisions
   log**, caught only because the publish was refused for not having read the
   live version. *Lesson: merge, never replace, a document that accumulates.*

---

## 8. HOW MATT WANTS TO WORK

- He is technical. Do not over-explain, and do not pad. He will correct you.
- **Real assessments, not encouragement.** He has explicitly rejected the
  "yeah totally dude" register and will distrust everything after it. If a
  plan is bad, say so.
- For any bulk file or data task, **write one script that produces one compact
  output file and read that.** Never explore interactively with repeated tool
  calls.
- **Validate generated code before shipping it** - name collisions, syntax,
  dry run. Do not make him hit the bug.
- **Self-clean loose ends without being asked.** Retire superseded scripts,
  prune stale backups, close out anything half-done.
- State the approach briefly and start. Do not make him direct the method.
- Deliver what was asked for, not extra reports or polish.
- Scope compatibility checks proportionately - a candidate's own stated
  requirements plus mods in domains that could plausibly collide, not every
  item against every other.
- **Shell commands: every command for a step in ONE block, always complete
  absolute paths, never a variable set in an earlier block.** He is often in a
  fresh window. This one was learned the hard way.
- When he pastes script output, he pastes the filtered summary sections, not
  whole transcripts. Design your scripts to print a compact summary at the end.

---

## 9. THE TWO-AGENT PROTOCOL

There are two Claude sessions on this project:

- **CODE** - Claude Code, running locally on the Windows machine. Runs the
  scripts, reads the logs, does the installs and the generation chain.
  This is the primary session.
- **CHAT** - a Cowork session, which maintains the published build-plan
  artifact and can be reached from Matt's phone. Secondary, and being wound
  down.

Both read and write the same files. The rules:

1. **`PLAN.md` is the shared source of truth.** Either side may edit it.
   Edit in place, never rewrite wholesale - it accumulates history and a clean
   rewrite has already nearly destroyed the decisions log once.
2. **`INBOX.md` is the message channel.** Append-only. When you change
   something the other side needs to know about, append an entry. Read it at
   the start of a session and after any long-running job. Format is at the top
   of that file.
3. **Never delete another side's entry.** Mark it handled instead.
4. **`NEXT.md` is the work queue.** Either side may reorder or extend it.
   Strike items as they are finished rather than deleting them, so the next
   session can see what was already done and in what order.
5. **`build-plan.html`** at the root is a snapshot of the published artifact,
   for reference. CHAT owns the live version; CODE should read it but not
   try to publish it.
6. Anything that changes the load order, the profile, or the generation chain
   gets an INBOX entry. Routine reads do not.

---

## 10. WHERE THINGS STAND - 2026-09-08

Read `PLAN.md` for the full picture. In brief:

- **Done:** the character/skin/face pass, the wardrobe pass, the framework
  layer (46 mods), the movement + reactivity block (in progress at handoff),
  AI Overhaul via the SPID/SkyPatcher route.
- **Open decisions:** the UI pick (Untarnished 75188 / Norden 166086 /
  Oathvein 160916 / Vel'dun 176230 - he is reviewing galleries); a combat
  moveset overhaul (MCO / BFCO) and whether to add a behaviour engine
  (Pandora); Alternate Perspective 50307 as a swap for Alternate Start.
- **Open tasks:** seasons patches for six tree/flora mods (S3DTrees
  NextGenerationForests, Nature of the Wild Lands, Blubbo aspens, Folkvangr,
  Alpine Forest of Whiterun Valley, Bent Pines) - if most lack one, raise it
  BEFORE the chain runs; verify Toys&Love 63512 against OStim Standalone
  98163; verify overlays in game via RaceMenu Face Paint (the co-save showed
  all slots empty); check LOD Unloading Bug Fix 61251 against the stranded
  Whiterun billboard; Simply Knock 14098 has no confirmed 1.6.1170 DLL.
- **Housekeeping:** ~250 stale `.bak` files in `profiles\Default`; a disabled
  `Towels UBE` mod folder and a BnP UNP archive to remove.
- **Not yet started:** the LoversLab pass (method is in PLAN.md section A-3 -
  he browses signed in, sends file page URLs, `ips_get.ps1` fetches them);
  the graphics package; the generation chain itself.
