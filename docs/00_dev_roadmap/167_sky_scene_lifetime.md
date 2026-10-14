# 167 — Sky lifetime during save loading

Fixed 2026-10-13. Loading a save after the full-sphere sky upgrade could report
`!is_inside_tree()` at the sun and moon direction reads in `SkyController._update`.
The autoload continued updating after Godot synchronously detached the old
scene, before SaveManager's `scene_changed` callback bound the replacement.
The lights still existed, so checking only for null did not make their global
transforms safe to read. This was a runtime scene-lifetime bug, not save damage.

`SkyController` now clears its scene binding on the WorldEnvironment's
`tree_exiting` signal. Updates stop during the replacement gap, and SaveManager's
existing rebind resumes them. Rebinding disconnects the previous exit listener
so a departing older scene cannot clear a newer binding. Individually detached
or freed celestial lights are also skipped and hidden in the backdrop.
SaveManager, save schema, saved content and sky appearance are unchanged.

Validation:

- `SkySceneLifecycleTest` reproduces the exact two reported global-transform
  errors before the fix. All 22 checks pass afterward, covering day/night,
  detach/update/free, repeated binding, replacement and individually removed
  lights. The test explicitly ticks the driver during the gap.
- `DioramaSkyTest` passes its headless state checks. The prior native sky art
  captures remain the appearance reference; this fix changes scene lifetime.
- `SaveManagerRoundTripTest` passes actual dock-menu autosave, backup recovery,
  structural recovery and rejected-load checks. It now binds the sky before the
  first load, guarantees a sky tick during detachment and verifies replacement
  lights. Its world uses seed 1234 to keep flora and wildlife arrival fixtures
  reproducible; an initial random world lacked the required wolf corridor.
- A byte-verified copy of the player's **2026-10-13 22:52:02 UTC** quicksave
  loads through the real menu under the native renderer. Five dwarves, 19
  installed furniture pieces, 13 scene sections, clock, weather and dwarf
  identity/appearance checks pass; the resulting snapshot validates. The sky
  is bound to the replacement Environment and both lights are in the tree.
- All four original save files retain their original SHA-256. Headless editor
  import passes without errors.

Evidence: [tests](concepts/167_sky_scene_lifetime/tests.json),
[copied-save review](concepts/167_sky_scene_lifetime/user_save_review.json),
[save hashes](concepts/167_sky_scene_lifetime/save_hashes.json), and
[restored game](concepts/167_sky_scene_lifetime/restored_save.png).
Reproduction and native review logs are in `tmp/sky_load_20261013/`.

Stop the paused debug run, restart Play, and load the existing save normally.
No save migration or new world is needed.
