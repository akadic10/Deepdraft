# 20 — Save / Load Persistence

Status: **SHIPPED and verified 2026-07-18.** Version 1 provides an independent manual
quick-save slot and five-minute autosave slot through the dock's **💾 Save / Load** menu.
Taking either snapshot is observational and does not interrupt workers or mutate
simulation state. Validated transactional replacement protects the last good generation
of each slot from an interrupted or corrupt write.

---

## 1. Scope and invariants

The persistence model is **deterministic base world + authoritative deltas**, not a dump
of every materialised chunk or runtime object.

1. `world_seed` regenerates the untouched terrain, water bodies, strata, resource layout,
   and seed-derived surface flora.
2. Player/colony state is serialised by the system that owns it.
3. Runtime integer block IDs never enter the save. Mining removals need only coordinates;
   future non-void terrain writes must use namespaced block keys.
4. Tasks, leases, reservations, paths, meshes, occupancy indexes, and interior indexes are
   transient or derived and rebuild after load.
5. Saving must not pause time, release work, change an assignment, clear a reservation,
   move an entity, or drop an item.
6. Loading replaces the current world and therefore creates a fresh transient task state.

The manual slot is `user://saves/quicksave.json`; the automatic slot is
`user://saves/autosave.json`. Each retains one previous valid generation at the matching
`.backup.json` path. The current `schema_version` is `1` for both slots.

---

## 2. File schema

`SaveManager` is the sole reader and writer of runtime save JSON.

```json
{
  "schema_version": 1,
  "project": "Deepdraft",
  "saved_at_utc": "2026-07-18T12:00:00Z",
  "world_seed": 123456789,
  "clock": {
    "day": 1,
    "season": "summer",
    "year": 1,
    "hour": 8.0,
    "speed": 1.0,
    "paused": false
  },
  "weather": {
    "current_id": "base:weather:clear",
    "rng_state": 1234
  },
  "scene": {
    "mining": {},
    "settlement_flag": {},
    "stockpiles": {},
    "furniture": {},
    "items": {},
    "dwarves": {},
    "camera": {},
    "slice": {}
  }
}
```

The metadata fields identify the project, schema, creation time, and deterministic world.
`clock` and `weather` are autoload-owned state. `scene` contains independent sections
contributed by scene nodes through the ownership contract below.

---

## 3. Scene ownership contract

A scene node joins the `save_state_owner` group and implements:

```gdscript
func save_section_key() -> String
func save_restore_priority() -> int
func serialize_state() -> Dictionary
func restore_state(state: Dictionary) -> void
```

`SaveManager` collects every owner by section key. On load it sorts owners by restore
priority so dependencies exist before consumers restore.

| Priority | Section | Owner | Authoritative content |
|---:|---|---|---|
| 10 | `mining` | `MiningDesignationController` | Mined block coordinates and outstanding mining-zone block sets |
| 20 | `settlement_flag` | `FlagPlacementController` | Placed state and grid cell |
| 30 | `stockpiles` | `StockpileDesignationController` | Zone IDs/cells, filters, and stored item keys/counts |
| 40 | `furniture` | `FurniturePlacementController` | Ghosts, installed pieces, yaw, uninstall flags, and container inventories |
| 50 | `items` | `ItemDropManager` | Loose item keys, positions, and yaw |
| 60 | `dwarves` | `DwarfDirector` | Roster identity/appearance, profession data, position, sleep state, and carried item keys |
| 70 | `camera` | `Camera` | Target position, zoom, pitch, and orbit |
| 80 | `slice` | `SliceController` | Active/seeded state, current plane, and last manual plane |

Section keys must be unique. A new scene-owned system must document both its priority and
why its state is authoritative rather than seed-derived or transient.

---

## 4. Observational snapshot rule

The first implementation released active tasks before serialising. In play, pressing Save
made one dwarf abandon a mining zone and another claim the lease. That was correct from a
data-safety perspective but wrong for player experience and incompatible with background
autosaves.

The shipped rule is stronger: **Save observes; it never participates in simulation.**
Manual and automatic saves ask owners for dictionaries and write them without calling
task reset/release APIs or changing agents.

The autosave counter advances only while the world maps are ready, deterministic
generation is idle, and no load is running. At 300 seconds it takes the same observational
snapshot into the independent autosave slot and shows a short **Autosaved.** toast. Manual
saves do not reset this counter; completing a load does, avoiding an immediate post-load
autosave.

An item currently carried by a dwarf is a boundary case. The save records its namespaced
item key in that dwarf's `carried_items`, while the live task and reservation remain
transient. On load, those items materialise loose around the restored dwarf's feet. Rebuilt
work sources can reclaim them without duplicating or losing inventory. This conversion
happens only on load; pressing Save does not drop the live carried item.

---

## 5. Load lifecycle

1. Select the manual or autosave slot, then open, parse, and validate its primary file.
2. If the primary is missing or invalid, validate the backup. A valid backup is copied
   back to the primary path before the load continues, repairing the live slot.
3. Validate the project marker, schema range, non-zero world seed, and `scene` dictionary.
4. Store the snapshot as the pending restore and pause the clock.
5. Reset transient autoload state:
   `TaskManager`, `StockpileManager`, `InteriorTracker`, `NavGrid`,
   `PlacedEntityRegistry`, `WorldGenerator`, and `WorldData`.
6. Reload the current world scene.
7. `WorldRenderer` asks `SaveManager.generation_seed_for_new_scene()` for the saved seed and
   starts deterministic generation.
8. Rebind scene-dependent autoload services such as `SkyController`.
9. Wait until the generator reports maps ready and no generation work remains, followed by
   two quiet frames for scene owners and deferred hookups.
10. Restore scene owners in priority order.
11. Rebuild `StockpileManager` totals, then restore clock and weather last.
12. Clear the pending snapshot and show **Game loaded.** Backup recovery is reported
    explicitly when that path was needed.

The derived systems rebuild naturally: installed entities repopulate occupancy,
designations/work sources post fresh leases, dwarves register with `TaskManager`, mined
blocks rebuild interior data, and renderer/nav caches follow their normal invalidation
paths.

---

## 6. Persisted versus rebuilt

| Persisted | Regenerated or rebuilt |
|---|---|
| World seed | Untouched terrain and seed-derived flora |
| Calendar, speed/pause, weather and weather RNG | Render meshes and dirty queues |
| Mined coordinates and mining designations | Task objects, statuses, assignments, leases, and backoff |
| Settlement flag and dwarf roster | Item/block/task reservations |
| Ground stockpiles and stored contents | Navigation walkability/path caches |
| Furniture ghosts, installed pieces, uninstall flags, container inventories | `PlacedEntityRegistry` occupancy index |
| Loose and in-transit item identity | `InteriorTracker` regions |
| Camera and slice state | Active executor phase and partial work timers |

The task assignment visible immediately after loading may differ from the moment of saving;
that is intentional because tasks are reconstructed. The act of **saving**, however, leaves
the current assignment completely untouched.

---

## 7. Validation and player feedback

Load is rejected before mutating the world when:

- neither a primary nor backup exists for the selected slot;
- the file cannot be opened or parsed as a JSON dictionary;
- `project` is not `Deepdraft`;
- the schema is missing or newer than the running game;
- the world seed is missing/zero; or
- scene state is missing.

Manual Save is rejected while the deterministic world maps are still generating. Autosave
waits without accumulating time while generation is active. All actions report through a
short `DockUI` toast. The save menu remains presentation only: it emits
`save_game_requested`, `load_game_requested`, or `load_autosave_requested`, while
`SaveManager` owns the timer, I/O, and lifecycle logic.

---

## 8. Verification record

Verified during the 2026-07-18 implementation session:

- The dock menu exposes manual Save, manual Load, and Load Autosave. Manual Save/Load were
  confirmed in-engine; Load Autosave is wired to the regression-tested backend.
- A version-1 file parses as valid JSON and contains all eight scene-owner sections.
- Reload reproduces the saved seed and restores non-empty mining, flag, dwarf, stockpile,
  furniture/container, loose-item, clock/weather, camera, and slice state.
- Saving during assigned mining leaves the dwarf/task assignment unchanged.
- Saving while carrying an item leaves the live carried item unchanged.
- Loading that snapshot restores the in-transit item loose at the carrier's saved position.
- Tasks/reservations rebuild without orphaned state, and stockpile totals are recalculated.
- Alen's in-engine follow-up confirmed that saving no longer feels interrupted.
- The automated round-trip test crosses the five-minute threshold, verifies the autosave
  cannot create or overwrite the manual slot, rotates an autosave backup, loads the
  autosave independently, and verifies that both automatic and manual snapshots are
  observational. It also corrupts the manual primary, recovers its backup, repairs the
  primary, and verifies all eight scene-owner sections plus seed and clock.

Run the regression from the project root:

```text
godot --headless --path . --script res://scripts/tests/SaveManagerRoundTripTest.gd
```

Success prints `SAVE_MANAGER_ROUND_TRIP_OK` and exits with code 0. The harness uses a
dedicated `user://save_manager_round_trip_test` directory and never touches player saves.

---

## 9. Durability and remaining follow-ups

The autosave durability prerequisites are shipped:

1. JSON is written to the selected slot's `.tmp.json`, flushed, closed, parsed, and
   schema-validated.
2. The current primary is rotated only when it is valid. Its staged backup is validated
   before replacing that slot's `.backup.json`; an invalid primary never overwrites a good
   backup. Manual and automatic paths never rotate into one another.
3. The validated temporary file replaces the primary only after those checks, and the
   installed primary is validated again.
4. A failed promotion attempts to restore the valid backup.
5. Load falls back to the backup when the primary is corrupt and repairs the primary slot.
6. The repeatable headless regression covers manual and automatic round trips, slot
   isolation, backup rotation, and the corrupt-primary path.

Explicit schema-migration functions remain required before schema version 2. Multiple
named slots, thumbnails, configurable autosave cadence/triggers, and a broader retention
policy remain separate UI/product decisions.

---

*Prev: [19_containers_furniture.md](./19_containers_furniture.md)*
