# CLAUDE.md - Skyrim SE 1.6.1170, DLSS 5 neural rendering test bed

This is the single handoff file. It supersedes the old `NEXT.md` and the
two-agent `INBOX.md` protocol, both of which are retired. Read this, then
`tools\PLAN.md` for the deep history and the decisions log.

You are picking up a project that has run for days across several sessions.
The single most expensive failure mode here is confidently repeating a mistake
that was already made and solved, so sections 2, 6 and 7 are the ones that
actually save you time.

Last updated 2026-09-08 19:00 ET.

---

## 1. WHAT THIS IS, AND WHERE IT STANDS

A Skyrim Special Edition 1.6.1170 install at `X:\MODDING\SKYRIM`, built as a
test bed for DLSS 5 and neural rendering, and built BY SCRIPT rather than by
clicking in Mod Organizer. Every install, every conflict check, every config
edit goes through a PowerShell script in `tools\`. The MO2 GUI is a viewer,
not the interface.

### State as of 2026-09-08 19:00 ET

| what | value |
|---|---|
| plugins | 262, `check_masters.ps1` clean |
| mod folders | 220, 214 enabled, 6 disabled |
| `check_order.ps1` | 0 violations, verified after a real LOOT sort |
| `runtime_check.ps1` | 0 wrong-runtime, 2 wrong-but-disabled, 7 covered ok |
| SKSE launch | boots to the game window, no AddressLibrary popup |

CBBE 3BA body, Community Shaders, DLSS, RaceMenu, Ordinator, Apocalypse, Odin,
Wintersun, Sacrosanct, Growl. The framework layer of SPID, KID, SkyPatcher,
OAR, po3's suite and MCM Helper went in whole on 09-08. The movement and
reactivity block and AI Overhaul via the SPID and SkyPatcher route are in.

### Layout

```
X:\MODDING\               the git working tree, see section 9
  SKYRIM\
    SKYRIM_SE\            the MO2 instance
      mods\<name>\        one folder per mod = what would sit in Data\, plus meta.ini
      downloads\          Nexus archives
      profiles\Default\   modlist.txt, plugins.txt, loadorder.txt
    STOCK GAME\           the actual game files MO2 launches against
    MO2\                  Mod Organizer itself, plus its bundled loot\lootcli.exe
    tools\                every script, PLAN.md, WORKING_CONFIG.md, DECISIONS.md
    logs\                 script output
    data\                 script state, holds .nexus_api_key, git-ignored
    _incoming\            staging for generated assets before install
    _retired\             dead scripts. The live tools\ folder is already clean.
    backups\
  OBLIVION\               a second, separate build. Not this project.
```

---

## 2. HARD CONSTRAINTS - THESE ARE NOT NEGOTIABLE

**The Steam install and the Windows registry are off limits.** Matt was
explicit and profane about this. Do not modify, move, verify, downgrade or
"fix" anything under
`C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition`, and do
not write to the registry. Reading a directory listing for information is
fine. Anything else is not. The build runs against `STOCK GAME\`, which is a
separate copy and IS yours to change.

Two live tripwires on this constraint, both found on 09-08:

- **Do not run standalone `LOOT.exe`.** `LOOTDebugLog.txt` shows it builds its
  game handle against the Steam path, not `STOCK GAME`. Sort from inside MO2,
  which runs its own bundled `loot\lootcli.exe` under the usvfs. See section 6.
- **`clean_masters.ps1` can leave the Steam install modified.** Open bug, see
  section 10. It is needed before DynDOLOD, so it has to be fixed first.

**Off-Nexus downloads require an active, reputable source.** A host outside
Nexus is used only when the link comes from a page you can see right now, such
as a Nexus mod's requirements section or a GitHub release. Never from a search
result, never from recall, never from a forum post or migration note more than
a year old. Domains lapse and get bought.

On 2026-09-08 a session recommended `vectorplexis.com` from a July 2022
Wabbajack issue. It had become a ClickFix fake-CAPTCHA malware page and it
served Matt an unsigned executable. A successful fetch returning
sensible-looking content is NOT verification, because a clone and a
compromised site both read as normal. **Never send him to vectorplexis.com or
vectorplexus.com.** The first is malware, the second is dead.

**No credentials, no CAPTCHAs.** Do not enter his Nexus or LoversLab
credentials anywhere, do not attempt to solve or bypass a CAPTCHA, and do not
build a page that collects a login. The agreed pattern for authenticated sites
is that he signs in himself, exports his session cookie, and `ips_get.ps1`
uses it.

He has said explicitly he does not care about the Nexus API key sitting in
plaintext in `data\`. That is settled, do not re-raise it. `data\` is
git-ignored so it never reaches the archive.

---

## 3. HOW MO2 ACTUALLY WORKS - the model the scripts assume

- A mod is just a folder under `mods\` whose contents are what would otherwise
  be in `Data\`, plus a `meta.ini`. That is the entire format.
- `profiles\Default\modlist.txt`: **first line is HIGHEST priority.** Later
  lines lose file conflicts. `+` prefix is enabled, `-` is disabled.
- `meta.ini` carries `modid=` and `installationFile=`.
- MO2 redirects a write to an *existing* virtual file back into the mod that
  owns it. Only genuinely new files land in `Overwrite`. This is why
  `claim_overwrite.ps1` exists and why "nothing to claim" is a normal result.
- **MO2 holds the plugin list in memory and writes it on exit.** Editing
  `loadorder.txt` or `plugins.txt` while MO2 is open gets silently overwritten
  when it closes. Close MO2 before touching those files, every time.
- **"Refresh" is not "Sort".** Refresh, or F5, only rescans mod folders for
  filesystem changes and never touches load order. Sort is the LOOT-icon
  button at the bottom of the right-hand Plugins pane.

---

## 4. THE LOD GATE RULE - the most important technical fact in the project

An earlier version of this said "any plugin gates behind the DynDOLOD run."
**That was wrong and it was blocking half the build.**

Sheson's actual mechanism: tree LOD unloads by matching FORM IDS, and it
breaks when the load order OF PLUGINS THAT ADD TREE REFERENCES changes.

**The real rule: world references and static meshes gate behind the chain.
Item and actor mods do not.**

FREE LANE, installable at any time including after the chain has run: weapons,
armour, clothing, jewellery, books, instruments, creatures, mounts, followers,
audio, dialogue, UI, animation behaviour, skin, face, overlays, and
**interior-only overhauls**, because interiors have no LOD at all.

GATED, must be decided before the chain runs: new worldspaces, city and
settlement overhauls, flora and grass, world statics, exterior structures,
dungeon and player-home *entrances*, and anything that places a new reference
in an exterior cell.

When in doubt, ask: does this plugin place a new object in an exterior cell,
or change a static mesh that LOD is baked from? If no, it is free lane.

### The generation chain, strict order

BodySlide, then PGPatcher, then Grass cache, then xLODGen terrain, then
TexGen, then DynDOLOD, then Occlusion.

- PGPatcher errors out if DynDOLOD output is active.
- Any PGPatcher run forces TexGen and DynDOLOD to be redone.
- **Seasons is confirmed and priced in.** It requires terrain LOD generated
  per season, so xLODGen runs five times, four seasons plus default, and
  TexGen and DynDOLOD run with Seasons enabled. That stage is hours, not
  ninety minutes. Seasons cannot be added retroactively.
- Because the chain is that expensive, every gated decision is made BEFORE it
  runs, once.

---

## 5. THE TOOLING

Everything lives in `X:\MODDING\SKYRIM\tools\`. All scripts take
`-Root 'X:\MODDING\SKYRIM'` implicitly and most are dry-run by default with an
`-Apply` switch. **Read a script's header comment before using it**, each one
documents its own traps.

| script | what it does |
|---|---|
| `install_mod.ps1` | the workhorse. Download, install and activate, no clicking. `-Mod <id>` / `-Archive <path>` / `-All`, `-File <id>`, `-Fomod "Group=Option; ..."`, `-FomodDefaults`, `-FomodPlan`, `-Name`, `-Bottom`, `-NoPlugins`, `-KeepTop` |
| `nexus_get.ps1` | list a mod's files. **Run this before installing any SKSE plugin**, see section 6 |
| `check_masters.ps1` | every plugin's masters present, active, correctly ordered. Run after every install block |
| `check_order.ps1` | asserts the conflict-winner ordering rules that `check_masters` cannot see. Exit 1 on violation. **Run after any sort** |
| `runtime_check.ps1` | flags SKSE plugins installed as the wrong runtime build |
| `launch_check.ps1` | launches through MO2, reads and answers SKSE error dialogs itself, reports. Unattended |
| `deploy_loot_rules.ps1` | installs `tools\loot-userlist.yaml` into LOOT's data directory |
| `mo2_conflicts.ps1` | file-level conflicts without the MO2 UI |
| `plugin_who.ps1` | which plugins edit a record, without opening xEdit |
| `nr_check.ps1` | neural rendering and DLSS config check |
| `bodyslide_pick.ps1` | picks the right body build per outfit mod, by rule |
| `bodyslide_coverage.ps1` / `bodyslide_conflicts.ps1` | what has no build, what fights |
| `claim_overwrite.ps1` | move Overwrite contents into the owning mod |
| `collection_diff.ps1` | diff a Nexus collection against this install, v2 GraphQL |
| `fix_modids.ps1` | repair wrong or missing `modid=` in meta.ini. `-Restore` reverts |
| `clean_masters.ps1` | **HAS AN OPEN BUG, see section 10 before running** |
| `ips_get.ps1` | cookie-authenticated downloader for LoversLab and IPS sites. `-Enumerate` lists a forum's file pages |
| `racemenu_overlays.ps1` | edits the winning `skee64.ini` overlay slot counts |
| `freckle_strength.ps1` | `-Level 0\|25\|50\|100` on the BnP complexion detail map |
| `working_config.ps1`, `toggle_mods.ps1`, `diag.ps1`, `display.ps1` | config and diagnostics |

`WORKING_CONFIG.md` is the known-good configuration. `DECISIONS.md` and the
decisions log in `PLAN.md` record what was settled and why. **Do not
re-litigate anything in them.**

`tools\loot-userlist.yaml` is the tracked master copy of the LOOT user rules.
LOOT's live copy lives in `%LOCALAPPDATA%` which is outside the archive, so
the tracked copy is the source of truth and `deploy_loot_rules.ps1` pushes it.

---

## 6. FACTS LEARNED THE HARD WAY

### Verification, the meta-lesson

On 09-08 three separate checks passed on a broken system, each measuring
something adjacent to the property that mattered. `check_masters` passed with
a wrong-runtime DLL present because it only tests masters. It passed again
with AI Overhaul at the bottom of the load order, because both orders are
master-legal and the question was which mod wins a conflict, not whether
masters resolve. And `check_order` passed before a sort had run, because it
re-read the file that had just been hand-edited.

**A check that passes when the mechanism is switched off is not a check.** If
the thing under test is already in the desired state, a passing result cannot
distinguish "the mechanism worked" from "the mechanism never ran". Break it on
purpose, confirm the check fails, then fix it and confirm the check passes.
That is how the LOOT rule was actually proved.

### Runtime-versioned SKSE plugins, TWO traps not one

- *In a FOMOD:* the DLL version group is listed NEWEST FIRST. `-FomodDefaults`
  takes the first option, which on this 1.6.1170 build installs a 1.7.x DLL.
  **Always name the runtime group explicitly.** Substring matching on
  `1.6.1170` is reliable.
- *At file selection:* many SKSE plugins ship a SEPARATE MAIN FILE per runtime,
  1.7.99+, 1.6.629+, 1.6.318-353, 1.5.97, and Nexus marks the NEWEST-runtime
  one as primary. `install_mod.ps1 -Mod <id>` takes the primary, which on this
  build is the WRONG one. **Before installing any SKSE plugin run
  `nexus_get.ps1 -Mod <id>` and check whether more than one MAIN file exists.**
  If it does, pass `-File <id>` for the 1.6.629+ build. 1170 sits inside that
  range.
- The symptom is not a missing master and `check_masters.ps1` will not see it.
  It is a popup at launch reading `AddressLibrary.cpp(...): Identifier not
  found, <number>`, naming the offending DLL.
- `runtime_check.ps1` catches this class, but only when the installation
  filename carries a version token. **To Your Face AE carried none and was
  invisible to it.** The mod that finally caught that was `launch_check.ps1`,
  because it asks the game rather than the filename.
- Known-good and NOT to be touched, 1170 is inside their ranges: Scrambled
  Bugs, Equip Enchantment Fix, Immersive Equipment Displays, Simple Dual
  Sheath, and Address Library All in One v13, which carries every database.

### SKSE and launching

- **SKSE writes `skse64.log` PAST the plugin-failure gate.** Answering the
  "Exit game? (yes highly suggested)" dialog with Yes destroys the evidence and
  names only the first bad DLL. `launch_check.ps1` clicks No by default, which
  is safe for a boot-to-main-menu because no save is loaded, and it surfaces
  every failing plugin in one run.
- Reading a dialog owned by another process needs `SendMessage WM_GETTEXT`.
  `GetWindowText` returns empty for a child control in another process, so
  `Get-Process | Select-Object MainWindowTitle` cannot read a dialog body.

### LOOT and sorting

- MO2 sorts with its own bundled `MO2\...\loot\lootcli.exe` running inside the
  usvfs, which is the only way anything sees `mods\` as a populated Data
  folder. Standalone `LOOT.exe` points at the Steam install, see section 2.
- **A sort writes NO entry to `mo_interface.log` at default verbosity.** Using
  that log to decide whether a sort ran gives a false negative. The reliable
  signals are the mtime on `profiles\Default\loadorder.txt` and whether the
  order actually moved.
- LOOT has no "before" key. To say "A loads before B" you write the rule on B
  as `after: [A]`.
- A plugin is always ordered after its masters, so a patch whose parent is a
  master needs no rule.
- `lockedorder.txt` being empty means nothing is pinned, so a hand-sort will be
  undone by the next sort. Declare the constraint in `loot-userlist.yaml`
  instead.

### PowerShell

- `$ErrorActionPreference = 'Stop'` inside a called script means a `throw`
  there is terminating and will abort the CALLER's entire `foreach`. Wrap every
  call in a batch loop in `try/catch` or one bad mod kills the run.
- The escape character is a backtick, not a backslash. `\"` ends a string early
  and the rest of the line is parsed as commands.
- Variable names are case-insensitive, so a local `$fomod` IS the `-Fomod`
  parameter. Assigning an array to a `[string]` parameter silently coerces it
  and `[0]` then returns the first CHARACTER.
- `Set-Content -Encoding UTF8` on PowerShell 5.1 writes a BOM. MO2 will not
  read `modlist.txt`, `plugins.txt` or `meta.ini` with one. Always use
  `[IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding $false))`.
- `HttpClient.DefaultRequestHeaders.Add` validates and throws on real browser
  cookie strings. Use `TryAddWithoutValidation`.
- Python f-strings cannot contain backslashes, which bites when generating
  PowerShell from Python.
- Validate a generated script before running it, with
  `[System.Management.Automation.Language.Parser]::ParseFile` and, for an
  `Add-Type` block, by compiling it once on its own.

### FOMODs

- A DLL version group is listed NEWEST FIRST. Name it explicitly, always.
- Option names rarely match what you would guess. `AIO` was actually
  `All-in-one`. The script errors rather than guessing, which is correct, so
  read the printed option list and answer it.
- Groups can be hidden behind an earlier answer. BnP's "Body muscle selection"
  only appears after "Boob size", and the CC patch's Creations list disappears
  when Merged is chosen. A "named a group that does not exist" warning after a
  successful install usually means exactly that.
- Selecting a patch for a mod that is not installed produces a plugin with a
  missing master. Pass `-` to select none.

### Nexus APIs

- v1 REST `.../mods/md5_search/{md5}.json` returns EVERY mod page hosting a
  byte-identical file, not one answer. Corroborate against the id in the
  archive filename before trusting it.
- v2 GraphQL at `https://api.nexusmods.com/v2/graphql` with an `apikey` header
  serves `collectionRevision(slug, domainName, viewAdultContent)`.

### Textures and co-saves

- `femaleheaddetail_frekles.dds` is BnP's complexion detail map. Native range
  29 to 70, neutral is exactly RGB 63,63,63, the value of `blankdetailmap.dds`.
- DXT5 across a 41-level range produces compression noise comparable to the
  signal, so write variants of a detail map as 32-bit uncompressed.
- SKSE co-save format: magic `SKSE`, then four uint32 of `formatVersion`,
  `skseVersion`, `runtimeVersion` and `pluginCount`, then per-plugin
  `signature`, `numChunks`, `length`, then chunks of `type`, `version`,
  `length`. RaceMenu's signature reads as `EEKS`, which is SKEE reversed.
  Overlays live in `OVST` chunks and the string table is `BTTS`.

---

## 7. MISTAKES THAT WERE ACTUALLY MADE, AND WHAT THEY COST

These are here so you do not repeat them. Each one shipped a wrong result.

1. **`fix_modids.ps1` v1 corrupted three correct mod ids.** It took the first
   `md5_search` result as truth, overwrote SkyUI's 12604 with 181278 and gave
   UIExtensions the same id. *Lesson: verifying that a write landed is not
   verifying that the value is right.*
2. **BnP installed as the UNP build on a CBBE 3BA body.** The filename said
   `(UNP Player and Replacer)` and it was read past twice. *Lesson: read the
   body variant in the filename before installing anything that touches the
   body.*
3. **Towels installed as the UBE variant.** Found only because
   `check_masters.ps1` caught a dead `Towels UBE patch.esp`, since its meshes
   were inside a BSA and the loose-file scan never saw them. *Lesson: a BSA
   hides a mod from file-level scans.*
4. **vectorplexis.com.** Covered in section 2. The worst one.
5. **A wrong claim about Gate To Sovngarde's spell visuals**, made from a
   keyword hunt that never searched the obvious terms. *Lesson: a negative
   result from your own search is not evidence of absence, so say which terms
   you searched.*
6. **Recommended Conditional Expressions, then chose OStim, which lists it as
   incompatible.** *Lesson: when a spine decision lands, re-check the
   recommendations already made against it.*
7. **Read a stale container mirror of `tools\`** and reported twenty
   superseded scripts needing clearing. They had already been retired.
   *Lesson: list the real directory, not a cached copy.*
8. **Installed the 1.7.99+ builds of Actor Limit Fix and Bug Fixes SSE on a
   1.6.1170 game.** Passed `check_masters` clean and only surfaced as an
   AddressLibrary popup on the first SKSE launch. *Lesson: the FOMOD
   DLL-version trap has a twin at file selection, and the FOMOD guard does not
   cover it.* Fixed 09-08.
9. **An artifact rewrite would have silently dropped the entire decisions
   log**, caught only because the publish was refused for not having read the
   live version. *Lesson: merge, never replace, a document that accumulates.
   This is why `PLAN.md` is still a separate file.*
10. **Concluded "no sort has run" from `mo_interface.log`.** MO2 does not log
    `lootcli` at default verbosity, so it was a false negative on a sort that
    genuinely had not run yet, then would have been a false negative on one
    that had. *Lesson: confirm which signals a tool actually emits before
    treating silence as evidence.*

---

## 8. HOW MATT WANTS TO WORK

- He is technical. Do not over-explain, and do not pad. He will correct you.
- **Real assessments, not encouragement.** He has explicitly rejected the
  "yeah totally dude" register and will distrust everything after it. If a
  plan is bad, say so. If he proposes something unnecessary, say that too.
- For any bulk file or data task, **write one script that produces one compact
  output file and read that.** Never explore interactively with repeated tool
  calls.
- **Validate generated code before shipping it.** Name collisions, syntax, dry
  run. Do not make him hit the bug.
- **Self-clean loose ends without being asked.** Retire superseded scripts,
  prune stale backups, close out anything half-done.
- State the approach briefly and start. Do not make him direct the method.
- Deliver what was asked for, not extra reports or polish.
- Scope compatibility checks proportionately. A candidate's own stated
  requirements plus mods in domains that could plausibly collide, not every
  item against every other.
- **Shell commands: every command for a step in ONE block, always complete
  absolute paths, never a variable set in an earlier block.** He is often in a
  fresh window. This one was learned the hard way.
- When he pastes script output he pastes the filtered summary sections, not
  whole transcripts, so design scripts to print a compact summary at the end.
- **Do not make him babysit a GUI.** If a check needs a human watching for a
  popup, automate the popup. `launch_check.ps1` exists because of this. The
  only clicks he should ever need are ones genuinely undrivable, and MO2's
  Sort button is currently the only known one.

### Time

US Eastern, UTC-4 on daylight time and UTC-5 in winter. Use his clock. After
8pm his time, UTC has already rolled to tomorrow, so date commits, logs and
snapshots by the evening the work happened, not by UTC.

### Writing, for files in this repo

No em dashes. No semicolons, parentheses, ellipses or bullet lists inside
prose. Comma-chained sentences of medium length, contractions throughout, "but"
as the main connector. No corporate vocabulary. Headings, tables and list
blocks are fine, this rule is about sentences.

---

## 9. HOW THIS PROJECT IS RUN NOW

**One local Claude Code session on the Windows machine. That is it.**

The old two-agent CODE and CHAT protocol is **retired**. A cloud or Cowork
session cannot reach `X:\MODDING`, cannot run a script, and on 2026-09-08 could
not even reach Nexus through its egress proxy. It produced good audits, but
every finding still queued up for a local session to execute, and the sync cost
rebases, a merge conflict and an INBOX entry that sat unread on a branch for
three hours. Not worth it.

If a second session is ever spun up again, it reads only. It does not write
files and it does not push.

### Git

`X:\MODDING` **is** the working tree. There is no separate checkout and nothing
is ever copied between a folder and a repo. Remote is
`https://github.com/crypticnull/tes_modding` on branch
`claude/skyrim-oblivion-modlist-archive-489zub`.

Git earns its place here because this build breaks silently. A `git diff` on
`SKYRIM/SKYRIM_SE/profiles/Default/loadorder.txt` says exactly what a sort
moved, which is the only cheap way to catch a reordering at 262 plugins. The
tracked set is about 2.7 MB of text.

- **Commit after anything that changes the load order, the profile, a script
  or a decision.** Routine reads do not need one.
- The commit message IS the changelog now that `INBOX.md` is retired. Write it
  properly, explaining why, not just what.
- `.gitignore` excludes all bulk data. If a `git status` ever shows thousands
  of untracked files, stop and fix the ignore file rather than committing.
- Two exclusions that are easy to get wrong: `SKYRIM/tools` is tracked for its
  scripts but `tools/DynDOLOD` at 2.5 GB and `tools/xEdit` at 128 MB are
  ignored, and the script backups are named `.bak-<timestamp>` so a bare
  `*.bak` pattern matches none of them.
- The remote is optional. It is free off-machine backup for a few megabytes of
  text. Dropping it is `git remote remove origin` and local history still works.

### Ground rules

- Snapshots under `snapshots\` are immutable. Never edit one, take a new one.
- Never claim a mod is installed, a conflict is resolved or a load order is
  correct without a log, a snapshot or a script result backing it. Guesses get
  labelled as guesses.
- No mod archives, game files, BSAs or ESPs in git. Text only.
- Ask before adding a dependency. The scripts are plain PowerShell 5.1 with no
  modules on purpose, keep it that way.
- Prefer boring. This runs for years across many sessions, so plain text,
  stable paths and no clever tooling that needs maintenance.

---

## 10. THE WORK QUEUE

Close MO2 before running anything that installs. `install_mod.ps1` refuses
while `ModOrganizer.exe` is running, which is correct, not a bug.

### DONE, do not redo

- ~~**Wrong-runtime SKSE plugins.**~~ Closed 09-08. Bug Fixes SSE 33261 as file
  368384 and Actor Limit Fix 32349 as file 368385, both the "1.6.629.0 and
  later" build. Both 1.7.99 folders disabled. Verified by `runtime_check.ps1`
  and a clean SKSE boot.
- ~~**AI Overhaul before Bijin.**~~ Closed 09-08. It was wrong, sitting at 251
  of 262 behind all four Bijin plugins. Now declared in `loot-userlist.yaml`
  and **proved by perturbation**, LOOT pulled it from 260 back to 136 on its
  own. Re-check with `check_order.ps1` after any sort.
- ~~**To Your Face AE 24720.**~~ Disabled 09-08. Fails SKSE's own version gate
  and 1.0v is already the newest AE build, so there is nothing to swap to.
  Same category as Simply Knock. DLL-only, so no master impact.

### A. Fix `clean_masters.ps1` before anything else

It is needed before DynDOLOD and it currently risks the one hard constraint.

1. **It can leave the Steam install modified.** Its own header notes xEdit has
   been observed cleaning the Steam copy even when pointed elsewhere, and the
   script detects that by hashing both copies. But when Steam is the one that
   changed, it only copies the cleaned file OUT into `mods\Cleaned Masters`.
   Nothing restores the Steam copy and no backup is taken first. Probably has
   not fired yet, since `Where=Steam` in the summary table would have been
   noticed. Fix proposal is in `SKYRIM/issues.md`.
2. **Line 143 writes `meta.ini` with `Set-Content -Encoding UTF8`**, so a BOM
   lands ahead of `[General]` and MO2 reads the mod as having no metadata. One
   line, and it is the last straggler. Every other script already uses
   `WriteAllLines` with a no-BOM encoder.

### B. Finish the pending install block

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
& 'X:\MODDING\SKYRIM\tools\launch_check.ps1'
```

**PAPER 73849 is the open risk.** v2.2.4, last updated July 2023, page states
SE 1.5.97 and AE 1.6.353 with community reports of 1.6.6xx+ working. It does
not state 1.6.1170. It is Address Library based and the AiO covers 1170, so it
should resolve, but verify with `launch_check.ps1` rather than assuming.

If PAPER does not load, both EBT companions have non-SPID main files, mod 76767
"Optimised Scripts, Non-SPID version" and mod 56560 "EBT SE Settings Loader",
and EBT itself reinstalls with `SPID Compatibility=Standard Install with Long
Distance`. The Settings Loader must load AFTER the optimised scripts or it
loses the file conflict.

### C. Seasons patches for the flora mods, BEFORE the chain

Seasons is CONFIRMED and cannot be added after the chain runs, so every tree
and flora mod needs a seasons patch or it stays summer forever. **If most of
them lack one, raise it with Matt before the chain runs**, because it may
change whether Seasons is worth the five terrain generations.

Ids confirmed from the 09-08 snapshot: Skyrim 3D Trees and Plants 12371,
Nature of the Wild Lands 63604, Blubbo aspen replacer 85233, Folkvangr 44899,
Alpine Forest of Whiterun Valley 18866, Bent Pines II 8306. **Immersive Fallen
Trees 8767 is installed too and is in the same boat**, it was missing from the
old queue.

### D. Verification tasks carried over

- **Overlays are not confirmed working in game.** `racemenu_overlays.ps1`
  raised the slot counts and verified by read-back, but the SKSE co-save showed
  every `OVST` slot empty. Check RaceMenu, then Face Paint, in game.
- **Toys and Love 63512 against OStim Standalone 98163**, coexistence is
  UNVERIFIED. OStim is the decided spine, Toys and Love was only ever
  interesting for its bondage half. Verify before installing either together.
- **LOD Unloading Bug Fix 61251** against the stranded Whiterun billboard.
- **Simply Knock 14098** has no confirmed 1.6.1170 DLL. Confirm or drop it.
- **`plugin_who.ps1` does not scan `STOCK GAME\Data`**, so any record whose
  only editor is a vanilla master reads as "does not exist". That produced a
  wrong answer once already, on vampire races.
- **`DP_Extender.dll` fails to load every launch.** Now that
  `launch_check.ps1` exists, run it and read the dialog rather than guessing.

### E. Housekeeping

- Roughly 450 timestamped `.bak-*` files in `SKYRIM_SE\profiles\Default`. Keep
  the newest two or three per file, drop the rest. They are git-ignored, so
  this is disk hygiene only.
- The disabled `Towels UBE` mod folder and the BnP **UNP** archive in
  `downloads\`, both wrong-variant leftovers, both already replaced.
- Stale `meshes\armor\84_storm\head` in BodySlide Output.
- `cleanup.ps1` was written and never run. Read it before running it.
- SSE Display Tweaks still logging at debug level.
- `SkyrimSE.exe.manifest`, dead file, verify then remove.
- `X:\MODDING\OBLIVION\MO2` holds both Mod.Organizer-2.5.2 and 2.5.3 with
  identical config pointing at the same instance, which looks like an upgrade
  leftover. Low priority and it is the other build, not this one.

### F. DECISIONS THAT NEED MATT, NOT RESEARCH

**Do not batch these and do not decide them for him.** Each was deliberately
held back.

- **The UI pick.** Untarnished 75188, Norden 166086, Oathvein 160916, Vel'dun
  176230. He was reviewing galleries and never chose. Gates the interface phase
  and interacts with the map decision.
- **A combat moveset overhaul**, MCO or BFCO, and whether to add a behaviour
  engine such as Pandora to support it. Largest remaining free-lane block and it
  changes how the game feels more than anything else left. He asked for
  Precision and got it, movesets are the separate question.
- **Alternate Perspective 50307** as a REPLACEMENT for Alternate Start, Live
  Another Life, which is installed. A swap, not an addition.
- **RASS 22780 vs the installed CS Wetness Effects.** They partially overlap. A
  decision, not a stack.
- **True Storms is the weather set by default**, it went in with no other
  weather mod present. If the graphics package later picks a weather aesthetic
  mod they need a patch or one of them goes, the author is explicit that
  weather mods overwrite each other.

### G. Free lane vs gated, for anything new

Re-read section 4 before adding anything.

Held back on purpose, each for a stated reason:
- Auto Parallax 79473, belongs with the PBR package not the framework layer.
- Flat World Map Framework 29932, decide together with the map.
- Dynamic Key Action Framework 87706, overlaps the installed Dynamic
  Activation Key.
- Precision Locational Damage 78744 is **dead**, hidden by its author on
  22 Aug 2025 as obsolete. Successor 111351 needs Wounds Some Improvements plus
  a separate integration addon and does nothing without both. Dropped.

Pulled from the reactivity block because they are GATED, not free lane:
Missives 17576 places mission boards in exterior cells, Immersive World
Encounters 18330 places encounter markers, and Dynamic Things Alternative 60741
is unverified either way.

Still untouched and all free lane: the LoversLab pass, method is in `PLAN.md`
section A-3 where Matt browses signed in, sends file page URLs and
`ips_get.ps1` fetches them with his exported session cookie. **Do NOT guess mod
ids from recall, that is exactly what produced the vectorplexis incident.**
Also the player homes, quests and followers mining, and the magic VFX and
skill-tree hunts.

### H. THEN, AND ONLY THEN, PART TWO

Everything above is Part One and none of it requires the generation chain. Part
Two is the graphics package plus the chain, and it runs ONCE.

Do not start it until section F is answered and every gated mod from section G
is installed. PGPatcher errors out if DynDOLOD output is active, and any
PGPatcher run forces TexGen and DynDOLOD to be redone. The full ordering and
its reasoning are in `PLAN.md` under BUILD ORDER.
