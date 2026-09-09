# Skyrim open issues

Problems that are live, plus problems that are settled but keep getting
re-proposed. Read this before suggesting a fix, because most obvious fixes have
already been tried.

Each entry gets a status of open, watching, fixed or wontfix, the symptom, what
has been ruled out, and where the evidence is. A crash is not an issue until
there is a log or a repro.

---

## clean_masters.ps1 can leave the Steam install modified, and never puts it back

Status: **FIXED 2026-09-08 19:20 by the local session.** But see the correction
below, because it had ALREADY TRIGGERED before the fix landed.
Found: 2026-09-08 by the cloud session, from reading the script
Gates: DynDOLOD, so this lands in Part Two

### CORRECTION 2026-09-08 19:20 - it already fired, on 09-06

The entry below says "It has probably not fired yet." That was wrong, and the
reasoning was sound but the evidence was never checked. `$results` showing
`Where=Steam` would only have been noticed if someone was reading the summary
table at the time, and nothing persisted it, because this script writes no log.

What the disk says:

- `mods\Cleaned Masters` exists, created 2026-09-06 19:30, and holds
  `Update.esm`, `Dawnguard.esm`, `HearthFires.esm` and one CC esl.
- In the Steam Data folder those same three masters carry write times of
  2026-09-06 19:20 to 19:24, while `Skyrim.esm` and `Dragonborn.esm` still sit
  at their original 2026-08-28 05:01 stamps.
- SHA256 of all three is identical across the Steam copy, the `STOCK GAME`
  copy and the `Cleaned Masters` copy.

So xEdit cleaned three DLC masters in place inside the Steam install, this
script copied them out, and nothing put them back. No backup was taken, so the
pristine originals do not exist anywhere on this machine.

Impact is narrow. A cleaned master is the desired state for modding, the game
runs the same, and `check_masters` is clean at 262 plugins. Nothing is broken.
The install is simply no longer pristine, which is what the constraint existed
to prevent. Restoring would mean Steam's "verify integrity of game files", and
CLAUDE.md section 2 lists "verify" among the things that are off limits, so
that is Matt's call and nobody else's. Decision as of 19:20: leave it.

### The fix as applied

Follows the proposal below, with hashes rather than sizes for the verify, and
per plugin rather than batched at the end so a crash mid-loop cannot leave the
Steam install dirty:

1. Before xEdit runs, the Steam copy is copied to
   `backups\steam-guard\<timestamp>\` and hashed.
2. If the Steam copy is the one that changed, the cleaned file is collected
   into `mods\Cleaned Masters` FIRST, since that is the only place the cleaned
   bytes exist.
3. The Steam file is then restored from the guard copy and re-hashed. On a
   mismatch the script THROWS and stops, naming the backup path.
4. A `Steam` column in the summary reports `untouched`, `restored` or
   `NO BACKUP` per plugin.

Verified before shipping, by backing up a file, modifying it, restoring it and
confirming the hash matched, plus a negative case confirming a bad restore is
actually detected. The first attempt at that test was itself broken, since
`[byte[]](1..2000)` overflows at 256 so no file was created and the comparisons
were `$null -eq $null` reporting True. Worth recording, because it is the same
false-positive shape as the rest of today.

CLAUDE.md section 2 says the Steam copy at
`C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition` is not to
be modified. `clean_masters.ps1` can modify it, and its own header says so:

    xEdit has its own Steam detection and has been observed cleaning the Steam
    copy of the game even when the registry points elsewhere.

The script handles that well right up to the last step. It passes
`-D:` pointed at `STOCK GAME\Data`, it does not trust that, and it hashes each
plugin in both locations before and after so it knows which copy actually
changed. When the Steam copy is the one that changed it copies the cleaned file
out into `mods\Cleaned Masters` so the result is still usable.

Then it stops. The Steam copy stays cleaned. Nothing restores it, there is no
backup taken before the run, and the only `Copy-Item` in the file copies out of
Steam rather than back into it. So a run that trips xEdit's Steam detection
leaves a permanently modified master in the Steam install, which is the exact
outcome the constraint exists to prevent.

It has probably not fired yet. `$results` would have shown `Where=Steam` and
that would have been noticed. But this script is needed before DynDOLOD and
DynDOLOD is Part Two, so it will be run.

### Proposed fix, not applied

Deliberately not patched from the cloud session. This script writes to the one
directory that is off limits, so the fix should be made and tested by a session
that can actually run it and read the result.

Take a backup before the run rather than trying to stop xEdit, because the
header is clear that xEdit ignores where it is pointed:

1. Before invoking xEdit for plugin `$p`, if `Join-Path $SteamData $p` exists,
   copy it to a session backup folder under `$Root\backups\steam-guard\`.
2. Keep the existing collect step. The cleaned file still belongs in
   `mods\Cleaned Masters`, whichever copy produced it.
3. Add a restore step after the collect. If `Where -eq 'Steam'`, copy the
   backup back over the Steam file and re-hash to confirm it matches `Before`.
4. Fail loudly if the restore does not verify. A silent failure here is worse
   than the original problem.

Making the Steam file read-only before the run is the other option, but it is
worse. xEdit's behaviour when it cannot write is unknown, and a half-written
plugin in the Steam install is a bigger mess than a cleaned one.

## clean_masters.ps1 writes meta.ini with a BOM

Status: **FIXED 2026-09-08 19:20.** The script now uses `WriteAllLines` with a
no-BOM encoder, and the already-written `meta.ini` on disk was repaired.
Found: 2026-09-08, same read

### CORRECTION 2026-09-08 19:20 - this had already landed too

Not hypothetical. `mods\Cleaned Masters\meta.ini` on disk began
`EF BB BF 5B 47 65`, so a real BOM sat ahead of `[General]`, and the mod is
ENABLED in modlist.txt. MO2 has been reading it as having no metadata since
2026-09-06. Rewritten in place without the BOM, content preserved exactly, old
copy kept as a `.bak-` file. First bytes now read `5B 47 65 6E 65 72`.

Line 143 writes the `Cleaned Masters` meta.ini with
`Set-Content -Encoding UTF8`, which on PowerShell 5.1 emits a BOM. Every other
script that writes a profile or meta file uses
`[IO.File]::WriteAllLines(..., $Utf8NoBom)`, including `install_mod.ps1` line
646 and `claim_overwrite.ps1` line 132. This is the only one that does not.

A BOM ahead of `[General]` means the section header is not `[General]` any more,
so MO2 can read the mod as having no metadata at all. Same class as the trap
NEXT.md documents for modlist.txt, just in a file that fails quietly instead of
loudly. Match the pattern the other scripts already use.

Checked while there: every script that writes `modlist.txt`, `plugins.txt` or
`loadorder.txt` already uses `WriteAllLines` with `$Utf8NoBom`. That lesson
landed everywhere it mattered. This is the one straggler.

Also checked and cleared: `deploy_dlss5.ps1` references the Steam Oblivion
Remastered binaries, but only reads from them, copying ReShade and the
Streamline runtime out into `STOCK GAME`. That is a read and it is fine.

## Jump Behavior Overhaul 36889 crashes this build at startup

Status: DROPPED 2026-09-08. Disabled, not uninstalled.
Found: 2026-09-08 by bisect, after it crashed every launch

Symptom: black screen for 7 to 9 seconds, then straight to desktop. No Crash
Logger dump, because it is exception 0xc0000409 in ucrtbase.dll, a fastfail
abort rather than an exception Crash Logger hooks. CrashLogger.log contains only
its own init lines, which reads exactly like a clean run. The ONLY record is the
Windows Application log, Event ID 1000.

Bisected in five launches, each with tonight's 26 mods as the search space:

  all 26 off                              survives
  behaviour + animation group of 12       crash
  Pandora half of 5                       crash
  Pandora Output off, 4 left              crash
  JBO + Payload Interpreter               crash
  Payload Interpreter alone               SURVIVES

So it is Jump Behavior Overhaul on its own. It is not the missing Nemesis patch:
Pandora ran at 19:58 with JBO included and its log lists
"Pandora Mod 1 : Jump Behavior Overhaul", and it still crashed afterwards.

The mod page claims compatibility with Better Jumping SE 18967 and says most
behaviour mods work once patched with Nemesis. This build has Better Jumping NG,
a different mod, alongside True Directional Movement, Behavior Data Injector and
Precision. JBO is v1.5 from September 2022. Not worth chasing for directional
jump when Better Jumping NG is already installed.

Re-test procedure if it is ever revisited: enable it, run Pandora, then
launch_check.ps1 with a soak. Do not trust a launch that was not soaked.

## launch_check.ps1 reported three clean passes on a crashing game

Status: FIXED 2026-09-08

The first version watched for a game window, then killed the process and
reported success. A crash to desktop shows a black WINDOW for several seconds
first, so "reached game window" was true while the game was already dying. The
crashes at 20:04:42, 20:05:47 and 20:07:27 in the Windows Application log are
all launch_check's own runs, each reported as a pass.

Two fixes, both required:
1. -SoakSeconds, default 30. After the window appears it watches the process
   stay alive, second by second, and reports the elapsed time if it exits.
2. A Get-WinEvent query against the Application log for Event ID 1000 mentioning
   SkyrimSE since launch, printing faulting module and exception code.

Verified by running it against the KNOWN-BROKEN state first and confirming it
reported CRASHED, before trusting it to report a pass. A check that has never
been observed failing is not evidence.
## Cosplay Pack ships two invalid DAR condition folders

Status: open, cosmetic, low priority
Found: 2026-09-08 from OpenAnimationReplacer.log

    invalid directory name at data\meshes\actors\Character\animations\
    DynamicAnimationReplacer\_CustomConditions\female, skipping

DAR requires every folder under `_CustomConditions` to be numeric, since the
number is the priority. `Cosplay Pack - hdt SMP (CBBE 3BA)` ships `female` and
`male` alongside one correctly numbered folder, so OAR skips two files. Nothing
else is affected and no other mod does this: Animated Armoury has 14 numbered
folders, Immersive Interactions 7, Sleeping Expanded 5, all valid.

Fix if it ever matters: rename the two folders to unused numbers. Not done
because the two skipped files have not been identified as doing anything, and
renaming inside a mod folder is the kind of change that gets lost on reinstall.
## Devious Devices: does it hard-require SexLab? UNANSWERED

Status: open, NOT blocking anything installed
Found: 2026-09-08

Only matters if and when Devious Devices actually gets installed. Nothing in the
current 284-mod build depends on it. Do not treat this as a gate.

What is already established, so this does not get re-researched from scratch:

- The DD core repos on GitHub - DeviousDevices/DDa, DDi, DDx - list their
  requirements as RaceMenu or NetImmerse Override plus each other, and do NOT
  list SexLab. Suggestive but NOT conclusive: those READMEs are Oldrim-era, they
  link nexusmods.com/skyrim and reference CBBE v3.2.3 and UNP v1.2, so they
  cannot speak for the SE 5.2 build.
- Unforgiving Devices, a DD extension, requires SexLab AND OSL Aroused AND
  Devious Devices 5.2 AND Devious Devices NG. So at least some DD-adjacent mods
  do pull SexLab in.
- OSL Aroused is framework-AGNOSTIC. It appears alongside SexLab in Unforgiving
  Devices' requirements, so a mod accepting OSL Aroused proves nothing about
  OStim compatibility. An earlier note here claimed otherwise and was wrong.

Why it is not simply looked up: loverslab.com is behind a Cloudflare managed
challenge, see ips_get.ps1's header. The Schaken-Mods RSS mirror 403s as well,
and web search does not return loverslab.com results at all. It needs a human
signed in on the page, reading the Requirements section.

DO NOT keep asking Matt to go find it. He tried, the site search did not help,
and it is not worth his time for something that blocks nothing. Raise it once,
when DD is actually about to be installed, and offer to work around it instead:
install DD, run check_masters, and let the missing masters name the real
dependencies. That answers the question empirically without reading any page.