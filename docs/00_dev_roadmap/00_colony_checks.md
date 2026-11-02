# 00 — Colony checks

A colony check plays recent changes in a copy of the owner's latest save. It runs the colony's
own dwarves, terrain and crowd: dwarves using the new furniture, work and goods. Pictures of
each check go in `tmp/` for the owner to look at.

From the owner, 2026-11-02: "I think the checks are good but probably overkill to run them every
time we change something". So a colony check runs **once a week**, not after each change:
- **The reminder.** The scheduled task `deepdraft-colony-check-reminder` runs Mondays at 9:00. It
  reads this log and sends a desktop notification when the last check is a week old or more and
  the changelog has entries since. It only reminds: an agent runs the check when the owner asks.
- **Between times,** a check runs only when the owner asks for one.

## Running one

1. **What to cover:** every `00_changelog.md` entry after the last row of the log below.
2. **The save:** copy the owner's latest quicksave into an isolated profile, never their own. Use
   the windowed-capture pattern: a scratch `Run.ps1` that points `APPDATA` and `LOCALAPPDATA`
   at a folder under `%TEMP%` and copies the save in as `quicksave.json`.
3. **The script:** one check script for the week's changes, writing only to
   `tmp/colony_check_YYYYMMDD/`. Cap every wait loop at about 30 game seconds and fail fast,
   so a missed event never stalls a run.
4. **Log it:** add a row at the top of the log, even when nothing was found.

## Log (newest first)

| Date | Covered | Findings | Pictures |
|---|---|---|---|
| 2026-11-02 | The tool rack (doc 294, step 3): a dwarf hung it on a rock wall by the camp, haulers filled it with three tools ahead of the colony's zone, its windows, and a dwarf took off the hoe once it was no longer kept | Worked. Fixed in the check script, not the game: the reach shot's distance limit was too tight | `tmp/storage_build_20261102/colony/` |
| 2026-11-01 | The stone stool (doc 293, step 3): Ingvin made one at the mason's bench, and it was put at the colony's dining table | The stool worked. Ralin ate elsewhere, because the dining search ran out of time at triple speed; not a stool bug | `tmp/mason_carpenter_build_20261101/stool/` |
| 2026-11-01 | The carpenter's and mason's benches (doc 293, step 2): both at work, the Stonemason's career page, the Carpenter's crafting page | Worked | `tmp/mason_carpenter_build_20261101/colony/` |
