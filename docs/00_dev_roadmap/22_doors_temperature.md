# 22 — Doors & Sealed-Room Temperature

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this milestone</span>

Status: **BUILT, ROOM DETECTION VERIFIED IN-ENGINE — 2026-08-03, updated 2026-08-14
(Addendum 8: Alen's verification pass banked the core room items; a short §4 remainder
is listed there).** Doors (new
furniture piece) and doc 34's sealed-room + temperature engine (`RoomManager`, new
autoload) are both fully coded and wired together. Alen's first underground playtest
(2026-08-06, Addenda 2 and 3 below) confirmed the door places, is walkable, and can be
built into a real mined room — but also surfaced that the World Info Rooms/Doors readout
was silently dead code the whole time (now fixed), so the room-count verification items
in section 4 below were never actually checkable until today and still need a fresh pass.
**This is the first milestone since doc 19 to register a new autoload — an editor Reload
Current Project is required before playtesting** (`AGENT.md` Playtest Handoff Note).

**Why this milestone:** doc 21 shipped a Hearth with an inert `heat_source.heat_units`
field and a Tavern Bar with inert `room_anchor` fields — both waiting on a temperature/
room-detection system that didn't exist. Picking up doc 34 directly hit a hard blocker:
its sealed-room algorithm flood-fills from door blocks, and doors didn't exist anywhere in
the codebase — no placeable door, and no player-facing "build a wall" mechanic at all
(`WorldData.set_block` had never been called with anything but `AIR_ID`). Alen chose to
build a minimal door first, in the same pass, rather than defer doc 34 again.

---

## 1. Scope decisions made during planning

**Doors don't need a new terrain block, and don't need `WorldData` writes at all.**
Investigating `NavGrid.is_walkable()` and `FurniturePlacementController._install()` showed
that a door only needs to stay *walkable* — the cell's actual block ID (air) never has to
change. `FurniturePlacementController` already skips occupancy registration entirely for
any def whose `collision_regions` array is empty (it's a straight loop, `[]` → zero boxes
registered). So `base:furniture:door` ships as ordinary furniture through the existing
doc 19 pipeline, with an empty `collision_regions` array — zero new placement code needed.
This was the single biggest scope reduction in this milestone.

**RoomManager doesn't subscribe to furniture signals — it's called directly.**
`FurniturePlacementController` is a scene node (per doc 13, "presentation = scene node"),
not an autoload, so it isn't guaranteed to exist when an autoload's own `_ready()` runs.
Every other cross-system link in this codebase runs the other direction (scene nodes call
INTO autoloads: `TaskManager.register_work_source(...)`, `StockpileManager.register_container(...)`,
etc.), so `RoomManager` follows the same pattern: `FurniturePlacementController` calls
`RoomManager.on_furniture_changed(key, cell, def, installed)` directly at both its install
and uninstall sites, instead of `RoomManager` subscribing to `furniture_installed`.

**Rooms are DERIVED state, never saved** — the exact `InteriorTracker` (doc 11 X0)
precedent. `RoomManager` has no `save_section_key()`/`serialize_state()`. On load,
`SaveManager` restores furniture (including doors) through the same `_install()` call path
used at runtime, which calls `on_furniture_changed()` exactly as it would live — rooms
rebuild themselves automatically, no special load-order hook required.

**Full rebuild on every geometry trigger, throttled — not incremental per-room diffing.**
Doc 34 specifies recomputing only rooms whose *perimeter* an edit touches. `RoomManager`
instead re-flood-fills from every known door cell on any relevant trigger (door add/remove,
any `WorldData.chunk_dirtied`), throttled to at most once per 0.5s. Simpler, and correct at
the door counts a colony will realistically have; flagged in doc 34 as something that would
need real per-room diffing at much larger scale.

**`MAX_ROOM_CELLS` (4096) approximates doc 34's "leaked to unbounded space" check.**
Doc 34's abort condition ("expansion reaches a block that is neither solid nor a door") is,
read literally, only checkable by flood-filling the *entire* reachable open world to prove
a negative — infeasible on every trigger. A cell-count cap is the same kind of tuning call
as `NavGrid`'s 1200-node reachability cap (doc 32): a fill that hasn't terminated by 4096
cells is presumed to have escaped into open space. Correct for any realistically-sized
room; approximate at the boundary. Full reasoning in `RoomManager.gd`'s file header and in
doc 34's new "Implementation notes" section.

---

## 2. What was built

### Door (furniture)

`data/furniture/door.json` — 1×1 footprint, `placement: "floor"`, `item_key` +
`yaw_steps` (the doc 19 fields, so it rides the existing Build-panel/fetch-and-build
pipeline unmodified) — but **`collision_regions: []`**, the one deliberate deviation from
every other furniture def in the project. No doorway validation in v1 (no check that the
piece sits between two walls) — just the standard `NavGrid.is_walkable(cell)` check every
floor piece gets. `tools/generate_furniture_glbs.py` gained `build_door()`: a thin
(2-voxel-deep) plank plane with iron hinges and a handle, ~2 blocks tall. Registered in
`FURNITURE_PANEL_ITEMS` (DockUI) and `DEV_FURNITURE_MIX` (StockpileDesignationController),
same mechanical pattern as doc 21.

```
furniture/door.glb   240 voxels   62156 B
```

### RoomManager (new autoload)

`scripts/systems/RoomManager.gd`, registered in `project.godot` `[autoload]` after
`InteriorTracker`. Implements, faithfully ported from doc 34:

- **Sealed-room flood-fill** from every known door cell, through air only, stopped by
  `BlockRegistry.is_solid()` or another door cell (Sealing Rules 1–3).
- **The full temperature formula** — depth gradient, heat bonus, seasonal offset (solstice
  cosine curve), daily offset (sine, peaks 14:00) — ported verbatim from the GDScript block
  already in doc 34.
- **`mean_floor_y`** computed the doc-specified way: average of the *lowest* air cell per
  `(x, z)` column, not the geometric centre.
- **Heat aggregation** from any installed furniture whose def carries a `heat_source` key
  (currently only the Hearth, doc 21) — summed per room, divided by room volume.
- **Frozen Vault flag** (`temp_c <= 0.0`).
- **Recalculation triggers**: door install/uninstall (direct call), any block edit
  (`WorldData.chunk_dirtied`, throttled), `WorldClock.hour_changed` (cheap, formula-only,
  skips rooms with zero seasonal influence — exactly doc 34's own optimisation).

### FurniturePlacementController (small, additive changes)

- New `signal furniture_uninstalled(furniture_key, origin_cell)` — didn't exist before;
  needed so door removal can be tracked as precisely as door installation.
- Two new one-line calls into `RoomManager.on_furniture_changed(...)`, at the existing
  install site and the existing `_teardown_installed()` site. No other logic touched.

### Visibility (stopgap, not a real UI)

`DockUI._world_info_rows()` gained two lines (door count, room count + frozen-vault count)
behind a `get_node_or_null("/root/RoomManager")` guard. This is **not** the doc 34 inspect
panel (Section "UI — Room Temperature Display") — just enough to confirm the system is
doing something without reading engine logs. See *Deferred*.

---

## 3. Deferred (explicitly out of scope)

<span style="color:#f85149;">Doorway validation</span> — no check that a door is placed
between two solid walls. A door placed in open space is harmless (no room will ever form
around it) but nothing stops the player from trying.

<span style="color:#f85149;">Door open/close animation</span> — every installed door is
permanently "closed" for sealing purposes. Doc 34 explicitly allows this (a strict superset
of its own rule), but there's no visual swing, no dwarf-passing-through state.

<span style="color:#3fb950;">Room inspect panel — BUILT 2026-08-07 (Addendum 4)</span> —
doc 34's "Room: Sealed / Frozen Vault / Temperature / Volume / Heat sources / Seasonal
influence" readout now lives in the **Block Inspector** (🔍), appended whenever the
inspected face borders a sealed room's interior. Only the aging-recipe gray-out strings
remain future work (no aging cellar exists).

<span style="color:#f85149;">Aging Cellar / Food Preservation hooks</span> — both
consuming systems (doc 42) don't exist in code yet, so there's nothing to pause/resume or
spoil. `get_room_at(cell).temp_c` is the hook point whenever they land.

<span style="color:#f85149;">Dwarf comfort / `biting_cold` thought</span> — depends on
doc 41's needs/mood system, not yet implemented.

<span style="color:#f85149;">Per-room incremental recomputation</span> — see scope
decisions above. Full-rebuild-on-dirty is the v1 approach.

## 4. Verification (partially done — see Addenda 2 and 3 for what's confirmed)

Per `AGENT.md`'s Playtest Handoff Note, **a new autoload was registered this session — a
Godot editor Reload Current Project is required before any of this will work**, not just a
normal play test. After reloading:

> **2026-08-06 note:** the door-placement and walkability items below are now confirmed —
> Alen mined a corridor, built a 4×4 room, and placed a door in it. The Rooms-count item is
> still unconfirmed as written: the World Info overlay never actually showed a Rooms/Doors
> line before today (dead code, see Addendum 3), so no one has yet seen it increment for a
> real sealed room — that's the next concrete thing to check now that the display is fixed.

- [ ] `RoomManager: ready (doc 34/22).` prints on boot with no errors.
- [ ] Build panel: `📥 Door` appears, places, and is walkable (a dwarf or the DEV cursor
      can cross the tile without detouring).
- [ ] Dig out a small room with exactly one door-sized gap; place a Door in the gap; the
      World Info overlay's Rooms count increments by 1.
- [ ] Place a Hearth inside that room; reopen World Info — no direct temp readout yet
      (see Deferred), but nothing should error; a print/log check that `heat_units`
      contributed to the room's `temp_c` is the practical verification until the UI exists.
- [ ] Mine out the door (uninstall it): the room count should drop back — the seal breaks.
- [ ] Save, reload the game: door(s) restore, room count matches pre-save state (confirms
      the DERIVABLE-state assumption holds).
- [ ] Dig a very large, open cavern (no doors) — confirm no false-positive "sealed" rooms
      and no performance stall (the throttle should keep chunk_dirtied spam from hitching).

## 5. Addendum (doc 22b, 2026-08-06): door resized after first playtest

Alen's first in-engine pass flagged the door as visually out-of-proportion — a
single 1×1 tile, ~2 blocks tall, next to 3-tall dwarves and 1-wide corridors. Resized
to **2×1 footprint, 2 blocks wide x ~4 blocks tall**, rebuilt as a proper double-leaf
door (two plank leaves, dark centre seam, hinges on each outer edge, handles near the
seam) rather than one slab stretched to fit.

**This was not purely a visual change.** `RoomManager.on_furniture_changed()` only
ever tracked the door's *origin* cell as a sealing boundary — fine at 1×1, where
origin was the whole footprint, but wrong at 2×1: the second cell would have read as
plain open air, and the sealed-room flood-fill would leak straight through it. Fixed
by changing the call signature from `on_furniture_changed(key, cell, def, installed)`
to `on_furniture_changed(key, cells, def, installed)` — `FurniturePlacementController`
now passes `component.cells` (the already-computed full footprint) instead of just
`origin`, and `RoomManager` registers every cell of a door's footprint into
`_door_cells`. No change was needed in `_flood_fill_from_door()` itself: it already
treats each `_door_cells` entry as an independent boundary cell and dedupes
physically-adjacent cells of the same door via its `claimed_doors` set, so a 2-cell
door "just works" once both cells are registered. Heat-source tracking (currently
only the 1×1 Hearth) deliberately stays keyed to the origin cell only — summing
`heat_units` at every footprint cell of a future multi-cell heat source would
double-count it in `_sum_heat()`.

Files touched: `data/furniture/door.json` (footprint), `tools/generate_furniture_glbs.py`
(`build_door()` rebuilt for the new envelope), `scripts/systems/RoomManager.gd`
(`on_furniture_changed` signature), `scripts/systems/FurniturePlacementController.gd`
(both call sites). No autoload registration changed — a plain script edit, no editor
Reload Current Project required, just a re-run/hot-reload.

## 6. Addendum 2 (2026-08-06): first underground playtest — three bugs found

Alen's first attempt to actually place a door in a mined, sliced-open tunnel surfaced three
separate pre-existing bugs, none specific to doors:

**Floating drop items.** `ItemDropManager._rest_y()` only scanned 8 blocks straight down
looking for a floor to rest a dropped item on (`REST_SCAN_DEPTH`), falling back to the mined
block's own height — floating in place — if it scanned out. Fine for shallow pits; wrong for a
wall/ceiling block mined out of a deep or diagonal tunnel, where the real floor is well below
but not straight under the mined cell within 8 tiles. Now scans all the way to bedrock.

**Furniture couldn't be placed underground at all.** `FurniturePlacementController._surface_cell_for()`
(the click-to-place raycast) marched against `WorldGenerator.get_visible_surface_y()` — the
STATIC world-gen heightmap, frozen at generation and never updated by mining. Every placement
click resolved to the *original, unmined* ground height for that column, no matter what the
slice tool had cut away or what mining had exposed below — so a door (or any furniture) could
only ever be placed at the natural outdoor surface, never inside a dug room. Replaced with a
proper slice-aware voxel DDA raycast against the live block grid, porting the same technique
`MiningDesignationController._raycast_voxel()` already used correctly.

**Stockpile zones had the identical bug** (`StockpileDesignationController._surface_cell_for()`),
and its header comment even documented the limitation as deliberate ("zones are SURFACE
designations"). Fixed the same way. This was flagged to Alen before fixing, since it was a
documented design decision, not an obvious accident — confirmed to fix.

Both raycast fixes are drop-in: the return contract (`{x, y, z}`, `y` = the walkable cell above
the hit floor) is unchanged, so no downstream validity/placement code needed to change. Above-
ground behaviour is unaffected in both cases.

**Drop rates retuned.** Separately, Alen reported dirt and stone piling up too fast. Rock/stone
(`base:terrain:rock:*`) was already at 0.25 (halved once before, 2026-06-10); cut again to 0.12.
Soil/dirt/grass (`base:terrain:surface:grass_*`, `dirt_*`, `soil:cave/light/dark`) had been a
guaranteed 1.00 the whole time — the real asymmetry, since it out-paced even the already-tuned-
down stone. Cut to 0.30. Ore and gem drop chances were left untouched (not reported as a
problem). All in `data/terrain/block_resources.json`, easy to re-tune further — see doc 43.

Files touched: `scripts/systems/ItemDropManager.gd` (`_rest_y`, `REST_SCAN_DEPTH` removed),
`scripts/systems/FurniturePlacementController.gd` (`_surface_cell_for`, `RAY_STEP` removed),
`scripts/systems/StockpileDesignationController.gd` (same), `data/terrain/block_resources.json`
(drop chances), `docs/40_economy_colony/43_mining_materials.md` (kept in sync). No autoload
registration changed — normal script hot-reload/re-run, no editor Reload Current Project needed.

## 7. Addendum 3 (2026-08-06, same day): regression fix, dead-code panel fix, drop rates cut again, stray floating item explained

Four small follow-ups from the same playtest session, after Addendum 2 above:

**Self-introduced off-by-one regression, fixed same day.** The two `_surface_cell_for()` DDA
rewrites in Addendum 2 initially returned `y = pos.y + 1` (one cell above the hit solid block)
instead of `y = pos.y` (the solid block's own cell). This broke furniture placement AND
stockpile zone drawing completely — every cell failed `NavGrid.is_walkable(cell)`, since
`NavGrid._compute_walkable()` requires `cell.y` itself to be solid (clearance is checked
*above* it separately). Alen reported this as "I lost the ability to draw storage zones
now." Root-caused against `NavGrid._compute_walkable()` and fixed in both files by returning
`pos.y` directly. Purely a same-day regression in the Addendum 2 fix, not a new or
pre-existing bug.

**Doors/Rooms debug display was dead code.** The doc 22 addition of Doors/Rooms lines to
`DockUI._world_info_rows()` never rendered anywhere: `DockUI._toggle_window()` short-circuits
`target == "world_info"` straight to `_toggle_world_info_overlay()` and returns, so
`_window_rows()`/`_make_window()` (and therefore `_world_info_rows()`) is never reached for
that target. Alen built a real 4×4 sealed room with a door and saw no Doors/Rooms line in the
"World Build" panel, which is `DebugLoadingOverlay` — a different script entirely. Fixed by
adding a new `_rooms_text()` to `DebugLoadingOverlay.gd` (the actual live panel) and leaving a
`DEAD CODE` doc comment on the unreachable `DockUI._world_info_rows()` explaining why. The
room detection itself (`RoomManager`'s door-seeded flood-fill) was never confirmed broken —
there was simply no visibility into its result until this fix.

**Drop rates cut again, to a flat 5%.** Rock/stone and soil/dirt/grass (already retuned to
0.12 / 0.30 in Addendum 2) were cut further to 0.05 / 0.05 — Alen's testing-convenience
request, explicitly not a final-balance number. `data/terrain/block_resources.json` and
doc 43 kept in sync.

**Stray floating item over a lake, explained (no code bug found).** Alen spotted a light-grey
loose item hovering above a lake/tarn's water surface with a visible gap beneath it, in the
same "World Build" screenshot. Traced every current path that can place a loose item:

- Mining (`MiningDesignationController._spawn_block_drops()` → `ItemDropManager.spawn_drop()`)
  passes the real mined block, and `_rest_y()` (fixed in Addendum 2) scans straight down
  through water — confirmed non-solid via `BlockRegistry.is_solid()` — to the true lakebed.
  A freshly-mined drop cannot rest above a lake's water surface with today's code.
- The DEV-spawn buttons (`StockpileDesignationController.dev_spawn_drops/_dev_spawn_mix`)
  route through `_screen_center_surface_cell()` → the same (also since-fixed) DDA
  `_surface_cell_for()`, so a fresh DEV spawn today also resolves to the lakebed, not the
  water's static surface height.

Conclusion: this item is very likely a stray survivor from *before* those fixes landed
earlier in this same session — either a mined drop that used the old capped 8-block
`_rest_y()` scan, or a DEV-spawned item placed via the old static-heightmap raycast, which for
a lake/tarn column returns `LAKE_WATERLINE`/`tarn_waterline` (the water's surface Y) instead
of the real lakebed — exactly the "floating at the waterline with a gap underneath" look in
the screenshot. No live bug was found in the current code path, so no fix was applied here;
picking the stray item up in-game clears it, since nothing will re-spawn it in that state
going forward. Note a save/reload would NOT have fixed it on its own —
`ItemDropManager.restore_loose_item()` restores a loose item's exact saved position rather
than recomputing a rest height, so a bad pre-fix position persists across saves until the
item is picked up or otherwise removed.

Files touched: `scripts/systems/FurniturePlacementController.gd`,
`scripts/systems/StockpileDesignationController.gd` (off-by-one fix, both),
`scripts/ui/DebugLoadingOverlay.gd` (`_rooms_text()` added),
`scripts/ui/DockUI.gd` (`_world_info_rows()` dead-code doc comment, no behaviour change),
`data/terrain/block_resources.json` + `docs/40_economy_colony/43_mining_materials.md`
(5%/5% drop rates). No code changed for the floating-item item — investigation only.

## 8. Addendum 4 (2026-08-07): close-out + polish pass

Session goal: give the §4 verification items a real UI surface, and clear small debt
before the next milestone. No new autoloads, no new `class_name` scripts — **a plain
script hot-reload / re-run is enough; no editor Reload Current Project needed.**

**Room inspect panel (doc 34 UI, v1).** The Block Inspector (🔍) is now the doc 34
inspect panel. `WorldRenderer._find_block_on_ray()` additionally returns `air_pos` — the
last air cell the ray crossed before the solid hit (i.e. the open cell adjacent to the
hit face; a sealed room's interior is air, the hit block itself never is). The inspector
passes it to the new `_room_inspect_lines()`, which queries `RoomManager.get_room_at()`
(null-safe, explicit types per the Variant-inference trap) and appends: sealed/frozen
label + depth-zone name (from mean floor Y, doc 34 gradient table), temp °C, volume,
heat units with the computed +°C bonus, door count, and seasonal influence %. Open air
shows a quiet `room: none` line so a failed detection is distinguishable from a missing
query. This directly serves §4's "print/log check that heat_units contributed" item —
place a Hearth in a sealed room and the panel shows both the units and the bonus.

**Coal shadowing fixed (doc 12 item 1, bug-grade).** `block_resources.json`: coal's
`noise_threshold` 0.72 → **0.62**, restoring doc 43's monotonic-descent rule (coal is
evaluated last; its threshold must be the lowest). Coal now spawns across its whole
declared Y12–90 band and is the most common metal — correct for the doc 44 bulk fuel.
Docs 43 + 12 updated in sync. Density check deferred to the doc 44 milestone.

**Small debt cleared:**
- `debug_world.tscn`: `overview_profile = false` (was committed `true`; profiling
  accumulators ran in normal play — re-enable in the scene when profiling).
- Mining hint window: "Esc or right-click: exit" → "Esc: exit" (right-mouse is reserved
  for camera orbit and was never consumed — doc 21 tool input contract; doc 43's control
  table row fixed to match).
- `dock.json`: "fo gathering" typo; calendar tooltip was a copy of clock's.
- **Profession key drift fixed** (`DwarfFactory.PROFESSION_KEYS` vs `professions.json`):
  carpenter was in the JSON but missing from the factory (new dwarves never got the key
  in `profession_experience`); weaponsmith/armorsmith were in the factory but absent from
  the JSON. Carpenter added to `PROFESSION_KEYS`; weaponsmith/armorsmith added to
  `professions.json` as `not_implemented` stubs (`promotes_from: blacksmith`, per doc 44).
  Existing saves are unaffected — `restore_state` copies the dict as saved.

### Updated §4 verification state

Confirmed earlier (Addenda 2–3): door places, is walkable, installs in a real mined room.
**Still to verify in-engine (all now have visibility):**

- [ ] Boot: `RoomManager: ready (doc 34/22).` prints, no errors; no regressions from this
      pass (inspector opens, mining hint shows, dock tooltips read correctly).
- [ ] Sealed 4×4 room + door → **World Build panel** Rooms count increments AND the
      Block Inspector on the room's floor/wall shows the `room: Sealed (...)` block with
      a plausible temp for its depth.
- [ ] Place a Hearth inside → inspector shows `room heat: 400 units (+N.N°C)` and temp
      rises by exactly that bonus.
- [ ] Uninstall/mine the door → Rooms count drops; inspector reverts to `room: none`.
- [ ] Save, reload → door restores, Rooms count and inspector readout match pre-save.
- [ ] Large open cavern (no doors) → no false-positive rooms, no hitching.
- [ ] While mining below ~Y72: coal veins now appear at mid-depths (was Y12–19 only).

## 9. Addendum 5 (2026-08-07, same day): 🚪 Rooms overlay tool

Alen's playtest follow-up on the Addendum 4 inspect panel: *"I can't quite click into a
room"* — the Block Inspector needs a face adjacent to room air under the cursor, which is
fiddly from a sliced top-down view. Built the requested dedicated tool instead:

- **New `RoomOverlayController`** (`scripts/systems/`, scene node in `debug_world.tscn`,
  new `class_name` — **editor Reload Current Project required before playtesting**, the
  doc 19 Phase 3 lesson). Dock entry **🚪 Rooms** (`dock.json`, after X-Ray; DockUI routes
  the announce; controller self-toggles — the stockpile-tool convention).
- While active: every sealed room draws a translucent floor overlay (fill + exterior
  outline at the lowest air cell per column; amber, icy blue for Frozen Vaults), rendered
  **no-depth** (mining ghost-layer treatment) so rooms read through the mountain; rooms
  above the slice plane hide. Left-click marches the mouse ray and selects the first room
  interior it crosses (x-ray clicks, matching the overlay); a compact window shows the
  doc 34 readout (state, zone, temp, volume, heat + bonus, doors, seasonal %, mean floor
  Y) at 2 Hz. ESC exits; RMB untouched (camera contract).
- **`RoomManager` additions:** read-only `get_rooms()` and `get_room_id_at(cell)` (room
  ids renumber on every rebuild — the tool re-resolves selection through the clicked
  cell). No autoload-list change.
- Spec recorded in `23_user_interface.md` §The Rooms Tool; doc 34 status updated; dock
  Default Items renumbered (Rooms = 15).

Verification (add to the §4 list): activate 🚪 with a sealed room present → amber floor
shape visible through terrain; click it → window shows the same numbers as the Block
Inspector on that room; place/remove a Hearth → window heat line updates within ~0.5 s of
the room rebuild; break the seal → overlay disappears and the window reports it.

## 10. Addendum 6 (2026-08-07, same day): sealing NEVER worked — two geometry bugs, found by the Rooms tool

Alen activated the new 🚪 Rooms tool on a real mined room with a door and a hearth: no
overlay. The tool did its job — it made the detection visible for the first time, and the
detection turned out to be broken since doc 22 shipped. **No sealed room has ever been
detected in this codebase until today.** (The §4 "Rooms count increments" item was never
actually banked; Addendum 3 only fixed the *display*.)

**Bug 1 — the doorway leaked.** Only the door's footprint FLOOR cells were registered as
fill boundary. The doorway is a 2-wide, ~4-tall gap of open air above those cells (the
door piece is walkable and has no terrain identity), so the flood-fill walked straight up
through the gap, out into the corridor and the open world, hit `MAX_ROOM_CELLS`, and
declared everything unsealed — for every door, always. **Fix:** each door tile now seals a
vertical column — floor + `DOOR_SEAL_HEIGHT` (4) air cells, matching the doc 22b door's
height (`_door_boundary_cells()`).

**Bug 2 — seeding merged both sides.** With the column sealed, the old seed-from-the-door
fill would discover BOTH sides of the door (room + corridor) as one region and leak
anyway. A door separates two spaces — they must fill separately. **Fix:** every air cell
adjacent to a door column starts its own fill; a fill that terminates within the cap is a
sealed room, and a leaked fill's cells are memoised per rebuild so the open corridor is
probed once, not once per neighbour. Verified against a synthetic 4×4×4 room + doorway +
open corridor (one room, 64 cells, 2 door tiles, corridor probed exactly once).

**Bug 3 — hearth heat never counted.** Heat sources register at their footprint floor
cell (solid ground); a room's cells are interior AIR. `_sum_heat` compared the floor cell
against the air set — never a match, so `heat_units` contributed 0°C to every room since
doc 22. **Fix:** membership is tested at the air cell directly above the heat source's
floor cell.

All three fixes are in `RoomManager.gd` only (no signature changes, no new class_name —
plain hot-reload). Doc 34's Implementation notes updated. Behavioural consequence worth
knowing in play: a doorway gap taller than 5 blocks is *not* sealed by a door — by
design; a normal 4-high corridor gap seals fully.

§4 verification stands as written in Addendum 5 — this addendum is what should make those
checks actually pass. Note the room must be fully roofed: a shaft open to the sky above
the interior is a genuine (correct) leak.

## 11. Addendum 7 (2026-08-07, same day): Rooms tool polish after the first working detection

Alen's second Rooms session (the fixes landed — overlay + window both worked on a real
sealed room) produced two refinements:

- **Volume shell instead of a floor quad** ("make the volume of the room more obvious,
  draw it similar to a mining zone"): the overlay now emits every exterior face of the
  room's air volume (inset 0.04 so it never z-fights the walls) plus silhouette outline
  edges, with interior coplanar edges deduped away — the mining-zone exterior-lines
  lesson. Same-day follow-up: outline edges moved to the TRUE cell boundary (fill stays
  inset) so the two faces meeting at a corner merge into ONE drawn line — the inset edge
  positions drew visible doubles at every corner; the dedupe rule became "skip only when
  all contributions share one face orientation" so creases and doorway rims still draw. Colour moved amber → **green** (mining owns yellow, and a translucent amber
  volume would read as a mining designation); Frozen Vaults stay icy blue.
- **Doors count PIECES, not tiles** ("the room has one door even though it is two blocks
  wide"): `RoomManager._door_cells` now maps each footprint cell to its piece's ORIGIN
  cell; the boundary map, fill result, room window, Block Inspector line, and the World
  Build `doors` stat all count distinct origins — a 2×1 door is one door everywhere.

Both plain script edits (`RoomOverlayController.gd`, `RoomManager.gd`) — hot-reload, no
editor reload.

## 12. Addendum 8 (2026-08-14): room verification pass — BANKED

Alen's playtest banked the core §4 / Addendum 5 room items ("the room related things are
a pass"), with screenshot evidence of a real mined 4×4 room, door and Hearth installed:

- **Sealed-room detection works live** — 🚪 Rooms tool draws the green volume shell on
  the room, through terrain, correctly bounded by the door.
- **Room window readout correct** — `Room 2 · Sealed (Deep Cold) · 9.2°C · 64 blocks ·
  400 units (+6.3°C) · Doors: 1 · seasonal 31% · mean floor Y 44.0`.
- **Hearth heat contributes** (the Addendum 6 Bug-3 fix confirmed): 400 / 64 = +6.25°C,
  matching the displayed +6.3. The absolute temperature corroborates the full doc 34
  formula: base ≈ 2.5°C at mean floor Y 44 + 6.25 heat + seasonal/daily ≈ 9.2°C. Zone
  label correct (Y 44 → Deep Cold), seasonal influence 31% ≈ inverse_lerp(30, 75, 44).
- **Doors count pieces, not tiles** (Addendum 7): the 2×1 door reads `Doors: 1`.
- Tool UX confirmed in passing: overlay + click-to-select + window refresh all behave.

**Banked same day (Alen, follow-up):** door uninstall/mine → seal breaks and the Rooms
count drops ✓; save → reload → the room survives intact (the DERIVABLE-state check —
furniture restore rebuilding rooms through the normal install path works) ✓.

**§4 remainder, still open:** large doorless cavern → no false-positive rooms, no
hitching (untested, low risk); coal at mid-depths — not yet encountered in normal
mining, will bank organically when a vein turns up (full density eyeball stays with the
doc 44 milestone either way).

*(Also fixed this pass: a stray `w` typo that had crept onto this doc's title line.)*

---

*Prev: [21_tavern_furniture.md](./21_tavern_furniture.md)*
