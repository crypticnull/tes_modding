# CLAUDE.md

Rules for any session working in this repo. Read `PLAN.md` first for what the
project is.

## Where things actually live

The modlists are on a Windows machine at `X:\MODDING`. A remote or cloud session
cannot read that path. If you are running anywhere other than that machine, you
can read and write this repo but you cannot see the install, so do not state
anything about the current install as fact unless a committed snapshot says it.

## Commands

Every command written for Matt to run is a full absolute path, every time, with
no `cd` in front of it. Several commands go in one block chained with `;`, never
a stack of separate blocks he has to copy one at a time.

`powershell -ExecutionPolicy Bypass -File X:\MODDING\tes_modding\tools\export-mo2.ps1`,
never `.\export-mo2.ps1`.

## Time

US Eastern, UTC-4 on daylight time and UTC-5 in winter. Say times in his clock.
After 8pm his time the repo has already rolled to tomorrow in UTC, so date
commits, logs and snapshots by the evening the work happened, not by UTC.

## Writing

No em dashes. No semicolons, parentheses, ellipses or bullet lists inside prose.
Comma-chained sentences of medium length, contractions throughout, "but" as the
main connector. No corporate vocabulary. Headings and tables are fine, this rule
is about sentences.

## Ground rules for changes

- Snapshots are immutable. Never edit a committed snapshot, take a new one.
- Never claim a mod is installed, a conflict is resolved, or a load order is
  correct without a snapshot or a log entry backing it. Guesses get labelled as
  guesses.
- The archive is append-heavy on purpose. Prefer adding a dated entry over
  rewriting an old one. If an old entry turned out wrong, add a correction under
  it rather than deleting it.
- No mod archives, no game files, no BSAs, no ESPs in git. Text only.
- Ask before adding a dependency. The intake script is plain PowerShell 5.1 with
  no modules on purpose, keep it that way.
- Research goes in `docs/research/` as prose with sources, not as a link dump.
  A link with no summary is worthless in six months when the page is gone.

## Prefer boring

This runs for years across many chat sessions. Plain text, stable paths, no
clever tooling that needs maintenance.
