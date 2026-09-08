# Oblivion open issues

Problems that are live, plus problems that are settled but keep getting
re-proposed. Read this before suggesting a fix, because most obvious fixes have
already been tried.

Each entry gets a status of open, watching, fixed or wontfix, the symptom, what
has been ruled out, and where the evidence is. A crash is not an issue until
there is a log or a repro.

---

## No issues recorded

Nothing yet.

## Two MO2 program folders under X:\MODDING\OBLIVION

Status: open, low risk, cosmetic until proven otherwise
Found: 2026-09-08, from the first export

`X:\MODDING\OBLIVION\MO2\Mod.Organizer-2.5.2` and
`X:\MODDING\OBLIVION\MO2\Mod.Organizer-2.5.3` both exist, and their
`ModOrganizer.ini` files are identical apart from the version number. Both point
at the same instance, `X:\MODDING\OBLIVION\OBLIVION_REMASTERED`.

Almost certainly a leftover from the 2.5.2 to 2.5.3 upgrade rather than a real
duplicate, but it means the exporter finds two instances and writes two
identical snapshots per run, and it means launching the wrong exe is possible.
Confirm 2.5.2 is dead, then remove it. Skyrim has only 2.5.3 and does not have
this.

Evidence: `games/oblivion/snapshots/2026-09-08-Default/raw/ModOrganizer.ini`
against `games/oblivion/snapshots/2026-09-08-Default-b/raw/ModOrganizer.ini`.

## The first Oblivion snapshot reports 0 of 55 plugins enabled. It is wrong.

Status: fixed in the tool, stale in the snapshot
Found: 2026-09-08

Oblivion's `plugins.txt` uses the old format, where the file lists only the
enabled plugins with no prefix. Skyrim SE writes every plugin and marks the
enabled ones with `*`. The exporter applied the Skyrim rule to both, so every
Oblivion plugin read as disabled.

Real state at that snapshot is 55 enabled. `tools/export-mo2.ps1` now detects
the format and records which rule it applied as `plugins_format` in
`snapshot.json`. The existing snapshot keeps the wrong count rather than being
edited, because snapshots are immutable. Read `raw/plugins.txt` there instead.
