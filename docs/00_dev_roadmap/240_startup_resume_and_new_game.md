# 240 — Resume latest save at launch and New Game

Implemented 2026-10-18 for faster testing and review.

Launching normal Play now resumes the newest valid quick save or autosave,
including their backups. The saved UTC timestamp orders candidates; primary
files win equal timestamps over backups, then modification time breaks ties.
Missing/noncanonical timestamp metadata falls back to modification time.
Unfinished `.tmp` files are ignored. Invalid candidates are skipped. With no
valid save, the game generates a fresh world.

The first renderer seed request performs selection before generation. Only the
chosen world is generated; the ordinary loading screen covers the existing
terrain/owner restoration pipeline. This is a one-time startup action, so later
manual loads retain their explicitly chosen slot. Startup recovery reads files
without rewriting a damaged primary; explicit Load keeps its established
backup-repair behavior.

The gear/options **Colony menu → New Game** action closes the menu and replaces
the current world. It clears runtime jobs, reservations, colony state and terrain
edits, chooses a fresh seed, resets the calendar to `calendar.json`, restores
normal speed/unpaused preference and seeds fresh weather. The scene's loading
hold still freezes simulation until ready. Naturally exposed caves are revealed
for the new seed; previous player exploration is discarded.

New Game discards unsaved session progress. It does not delete or overwrite save
files. Normal autosaving continues after five minutes in the new world; the
manual quick save remains available through Save / Load. New Game is rejected
while a save or load is in progress. Its tooltip explains the unsaved-progress
behavior.

## Implementation

- `SaveManager.gd`: bounded metadata reads, validated newest-save selection,
  one-time resume, shared scene reset/reload and the New Game action.
- `WorldClock.gd` / `WeatherManager.gd`: explicit initial-state reset APIs.
- `DockUI.gd` / `data/ui/dock.json`: stable `new_game` menu action and backend signal.
- Existing save schema and owner serialization remain unchanged.

## Verification

- Godot editor import/parse passes.
- `StartupSaveTest.gd --prepare` passes: no-save startup, timestamp ordering,
  newer quick/autosave selection, primary/backup ties, corrupt-file fallback,
  backup-only recovery, ignored temporary files and unchanged recovery bytes.
- A separate native process running `StartupSaveTest.gd --resume` passes:
  all physical scene-owner state and stable job identities restored, clock and
  weather/RNG restored, one generation at startup, loading-screen coverage,
  real menu-button dispatch, fresh seed/calendar/weather, cleared colony/jobs,
  new-world-only exposed caves, unchanged save hashes and explicit Load afterward.
- `DockPersistenceLifecycleTest.gd` passes, including New Game and queued layout
  callbacks after the old dock is detached.
- `SaveManagerRoundTripTest.gd` and `SaveWorkerChecks` pass: manual/autosave
  transactions, full colony round trips, malformed-save recovery, backup repair,
  save-worker overlap guards (including New Game), and three write-failure stages.

Initial startup-test assertions were corrected to match existing contracts:
job diagnostic history is reassessed on restore, and exposed cave cells are
legitimate fresh-world exploration. No production behavior was changed to hide
those differences. Script-driven tests retain the known first-frame missing-scene
sky/weather warnings; final runs have no script errors or failed assertions.

Logs are under `tmp/settlement_art_20261013/startup_*`. The native menu capture,
task-only diff, source recovery ZIP, completion ZIP and SHA-256 manifests are in
`tmp/startup_resume_20261018/`. Test profiles are isolated from the player's saves.

Restart Play to use the change. No export, git commit or player-save write.
