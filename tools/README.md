# tools

## export-mo2.ps1

Walks a folder for MO2 instances and writes a dated snapshot of each profile
into the archive.

Run it from anywhere on the Windows machine:

```
powershell -ExecutionPolicy Bypass -File X:\MODDING\tes_modding\tools\export-mo2.ps1 -Root X:\MODDING
```

With a note attached, which shows up in the snapshot summary:

```
powershell -ExecutionPolicy Bypass -File X:\MODDING\tes_modding\tools\export-mo2.ps1 -Root X:\MODDING -Note "baseline before ENB swap"
```

One profile only:

```
powershell -ExecutionPolicy Bypass -File X:\MODDING\tes_modding\tools\export-mo2.ps1 -Root X:\MODDING -ProfileName Default
```

### What it reads

Under `-Root`, to a depth of 3 by default, it looks for `ModOrganizer.ini`. For
each instance it reads that file for the game name, game path, base directory
and selected profile, then reads `mods/*/meta.ini` for every installed mod and
`profiles/*/` for every profile's mod and plugin order.

It reads nothing outside `-Root` and it makes no network calls.

### What it writes

`games/<game>/snapshots/YYYY-MM-DD-<profile>/` containing:

- `SUMMARY.md`, the readable form, mods grouped under their MO2 separators
- `snapshot.json`, the machine form, with priorities, enabled flags, Nexus mod
  ids, versions and install file names
- `raw/`, the untouched `modlist.txt`, `plugins.txt`, `loadorder.txt`, the
  profile ini files and `ModOrganizer.ini`

It never overwrites an existing snapshot folder. A second run on the same day
gets a `-b` suffix, then `-c`, and so on.

### Notes on the file formats

MO2 writes `modlist.txt` highest priority first, which is the reverse of what
the left pane shows, so the last line of the file is the entry at the top of the
pane. The parsed `modlist` array in `snapshot.json` corrects for that, where
priority 0 is the top of the pane and loses every conflict, and the highest
priority number is the bottom of the pane and wins. The raw file is kept
untouched either way, so if this convention ever turns out to be backwards the
snapshots are still correct.

Worth spot checking against the MO2 window on the first run. Compare the first
few lines of `SUMMARY.md` against the top of the left pane and confirm they
match.

In `plugins.txt` an asterisk prefix means the plugin is enabled. Entries in
`modlist.txt` are prefixed `+` for enabled and `-` for disabled, and any name
ending in `_separator` is a divider rather than a mod.

### Privacy

`ModOrganizer.ini` contains absolute paths, which can include a Windows user
name. Check the first snapshot before pushing if that matters.
