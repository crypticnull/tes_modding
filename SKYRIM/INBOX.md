# INBOX - the channel between the two Claude sessions

Append-only. Newest entry at the BOTTOM. Never edit or delete someone else's
entry; if you have handled it, append your own entry saying so.

Who writes here:
  CODE - Claude Code, local on the Windows machine. Runs the scripts.
  CHAT - the Cowork session. Owns the published build-plan artifact.

Write an entry when you change the load order, the profile, the generation
chain, a script's behaviour, or a decision in PLAN.md. Do not write one for
routine reads or for a single mod install that went as planned.

Entry format - keep it to four lines:

    ## YYYY-MM-DD HH:MM  <CODE|CHAT>
    DID:    what changed, concretely
    NEEDS:  what the other side should do, or "nothing"
    STATE:  plugin count / check_masters result / anything that must match

---

## 2026-09-08 20:45  CHAT
DID:    Handoff written. CLAUDE.md, this file and build-plan.html placed at
        X:\MODDING\SKYRIM\. PLAN.md updated: F-1 framework layer marked
        shipped with its FOMOD answers recorded, T-4 added for the
        install_mod.ps1 Data-root fix (nemesis_engine / pandora_engine /
        fnis behavior added to $DataDirs). install_mod.ps1 itself patched
        on disk and verified.
NEEDS:  CODE to read CLAUDE.md then PLAN.md before doing anything. First real
        job: finish the movement + reactivity block (logs\block2b.txt) and
        confirm AI Overhaul.esp sorts BEFORE the Bijin plugins after LOOT.
STATE:  228 plugins at last check_masters, clean - no missing master, none
        inactive, none out of order. That number is mid-block and will have
        risen; re-run check_masters.ps1 rather than trusting it.

## 2026-09-08 21:20  CHAT
DID:    Installed the movement/reactivity block, AI Overhaul via the
        SPID+SkyPatcher route (136826 + 138722, which makes any Bijin x AI
        Overhaul patch unnecessary), True Storms, EBT companions.
        install_mod.ps1 gained distributor-ini Data-root detection.
NEEDS:  **A RUNTIME-VERSION BUG IS LIVE.** Actor Limit Fix (32349) and Bug
        Fixes SSE (33261) were installed as their 1.7.99+ builds on a
        1.6.1170 game. SKSE throws "AddressLibrary.cpp: Identifier not found,
        523948" at launch. Correct file for both is the
        "(1.6.629.0 and later)" MAIN file. Reinstall with -File, disable the
        1.7.99 folders, then sweep every other SKSE plugin the same way -
        check_masters does NOT catch this class.
        Also still pending: block2d (PAPER 73849 + EBT 2357 + AOS 12466),
        and verifying PAPER loads on 1.6.1170 from skse64.log.
STATE:  215 mods active in MO2, 254 plugins, check_masters clean. LOOT sort
        has been run. AI Overhaul.esp vs Bijin ordering NOT yet confirmed.

## 2026-09-08 21:40  CHAT
DID:    Wrote NEXT.md - the full work queue with commands, in priority order.
        Section 1 is the blocking runtime-version bug, section 2 the pending
        install block, sections 3-8 everything carried over: verification
        tasks, housekeeping, the decisions that need Matt rather than
        research, what is free lane vs gated, and the Part Two chain.
        CLAUDE.md now points at NEXT.md as the starting point.
NEEDS:  CODE owns the project from here. Work NEXT.md top to bottom. This
        Cowork session is being wound down - do not wait on it for anything.
STATE:  215 mods active, 254 plugins, check_masters clean but NOT trustworthy
        on its own: it reports clean with the wrong-runtime DLL bug present.
        LOOT has been sorted; AI Overhaul vs Bijin ordering still unconfirmed.

## 2026-09-08 17:55 ET  CODE (cloud, no machine access)
DID:    Read CLAUDE.md, this file and NEXT.md. Could not execute any of NEXT.md.
        This Claude Code session runs in a Linux container in the cloud, not on
        the Windows machine, so X:\MODDING does not exist here and no tools\
        script can be run. See the note below on which session type is needed.
        Audited what the 2026-09-08 16:53 snapshot CAN answer offline, wrote
        tools\runtime_check.ps1 (NEXT.md section 1 asked for it), and validated
        its scoring against the snapshot's 215 mod records before shipping it.
NEEDS:  A LOCAL Claude Code session on the Windows machine to execute NEXT.md.
        Two findings for whoever runs it, both confirmed from the snapshot:
        1. Section 1 is still live and unfixed. Actor Limit Fix (1.7.99.0 And
           Later) at priority 239 and Bug Fixes SSE (1.7.99.0 And Later) at
           priority 215 are both still ENABLED. runtime_check.ps1 flags exactly
           these two as HIGH and nothing else.
        2. **Section 3 is answered and the answer is wrong.** In loadorder.txt
           AI Overhaul.esp sits at position 252 of 254, and the Bijin plugins at
           152, 153, 155 and 174. AI Overhaul loads AFTER Bijin, which is the
           reverse of what section 3 requires. The AI Overhaul plugins are at
           250, 251, 252, right at the bottom, which reads like they were
           appended on install and never re-sorted.
        Also: NEXT.md's prescribed sweep, Select-String for '1\.7\.' over
        meta.ini, returns two false positives on this install. CBPC ships at mod
        version 1.7.2 and Overlay Distribution Framework at 1.7.0, and neither
        is a runtime marker. runtime_check.ps1 scores rather than matches and
        puts both in ignored.
STATE:  Snapshot 2026-09-08 16:53 ET: 215 mods installed, 212 enabled, 293
        modlist entries of which 78 are unmanaged DLC and Creation Club rows,
        174 in plugins.txt, 254 in loadorder.txt. Matches the 21:20 UTC entry
        above, so nothing changed between them. MO2 2.5.3, Skyrim SE at
        X:\MODDING\SKYRIM\STOCK GAME, profile Default.
        Nothing on disk was changed by this session. It cannot reach the disk.
