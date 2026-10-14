# 161 — Save menu scene teardown

**Completed 2026-10-13.** Loading a valid quicksave through the dock could stop
at `DockUI._position_action_panel()` with a null viewport. `SaveManager` reloads
the current scene synchronously enough to detach the old dock before its signal
handler returns. The old command then hid the menu; its `visibility_changed`
callback tried to position that detached menu. Queued layout callbacks had the
same missing lifetime check. The error is independent of the fire assets.

`DockUI` now finishes closing its menu before emitting any persistence request.
Both illustrated commands and legacy caption routes share that ordering. Layout
and position callbacks return when the dock is outside the scene tree. Save data,
validation, restoration, and art assets are unchanged.

Verification:

- `DockPersistenceLifecycleTest` reproduced the reported line-396 error before
  the fix. Afterward all six command/route combinations pass, including callbacks
  queued before detachment and menu state observed inside the persistence handler.
- `RemainingMenusTest` passes normal menu behavior and layouts.
- `SaveManagerRoundTripTest` now presses production menu buttons for autosave,
  quicksave backup recovery, structural-corruption recovery and rejected loads.
  All content comparisons, validation and recovery checks pass.
- A byte-verified copy of the player's quicksave from 2026-10-13 21:00:42 UTC
  loads through the real menu under the native renderer. All five dwarves and
  14 installed furniture pieces restore. Thirteen authoritative scene sections,
  clock, weather, seed, and dwarf identities/appearance compare successfully;
  the resulting snapshot passes validation. The restored scene displays the
  current fire art. All four original save files retain their original SHA-256.
- Godot's headless editor import finishes without errors.

Evidence: [fixture results](concepts/161_save_menu_scene_teardown/tests.json),
[copied-save checks](concepts/161_save_menu_scene_teardown/user_save_review.json),
and [restored world](concepts/161_save_menu_scene_teardown/restored_save.png).
Reproduction and native review logs are in `tmp/dock_load_20261013/`.

Stop the paused debug run, start Play again, and load the existing save normally.
No migration, replacement save or new world is needed.
