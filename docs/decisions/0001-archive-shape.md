# 0001. The archive is text snapshots plus reasoning, not a backup

Date: 2026-09-08
Status: accepted

## Context

Two MO2 modlists live at `X:\MODDING` on a Windows machine. Chat sessions kept
having to be told what was installed, which wasted time and produced advice
based on a list that was already out of date. The install itself is large,
binary, and already on disk, so copying it into git was never the answer.

## Decision

The repo holds the memory around the installs, not the installs. Three things go
in git.

1. Dated, immutable snapshots of MO2 state, taken by `tools/export-mo2.ps1`.
   Each snapshot keeps the raw profile files verbatim, a parsed JSON form, and a
   readable summary.
2. The reasoning, meaning the changelog, the issue list, the research and the
   decision records.
3. `PLAN.md` as the single entry point that any session reads first.

Snapshots are never edited after they are committed. State that changed gets a
new snapshot.

The intake script is plain PowerShell with no modules, no network calls, and it
reads only under the root it is given.

## Consequences

Any session, local or remote, can reconstruct what the lists looked like on any
date the snapshot was taken, and can see the reasoning that got there. A session
running anywhere other than the Windows machine cannot see the live install at
all, so it has to say so rather than guessing.

The cost is that snapshots only exist when the script is run. A change made
without a snapshot afterwards is invisible to the archive, so running the export
is part of finishing a session, not an optional extra.
