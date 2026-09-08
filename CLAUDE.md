# CLAUDE.md - X:\MODDING

`X:\MODDING` is itself the git working tree. There is no separate checkout and
nothing is ever copied between a folder and a repo.

Two separate builds live here:

- `SKYRIM\` - Skyrim SE 1.6.1170, the active project.
  **`SKYRIM\CLAUDE.md` is the single handoff document.** Read it before
  touching anything under `SKYRIM\`. It carries the hard constraints, the
  traps, the tooling and the work queue. `SKYRIM\tools\PLAN.md` is the deep
  reference behind it and holds the decisions log, which is merged and never
  rewritten.
- `OBLIVION\` - a second, separate build. Not the active project.
  `OBLIVION\README.md` and `OBLIVION\issues.md`.

One local Claude Code session runs this, on the Windows machine. The old
two-agent cloud protocol is retired, see section 9 of `SKYRIM\CLAUDE.md`.
`SKYRIM\NEXT.md` and `SKYRIM\INBOX.md` are retired too and kept only for
history.

## Archive-wide rules

These apply to both builds. The Skyrim file repeats them in context.

- **Snapshots are immutable.** Never edit a committed snapshot, take a new one.
- **Never claim** a mod is installed, a conflict is resolved or a load order is
  correct without a log, a snapshot or a script result backing it. Guesses get
  labelled as guesses.
- **Append, do not rewrite.** If an old entry turned out wrong, add a dated
  correction under it rather than deleting it.
- **Text only in git.** No mod archives, game files, BSAs or ESPs. If a
  `git status` shows thousands of untracked files, stop and fix `.gitignore`
  rather than committing.
- **Ask before adding a dependency.** The scripts are plain PowerShell 5.1 with
  no modules on purpose, keep it that way.
- **Commands** are written as full absolute paths every time, with no `cd` in
  front, and every command for a step goes in ONE block. He is often in a fresh
  window and a variable set in an earlier block will be empty.
- **Time** is US Eastern, UTC-4 on daylight time and UTC-5 in winter. Use his
  clock. After 8pm his time UTC has already rolled over, so date commits, logs
  and snapshots by the evening the work happened.
- **Writing in this repo:** no em dashes, and no semicolons, parentheses,
  ellipses or bullet lists inside prose. Comma-chained sentences of medium
  length, contractions throughout, "but" as the main connector. No corporate
  vocabulary. Headings, tables and list blocks are fine, this rule is about
  sentences.
- **Prefer boring.** This runs for years across many sessions, so plain text,
  stable paths and no clever tooling that needs maintenance.
