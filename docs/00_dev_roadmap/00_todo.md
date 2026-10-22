# 00 — To do

Work the owner has deferred. Each item has a confirmed cause and a fix direction, but
none is scheduled: start one only when the owner asks. When an item is finished, delete
it here and add an entry to [00 — Changelog](00_changelog.md).

Playtest reports that still need investigating live in [00 — Open issues](00_open_issues.md).

---

## Save and load

Deferred by the owner on 2026-10-21: saving is not a priority during development. All
three come from the [254 review](254_full_project_review_2026_10_20.md) (§4.7, §4.9) and
were re-checked against the code on 2026-10-21.

### Saves from another build are deleted by the next save

- **What happens.** A save written by a different build fails validation at startup:
  a newer `schema_version`, or a river layout that doesn't match `RiverLayout.VERSION`.
  The game quietly starts a new world, and the next quicksave or autosave deletes the
  old file. The colony is gone, and the player never saw a warning.
- **Why.**
  - `SaveFileStore._rotate_primary_to_backup_if_valid` (`SaveFileStore.gd:88`) won't
    move an invalid primary into the backup slot, and `_replace_primary_with_temp`
    (line 122) then removes it.
  - The notice "No valid save could be loaded…" (`SaveManager.gd:166`) is raised from
    `WorldRenderer._ready` (line 314), before `DockUI` registers (`DockUI.gd:132`). It
    only reaches `push_warning`. Its text also says existing saves are unchanged.
- **Fix direction.** Old saves still don't need to load (no backward compatibility
  during development), but the file must not be destroyed.
  - Delete only a primary that fails to parse as JSON. Rename any other invalid file
    aside, for example `quicksave.rejected-<utc>.json`.
  - Queue notices until the dock registers, so the player sees why a new world started.
- **Done when** a save with a bumped `schema_version` is set aside rather than deleted
  by the next save, and the notice shows on screen.

### New Game and Load act on one click

- **What happens.** New Game (Colony menu) and Load Game / Load Autosave (Save / Load
  panel) replace the running colony as soon as they are clicked. There is no
  confirmation anywhere in the UI, so one misclick throws away unsaved progress.
- **Where.** `DockUI._dispatch_command` (`DockUI.gd:699-710`) emits the request at
  once, and `SaveManager.request_new_game` / `request_load` act on it. The buttons are
  `new_game` and the `save_load` panel in `data/ui/dock.json`.
- **Fix direction.** Add a confirmation step to New Game and both Loads, with the UI on
  the CanvasLayer (Hard Rule 7).
- **Done when** each of the three actions needs a second click, and Cancel leaves the
  colony untouched.

### Starting with a save present comes back paused

- **What happens.** When the game starts with a save present (the normal startup
  resume), the colony comes back paused. The player's saved pause setting is also
  overwritten with "paused". The review also reported this after Load and New Game;
  only the startup case was re-checked.
- **Why.** `WorldClock.paused` (`WorldClock.gd:33-35`) also reports the loading
  screen's hold. `SaveManager` stores that combined value as the pre-load state
  (`SaveManager.gd:194, 371`) and sets the player's own pause (`set_paused(true)`,
  lines 195 and 376). The loading hold leaks into the player's setting.
- **Test.** `WorldLoadingScreenTest` covers it, but it only fails once a save exists:
  - on a fresh profile it passes, because there is nothing to resume;
  - its second run resumes the quicksave the first run left, and fails "loading hold
    never changes the saved pause preference" and "original running state restored"
    (checked 2026-10-21).
  - It is not in the job gate.
- **Fix direction.** Store the player's own pause (`_player_paused`, through an accessor
  on `WorldClock`) instead of the combined getter, so the loading hold never reaches
  the saved setting. Make the test write its own save first, so it fails on a fresh
  profile too.
- **Done when** that test passes with a save present at startup, and resuming an
  unpaused save comes back running.

---

## Performance

### The first mined block after a load hitches once

- **What happens.** The first block mined after loading a save stalls the game once,
  for 0.4–0.6 s. Later blocks cost 15–30 ms. Before the 2026-10-21 stutter fix, one
  block in a run showed the same extra ~0.4 s (695 ms against ~280 ms for the others).
- **Measured** on a copy of the owner's save (49k edits, 5 dwarves), headless, with the
  clock paused, across three runs:
  - 47 ms inside `MiningDesignationController._mine_block_world`, then a 394 ms frame;
    the next five blocks took under 1 ms in the call and 15–29 ms per frame;
  - 68 ms in the call, then a 573 ms frame;
  - a 439 ms frame, then 16, 38, 17 and 19 ms.
- **Not the renderer.** The renderer's own work for that block took 16 ms, and its
  overview snapshot patch is negligible. The long frame comes from another system.
  Unchecked candidates: the first dropped item (model load), the first underground
  lighting or NavGrid update after a load, water, and cave discovery.
- **Reproduce** with `tools/performance/RunShaderSlots.ps1 -Mining`. Its report lists
  the mined blocks in order, and the first one carries the hitch.
- **Fix direction.** Profile that one frame to find the system doing first-time work,
  then do that work while the loading screen is still up.
- **Done when** the first mined block after a load costs about the same as the next
  ones.

---

## Rendering

### Lit-shader per-object slots (8,192 cap)

Owner decision 2026-10-21: log the proper fix and leave `buffer_size` unchanged
([254 §4.3](254_full_project_review_2026_10_20.md)).

- **Limit.** `scripts/shaders/underground_lighting_common.gdshaderinc` declares three
  `instance uniform`s (`actor_sky_access`, `doorway_light_plane`, `doorway_light_span`).
  Every mesh whose shader includes it reserves a 16-slot block of the global shader
  buffer, used or not. `project.godot` sets
  `rendering/limits/global_shader_variables/buffer_size=131072`, which is 8,192 objects.
  Past that, Godot logs "Too many instances using shader instance variables" and the
  extra meshes render black. At the old 4,096 default, a benchmark with the full forest,
  24 dwarves, wildlife and 48 furniture pieces turned some dwarf parts black
  ([24](../20_player_interface/24_world_rendering.md)). Doubling the buffer only moved
  the limit.
- **Measured** on a copy of the owner's save (5 dwarves, 2026-10-20): 4,147 of 8,192 (51%).
  - By system: surface details 2,175, terrain renderer 1,191, wildlife 543, item drops 98,
    furniture 80, dwarves 60.
  - The per-column cavity and built-block meshes (2026-10-21) add one slot per 16×16
    column that has them: +54 at that save's slice (4,201 in all), about +100 with the
    slice off.
  - Most slots go to plants and animals. Each dwarf takes about 12, so 30 dwarves add
    about 300.
- **Proper fix.** Only actors (`actor_sky_access`) and door meshes (`doorway_light_*`)
  read these values. Move the `instance uniform`s into an actor/door-only variant of
  the include, so terrain, plants, props and items reserve no slots. Doors keep their
  values per instance, so cached door materials stay shared across rotations
  (`UndergroundLighting.bind_door_tree`).
- **Fallback.** Raising `buffer_size` lifts the cap at 16 bytes of GPU memory per slot.
  It changes a rendering setting, so it needs the owner's OK.
- **Count** with `tools/performance/RunShaderSlots.ps1` (copy of a save, throwaway
  profile). The report gives users, the cap and a per-system breakdown.
- **Done when** a slot count over a large save shows only actors and doors reserving
  slots, and dwarves, animals and doorways light exactly as before.
