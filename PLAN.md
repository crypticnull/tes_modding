# PLAN.md

Long-term archive for Matt Rodenbeck's Skyrim and Oblivion modlists, built and
maintained in Mod Organizer 2 under `X:\MODDING`.

This file is the entry point. If you are a chat session picking this up cold,
read this file first and then follow the links. Do not re-derive state that is
already recorded here.

---

## What this repo is

The modlists themselves live on disk at `X:\MODDING`. This repo is the memory
around them: what the lists are, what has been done to them, why, what broke,
what is planned, and the research behind the bigger installs.

The repo does not contain mod archives, mod files, or game data. It contains
text snapshots of MO2 state plus the reasoning that produced them.

## What this repo is not

Not a wabbajack list, not a distributable modlist, not a backup. If the drive
dies, this repo tells you what was installed and in what order, but it will not
reinstall it for you.

---

## How another chat should use this

1. Read this file.
2. Read `docs/goals.md` for where the lists are headed.
3. Read `games/<game>/README.md` for the facts about that list, versions,
   hardware, engine build, and which MO2 profile is live.
4. Read `games/<game>/issues.md` before proposing a change. Most proposals have
   already been tried.
5. Read the newest folder in `games/<game>/snapshots/` for the actual current
   mod and plugin order.
6. Append to `games/<game>/changelog.md` when work lands. Write a decision
   record in `docs/decisions/` when a choice will be questioned later.

Never edit a snapshot after it is committed. Snapshots are a record of a moment.
If state changed, take a new snapshot.

---

## Current state

| | Skyrim | Oblivion |
|---|---|---|
| Edition | not recorded | not recorded |
| MO2 instance | not recorded | not recorded |
| Live profile | not recorded | not recorded |
| Latest snapshot | none | none |
| Status | awaiting first snapshot | awaiting first snapshot |

This table is stale until the first export runs. Update it in the same commit as
the snapshot that fills it.

---

## Taking a snapshot

On the Windows machine, from anywhere:

```
powershell -ExecutionPolicy Bypass -File X:\MODDING\tes_modding\tools\export-mo2.ps1 -Root X:\MODDING ; cd X:\MODDING\tes_modding ; git add -A ; git status
```

That walks every MO2 instance under `X:\MODDING`, copies the profile files
verbatim, parses `meta.ini` for every installed mod, and writes a dated snapshot
under `games/<game>/snapshots/`. It writes nothing outside the repo and reads
nothing outside `X:\MODDING`.

Then commit. Snapshots are cheap and the whole point is having a long series of
them.

---

## Conventions

- Dates and times are US Eastern, Matt's clock. After 8pm the UTC date has
  already rolled over, so date things by the evening the work actually happened.
- Snapshot folders are `YYYY-MM-DD-<profile>`. Two in one day get `-b`, `-c`.
- Prose here has no em dashes and no semicolons. Comma-chained sentences,
  contractions, plain words.
- Every claim about the list comes from a snapshot or a log entry. If it is a
  guess, say it is a guess.

## Layout

```
PLAN.md                     this file, the index
CLAUDE.md                   rules for sessions working in this repo
docs/goals.md               where the lists are headed
docs/research/              long-form install research, one file per topic
docs/decisions/             decision records, numbered
games/skyrim/               profile facts, changelog, issues, snapshots
games/oblivion/             same
tools/export-mo2.ps1        the intake script
```

## Open threads

Nothing recorded yet. First real session should fill this in from the live
install.
