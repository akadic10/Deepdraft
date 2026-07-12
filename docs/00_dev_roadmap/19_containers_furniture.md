# 19 - Storage Containers & Furniture Placement (Third Colony Milestone)

> **Document review legend for Obsidian**
>
> <span style="color:#3fb950;">Green = decided / ready to build</span> |
> <span style="color:#d29922;">Yellow = decision needed or tune-in-engine</span> |
> <span style="color:#f85149;">Red = explicitly out of scope for this milestone</span>

Status: plan, drafted 2026-07-11; **revised same day after the P:\stonehearth deploy/undeploy
source review (Alen's ask — furniture placed FROM storage, 📥 place / 📤 uninstall).**

**Why this milestone:** doc 18 shipped ground stockpiles with a deliberate density ceiling —
one item per tile, WYSIWYG (Alen, 2026-07-06). Density was explicitly deferred to
**containers**, the Stonehearth-verified upgrade path (small crate 8 → large crate 32 →
vault 256; doc 18 §2.5). Containers need a **furniture pipeline**, which does not exist —
and that pipeline is the gateway for every future placeable: workshop props (doc 44),
tavern furniture (doc 51), the Armory's stands and displays (doc 52), beds, torches.
Following the Stonehearth review (§2 below), furniture is not conjured — it is an **item**
that dwarves fetch from storage and install, and uninstall back into storage. Both
directions ride the doc 18 haul pipeline. The doc 16 architectural bet gets its third and
fourth tests: containers post HAUL leases; placement ghosts post FETCH-AND-BUILD leases.

Deliverable: **the player 📥-places a barrel, chest, or storage shelf as a ghost from the
Build panel; a dwarf fetches the furniture item and installs it; dwarves haul loose drops
into the installed container; 📤 marks it for uninstall — a dwarf breaks it down into its
item form (contents dumped loose) and normal hauling restocks everything — with every step
interruptible under the release protocol.**

---

## 1. Where Deepdraft stands today (gap analysis)

| Piece | State today | Gap |
|---|---|---|
| Furniture data schema | `data/furniture/trade_counter.json` — rich canonical schema (footprint, collision_regions, room_anchor…) but nothing loads it | No loader, no other furniture defs, no ITEM-form defs |
| Furniture assets | **None.** `assets/models/` has flora + items only; doc 61 §5.4 has authored SPECS for barrel + storage crate | Full-size GLBs (placed form) + item-drop GLBs (carryable form); shelf needs a doc 61 spec |
| Placement tool | `FlagPlacementController` — single-entity ghost + validity tint + `PlacedEntityRegistry.register_box` (256 lines, one-shot) | No data-driven ghost tool, no rotation, no fulfilment leases |
| Entity occupancy | `PlacedEntityRegistry` + `occupancy_changed` → NavGrid invalidation, proven by flag + trees | Nothing — reused as-is |
| Item pipeline | `ItemDropManager` loose-item index + reservations + hauling, shipped + verified 2026-07-11 | Furniture item defs join `resources.json`; a new `stockpile_furniture` filter tag |
| Storage logic | `StockpileZoneComponent` — accept/reserve/deposit + the pouch haul loop, designed as the future shared contract (doc 18 §2.5) | Extract the contract; container implements it with slots instead of cells |
| Source ids | Mining raw; stockpile zones at 1M offset; **doc 18 tech debt: TaskManager allocator "when a third source system appears"** | Third AND fourth families arrive (containers, ghosts) — the debt is due |
| UI | Dock `build` panel entry exists, panel is a stub | Build panel gets 📥 placement; furniture window gets 📤 |

---

## 2. Stonehearth reference findings (verified from `P:\stonehearth` source, 2026-07-11)

Read directly from `components/entity_forms/entity_forms_component.lua`,
`lib/entity_forms/entity_forms_lib.lua`, `call_handlers/place_item_call_handler.lua`,
`ai/actions/pickup_placed_item_adjacent_action.lua`, `place_item_type_on_structure_2.lua`,
and `data/commands/undeploy_item/`.

### The three-form model

Every placeable item is ONE logical entity with three representations:

| Form | What it is | Where it lives |
|---|---|---|
| **Root** | Full-size deployed object | In the world, registered with nav/collision |
| **Iconic** | Small carryable lump | In stockpiles/containers, in a worker's hands, loose on the ground |
| **Ghost** | Translucent placement preview | In the world as a **persistent task marker** until fulfilled |

The player's inventory tracks root XOR iconic depending on which is in-world — a parent
trace swaps them (`_on_parent_changed`). The ghost copies the root's collision shape but
sets it to `RegionCollisionShape.NONE`: **nav is unaffected until the item is actually
installed.**

### Place = a standing request, type-matched

`place_item_type_in_world` drops a ghost and asks the town for fulfilment. The AI action
matches **any iconic of that URI** (not a specific instance) that is not itself being
placed, leases it, and a worker carries it to the ghost and swaps ghost → root. The UI
returns `more_items` so the tool can stay active while stock remains.

### Undeploy = a restock toggle, then normal hauling

`undeploy_item` sets `should_restock` on the placed item (a TOGGLE — clicking again
cancels), shows an overlay effect, and cancels competing tasks. A worker executes
`pickup_placed_item_adjacent`: walk adjacent, `work` effect, unparent the root, pick up
the **iconic** — from that moment it is ordinary restockable inventory and the doc 18-style
restock machinery stores it. Undeploying and placing are mutually cancelling
(`_place_item` calls `set_should_restock(false)`; restocking cleans up placement tasks).

### Gear worth stealing later (recorded, not v1)

- **Command locking:** an item placed ON another (lamp on table) locks the base item's
  move/undeploy commands until the child leaves (`_on_children_changed`).
- **Placement limits:** `stonehearth:item_placement_limit` caps per-town placements by tag.
- **Ladders:** wall placements auto-request pickup/put-down ladders — skip until walls.
- **Move-item:** relocation = the same ghost pipeline with `moving_placed_item = true`.

### <span style="color:#3fb950;">What doc 19 adopts</span>

The full three-form pipeline, translated: furniture ITEM defs in `resources.json` (iconic ≙
our existing item drops), full-size placed form registered in `PlacedEntityRegistry`, ghost
as a work source posting a FETCH-AND-BUILD lease, 📤 as a toggle flag that posts an
UNINSTALL lease, type-matched fetches, nav untouched by ghosts. Skipped: walls/ladders,
placement limits, move-item (uninstall + re-place covers v1), command locking (nothing
stacks on furniture yet).

---

## 3. ARCHITECTURE

### <span style="color:#3fb950;">3.0 Direction</span>

1. **Furniture is an item with a placed form — never conjured.** The item form is a normal
   `resources.json` entry (drop GLB, `stockpile_furniture` tag) that mining… does not
   produce; v1 items enter via a DEV spawner (economy fills this via crafting/trade later).
   The placed form is the full-size GLB + occupancy + (for storage pieces) a storage
   component.
2. **The ghost is a work source (doc 16 §2.1, fourth family).** Placing with 📥 creates a
   `FurnitureGhost` that posts ONE fetch-and-build lease, type-matched against the
   loose-item index and storage aggregates. No dwarf, no fulfilment — the ghost waits
   patiently, exactly like a mining designation.
3. **📤 is a toggle, not a command (SH parity).** It flags the placed piece; the flag posts
   an uninstall lease; clicking 📤 again clears flag + lease. Uninstall dumps stored
   contents as loose drops, swaps placed form → item form at the stand cell, and the
   ordinary doc 18 hauling puts everything away.
4. **One storage contract, many faces (doc 18 §2.5).** `StorageComponent` base owns the
   haul-loop machinery; ground zone = per-item floor cells; container = capacity slots
   behind one stand cell. The `DwarfAgent` haul executor is untouched.
5. **The WYSIWYG split is a principle:** ground zones + shelf show every item they hold
   (shelf capacity = anchor count); barrel/chest trade visibility for density and show
   counts in their window.
6. **Release stays cheap and legal (Hard Rule 12):** an interrupted fetcher drops the
   furniture item at its feet (it re-enters the index; the ghost re-leases); an
   interrupted uninstaller leaves the piece installed with the 📤 flag still set.

### 3.1 Furniture data

Three defs following the `trade_counter.json` schema, `furniture_category: "storage"`, plus
NEW shared fields: `item_key` (the resources.json item form), `placement` (`"floor"` |
`"floor_wall"`), `yaw_steps: 4`, and a `storage` block for containers:

| Def | Footprint | Storage block | Item form (resources.json) |
|---|---|---|---|
| `base:furniture:barrel` | 1×1, 1 tall | `{ "capacity": 8, "render_contents": false }` | `base:resources:furniture:barrel` |
| `base:furniture:storage_chest` | 1×1, 1 tall | `{ "capacity": 24, "render_contents": false }` | `base:resources:furniture:storage_chest` |
| `base:furniture:storage_shelf` | 1×1×2, **wall-adjacent** | `{ "capacity": 8, "render_contents": true, "anchors": [×8] }` | `base:resources:furniture:storage_shelf` |

Item forms get `material_tags: ["stockpile_furniture"]` (new filter tag; zones' v1
accept-everything default gains it) and `weight_class: "heavy"`. `storage.anchors` are
local float offsets (blocks) where stored item GLBs render on the shelf.

**Loader:** `FurniturePlacementController` owns `data/furniture/*.json` (system-owns-its-
data, doc 13). Item defs stay solely with `ItemDropManager`.

### 3.2 Placement tool — 📥 (`FurniturePlacementController`, scene node)

- Build panel: one 📥 entry per placeable → `tool_requested("furniture")` + def key; joins
  the click-tool exclusion contract (2026-07-06 fix).
- **Ghost preview** on the cursor: the placed-form GLB, translucent, validity-tinted
  (flag-tool language), yaw in 90° steps on <span style="color:#d29922;">**R** (lean — the
  wheel is contractually camera/brush, doc 21)</span>.
- **Validity:** footprint cells NavGrid-walkable at one floor Y, unoccupied
  (`PlacedEntityRegistry`), not on stockpile-zone cells, not water; `floor_wall` probes the
  block behind the ghost's back face for solidity.
- **On confirm:** a `FurnitureGhostComponent` is created (translucent node stays in-world —
  the SH persistent task marker; **no occupancy registration** — ghosts are non-solid) and
  registered as a work source. Tool stays active while matching items remain (SH
  `more_items`); ESC-only cancel.
- **Click-select with the tool off** (the doc 18 A3 lesson, built in from day one): clicking
  a ghost opens its window (item wanted, Cancel 📥); clicking an installed piece opens
  contents summary + **📤 Uninstall** (toggle) + the container inventory list.

### 3.3 Fetch-and-build lease (the ghost work source)

```
1. Ghost posts ONE lease (type-matched: item_key present loose OR in colony storage)
2. Dwarf pulls: nearest matching item — loose (index) first, else withdraw from the
   nearest zone cell / container holding one (storage components gain
   withdraw(item_key, dwarf_id) -> Node3D; zone cell empties, container count drops)
3. Carry to the ghost's stand cell (heavy carry speed) -> `work` swing timer
4. Swap: item node freed; placed form instanced; collision_regions boxes registered with
   PlacedEntityRegistry (NavGrid invalidates); storage component created + registered
   with StockpileManager; ghost destroyed; lease completes
5. Interrupt anywhere: item drops at the feet (re-enters index), ghost re-leases —
   Hard Rule 12
```

No matching item in the colony → the lease stays PENDING under the normal backoff; the
ghost window shows *"needs: barrel (none in colony)"*.

### 3.4 Uninstall lease — 📤

📤 toggles `flagged_uninstall` on the placed piece. While set: an overlay tint on the
piece (SH's undeploy overlay, our validity-tint language), its storage component stops
posting HAUL leases and cancels live ones, and ONE uninstall lease posts:

```
1. Dwarf walks to the stand cell -> `work` swing timer
2. Stored contents dump as loose drops at the stand cell (jittered — 2026-07-11 fix)
3. Placed form freed; occupancy unregistered (NavGrid); storage deregistered;
   item-form drop spawns at the stand cell
4. Everything on the ground is now ordinary loose inventory — existing zone/container
   leases wake on drop_spawned and put it all away
```

📤 again before step 1 completes → flag cleared, lease cancelled, piece untouched.

### 3.5 Storage contract extraction (`scripts/components/StorageComponent.gd`)

The doc 18 §6.5 lean, executed: hoist from `StockpileZoneComponent` everything that is not
cell-specific —

```gdscript
# StorageComponent (base, RefCounted) — the haul work-source machinery
#   update_leases / on_task_gone / reserve_haul / cancel_haul / take_item /
#   skip_item / commit_haul / nearest_stand_target          (doc 18 §2.2–2.3, unchanged)
# Subclass surface (abstract):
#   _reserve_deposit(item_key, near, dwarf_id) -> Variant   # zone: cell; container: slot token
#   _release_deposit(token) / _commit_one(token, item_key) / _has_any_room()
#   _deposit_walk_target() -> Vector3i                      # zone: first cell; container: stand cell
#   _place_visual(node, token) -> void                      # zone: place_stored; container: absorb/anchor
#   withdraw(item_key, dwarf_id) -> Node3D                  # NEW (fetch-and-build, §3.3)
```

`StockpileZoneComponent extends StorageComponent` — behaviour identical; **the doc 18
verification checklist re-runs as the regression gate.** New
`ContainerStorageComponent extends StorageComponent`: flat inventory (item_key → count),
capacity check, one stand cell, counted-slot reservations. `render_contents` false → the
deposited node is freed (the barrel absorbs it; window shows counts); true → the node
snaps to the next free anchor at <span style="color:#d29922;">~0.45 scale (tune by
eye)</span>, slice-culled. `StockpileManager` registers containers like zones; aggregates
and `stockpile_changed` span both.

### 3.6 Source-id allocator (the doc 18 tech debt, now due twice)

`TaskManager.allocate_source_id() -> int` — monotonic from 10,000,000. Containers and
ghosts use it. <span style="color:#d29922;">Migrating mining (raw ids) and zones (1M
offset) is optional cleanup — lean: new families only.</span>

### <span style="color:#f85149;">3.7 Explicitly out of scope</span>

Crafting/buying furniture items (v1 source = DEV spawner; doc 44 crafting and doc 51 trade
fill it for real). Input/output bins + restock priority bands (doc 44). Filter panel UI.
Move-item (uninstall + re-place). Wall/structure placement, ladders. Command locking
(nothing stacks on furniture yet). Placement limits. Trade counter placement (needs room
detection, doc 51). Beds, tavern, Armory furniture. Save/load (whole-project gap;
NOTE: ghosts and 📤 flags join the growing unsaved-state list).

---

## 4. Milestone phases

### Phase 0 — Instrument first (doc 07 lesson, third time)

Overlay `storage:` row grows `containers N`; new `furniture:` row: ghosts N / installed N /
uninstalling N. DEV: **Spawn Furniture Items** button (one item of each of the three).

### Phase 1 — Assets + data

`tools/generate_furniture_glbs.py` (items class: **8 vox/block, 0.125 baked**, the doc 61
§5.7 convention): `barrel.glb`, `storage_crate.glb`, `storage_shelf.glb` per doc 61 §5.4
specs (+ NEW shelf spec: 1×1×2, hewn stone uprights, two plank levels, iron brackets;
anchors clear of uprights — add to doc 61 when the asset ships). Item-form drop GLBs
(mini versions, same generator). `resources.json` gains the three item defs + the
`stockpile_furniture` tag; three furniture JSONs (§3.1). Review renders to
`tmp/furniture_review/`.

Acceptance: placed + item forms load in-engine at correct scale beside a dwarf; doc 61 §7
silhouette checklist passes.

### Phase 2 — Ghost placement tool

§3.2 without fulfilment: Build panel 📥 wiring (`dock.json`, DockUI), ghost preview +
validity + R-rotation, confirmed ghosts persist (non-solid, slice-culled), ghost window
with Cancel, click-select with tool off, tool exclusion verified. DEV: **Instant Build**
button on the ghost window (materialises without a dwarf — the DEV-mine precedent) so
Phase 4 storage work can proceed before Phase 3 lands.

Acceptance: place ghosts for all three pieces on flats/terraces; shelf refuses placement
without a wall behind; ghosts never block pathing; ESC exits; cancel cleans up; zones
cannot be painted under ghosts/furniture and vice versa.

### Phase 3 — Fetch-and-build + uninstall leases

§3.3 + §3.4 + allocator (§3.6). DEV-spawn items → dwarves fetch and install; 📤 →
break-down + restock chain end to end.

Acceptance: ghost + item in the world → a dwarf installs it (nav blocks only on install);
ghost with NO item → lease waits, window says needs; interrupt the fetcher mid-carry →
item drops, another dwarf finishes; 📤 a stocked barrel → contents + barrel item all end up
back in zones; 📤 twice quickly → nothing happens; the doc 18 conservation check holds
(loose + stored + carried + installed is constant).

### Phase 4 — Storage contract + container hauling

§3.5: extract `StorageComponent`, re-base the zone (**regression gate: full doc 18
checklist re-run**), add `ContainerStorageComponent` + StockpileManager registration.

Acceptance: zone AND installed barrel near a drop field → both fill via leases; barrel
absorbs (window count climbs, stops at 8); withdraw works (a fetch lease pulls a stored
furniture item OUT of a zone/container); interrupt mid-trip → Rule 12; overlay reconciles.

### Phase 5 — Shelf contents + polish

Anchor rendering, slice-culling of anchored items, container window inventory list,
aggregates verified, carry/deposit visuals against the walk gait.

Acceptance: 8 mixed drops onto a shelf → all 8 visibly sit on the levels; slice hides
shelf + contents together; 📤 the shelf → 8 + the shelf item drop loose; `get_total()`
matches zones + containers throughout.

---

## 5. Hard rules honoured (checklist for review)

1. **Rule 12** — fetcher drops the item, uninstaller leaves the piece installed; §3.3/§3.4.
2. **O(intents)** — one lease per ghost, per uninstall flag, per container stream; no
   per-item tasks; indexes event-maintained.
3. **JSON vs GDScript** — capacities, anchors, footprints, yaw, item_key in
   `data/furniture/*.json`; item defs in `resources.json`; behaviour in components.
4. **Namespaced IDs** — `base:furniture:*` + `base:resources:furniture:*`; never ints.
5. **Registry pattern** — FurniturePlacementController sole reader of `data/furniture/`;
   item defs only via `ItemDropManager`.
6. **Entity decoupling (doc 12)** — terrain grid never learns about furniture; occupancy
   via `PlacedEntityRegistry` boxes; ghosts register nothing.
7. **Scene decoupling** — controller is a scene node; components RefCounted; cross-system
   flow via TaskManager/StockpileManager signals.
8. **Never touch `.tres` / `.import`.**

---

## 6. Build order & file touch list

| Step | Files | Depends on |
|---|---|---|
| 0. Overlay rows | `DebugLoadingOverlay.gd` | — |
| 1. Assets + data | new `tools/generate_furniture_glbs.py`, `assets/models/furniture/*.glb`, `assets/models/items/furniture/*.glb`, `data/entities/items/resources.json`, new `data/furniture/{barrel,storage_chest,storage_shelf}.json`, doc 61 §5.4 shelf spec | — |
| 2. Ghost tool | new `scripts/systems/FurniturePlacementController.gd`, new `scripts/components/FurnitureGhostComponent.gd`, `data/ui/dock.json`, `DockUI.gd`, `debug_world.tscn` | 1 |
| 3. Fetch/build + uninstall | `FurnitureGhostComponent.gd`, new `scripts/components/InstalledFurnitureComponent.gd`, `DwarfAgent.gd` (FETCH/UNINSTALL executor arms), `TaskManager.gd` (allocator + task types), `Task.gd` | 2 |
| 4. Contract + containers | new `scripts/components/StorageComponent.gd`, `StockpileZoneComponent.gd` (re-base + withdraw), new `scripts/components/ContainerStorageComponent.gd`, `StockpileManager.gd`, **doc 18 checklist re-run** | 2 (DEV Instant Build) |
| 5. Shelf + windows | `FurniturePlacementController.gd`, `ContainerStorageComponent.gd`, `ItemDropManager.gd` (anchor helpers) | 3, 4 |

Docs to update on completion: `23_user_interface.md` (Build panel, 📥/📤), doc 61 §5.4
(shelf spec), `13_architecture.md` (allocator), `31_task_system.md` (FETCH/UNINSTALL
types), doc 18 §2.5 (container follow-on shipped), doc 12 (placed-entity forms note),
this doc's build log.

---

## 7. Open decisions (resolve before or during build)

1. <span style="color:#3fb950;">~~Chest capacity~~ — **DECIDED (Alen, 2026-07-11): 24.**
   The ladder step from barrel 8 stays meaningful without obsoleting ground zones at v1.</span>
2. <span style="color:#d29922;">**Rotation input**</span> — R key (lean) vs wheel.
3. <span style="color:#d29922;">**Allocator migration scope**</span> — new families only
   (lean) vs migrating mining/zone keyspaces.
4. <span style="color:#d29922;">**New Task.Type entries**</span> — FETCH_BUILD + UNINSTALL
   as first-class types (lean — visible in the task log, doc 23) vs overloading BUILD.
5. <span style="color:#d29922;">**Shelf anchor scale**</span> — ~0.45, tune by eye.
6. <span style="color:#d29922;">**`stack_max` on containers**</span> — v1 flat item count
   (SH parity); per-type density stays reserved, unwired.
7. <span style="color:#d29922;">**Ghost visual**</span> — translucent tinted GLB (lean) vs
   wireframe; SH uses a translucent ghost form.
8. <span style="color:#d29922;">**Hauler target preference**</span> — v1 nearest-first per
   source, no cross-source ranking; watch whether barrels starve zones in play.

---

## 8. Build log

| Date | Steps | State |
|---|---|---|
| — | — | — |

---

*Prev: [18_stockpiles_hauling.md](./18_stockpiles_hauling.md)*
