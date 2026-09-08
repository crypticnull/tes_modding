# Skyrim open issues

Problems that are live, plus problems that are settled but keep getting
re-proposed. Read this before suggesting a fix, because most obvious fixes have
already been tried.

Each entry gets a status of open, watching, fixed or wontfix, the symptom, what
has been ruled out, and where the evidence is. A crash is not an issue until
there is a log or a repro.

---

## No issues recorded

Nothing yet.

## clean_masters.ps1 can leave the Steam install modified, and never puts it back

Status: OPEN, hard-constraint risk, not yet triggered as far as anyone knows
Found: 2026-09-08 by the cloud session, from reading the script
Gates: DynDOLOD, so this lands in Part Two

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

Status: open, minor, one line
Found: 2026-09-08, same read

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
